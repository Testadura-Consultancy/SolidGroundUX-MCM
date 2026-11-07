#!/usr/bin/env python3
"""Generate SolidGroundUX documentation from the currently installed release files.

Release manifests are used to isolate each product in a temporary source tree.
The existing Markdown generator and Web Content Manager renderer do the actual work.
No saved documentation bundle or installed file is modified.
"""

import argparse
import contextlib
import io
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

from sgnd_doc_markdown import generate


# --- Product metadata ---------------------------------------------------------------
PRODUCTS = (
    ("framework", "Framework", "SolidGroundUX", "sgnd-definitions.sh", "SGND", "SolidGroundUX", "solidgroundux"),
    ("mcm", "Management Console", "SolidGroundUX-Management-Console-Modules",
     "solidground-management-console-modules-definitions.sh",
     "SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES", "SolidGroundUX-MCM", "solidground-management-console-modules"),
    ("sdk", "Software Development Kit", "SolidGroundUX-SDK",
     "solidgroundux-sdk-definitions.sh", "SGND_SOLIDGROUNDUX_SDK", "SolidGroundUX-SDK", "solidgroundux-sdk"),
)
SUPPORTED_SOURCES = {".sh", ".py"}


# --- Internal functions -------------------------------------------------------------
# fn: definition_value - Read a version/build assignment without executing Bash code.
def definition_value(path: Path, name: str) -> str:
    """Read an installed product identity value.

    Usage:
        definition_value(Path('sgnd-definitions.sh'), 'SGND_VERSION')
    """
    pattern = re.compile(r'^\s*' + re.escape(name) + r'\s*=\s*(.*?)\s*(?:#.*)?$')
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1).strip().strip('"\'')
    raise ValueError(f"Missing {name} in {path}")


# fn: installed_products - Discover active versions and matching archived manifests.
def installed_products(root: Path, state_root: Path) -> list[dict]:
    """Return product availability based on installed definitions and exact manifests.

    Usage:
        installed_products(Path('/'), Path('/var/lib/solidgroundux'))
    """
    rows = []
    for key, title, prefix, definitions_name, variable, identifier, project in PRODUCTS:
        definitions = root / "usr/local/lib/solidgroundux/globals" / definitions_name
        row = dict(key=key, title=title, id=identifier, installed=False,
                   available=False, version="", build="", manifest="", reason="")
        if not definitions.is_file():
            row["reason"] = "Product definitions not installed"
        else:
            try:
                version = definition_value(definitions, variable + "_VERSION")
                build = definition_value(definitions, variable + "_BUILD")
                if not re.fullmatch(r'[A-Za-z0-9._-]+', version) or not re.fullmatch(r'[A-Za-z0-9._-]+', build):
                    raise ValueError("Invalid installed version or build")
                row.update(installed=True, version=version, build=build)
                base = f"{prefix}-{version}.{build}"
                # Setup stores Framework history in state/archive, but each other
                # product has its own projects/<project>/archive directory.
                project_archive = (state_root / 'archive' if project == 'solidgroundux'
                                   else state_root / 'projects' / project / 'archive')
                manifest = project_archive / base / (base + ".manifest")
                if manifest.is_file():
                    row.update(available=True, manifest=str(manifest))
                else:
                    row["reason"] = f"Installed release manifest not found: {manifest}"
            except (OSError, ValueError) as exc:
                row["reason"] = str(exc)
        rows.append(row)
    return rows


# fn: selected_file - Reject unsafe manifest paths and unsupported installed files.
def selected_file(root: Path, entry: str) -> tuple[Path, Path] | None:
    """Resolve a manifest entry inside the installation root, if documented.

    Usage:
        selected_file(Path('/'), 'usr/local/libexec/solidgroundux/module.sh')
    """
    relative = Path(entry.lstrip('./'))
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError(f"Unsafe manifest path: {entry}")
    # Setup itself is installed below /var rather than /usr/local.
    if relative.parts[:2] != ("usr", "local") and relative.as_posix() != "var/lib/solidgroundux/sgnd-setup.sh":
        return None
    path = root / relative
    if path.is_symlink():
        resolved = path.resolve()
        if not resolved.is_relative_to(root.resolve()):
            raise ValueError(f"Source symlink escapes installation root: {entry}")
    if not path.is_file():
        return None
    docs = relative.parts[:4] == ("usr", "local", "share", "doc-sources")
    if docs:
        if any(part == '__pycache__' for part in relative.parts) or path.suffix in (".pyc", ".pyo"):
            return None
        return relative, path
    if relative.suffix.lower() in SUPPORTED_SOURCES:
        if '__pycache__' not in relative.parts:
            return relative, path
    if relative.as_posix() == "usr/local/share/testadura/solidgroundux/LICENSE":
        return relative, path
    return None


# fn: stage_product - Materialize exactly the source files owned by one installed product.
def stage_product(root: Path, manifest: Path, destination: Path) -> int:
    """Stage supported product sources without copying runtime state or unrelated products.

    Usage:
        stage_product(Path('/'), Path('release.manifest'), Path('/tmp/product'))
    """
    count = 0
    seen = set()
    for entry in manifest.read_text(encoding="utf-8").splitlines():
        entry = entry.strip()
        if not entry or entry.startswith('#'):
            continue
        record = selected_file(root, entry)
        if record is None:
            continue
        relative, source = record
        if relative in seen:
            continue
        seen.add(relative)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        count += 1
    if not any(path.is_file() for path in destination.rglob('*.sh')) and \
            not any(path.is_file() for path in destination.rglob('*.py')):
        raise ValueError(f"No documented scripts found in {manifest}")
    return count


