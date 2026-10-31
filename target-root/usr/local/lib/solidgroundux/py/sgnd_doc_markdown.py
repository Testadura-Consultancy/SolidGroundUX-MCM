#!/usr/bin/env python3
"""Generate a WCM Markdown source repository from a saved documentation bundle.

This generator does not import or alter WCM. It emits its documented source layout.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from collections import Counter
from pathlib import Path

DECL = re.compile(r'^\s*#\s+(fn|cls|var|mod|exe|lib|doc)(:|\$)\s+([A-Za-z_][\w.:-]*)(?:\s+-\s+(.+))?\s*$')
FIELD = re.compile(r'^\s*#\s*\.\s+(.+?)\s*$')
COMMENT = re.compile(r'^\s*#(?: ?)(.*)$')
DEF_START = re.compile(r'^\s*#\s*def:\s*(.+?)\s*$')
DEF_END = re.compile(r'^\s*#\s*def\$\s*$')
SECTION = re.compile(r'^\s*#\s(-{1,3})\s+(.+?)\s*$')
HEADER_TITLE = re.compile(r'^#\s+([^\s-][^-]*?)\s+-\s+(.+?)\s*$')
USELESS_TITLE = re.compile(r'^[#=\-_*~ ]+$')
META = re.compile(r'^\s*#\s*(Version|Build|Purpose|Description|Group|Subgroup|Title|Type)\s*:\s*(.*?)\s*$', re.I)
# A script section is a script-level heading regardless of how many dashes
# precede it in the legacy comment marker (# -, # --, or # ---).
SCRIPT_SECTION_HEADING = '## '
HEADER_CATEGORIES = re.compile(
    r'^(Description|Design principles|Role in framework|Non-goals|'
    r'Documentation|Introduction|Overview|Usage):\s*$', re.I)
EXAMPLE_SECTION = re.compile(r'^-{1,3}\s+(Example:\s*.+?)\s*$', re.I)
IDENTITY = re.compile(r'[^a-z0-9]+')
SKIP_DIRS = {'.git', '.cache', '__pycache__', 'node_modules', '.venv', 'venv', 'www-html', 'www-md'}


def slug(value: str) -> str:
    return IDENTITY.sub('-', value.lower()).strip('-') or 'untitled'


def is_template_source(rel: Path, metadata: dict, path: Path) -> bool:
    if metadata.get('type', '').strip().casefold() == 'template':
        return True
    parts = tuple(part.casefold() for part in rel.parts[:-1])
    return path.stem.casefold().endswith('-template') and any(part in ('templates', 'convenience-templates') for part in parts)


def template_priority(product_id: str, rel: Path) -> tuple:
    parts = tuple(part.casefold() for part in rel.parts)
    product_rank = 0 if 'software development kit' in product_id.casefold() else 1
    if parts[:5] == ('usr', 'local', 'lib', 'solidgroundux', 'templates'):
        location_rank = 0
    elif 'convenience-templates' in parts:
        location_rank = 2
    else:
        location_rank = 1
    return (product_rank, location_rank, len(parts), rel.as_posix())


def build_template_owners(products: list[dict]) -> dict[str, tuple[str, str]]:
    owners: dict[str, tuple[tuple, tuple[str, str]]] = {}
    for product in products:
        source = Path(product['source_dir']).expanduser().resolve()
        for candidate in sorted(p for p in source.rglob('*.sh') if p.is_file() and not any(part in SKIP_DIRS for part in p.relative_to(source).parts)):
            rel = candidate.relative_to(source)
            metadata, _, _ = parse_source(candidate)
            if not is_template_source(rel, metadata, candidate):
                continue
            key = candidate.name.casefold()
            current = (template_priority(product['id'], rel), (product['id'], rel.as_posix()))
            if key not in owners or current[0] < owners[key][0]:
                owners[key] = current
    return {key: owner for key, (_, owner) in owners.items()}


def prune_empty_headings(lines: list[str]) -> list[str]:
    """Remove headings without body text or meaningful child sections.

    A WCM td-details disclosure with heading=N is an independent document
    section at that level, not content belonging to the preceding heading.
    Treat it as a boundary so an empty heading such as ``## Bootstrap``
    cannot borrow the following Script metadata disclosure as its body.
    """
    markdown_heading = re.compile(r'^(#{2,6})\s+')
    details_heading = re.compile(r'^:::\s+td-details\b[^\n]*?\bheading=([2-6])\b')
    boundaries: list[int | None] = []
    fence_marker = ''

    for line in lines:
        stripped = line.strip()
        fence = re.match(r'^(`{3,}|~{3,})', stripped)
        if fence:
            marker = fence.group(1)
            if not fence_marker:
                fence_marker = marker
            elif marker[0] == fence_marker[0] and len(marker) >= len(fence_marker):
                fence_marker = ''
            boundaries.append(None)
            continue
        if fence_marker:
            boundaries.append(None)
            continue
        match = markdown_heading.match(stripped)
        if match:
            boundaries.append(len(match.group(1)))
            continue
        match = details_heading.match(stripped)
        boundaries.append(int(match.group(1)) if match else None)

    # An authored heading is meaningful when it contains actual content or
    # a meaningful, deeper subsection. Same-level disclosures are siblings.
    keep_heading: dict[int, bool] = {}
    for i in range(len(lines) - 1, -1, -1):
        level = boundaries[i]
        if level is None or not markdown_heading.match(lines[i].strip()):
            continue
        meaningful = False
        j = i + 1
        while j < len(lines):
            child_level = boundaries[j]
            if child_level is not None:
                if child_level <= level:
                    break
                # A populated nested heading or disclosure gives its parent
                # useful content; an empty nested heading does not.
                if details_heading.match(lines[j].strip()) or keep_heading.get(j, False):
                    meaningful = True
                j += 1
                continue
            value = lines[j].strip()
            if value and not re.fullmatch(r'[`*_=-]{3,}', value):
                meaningful = True
            j += 1
        keep_heading[i] = meaningful

    cleaned = [line for i, line in enumerate(lines)
               if i not in keep_heading or keep_heading[i]]
    result: list[str] = []
    previous_blank = False
    for line in cleaned:
        blank = not line.strip()
        if blank and previous_blank:
            continue
        result.append(line)
        previous_blank = blank
    return result


def front(title: str, order: int = 1000, summary: str = '', *, section: bool = True, template: str = 'page', nav_title: str | None = None) -> str:
    values = {'title': title, 'nav_title': title if nav_title is None else nav_title, 'summary': summary, 'template': template,
              'content_type': 'section' if section else 'page', 'nav_order': order,
              'draft': False, 'featured': False}
    return '---\n' + '\n'.join(f'{key}: {json.dumps(value, ensure_ascii=False)}' if isinstance(value, str)
                              else f'{key}: {str(value).lower() if isinstance(value, bool) else value}'
                              for key, value in values.items()) + '\n---\n\n'


def write_index(folder: Path, title: str, body: str, order: int = 1000, summary: str = '', template: str = 'page', *, nav_title: str | None = None) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f'{slug(title)}_Index_NL.md').write_text(front(title, order, summary, template=template, nav_title=nav_title) + body.strip() + '\n', encoding='utf-8')


def _section_marker(text: str, inside_item: bool, in_fence: bool):
    """Recognize old section headers, but never reinterpret Markdown lists."""
    if in_fence:
        return None
    m = SECTION.match(text)
    if not m:
        return None
    marks, label = m.groups()
    # A dashed divider unambiguously identifies the old section syntax.
    ruled = re.search(r'\s-{4,}\s*$', label)
    if ruled:
        label = label[:ruled.start()].strip()
    elif inside_item or len(marks) == 1:
        # Unruled '# - ...' lines are Markdown bullets, not sections.
        # '# --' and '# ---' are unambiguous structural markers.
        return None
    if not label or label.startswith(('-', '*', '[', '!')):
        return None
    # Metadata examples such as '# --- Example: Arguments' are labels, not
    # structural sections. Preserve them within their existing section.
    if re.match(r'^Example\s*:', label, re.I):
        return None
    title = label.split(':', 1)[1].strip() if ':' in label else label
    return {'kind': 'section', 'name': label, 'title': title,
            'level': len(marks), 'lines': []}


def parse_source(path: Path):
    """Extract documented items and Markdown while preserving source comment blocks."""
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    meta = {}
    for line in lines[:100]:
        m = META.match(line)
        if m and m.group(1).lower() not in meta:
            meta[m.group(1).lower()] = m.group(2)
    for line in lines[:30]:
        m = HEADER_TITLE.match(line)
        if m and 'title' not in meta:
            candidate = m.group(2).strip()
            if not candidate or USELESS_TITLE.fullmatch(candidate):
                continue
            meta['title'] = candidate
            break

    entries = []
    current = None
    fence = False
    in_header = True
    header_category = ''
    header_narrative = []
    in_code = False
    definition = None

    def header_line(text: str) -> str:
        # Header prose is conventionally indented by two spaces after '# '.
        # Remove only that shared margin so nested list bullets and code fences
        # retain their own Markdown structure.
        return text[2:] if text.startswith('  ') else text
    for line in lines:
        # # def: blocks document the *actual* following shell definitions.
        # Retain source lines verbatim; never source or evaluate Bash here.
        start = DEF_START.match(line)
        if start:
            declaration = start.group(1).strip()
            title, _, modifiers = declaration.partition(' | ')
            definition = {'kind': 'def', 'name': title, 'title': title,
                          'pivot': modifiers.removeprefix('pivot=') if modifiers.startswith('pivot=') else '',
                          'raw': [], 'lines': []}
            entries.append(definition)
            current = None
            in_header = False
            in_code = False
            continue
        if DEF_END.match(line):
            definition = None
            current = None
            continue
        if definition is not None:
            definition['raw'].append(line)
            continue
        comment = COMMENT.match(line)
        if not comment:
            if line.strip() and not line.lstrip().startswith('#'):
                in_header = False
                in_code = True
                # Script metadata consists of documentary comment blocks
                # interleaved with actual Bash assignments. Keep the section
                # open across those assignments; otherwise the comments for
                # all but the first variable disappear from the output.
                if not (current is not None and current['kind'] == 'section'
                        and current['title'].casefold().startswith('script metadata')):
                    current = None
                fence = False
            continue
        value = comment.group(1).rstrip()
        stripped = value.strip()
        # A Markdown code fence owns everything through its closing fence.
        if stripped.startswith(('```', '~~~')):
            fence = not fence
            if current:
                current['lines'].append(value)
            elif in_header or header_category:
                header_narrative.append(header_line(value))
            continue

        if not fence:
            decl = DECL.match(line)
            if decl:
                kind, marker, name, short = decl.groups()
                current = {'kind': kind + ('$' if marker == '$' else ''),
                           'name': name, 'title': (short or name).strip(), 'lines': []}
                entries.append(current)
                in_header = False
                in_code = False
                continue
            section = _section_marker(line, inside_item=current is not None and current['kind'] != 'section', in_fence=fence)
            if section and (current is None or current['kind'] == 'section' or re.search(r'\s-{4,}\s*$', stripped)):
                entries.append(section)
                current = section
                in_header = False
                in_code = False
                continue
            # Example labels may occur within comments surrounding executable
            # script metadata. They are documentary notes, not section headings.
            example = EXAMPLE_SECTION.match(stripped)
            if example:
                text = '**' + example.group(1) + '**'
                if current is None:
                    current = {'kind': 'narrative', 'name': '', 'title': '',
                               'lines': [text, '']}
                    entries.append(current)
                else:
                    current['lines'].extend(['', text, ''])
                in_header = False
                in_code = False
                continue

        if current is not None:
            # Field headers are legacy structural markup, not Markdown paragraphs.
            field = FIELD.match(line) if not fence else None
            if field:
                current['lines'].extend(['', '### ' + field.group(1).strip(), ''])
            else:
                current['lines'].append(value)
            continue

        if in_header:
            # Retain free-form header descriptions, but not scaffolding or raw metadata.
            if re.match(r'^[-=]{6,}$', stripped):
                continue
            category = HEADER_CATEGORIES.match(stripped)
            if category:
                header_category = category.group(1)
                header_narrative.extend(['', '## ' + header_category, ''])
                continue
            if META.match(line) or HEADER_TITLE.match(line):
                continue
            if re.match(r'^(Metadata|Attribution):\s*$', stripped, re.I):
                header_category = ''
                continue
            if header_category:
                header_narrative.append(header_line(value))
        elif not in_code and stripped and (stripped.startswith(('>', '|', '#', ':::', '![', '[', '*', '-'))):
            # Standalone documentation outside structured items.
            header_narrative.append(value)
    if any(line.strip() for line in header_narrative):
        entries.insert(0, {'kind': 'narrative', 'name': '', 'title': '', 'lines': header_narrative})
    return meta, entries, len(lines)



IMAGE_HEADING = re.compile(r"^\s*(?:(?:\#{1,6}|[.:])\s*)?Images?\s*$", re.I)
IMAGE_ITEM = re.compile(r"^\s*(.+?\.(?:png|jpe?g|gif|svg|webp|avif))(?:\s*::\s*(.*))?\s*$", re.I)


def markdown_documentation(lines: list[str]) -> list[str]:
    """Translate legacy Images blocks, preserving all other Markdown lines."""
    result = []
    index = 0
    while index < len(lines):
        line = lines[index]
        normalized = line.strip()
        if IMAGE_HEADING.fullmatch(normalized):
            cursor = index + 1
            while cursor < len(lines) and not lines[cursor].strip():
                cursor += 1
            images = []
            while cursor < len(lines):
                next_line = lines[cursor].strip()
                if not next_line:
                    break
                match = IMAGE_ITEM.fullmatch(next_line)
                if not match:
                    break
                name, caption = match.groups()
                name = name.strip()
                alt = (caption or Path(name).stem.replace('-', ' ').replace('_', ' ')).strip()
                if name.startswith(('http://', 'https://', 'data:', '/')):
                    url = name
                elif name.startswith(('assets/', 'images/')):
                    url = '/' + name
                else:
                    url = '/images/' + name
                images.append(f'![{alt}]({url})')
                cursor += 1
            if images:
                result.extend([''] + images + [''])
                index = cursor
                continue
        result.append(line)
        index += 1
    return result


def script_metadata_markdown(lines: list[str]) -> list[str]:
    """Render source metadata comments without losing alignment or examples.

    These comments alternate with live SGND_* assignments. They are not
    function headers and their indentation often describes Bash syntax or
    column-aligned field definitions, which ordinary Markdown collapses.
    Only script-metadata sections use this rendering; authored Markdown in
    other sections and function documentation is left unchanged.
    """
    import textwrap

    result: list[str] = []
    literal: list[str] = []
    author_fence = False
    in_explanation = False

    def close_explanation() -> None:
        nonlocal in_explanation
        if in_explanation:
            result.extend(["", ":::", ""])
            in_explanation = False

    def flush_literal() -> None:
        if literal:
            # Dedent the shared comment margin, not alignment within the sample.
            sample = textwrap.dedent('\n'.join(literal)).strip('\n')
            if result and result[-1] != '':
                result.append('')
            language = 'bash' if re.search(r'\bSGND_[A-Z0-9_]+\s*=\s*\(', sample) else 'text'
            result.extend([f'```{language}', sample, '```', ''])
            literal.clear()

    for line in lines:
        value = line.rstrip()
        stripped = value.strip()
        if stripped.startswith(('```', '~~~')):
            flush_literal()
            author_fence = not author_fence
            result.append(value)
            continue
        if author_fence:
            result.append(value)
            continue
        if not stripped:
            flush_literal()
            if result and result[-1] != '':
                result.append('')
            continue
        if re.fullmatch(r'SGND_[A-Z][A-Z0-9_]*', stripped):
            flush_literal()
            close_explanation()
            # Keep the metadata variables as subsections. Enclose their prose,
            # lists and code examples in a themed explanation card. A card is
            # ordinary Markdown content, not a preformatted code block.
            result.extend(['', f'### {stripped}', '', '::: sgnd-metadata-card', ''])
            in_explanation = True
            continue
        if stripped.startswith('### '):
            flush_literal()
            # Canonical '# . Purpose' and '# . Behavior' fields are plain
            # labels in script metadata, just like 'Use this to:' and 'Only list:'.
            # A blank line before and after gives the label breathing room.
            result.extend(['', stripped[4:].strip().rstrip(':') + ':', ''])
            continue
        if re.fullmatch(r'\*\*[^*]+\*\*', stripped):
            flush_literal()
            # Example labels emitted by parse_source should not look like
            # a higher-priority heading than other metadata explanations.
            result.extend(['', stripped[2:-2], ''])
            continue
        if re.match(r'^#{2,6}\s+', stripped):
            flush_literal()
            result.extend(['', stripped, ''])
            continue
        # Indented explanations of fields and command examples are literal
        # samples, while list items are still ordinary Markdown lists.
        if ((len(value) - len(value.lstrip()) >= 2 or re.match(r'^var:\s*=', stripped))
                and not re.match(r'^[-*+]\s+', stripped)):
            literal.append(value)
            continue
        flush_literal()
        if re.match(r'^[-*+]\s+', stripped):
            result.append(stripped)
        else:
            # Preserve explicit source-comment line breaks where Markdown
            # would otherwise merge separate metadata statements into prose.
            result.append(stripped + '  ')
    flush_literal()
    close_explanation()
    return markdown_documentation(result)


DEF_ASSIGN = re.compile(r'^\s*(?:export\s+|readonly\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$')


def _def_cell(value: str) -> str:
    """Escape table delimiters without interpreting shell syntax."""
    return value.strip().replace('\\', '\\\\').replace('|', '\\|').replace('\n', '<br>')


def _def_literal(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def _def_assignments(lines: list[str]) -> list[tuple[str, str, str, list[str] | None]]:
    """Read literal assignments, including multiline Bash arrays, without evaluation."""
    assignments = []
    position = 0
    while position < len(lines):
        match = DEF_ASSIGN.match(lines[position])
        if not match:
            position += 1
            continue
        name, text = match.groups()
        # Only comments separated by whitespace from the value are descriptions.
        value, divider, comment = re.split(r'\s+#\s*', text, maxsplit=1)[0], '', ''
        fragments = re.split(r'\s+#\s*', text, maxsplit=1)
        if len(fragments) == 2:
            value, comment = fragments
        value = value.strip()
        if value.startswith('('):
            data = []
            remainder = value[1:].strip()
            if remainder.endswith(')'):
                remainder = remainder[:-1].strip()
                if remainder:
                    data.append(remainder)
            else:
                if remainder:
                    data.append(remainder)
                position += 1
                while position < len(lines):
                    item = lines[position].strip()
                    if item == ')':
                        break
                    # An inline Bash comment after an array literal is not
                    # part of that value (including a comment after its quote).
                    item = re.split(r'\s+#\s*', item, maxsplit=1)[0].rstrip()
                    if item.endswith(')') and not item.startswith('#'):
                        if item[:-1].strip():
                            data.append(item[:-1].strip())
                        break
                    if item and not item.startswith('#'):
                        data.append(item)
                    position += 1
            assignments.append((name, 'array', comment, data))
        else:
            assignments.append((name, value, comment, None))
        position += 1
    return assignments


def definition_markdown(entry: dict) -> list[str]:
    """Render the established # def: blocks as tables from literal source.

    `pivot=LBL:Label,ICO:Icon` combines assignments sharing a suffix into
    one row, matching the existing style/palette definition convention.
    """
    assignments = _def_assignments(entry['raw'])
    if not assignments:
        return []
    result = ['### ' + entry['title'], '']
    pivot = []
    if entry.get('pivot'):
        for field in entry['pivot'].split(','):
            prefix, sep, heading = field.partition(':')
            if sep and prefix.strip() and heading.strip():
                pivot.append((prefix.strip() + '_', heading.strip()))
    if pivot:
        combined = {}
        order = []
        for name, value, comment, array in assignments:
            for prefix, title in pivot:
                if name.startswith(prefix):
                    key = name[len(prefix):]
                    if key not in combined:
                        combined[key] = {}
                        order.append(key)
                    combined[key][prefix] = value
                    break
        if order:
            result.extend(['| Group {rowspan} | ' + ' | '.join(title for _, title in pivot) + ' |',
                           '| --- | ' + ' | '.join('---' for _ in pivot) + ' |'])
            for key in order:
                cells = [_def_cell(key)] + [_def_cell(_def_literal(combined[key].get(prefix, ''))) for prefix, _ in pivot]
                result.append('| ' + ' | '.join(cells) + ' |')
            result.append('')
    others = []
    for name, value, note, array in assignments:
        if pivot and any(name.startswith(prefix) for prefix, _ in pivot):
            continue
        if array is not None:
            # Registry rows use the literal pipe-separated tuple format.
            structured = [_def_literal(item) for item in array]
            if structured and all('|' in item for item in structured):
                width = max(len(item.split('|')) for item in structured)
                empty_final = width == 4 and all(item.split('|')[-1] == '' for item in structured)
                if empty_final:
                    # The registry tuple's optional final slot is empty.
                    # Do not render an entire blank table column.
                    width = 3
                    headings = ['Scope', 'Variable', 'Description']
                elif width == 4:
                    headings = ['Scope', 'Variable', 'Description', 'Default']
                else:
                    headings = [f'Field {n}' for n in range(1, width + 1)]
                result += ['#### `' + name + '`', '', '| ' + ' | '.join(headings) + ' |',
                           '| ' + ' | '.join('---' for _ in headings) + ' |']
                for item in structured:
                    cells = item.split('|')[:width]
                    result.append('| ' + ' | '.join(_def_cell(cell) for cell in cells + [''] * (width-len(cells))) + ' |')
                result.append('')
            else:
                result += ['#### `' + name + '`', '', '| # | Item |', '| ---: | --- |']
                for ix, item in enumerate(structured, 1):
                    result.append('| ' + str(ix) + ' | `' + _def_cell(item) + '` |')
                result.append('')
        else:
            others.append((name, value, note))
    if others:
        result += ['| Variable | Value | Notes |', '| --- | --- | --- |']
        for name, value, note in others:
            result.append('| `' + name + '` | `' + _def_cell(value) + '` | ' + _def_cell(note) + ' |')
        result.append('')
    return result


def append_preface(target: list[str], entries: list[dict]) -> None:
    for entry in entries:
        if entry['kind'] == 'section':
            target.extend([SCRIPT_SECTION_HEADING + entry['title'], ''])
        elif entry['kind'] not in ('narrative',):
            target.extend(['### ' + entry['title'], ''])
        target.extend(markdown_documentation(entry['lines']))
        target.append('')


def copy_legacy_images(source: Path, root: Path) -> None:
    """Use the original product asset location and the existing doc-sources locations."""
    candidates = [source / 'usr/local/assets', source / 'target-root/usr/local/assets',
                  source / 'doc-sources/assets', source / 'usr/local/share/doc-sources/assets',
                  source / 'target-root/usr/local/share/doc-sources/assets']
    for directory in candidates:
        if not directory.is_dir():
            continue
        for asset in directory.rglob('*'):
            if not asset.is_file() or asset.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.avif'):
                continue
            target = root / 'images' / asset.name
            if target.exists() and target.read_bytes() != asset.read_bytes():
                raise ValueError(f'Image filename conflict: {asset.name} (from {directory})')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(asset, target)


def copy_assets_checked(source: Path, destination: Path) -> None:
    """Merge resource trees without silently replacing different files."""
    if not source.is_dir():
        return
    for file in sorted(source.rglob('*')):
        if not file.is_file():
            continue
        target = destination / file.relative_to(source)
        if target.exists():
            if target.read_bytes() != file.read_bytes():
                raise ValueError(f'Conflicting resource: {target} (from {file})')
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)


def missing_image_references(root: Path) -> list[str]:
    """Report unresolved local Markdown images without rejecting documentary examples."""
    image = re.compile(r'!\[[^\]]*\]\(([^)]+)\)')
    unresolved = set()
    for document in (root / 'content').rglob('*.md'):
        body = document.read_text(encoding='utf-8')
        for match in image.finditer(body):
            target = match.group(1).strip().split(' "', 1)[0].strip('<>')
            if not target or target.startswith(('http://', 'https://', 'data:', '#')):
                continue
            path = target.split('#', 1)[0].split('?', 1)[0]
            if path.startswith('/'):
                local = root / path.lstrip('/')
            else:
                local = document.parent / path
            if not local.is_file():
                unresolved.add(f'{document.relative_to(root)}: {target}')
    return sorted(unresolved)


def declaration_template(kind: str) -> str:
    if kind.startswith('fn'):
        return 'function'
    if kind == 'var':
        return 'variable'
    if kind == 'cls':
        return 'class'
    return 'declaration'


def source_document_template(filename: str) -> str:
    name = filename.casefold().replace('_', '-')
    if 'preface' in name:
        return 'preface'
    if 'epilogue' in name:
        return 'epilogue'
    return 'source'

def directory_title(path: Path):
    return path.name.replace('-', ' ').replace('_', ' ').strip().title()


def collect(product, content: Path, order: int, counters: Counter, template_owners: dict[str, tuple[str, str]]):
    """Use source metadata Group/Subgroup, never installation directories, for navigation."""
    source = Path(product['source_dir']).expanduser().resolve()
    if not source.is_dir():
        raise ValueError(f'Missing source directory: {source}')
    product_folder = content / slug(product['id'])
    write_index(product_folder, product['title'], '', order, template='chapter')
    paths = sorted(p for p in source.rglob('*.sh') if p.is_file() and not any(part in SKIP_DIRS for part in p.relative_to(source).parts))
    records = []
    for path in paths:
        metadata, entries, loc = parse_source(path)
        records.append((path, metadata, entries, loc))
    # Product-level prefaces and epilogues belong to the chapter index, not to
    # a new group named after the product. Group/subgroup prefaces remain in their
    # respective section indexes.
    grouped_records = []
    product_specials = []
    for path, metadata, entries, loc in records:
        special = source_document_template(path.name)
        purpose = metadata.get('purpose', '').strip().casefold()
        if special in ('preface', 'epilogue') and purpose == f'product {special}':
            product_specials.append((special, entries, loc))
        else:
            grouped_records.append((path, metadata, entries, loc))
    # Legacy renderer sorted groups and subgroups alphabetically, within each product.
    groups = sorted({metadata.get('group', '').strip() or 'Ungrouped' for _, metadata, _, _ in grouped_records}, key=str.casefold)
    route_names = set()
    special_pages = {}
    for special, entries, loc in product_specials:
        special_pages.setdefault(product_folder, {'preface': [], 'epilogue': []})[special].append(entries)
        counters['files'] += 1
        counters['lines'] += loc
    for group_index, group in enumerate(groups, 1):
        group_folder = product_folder / slug(group)
        group_body = []
        write_index(group_folder, group, '\n'.join(group_body), group_index, template='group')
        group_records = [r for r in grouped_records if (r[1].get('group', '').strip() or 'Ungrouped') == group]
        subgroup_names = sorted({r[1].get('subgroup', '').strip() for r in group_records if r[1].get('subgroup', '').strip()}, key=str.casefold)
        for subgroup_index, subgroup in enumerate(subgroup_names, 1):
            subfolder = group_folder / slug(subgroup)
            write_index(subfolder, subgroup, '', subgroup_index, template='group')
        for path, metadata, entries, loc in group_records:
            subgroup = metadata.get('subgroup', '').strip()
            parent = group_folder / slug(subgroup) if subgroup else group_folder
            rel = path.relative_to(source)
            # Defer prefaces/epilogues until every source is discovered, preserving
            # source ordering and placing introductions before closing material.
            special = source_document_template(path.name)
            if special in ('preface', 'epilogue'):
                section_folder = parent
                special_pages.setdefault(section_folder, {'preface': [], 'epilogue': []})[special].append(entries)
                counters['files'] += 1
                counters['lines'] += loc
                continue
            # Keep one source document per file, with anchored public declarations.
            basename = slug(path.stem)
            source_folder = parent / basename
            if source_folder in route_names:
                source_folder = parent / slug(str(rel.with_suffix('')))
            if source_folder in route_names or source_folder.exists():
                raise ValueError(f'Route collision: {rel} -> {source_folder}')
            route_names.add(source_folder)
            counters['files'] += 1
            counters['lines'] += loc
            is_template = is_template_source(rel, metadata, path)
            if is_template:
                owner = template_owners.get(path.name.casefold())
                if owner and owner != (product['id'], rel.as_posix()):
                    continue
            documented = [entry for entry in entries
                          if not (entry['kind'] in ('fn$', 'doc$') and not is_template)]
            # A source with no useful documentation belongs in statistics, not navigation.
            # Section markers alone are not content, nor is the source pathname.
            has_source_content = (bool(metadata.get('purpose', '').strip() or metadata.get('description', '').strip())
                                  or any(entry['kind'] not in ('section', 'narrative') for entry in documented)
                                  or any(entry['kind'] in ('section', 'narrative')
                                         and any(text.strip() for text in markdown_documentation(entry['lines']))
                                         for entry in documented))
            if not has_source_content:
                continue
            counters['functions'] += sum(e['kind'].startswith('fn') for e in documented)
            counters['declarations'] += sum(e['kind'] not in ('section', 'narrative') for e in documented)
            for key in ('version', 'build'):
                if metadata.get(key) and not counters.get(key):
                    counters[key] = metadata[key]
            title = metadata.get('title') or path.stem.replace('-', ' ')
            body = [f'**Source:** `{rel.as_posix()}`', '']
            if metadata.get('purpose'):
                body += [metadata['purpose'], '']
            if metadata.get('description'):
                body += [metadata['description'], '']
            public = [e for e in documented if e['kind'].startswith('fn') and not e['name'].startswith('_')]
            internal = [e for e in documented if e['kind'].startswith('fn') and e['name'].startswith('_')]
            if public:
                body += ['## Public functions', '']
                for entry in public:
                    page_slug = slug(entry['name'])
                    body.append(f'- [{entry["title"]}]({page_slug}/)')
                body.append('')
            if internal:
                # WCM's native details component renders Markdown inside a
                # closed-by-default disclosure. Keep the internal API table
                # accessible without overwhelming the source overview.
                body += ['::: td-details heading=2 Internal functions', '',
                         '| Function | Purpose | Arguments | Output |',
                         '| --- | --- | --- | --- |']
                for entry in internal:
                    def field_value(label):
                        lines = entry['lines']
                        for ix, line in enumerate(lines):
                            if re.match(r'^\s*###\s+' + label + r's?\s*$', line, re.I):
                                for value in lines[ix + 1:]:
                                    if value.strip().startswith('### '):
                                        break
                                    if value.strip():
                                        return value.strip().replace('|', r'\|')
                        return '—'
                    purpose = field_value('Purpose')
                    if purpose == '—' and entry['title'] != entry['name']:
                        purpose = entry['title'].replace('|', r'\|')
                    body.append(f'| `{entry["name"]}` | {purpose} | {field_value("Arguments")} | {field_value("Output")} |')
                body += ['', ':::', '']
            # Public functions receive full pages. All other documentation
            # remains on the source overview; internal functions appear only in the table.
            used_public_slugs = set()
            for entry in documented:
                kind = entry['kind']
                if kind == 'narrative':
                    body += markdown_documentation(entry['lines']) + ['']
                elif kind == 'def':
                    definitions = definition_markdown(entry)
                    # A # def: label matching the immediately preceding
                    # script section is its content, not another heading.
                    last = next((line.strip() for line in reversed(body) if line.strip()), '')
                    if (definitions and last.casefold() == ('## ' + entry['title']).casefold()
                            and definitions[0].startswith('### ')):
                        definitions = definitions[2:]
                    body += definitions
                elif kind == 'section':
                    if entry['title'].casefold().startswith('script metadata'):
                        # Script metadata is extensive but useful to have visible
                        # initially. Use WCM's native disclosure, expanded by
                        # default, and preserve its proper h2 document level.
                        metadata_lines = script_metadata_markdown(entry['lines'])
                        if any(line.strip() for line in metadata_lines):
                            body += [f'::: td-details heading=2 open {entry["title"]}', '',
                                     '::: sgnd-script-metadata', '']
                            body += metadata_lines + ['', ':::', '', ':::', '']
                    else:
                        body += [SCRIPT_SECTION_HEADING + entry['title'], '']
                        body += markdown_documentation(entry['lines']) + ['']
                elif kind.startswith('fn') and entry['name'].startswith('_'):
                    continue
                elif kind.startswith('fn'):
                    page_slug = slug(entry['name'])
                    if page_slug in used_public_slugs:
                        raise ValueError(f'Duplicate public function route in {rel}: {entry["name"]}')
                    used_public_slugs.add(page_slug)
                    page_path = source_folder / f'{page_slug}_NL.md'
                    page_path.parent.mkdir(parents=True, exist_ok=True)
                    declaration_body = [f'`{kind}: {entry["name"]}`', '']
                    declaration_body += markdown_documentation(entry['lines'])
                    page_path.write_text(
                        front(entry['title'], len(used_public_slugs), template='function', section=False, nav_title=entry['name'])
                        + '\n'.join(declaration_body).strip() + '\n', encoding='utf-8')
                else:
                    body += [f'### {entry["title"]}', '', f'`{kind}: {entry["name"]}`', '']
                    body += markdown_documentation(entry['lines']) + ['']
            # Remove structural headings whose section contains no documentation.
            # Apply this to the assembled overview (including header narrative).
            body = prune_empty_headings(body)
            # Use the real source filename in navigation; retain its descriptive page title.
            write_index(source_folder, title, '\n'.join(body),
                        summary=metadata.get('purpose', ''), template='source', nav_title=path.name)
    for section_folder, specials in special_pages.items():
        index_files = list(section_folder.glob('*_Index_NL.md'))
        if len(index_files) != 1:
            raise ValueError(f'Expected one section index in {section_folder}')
        index_file = index_files[0]
        existing = index_file.read_text(encoding='utf-8')
        front_end = existing.find('\n---\n', 4)
        if front_end < 0:
            raise ValueError(f'Invalid index front matter: {index_file}')
        prefix, body = existing[:front_end + len('\n---\n')], existing[front_end + len('\n---\n'):]
        intro, closing = [], []
        for entries in specials['preface']:
            append_preface(intro, entries)
        for entries in specials['epilogue']:
            append_preface(closing, entries)
        index_file.write_text(prefix + '\n' + '\n'.join(intro) + '\n' + body + '\n' + '\n'.join(closing), encoding='utf-8')
    # WCM uses section indexes as navigation metadata. Keep those with children,
    # but explicitly mark empty ones as navigation-only, not publishable pages.
    # Remove empty leaf sections completely.
    for folder in sorted([product_folder, *product_folder.rglob('*')], key=lambda path: len(path.parts), reverse=True):
        if not folder.is_dir():
            continue
        indexes = list(folder.glob('*_Index_NL.md'))
        if len(indexes) != 1:
            continue
        index_file = indexes[0]
        existing = index_file.read_text(encoding='utf-8')
        front_end = existing.find('\n---\n', 4)
        if front_end < 0:
            raise ValueError(f'Invalid index front matter: {index_file}')
        body = existing[front_end + len('\n---\n'):]
        if body.strip():
            continue
        # Child index-only sections previously removed will not count.
        has_descendants = any(child.is_file() and child.suffix == '.md' and child != index_file
                              for child in folder.rglob('*.md'))
        if has_descendants:
            index_file.write_text(existing[:front_end] + '\nnav_only: true' + existing[front_end:], encoding='utf-8')
        else:
            index_file.unlink()
            if folder != product_folder:
                folder.rmdir()
    return len(paths)




def _product_reference_files(source: Path, name: str) -> list[Path]:
    """Only authored repository documents; never generated caches or website output."""
    candidates = [source / name, source / 'usr/local/share/doc-sources' / name,
                  source / 'target-root/usr/local/share/doc-sources' / name]
    if name == 'LICENSE':
        candidates += [source / 'usr/local/share/testadura/solidgroundux/LICENSE',
                       source / 'target-root/usr/local/share/testadura/solidgroundux/LICENSE']
    return [candidate for candidate in candidates if candidate.is_file()]


def build_appendices(products: list[dict], content: Path, root: Path) -> dict:
    """Build one bundle-level reference index from the actually published pages."""
    appendix = content / 'appendices'
    entries = []
    variables = []
    for product in products:
        product_dir = content / slug(product['id'])
        for source_page in product_dir.rglob('*_Index_NL.md'):
            if source_page.parent == product_dir:
                continue
            text = source_page.read_text(encoding='utf-8')
            if not re.search(r'^template: "source"$', text, re.M):
                continue
            match = re.search(r'^\*\*Source:\*\* `([^`]+)`', text, re.M)
            if not match:
                continue
            src = match.group(1)
            source_path = Path(product['source_dir']).expanduser().resolve() / src
            if not source_path.is_file():
                continue
            meta, declarations, _ = parse_source(source_path)
            route = '/' + source_page.parent.relative_to(content).as_posix() + '/'
            for item in declarations:
                name = item['name']
                if not name or name.startswith('_'):
                    continue
                if item['kind'].startswith('fn'):
                    target = source_page.parent / f'{slug(name)}_NL.md'
                    if not target.is_file():
                        continue
                    entries.append({'name': name, 'description': item['title'] if item['title'] != name else '',
                                    'product': product['title'], 'source': src,
                                    'url': route + slug(name) + '/'})
                elif item['kind'] == 'var':
                    variables.append({'name': name, 'description': item['title'] if item['title'] != name else '',
                                      'product': product['title'], 'source': src, 'url': route})
    entries.sort(key=lambda row: (row['name'].casefold(), row['product'].casefold(), row['source']))
    variables.sort(key=lambda row: (row['name'].casefold(), row['product'].casefold(), row['source']))
    write_index(appendix, 'Appendices', '', 9999, template='group')
    index = appendix / 'api-index'
    write_index(index, 'API Index & Search', f'Search {len(entries)} documented public functions across the bundle.', 1, template='api-index')
    (root / 'assets' / 'sgnd-api-index.json').write_text(json.dumps(entries, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    if variables:
        sections = ['The following documented public variables are declared in the bundle.', '', '| Variable | Description | Product | Source |', '| --- | --- | --- | --- |']
        for row in variables:
            description = row['description'].replace('|', r'\|')
            sections.append(f'| [`{row["name"]}`]({row["url"]}) | {description} | {row["product"]} | `{row["source"]}` |')
        write_index(appendix / 'global-variables', 'Global Variables', '\n'.join(sections), 2, template='page')
    license_lines = []
    attribution_lines = []
    for product in products:
        source = Path(product['source_dir']).expanduser().resolve()
        license_files = _product_reference_files(source, 'LICENSE')
        if license_files:
            document = license_files[0].read_text(encoding='utf-8', errors='replace').strip()
            if document:
                license_lines.extend(['## ' + product['title'], '',
                                      f'**Source:** `{license_files[0].relative_to(source)}`', ''])
                license_lines.extend('> ' + line if line.strip() else '>' for line in document.splitlines())
                license_lines.append('')
        identities = set()
        for path in source.rglob('*.sh'):
            if any(part in SKIP_DIRS for part in path.relative_to(source).parts):
                continue
            for line in path.read_text(encoding='utf-8', errors='replace').splitlines()[:100]:
                match = re.match(r'^#\s*(Developers?|Company|Copyright)\s*:\s*(.*?)\s*$', line, re.I)
                if match and match.group(2) and match.group(2) != '-':
                    identities.add((match.group(1).casefold(), match.group(2)))
        if identities:
            attribution_lines += ['## ' + product['title'], '']
            attribution_lines.extend(f'- **{field.title()}:** {value}' for field, value in sorted(identities))
            attribution_lines.append('')
    if license_lines:
        write_index(appendix / 'licenses', 'Licenses', '\n'.join(license_lines), 3, template='page')

    # Each product owns its changelog. Keep a stable navigation page for every
    # product, even when its configured source tree does not include CHANGELOG.md.
    # This avoids silently merging releases or hiding an absent changelog.
    change_logs = appendix / 'change-logs'
    write_index(change_logs, 'Change Logs',
                'Release history for each product in this documentation bundle.',
                4, template='group')
    available_change_logs = 0
    for order, product in enumerate(products, 1):
        source = Path(product['source_dir']).expanduser().resolve()
        files = _product_reference_files(source, 'CHANGELOG.md')
        document = files[0].read_text(encoding='utf-8', errors='replace').strip() if files else ''
        if document:
            body = f'**Source:** `{files[0].relative_to(source)}`\n\n{document}'
            available_change_logs += 1
        else:
            body = 'No `CHANGELOG.md` was found in this product\'s configured source tree.'
        write_index(change_logs / slug(product['id']), product['title'], body,
                    order, template='page')

    if attribution_lines:
        write_index(appendix / 'attribution', 'Attribution', '\n'.join(attribution_lines), 5, template='page')
    return {'api_functions': len(entries), 'global_variables': len(variables),
            'licenses': bool(license_lines), 'change_logs': bool(available_change_logs),
            'attribution': bool(attribution_lines)}


def split_wcm_document(markdown: str) -> tuple[dict[str, str], str]:
    """Separate a WCM document's leading YAML metadata from its Markdown body.

    WCM page metadata belongs to the document, not the body that is promoted
    into another page. Do not interpret ordinary Markdown rules as metadata.
    """
    normalized = markdown.lstrip('\ufeff').replace('\r\n', '\n').replace('\r', '\n')
    lines = normalized.splitlines(keepends=True)
    metadata: dict[str, str] = {}
    if not lines or lines[0].strip() != '---':
        return metadata, normalized
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
    except StopIteration:
        return {}, normalized
    for line in lines[1:end]:
        match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$', line.rstrip('\n'))
        if not match:
            # A leading horizontal rule is valid Markdown, not necessarily YAML.
            return {}, normalized
        metadata[match.group(1)] = match.group(2)
    if not {'title', 'template', 'content_type'}.intersection(metadata):
        return {}, normalized
    return metadata, ''.join(lines[end + 1:])


def chapter0_body(markdown: str) -> str:
    """Return just the body of a promoted WCM page.

    Older generated introductions may already contain a *second* WCM page
    embedded after a logo. Consume that nested document boundary explicitly,
    rather than deleting arbitrary text that resembles YAML fields.
    """
    _, body = split_wcm_document(markdown)
    lines = body.splitlines(keepends=True)
    result: list[str] = []
    cursor = 0
    while cursor < len(lines):
        if lines[cursor].strip() == '---':
            # The second front matter has the same documented WCM page shape,
            # but may be located after an image/introductory content.
            nested_metadata, nested_body = split_wcm_document(''.join(lines[cursor:]))
            if nested_metadata:
                result.append(nested_body)
                break
        result.append(lines[cursor])
        cursor += 1
    return ''.join(result).strip()


def generated_chapter0_path(content: Path, reference: str, origin: str = '') -> Path | None:
    """Resolve a logical generated page, migrating old absolute output references.

    External authored Markdown is deliberately not interpreted as a generated
    route. A retained snapshot with an original generated path is migrated.
    """
    selected = reference
    if origin and '/content/' in origin:
        selected = origin
    if selected.startswith('content/'):
        relative = Path(selected[len('content/'):])
    elif '/content/' in selected:
        relative = Path(selected.rsplit('/content/', 1)[1])
    else:
        return None
    if relative.is_absolute() or '..' in relative.parts or relative.suffix.lower() != '.md':
        raise ValueError(f'Invalid generated Chapter 0 route: {reference}')
    target = (content / relative).resolve()
    if not target.is_relative_to(content.resolve()):
        raise ValueError(f'Invalid generated Chapter 0 route: {reference}')
    return target


def exclude_chapter0(content: Path, target: Path) -> None:
    """Promote exactly one generated page, removing its normal navigation entry."""
    target.unlink()
    folder = target.parent
    while folder != content and folder.is_dir() and not any(folder.iterdir()):
        folder.rmdir()
        folder = folder.parent


def rewrite_chapter0_links(content: Path, old_page: Path) -> None:
    """Retarget absolute links to a promoted page to its Introduction route."""
    relative = old_page.relative_to(content)
    parts = list(relative.parts)
    filename = parts.pop()
    stem = filename.removesuffix('_Index_NL.md') if filename.endswith('_Index_NL.md') else filename.removesuffix('_NL.md')
    routes = {'/' + '/'.join(parts + [stem]).strip('/') + '/'}
    if filename.endswith('_Index_NL.md'):
        routes.add('/' + '/'.join(parts).strip('/') + '/')
    for file in content.rglob('*.md'):
        text = file.read_text(encoding='utf-8')
        original = text
        for route in routes:
            text = text.replace('](' + route + ')', '](/introduction/)')
            text = text.replace('](' + route + '#', '](/introduction/#')
        if text != original:
            file.write_text(text, encoding='utf-8')


def generate(bundle: dict, docs_root: Path | None = None) -> dict:
    output = Path(bundle['output_dir']).expanduser().resolve()
    if not output.is_absolute() or output == Path('/'):
        raise ValueError('Invalid output directory')
    products = bundle.get('products', [])
    if len({slug(item['id']) for item in products}) != len(products):
        raise ValueError('Product identifiers generate duplicate routes')
    if not products:
        raise ValueError('Bundle has no products')
    for product in products:
        src = Path(product['source_dir']).expanduser().resolve()
        if not src.is_dir():
            raise ValueError(f'Missing source directory: {src}')
        if output == src or src in output.parents:
            raise ValueError('Output directory must not be within a source directory')
    if bundle.get('overwrite', 'replace') not in ('fail', 'replace'):
        raise ValueError('Overwrite policy must be fail or replace')
    if output.exists() and bundle.get('overwrite', 'replace') == 'fail':
        raise ValueError(f'Output already exists: {output}')
    # Generate away from the final directory so a failure leaves the previous site intact.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='sgnd-doc-') as staging:
        root = Path(staging) / 'website'
        content = root / 'content'
        (root / 'config').mkdir(parents=True)
        (root / 'assets').mkdir()
        (root / 'images').mkdir()
        (root / 'css').mkdir()
        (root / 'templates').mkdir()
        (root / 'config' / 'site.cfg').write_text(
            f'[site]\ntitle = {bundle.get("title", bundle["id"])}\ndefault_language = NL\n'
            '[paths]\ncontent = content\ntemplates = templates\ncss = css\nimages = images\n', encoding='utf-8')
        counts = Counter()
        counts['products'] = len(products)
        template_owners = build_template_owners(products)
        # Reserve the first top-level navigation position for an optional Chapter 0.
        chapter0 = bundle.get('chapter0', '')
        for i, product in enumerate(products, 2 if chapter0 else 1):
            collect(product, content, i, counts, template_owners)
        counts.update(build_appendices(products, content, root))
        # Images referenced by comments belong to each product source tree.
        # Keep /assets/... links valid without depending on an external website.
        for product in products:
            copy_legacy_images(Path(product['source_dir']).expanduser().resolve(), root)
            asset_dir = Path(product['source_dir']).expanduser().resolve() / 'assets'
            copy_assets_checked(asset_dir, root / 'assets')
        # The home/title page is independent of Chapter 0. It always displays
        # the bundle metrics; the home template supplies its established branding.
        metrics = ('\n'.join(f'- **{label}:** {counts.get(key, 0)}' for label, key in
                             [('Products', 'products'), ('Source files', 'files'),
                              ('Functions', 'functions'), ('Declarations', 'declarations'),
                              ('Lines of code and comments', 'lines')]))
        for key in ('version', 'build'):
            if counts.get(key):
                metrics += f'\n- **{key.title()}:** {counts[key]}'
        write_index(content, bundle.get('title', bundle['id']), metrics, 0, template='home')

        if chapter0:
            generated = generated_chapter0_path(content, chapter0, bundle.get('chapter0_origin', ''))
            if generated is not None:
                if not generated.is_file():
                    raise ValueError(f'Generated Chapter 0 route not found in this build: {generated.relative_to(content)}')
                intro = chapter0_body(generated.read_text(encoding='utf-8'))
            else:
                custom = Path(chapter0).expanduser().resolve()
                if not custom.is_file():
                    raise ValueError(f'External Chapter 0 Markdown missing: {custom}')
                intro = chapter0_body(custom.read_text(encoding='utf-8'))
            if not intro:
                raise ValueError('Chapter 0 Markdown contains no page body')
            if generated is not None:
                rewrite_chapter0_links(content, generated)
                exclude_chapter0(content, generated)
            write_index(content / 'introduction', 'Introduction', intro, 1, template='page')
        # Bundle defaults are supplied by the SDK documentation resources.
        # Product resources are scoped to their chapter; no product can overwrite
        # another chapter's templates or the bundle-wide defaults.
        if docs_root:
            for resource in ('assets', 'css', 'templates', 'images', 'js'):
                if (docs_root / resource).is_dir():
                    if resource in ('assets', 'images'):
                        copy_assets_checked(docs_root / resource, root / resource)
                    else:
                        shutil.copytree(docs_root / resource, root / resource, dirs_exist_ok=True)
        # Publish the existing branding logos in WCM's configured images folder.
        if docs_root:
            for logo_name in ('doc-index-logo.png', 'doc-header-logo.png', 'favicon.png'):
                logo_source = docs_root / 'assets' / logo_name
                if logo_source.is_file():
                    shutil.copy2(logo_source, root / 'images' / logo_name)
        for product in products:
            source_root = Path(product['source_dir']).expanduser().resolve()
            chapter = slug(product['id'])
            for candidate in (source_root / 'doc-sources', source_root / 'usr/local/share/doc-sources',
                              source_root / 'target-root/usr/local/share/doc-sources'):
                if not candidate.is_dir():
                    continue
                custom_templates = candidate / 'templates'
                if custom_templates.is_dir():
                    shutil.copytree(custom_templates, root / 'templates' / chapter, dirs_exist_ok=True)
                for resource in ('assets', 'css', 'images'):
                    if (candidate / resource).is_dir():
                        if resource in ('assets', 'images'):
                            copy_assets_checked(candidate / resource, root / resource)
                        else:
                            shutil.copytree(candidate / resource, root / resource, dirs_exist_ok=True)
        required = ('base.html', 'home.html', 'page.html', 'article.html')
        missing = [name for name in required if not (root / 'templates' / name).is_file()]
        if missing:
            raise ValueError('Missing default documentation templates in doc-sources/templates: ' + ', '.join(missing))
        image_warnings = missing_image_references(root)
        if output.exists():
            shutil.rmtree(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(root), str(output))
    return {'bundle': bundle['id'], 'output': str(output), **counts, 'missing_images': len(image_warnings), 'image_warnings': image_warnings}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', help='Saved bundle identifier')
    parser.add_argument('--store', default=str(Path.home() / '.config/solidgroundux/documentation-bundles'))
    parser.add_argument('--doc-sources', help='Optional documentation resources directory')
    args = parser.parse_args()
    try:
        name = args.bundle.replace(' ', '-')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name):
            raise ValueError('Invalid bundle identifier')
        data = json.loads((Path(args.store) / (name + '.json')).read_text(encoding='utf-8'))
        if data.get('id') != name or data.get('schema') != 1:
            raise ValueError('Invalid saved bundle')
        print(json.dumps(generate(data, Path(args.doc_sources) if args.doc_sources else None), ensure_ascii=False, indent=2, default=str))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
