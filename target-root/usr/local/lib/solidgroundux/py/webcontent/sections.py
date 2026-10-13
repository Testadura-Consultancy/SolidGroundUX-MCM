"""Create, inspect, relocate, archive and remove website section trees.

Section management operates on canonical Markdown files, never generated output.
Navigation roots are protected from destructive operations. All changes remain
uncommitted until the site maintainer explicitly commits them in Git.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import re
import shutil

from .content import load_navigation, load_site_config

SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
LANGUAGES = ("NL", "EN")


def _root(source):
    """Return the resolved canonical content directory for a valid repository."""
    return load_site_config(Path(source).expanduser().resolve()).content_dir.resolve()


def _section(content, relative, *, allow_root=False):
    """Validate a relative section directory without permitting path traversal."""
    relative = relative.strip().strip("/")
    if not relative:
        if allow_root:
            return content
        raise ValueError("The website root is not a manageable section")
    if any(not SLUG.fullmatch(part) for part in relative.split("/")):
        raise ValueError("Invalid section path; use lowercase slugs separated by /")
    directory = (content / relative).resolve()
    if not directory.is_relative_to(content):
        raise ValueError("Section path escapes the content directory")
    return directory


def _indexed(directory):
    """Check whether an existing directory defines at least one section index."""
    return directory.is_dir() and any((directory / f"index_{lang}.md").is_file() for lang in LANGUAGES)


def _protected(source, content, directory):
    """Prevent deletion of a section referenced in the main navigation config."""
    relative = directory.relative_to(content).as_posix()
    for item in load_navigation(Path(source).expanduser().resolve()):
        if item.path.strip("/") == relative:
            return True
    return False


def list_sections(source):
    """List indexed sections suitable for parent selection or management."""
    content = _root(source)
    sections = [{"path": "", "label": "Website root"}]
    for directory in sorted(content.rglob("*")):
        if directory.is_dir() and _indexed(directory):
            sections.append({"path": directory.relative_to(content).as_posix(), "label": directory.name})
    return {"success": True, "sections": sections}


def create_section(source, parent, slug, title_nl, title_en, languages="NL,EN"):
    """Create a new indexed section with draft NL/EN pages, without overwriting.

    Parent must already be indexed (except for the website root). Metadata
    identifies these as section listing pages. Language choice is explicit.
    """
    content = _root(source)
    base = _section(content, parent, allow_root=True)
    if base != content and not _indexed(base):
        raise ValueError("Parent must be an existing indexed section")
    if not SLUG.fullmatch(slug):
        raise ValueError("Slug must contain lowercase letters, digits and hyphens")
    chosen = [value.strip().upper() for value in languages.split(",") if value.strip()]
    if not chosen or len(chosen) != len(set(chosen)) or any(value not in LANGUAGES for value in chosen):
        raise ValueError("Languages must be NL, EN or NL,EN")
    titles = {"NL": title_nl.strip(), "EN": title_en.strip()}
    if any(not titles[language] for language in chosen):
        raise ValueError("Each selected language needs a section title")
    target = base / slug
    if target.exists():
        raise ValueError("Section already exists; refusing to overwrite")
    # Validate all strings before writing even the first file.
    if any("\n" in titles[lang] or "\r" in titles[lang] for lang in chosen):
        raise ValueError("Section title must be a single line")
    target.mkdir()
    created = []
    try:
        for language in chosen:
            title = titles[language].replace("\\", "\\\\").replace('"', '\\"')
            body = "Schrijf hier de introductie van deze sectie.\n" if language == "NL" else "Write the introduction for this section here.\n"
            path = target / f"index_{language}.md"
            path.write_text(f'---\ntitle: "{title}"\nsummary: ""\ntemplate: listing\ncontent_type: section\nfeatured: false\ndraft: true\n---\n\n{body}', encoding="utf-8")
            created.append(path.relative_to(content).as_posix())
    except Exception:
        shutil.rmtree(target)
        raise
    return {"success": True, "created": created, "section": target.relative_to(content).as_posix(), "changed_count": len(created)}


def inspect_section(source, section):
    """Report subtree size and protection before a destructive operation."""
    content = _root(source)
    directory = _section(content, section)
    if not _indexed(directory):
        raise ValueError("Select an existing indexed section")
    files = [path for path in directory.rglob("*") if path.is_file()]
    indexes = [path for path in files if re.fullmatch(r"index_[A-Z]{2}\.md", path.name)]
    return {"success": True, "section": directory.relative_to(content).as_posix(),
            "protected": _protected(source, content, directory), "files": len(files),
            "index_pages": len(indexes), "subsections": sum(1 for sub in directory.rglob("*") if sub.is_dir() and _indexed(sub)),
            "affected": [path.relative_to(content).as_posix() for path in sorted(files)]}


def remove_section(source, section, mode, destination="", archive_root=""):
    """Apply an explicitly chosen section removal policy.

    'move' transfers children (including subordinate section trees) to an
    existing indexed destination, then removes the selected section indexes.
    'archive' moves the complete section tree outside the live content tree.
    'delete' permanently removes the complete tree. Nothing edits inbound URLs.
    """
    info = inspect_section(source, section)
    content = _root(source)
    directory = _section(content, section)
    if info["protected"]:
        raise ValueError("Section is in main navigation; remove its navigation entry first")
    if mode not in {"move", "archive", "delete"}:
        raise ValueError("Mode must be move, archive or delete")
    warning = "Regenerate and validate website; links to old URLs are not rewritten."
    if mode == "move":
        target = _section(content, destination, allow_root=True)
        if target != content and not _indexed(target):
            raise ValueError("Destination must be an existing indexed section")
        if target == directory or target.is_relative_to(directory):
            raise ValueError("Cannot move into the section itself or a descendant")
        children = [p for p in directory.iterdir() if not re.fullmatch(r"index_[A-Z]{2}\.md", p.name)]
        conflicts = [p.name for p in children if (target / p.name).exists()]
        if conflicts:
            raise ValueError("Destination contains conflicting names: " + ", ".join(conflicts))
        # Section index pages are deliberately not merged into the target index.
        for child in children:
            shutil.move(str(child), str(target / child.name))
        shutil.rmtree(directory)
        return {"success": True, "mode": mode, "changed_count": info["files"], "warnings": [warning]}
    if mode == "archive":
        if not archive_root:
            raise ValueError("Archive directory is required")
        archive = Path(archive_root).expanduser().resolve()
        if archive.is_relative_to(Path(source).expanduser().resolve()):
            raise ValueError("Archive must be outside the canonical content tree")
        archive.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        target = archive / f"{timestamp}-{directory.name}"
        if target.exists():
            raise ValueError("Archive destination already exists")
        shutil.move(str(directory), str(target))
        return {"success": True, "mode": mode, "archive": str(target), "changed_count": info["files"], "warnings": [warning]}
    shutil.rmtree(directory)
    return {"success": True, "mode": mode, "changed_count": info["files"], "warnings": [warning]}