# fn: validate_output - Reject installation roots and dangerous output destinations.
def validate_output(root: Path, output: Path) -> None:
    """Keep generated documentation out of package and executable directories.

    Usage:
        validate_output(Path('/'), Path('/var/lib/solidgroundux/documentation/installed'))
    """
    forbidden = [root, root / "usr", root / "usr/local", root / "var",
                 root / "var/lib", root / "var/lib/solidgroundux",
                 root / "var/lib/solidgroundux/releases"]
    if output in forbidden or len(output.parts) < 4:
        raise ValueError(f"Output location is too broad or reserved: {output}")
    if output.is_relative_to(root / "usr/local"):
        raise ValueError("Documentation output must not be under installed program files")


# --- Public functions ---------------------------------------------------------------
# fn: run - Generate Markdown and optional HTML from selected installed releases.
def run(root: Path, state_root: Path, output: Path, selected: list[str], html: bool) -> dict:
    """Prepare temporary per-product sources and reuse the existing generator.

    Usage:
        run(Path('/'), Path('/var/lib/solidgroundux'),
            Path('/var/lib/solidgroundux/documentation/installed'), ['framework'], True)
    """
    validate_output(root, output)
    rows = installed_products(root, state_root)
    requested = set(selected)
    if not requested or 'all' in requested:
        requested = {row['key'] for row in rows if row['installed']}
    unknown = requested - {row['key'] for row in rows}
    if unknown:
        raise ValueError('Unknown product selection: ' + ', '.join(sorted(unknown)))
    selected_rows = [row for row in rows if row['key'] in requested]
    if not selected_rows:
        raise ValueError('No installed products were selected')
    for row in selected_rows:
        if not row['available']:
            raise ValueError(f"{row['title']}: {row['reason']}")

    with tempfile.TemporaryDirectory(prefix='sgnd-installed-doc-') as stage:
        staging = Path(stage)
        products = []
        staged_files = 0
        for row in selected_rows:
            source = staging / row['key']
            staged_files += stage_product(root, Path(row['manifest']), source)
            products.append(dict(id=row['id'], title=row['title'], source_dir=str(source)))
        bundle = dict(schema=1, id='installed', title='SolidGroundUX Documentation',
                      overwrite='replace', output_dir=str(output / 'markdown'), products=products)
        docs_root = root / 'usr/local/share/doc-sources'
        summary = generate(bundle, docs_root if docs_root.is_dir() else None)
        result = dict(selected_products=[row['key'] for row in selected_rows],
                      versions={row['key']: f"{row['version']}.{row['build']}" for row in selected_rows},
                      staged_files=staged_files, markdown=str(output / 'markdown'),
                      files=summary.get('files', 0), functions=summary.get('functions', 0),
                      missing_images=summary.get('missing_images', 0))
        if html:
            from webcontent.generator import generate_site
            # WCM prints progress to stderr. Keep the helper's result machine-readable
            # for the console frontend; all errors still surface in the summary.
            with contextlib.redirect_stderr(io.StringIO()):
                rendered = generate_site(str(output / 'markdown'), str(output / 'www'), 'NL', mode='public')
            if not rendered.success:
                raise ValueError('HTML generation failed: ' + '; '.join(rendered.errors))
            result['html'] = str(output / 'www')
            result['pages'] = rendered.pages_generated
            result['broken_links'] = rendered.broken_links
            result['warnings'] = rendered.warnings[:20]
        return result


# fn: main - Process the installed-documentation command-line interface.
def main(argv: list[str] | None = None) -> int:
    """List installed products or generate their documentation.

    Usage:
        main(['--list'])
        main(['--products', 'framework,sdk', '--html'])
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='/', help='Installed filesystem root (for testing/staged trees)')
    parser.add_argument('--state-root', help='Setup state root containing archive/ and projects/<project>/archive/')
    parser.add_argument('--output', default='/var/lib/solidgroundux/documentation/installed')
    parser.add_argument('--products', default='all', help='Comma-separated product keys: framework,mcm,sdk')
    parser.add_argument('--html', action='store_true', help='Also render HTML through the existing WCM engine')
    parser.add_argument('--list', action='store_true', help='Report installed products and manifest availability')
    args = parser.parse_args(argv)
    try:
        root = Path(args.root).expanduser().resolve()
        state_root = (Path(args.state_root).expanduser().resolve() if args.state_root
                      else root / 'var/lib/solidgroundux')
        if args.list:
            print(json.dumps(installed_products(root, state_root), ensure_ascii=False))
            return 0
        output = Path(args.output).expanduser().resolve()
        requested = [value.strip().lower() for value in args.products.split(',') if value.strip()]
        print(json.dumps(run(root, state_root, output, requested, args.html), ensure_ascii=False))
        return 0
    except (OSError, ValueError, RuntimeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
