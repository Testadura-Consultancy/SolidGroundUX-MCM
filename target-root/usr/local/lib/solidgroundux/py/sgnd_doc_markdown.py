#!/usr/bin/env python3
"""Generate a WCM Markdown source repository from a saved documentation bundle.

This generator does not import or alter WCM. It emits its documented source layout.
"""
from __future__ import annotations

import argparse
import ast
import inspect
import io
import tokenize
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




# --- Internal functions ------------------------------------------------------------
def source_files(root: Path) -> list[Path]:
    """Find supported source languages without crawling build or cache folders.
    
    Usage:
        ```python
        for path in source_files(source_root):
            print(path)
        ```"""
    return sorted((p for p in root.rglob('*') if p.is_file()
                   and p.suffix.lower() in ('.sh', '.py')
                   and not any(part in SKIP_DIRS for part in p.relative_to(root).parts)),
                  key=lambda p: p.as_posix())


def source_line_counts(path: Path) -> tuple[int, int]:
    """Return non-overlapping physical code/comment lines (blank lines excluded).
    
    Python docstrings are counted as documentation, not executable code.
    Inline comments remain part of the code line rather than being double-counted.
    
    Usage:
        ```python
        code_lines, comment_lines = source_line_counts(source_file)
        ```"""
    source = path.read_text(encoding='utf-8', errors='replace')
    lines = source.splitlines()
    if path.suffix.lower() == '.sh':
        code = sum(bool(line.strip()) and not line.lstrip().startswith('#') for line in lines)
        comments = sum(line.lstrip().startswith('#') for line in lines)
        return code, comments
    tree = ast.parse(source, filename=str(path))
    doc_lines: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                doc_lines.update(range(first.lineno, first.end_lineno + 1))
    code_lines: set[int] = set()
    comment_lines: set[int] = set(doc_lines)
    ignored = {tokenize.ENDMARKER, tokenize.ENCODING, tokenize.INDENT,
               tokenize.DEDENT, tokenize.NL, tokenize.NEWLINE}
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.COMMENT:
            comment_lines.add(token.start[0])
        elif token.type not in ignored:
            is_docstring = token.type == tokenize.STRING and all(
                line in doc_lines for line in range(token.start[0], token.end[0] + 1))
            if not is_docstring:
                code_lines.update(range(token.start[0], token.end[0] + 1))
    return len(code_lines), len(comment_lines - code_lines)


PY_SECTION = re.compile(r'^(Args|Arguments|Parameters|Returns|Raises|Yields|Examples|Usage|Notes|Attributes):\s*$', re.I)
PY_FIELD = re.compile(r'^\s*([*]{0,2}[A-Za-z_][A-Za-z_0-9]*)(?:\s*\([^)]*\))?:\s*(.*)$')
PY_API_SECTION = re.compile(r'^\s*#\s*-{1,3}\s*(Public|Internal)\s+(?:functions|classes|api|declarations)\b', re.I)
PY_API_DIRECT = re.compile(r'^\s*#\s*(?:API|Visibility)\s*:\s*(Public|Internal)\s*$', re.I)


def python_doc_markdown(doc: str, purpose: str) -> list[str]:
    """Render native Python docstrings into readable Markdown sections and lists.
    
    Usage:
        ```python
        python_doc_markdown(doc, purpose)
        ```"""
    if not doc.strip():
        return []
    lines = inspect.cleandoc(doc).splitlines()
    summary = []
    cursor = 0
    while cursor < len(lines) and lines[cursor].strip() and not PY_SECTION.match(lines[cursor].strip()):
        summary.append(lines[cursor].strip())
        cursor += 1
    result: list[str] = []
    description = ' '.join(summary).strip()
    if description and description.rstrip('.') != purpose.rstrip('.'):
        result.extend(['### Description', '', description, ''])
    section = ''
    fence = ''
    fence_indent = 0
    while cursor < len(lines):
        raw = lines[cursor]
        stripped = raw.strip()
        section_match = PY_SECTION.match(stripped) if not fence else None
        if section_match:
            section = section_match.group(1).lower()
            label = {'args': 'Arguments', 'parameters': 'Arguments',
                     'examples': 'Usage'}.get(section, section.title())
            result.extend(['', '### ' + label, ''])
        elif stripped.startswith(('```', '~~~')):
            if not fence:
                fence = stripped[:3]
                fence_indent = len(raw) - len(raw.lstrip())
            elif stripped.startswith(fence):
                fence = ''
                fence_indent = 0
            result.append(stripped)
        elif not stripped:
            result.append('')
        elif section in ('args', 'arguments', 'parameters', 'attributes', 'raises') and not fence:
            match = PY_FIELD.match(raw)
            if match:
                result.append(f'- **{match.group(1)}:** {match.group(2)}')
            elif result and result[-1].startswith('- '):
                result[-1] += ' ' + stripped
            else:
                result.append(stripped)
        elif section in ('returns', 'yields', 'notes') and not fence:
            # Google-style docstrings indent the field values; retaining that
            # indent would turn prose into an unintended Markdown code block.
            result.append(stripped)
        else:
            result.append(raw[fence_indent:] if fence and raw.startswith(' ' * fence_indent) else (raw if fence else stripped))
        cursor += 1
    return result


def parse_python_source(path: Path):
    """Discover Python functions/classes via AST and document their native docstrings.
    
    Comment markers supply optional descriptions; they do not define API shape.
    Parsing is static: the source is never imported or executed.
    
    Usage:
        ```python
        parse_python_source(path)
        ```"""
    source = path.read_text(encoding='utf-8', errors='replace')
    raw = source.splitlines()
    tree = ast.parse(source, filename=str(path))
    meta: dict[str, str] = {'group': 'Python Modules', 'type': 'module',
                            'title': path.stem.replace('_', ' ').title()}
    for line in raw[:100]:
        match = META.match(line)
        if match:
            meta[match.group(1).lower()] = match.group(2).strip()
    # Preserve Python package boundaries in navigation. A source within a
    # package (identified by __init__.py) appears below that package's own
    # subsection, rather than flattening the entire Python tree into one list.
    # Explicit source metadata always takes precedence.
    if not meta.get('subgroup') and meta.get('group') == 'Python Modules':
        package_root = None
        directory = path.parent
        while (directory / '__init__.py').is_file():
            package_root = directory
            directory = directory.parent
        if package_root is not None:
            meta['subgroup'] = package_root.name
    module_doc = ast.get_docstring(tree, clean=True) or ''
    if module_doc and not meta.get('purpose'):
        meta['purpose'] = module_doc.splitlines()[0].strip()
    entries: list[dict] = []
    if module_doc:
        narrative = python_doc_markdown(module_doc, meta.get('purpose', ''))
        if narrative:
            entries.append({'kind': 'narrative', 'name': '', 'title': '', 'lines': narrative})

    def marker_for(node: ast.AST, expected: str) -> str:
        """Find an adjacent documentation marker for a Python definition.
                
                Usage:
                    ```python
                    marker_for(node, expected)
                    ```"""
        first_line = min([getattr(decorator, 'lineno', node.lineno)
                          for decorator in getattr(node, 'decorator_list', [])]
                         or [node.lineno])
        previous = first_line - 2
        # A marker can be followed by a longer '# . Description' block.
        # Walk only the adjacent comment block; never attach earlier symbols.
        blank_allowed = 1
        while previous >= 0:
            line = raw[previous]
            if not line.strip() and blank_allowed:
                blank_allowed -= 1
                previous -= 1
                continue
            if not line.lstrip().startswith('#'):
                break
            match = DECL.match(line)
            if match:
                if match.group(1) == expected:
                    return (match.group(4) or '').strip()
                break
            previous -= 1
        return ''

    def walk(statements: list[ast.stmt], parents: tuple[str, ...] = (),
             accessible: bool = True, nested: bool = False,
             initial_line: int = 0) -> None:
        """Collect Python functions, classes, and documented variables from the syntax tree.
                
                Usage:
                    ```python
                    walk(statements, parents, accessible, nested)
                    ```"""
        # Section annotations classify the API without renaming or moving functions.
        # Adjacent '# API: Public/Internal' can override a section for one symbol.
        # Unannotated definitions retain the conventional underscore fallback.
        section_visibility = None
        previous_end = initial_line
        for node in statements:
            declaration_line = min([decorator.lineno for decorator in getattr(node, 'decorator_list', [])]
                                   or [getattr(node, 'lineno', previous_end + 1)])
            direct_visibility = None
            for line in raw[previous_end:declaration_line - 1]:
                section = PY_API_SECTION.match(line)
                explicit = PY_API_DIRECT.match(line)
                if section:
                    section_visibility = section.group(1).lower()
                if explicit:
                    direct_visibility = explicit.group(1).lower()
            previous_end = getattr(node, 'end_lineno', declaration_line)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                is_class = isinstance(node, ast.ClassDef)
                kind = 'cls' if is_class else 'fn'
                name = '.'.join((*parents, node.name))
                visibility = direct_visibility or section_visibility
                public = accessible and not nested and (visibility == 'public' or
                            (visibility is None and not node.name.startswith('_')))
                doc = ast.get_docstring(node, clean=True) or ''
                annotated = marker_for(node, kind)
                summary = doc.splitlines()[0].strip() if doc else ''
                purpose = annotated or summary or 'No purpose documented in source.'
                details = ['### Purpose', '', purpose, '']
                if not is_class:
                    args = ast.unparse(node.args)
                    returns = ' -> ' + ast.unparse(node.returns) if node.returns else ''
                    prefix = 'async def' if isinstance(node, ast.AsyncFunctionDef) else 'def'
                    details += ['### Signature', '', '```python',
                                f'{prefix} {node.name}({args}){returns}:', '```', '']
                details.extend(python_doc_markdown(doc, purpose))
                entries.append({'kind': kind, 'name': name, 'title': name,
                                'lines': details, 'public': public})
                walk(node.body, (*parents, node.name), public,
                     nested or not is_class, node.lineno)
            # Include explicitly documented Python module/class variables.
            elif isinstance(node, (ast.Assign, ast.AnnAssign)) and not nested:
                name_node = node.target if isinstance(node, ast.AnnAssign) else (node.targets[0] if len(node.targets) == 1 else None)
                if isinstance(name_node, ast.Name):
                    label = marker_for(node, 'var')
                    if label:
                        name = '.'.join((*parents, name_node.id))
                        entries.append({'kind': 'var', 'name': name, 'title': name,
                                        'lines': ['### Purpose', '', label],
                                        'public': accessible and not name_node.id.startswith('_')})
    walk(tree.body)
    return meta, entries, len(raw)


def parse_documented_source(path: Path):
    """Parse a Bash or Python source file using the matching documentation parser.
    
    Usage:
        ```python
        metadata, entries, total_lines = parse_documented_source(source_file)
        ```"""
    return parse_python_source(path) if path.suffix.lower() == '.py' else parse_source(path)



def slug(value: str) -> str:
    """Convert a label into a stable lowercase hyphenated route component.
    
    Usage:
        ```python
        slug("Active Directory Server")  # active-directory-server
        ```"""
    return IDENTITY.sub('-', value.lower()).strip('-') or 'untitled'


def is_template_source(rel: Path, metadata: dict, path: Path) -> bool:
    """Identify a source file that declares or lives in a template directory.
    
    Usage:
        ```python
        is_template_source(rel, metadata, path)
        ```"""
    if metadata.get('type', '').strip().casefold() == 'template':
        return True
    parts = tuple(part.casefold() for part in rel.parts[:-1])
    return path.stem.casefold().endswith('-template') and any(part in ('templates', 'convenience-templates') for part in parts)


def template_priority(product_id: str, rel: Path) -> tuple:
    """Rank template candidates by product, location, and path for deduplication.
    
    Usage:
        ```python
        template_priority(product_id, rel)
        ```"""
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
    """Select the authoritative owner for each shared shell template name.
    
    Usage:
        ```python
        build_template_owners(products)
        ```"""
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
    
    Usage:
        ```python
        prune_empty_headings(lines)
        ```"""
    markdown_heading = re.compile(r'^(#{2,6})\s+')
    # The older generator emitted a heading=N component option. The current
    # WCM renderer treats that text as part of the visible disclosure title.
    # Recognize both styles as document boundaries while emitting only the
    # supported human-readable titles for newly generated pages.
    details_heading = re.compile(
        r'^:::\s+td-details\s+(?:heading=([2-6])\s+)?(?:open\s+)?'
        r'(?:Internal (?:functions|classes)|Script metadata)\b', re.I)
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
        boundaries.append(int(match.group(1) or 2) if match else None)

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


def front(title: str, order: int = 1000, summary: str = '', *, section: bool = True, template: str = 'page', nav_title: str | None = None, nav_parent: str | None = None) -> str:
    """Build YAML front matter for a generated Markdown page.
    
    Usage:
        ```python
        front(title, order, summary, section=section, template=template, nav_title=nav_title)
        ```"""
    values = {'title': title, 'nav_title': title if nav_title is None else nav_title, 'summary': summary, 'template': template,
              'content_type': 'section' if section else 'page', 'nav_order': order,
              'draft': False, 'featured': False}
    if nav_parent is not None:
        values['nav_parent'] = nav_parent
    return '---\n' + '\n'.join(f'{key}: {json.dumps(value, ensure_ascii=False)}' if isinstance(value, str)
                              else f'{key}: {str(value).lower() if isinstance(value, bool) else value}'
                              for key, value in values.items()) + '\n---\n\n'


def write_index(folder: Path, title: str, body: str, order: int = 1000, summary: str = '', template: str = 'page', *, nav_title: str | None = None, nav_parent: str | None = None) -> None:
    """Write a descriptive Markdown index and its front matter to a section directory.
    
    Usage:
        ```python
        write_index(folder, title, body, order, summary, template, nav_title=nav_title)
        ```"""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f'{slug(title)}_Index_NL.md').write_text(front(title, order, summary, template=template, nav_title=nav_title, nav_parent=nav_parent) + body.strip() + '\n', encoding='utf-8')


def _section_marker(text: str, inside_item: bool, in_fence: bool):
    """Recognize old section headers, but never reinterpret Markdown lists.
    
    Usage:
        ```python
        _section_marker(text, inside_item, in_fence)
        ```"""
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
    """Extract documented items and Markdown while preserving source comment blocks.
    
    Usage:
        ```python
        parse_source(path)
        ```"""
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
        """Convert one legacy source heading into a Markdown line.
                
                Usage:
                    ```python
                    header_line(text)
                    ```"""
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
    """Translate legacy Images blocks, preserving all other Markdown lines.
    
    Usage:
        ```python
        markdown_documentation(lines)
        ```"""
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
                # Keep the authored description as an explicit caption. The
                # bundle-wide numbering pass assigns a figure number after all
                # pages have been written, in their published navigation order.
                image = f'![{alt}]({url})'
                if caption and caption.strip():
                    image += '{caption=' + json.dumps(caption.strip(), ensure_ascii=False) + '}'
                images.append(image)
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
    
    Usage:
        ```python
        script_metadata_markdown(lines)
        ```"""
    import textwrap

    result: list[str] = []
    literal: list[str] = []
    author_fence = False
    in_explanation = False

    def close_explanation() -> None:
        """Close the current explanation block before emitting the next declaration.
                
                Usage:
                    ```python
                    close_explanation()
                    ```"""
        nonlocal in_explanation
        if in_explanation:
            result.extend(["", ":::", ""])
            in_explanation = False

    def flush_literal() -> None:
        """Flush buffered literal content to the output Markdown stream.
                
                Usage:
                    ```python
                    flush_literal()
                    ```"""
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
    """Escape table delimiters without interpreting shell syntax.
    
    Usage:
        ```python
        _def_cell(value)
        ```"""
    return value.strip().replace('\\', '\\\\').replace('|', '\\|').replace('\n', '<br>')


def _def_literal(value: str) -> str:
    """Unquote a literal assignment value for the definition table.
    
    Usage:
        ```python
        _def_literal(value)
        ```"""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def _def_assignments(lines: list[str]) -> list[tuple[str, str, str, list[str] | None]]:
    """Read literal assignments, including multiline Bash arrays, without evaluation.
    
    Usage:
        ```python
        _def_assignments(lines)
        ```"""
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
    
    Usage:
        ```python
        definition_markdown(entry)
        ```"""
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
    """Append authored preface or epilogue entries to a section in order.
    
    Usage:
        ```python
        append_preface(target, entries)
        ```"""
    for entry in entries:
        if entry['kind'] == 'section':
            target.extend([SCRIPT_SECTION_HEADING + entry['title'], ''])
        elif entry['kind'] not in ('narrative',):
            target.extend(['### ' + entry['title'], ''])
        target.extend(markdown_documentation(entry['lines']))
        target.append('')


def copy_legacy_images(source: Path, root: Path) -> None:
    """Use the original product asset location and the existing doc-sources locations.
    
    Usage:
        ```python
        copy_legacy_images(source, root)
        ```"""
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
    """Merge resource trees without silently replacing different files.
    
    Usage:
        ```python
        copy_assets_checked(source, destination)
        ```"""
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
    """Report unresolved local Markdown images without rejecting documentary examples.
    
    Usage:
        ```python
        missing_image_references(root)
        ```"""
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
    """Select the generated page template for a declaration kind.
    
    Usage:
        ```python
        declaration_template(kind)
        ```"""
    if kind.startswith('fn'):
        return 'function'
    if kind == 'var':
        return 'variable'
    if kind == 'cls':
        return 'class'
    return 'declaration'


def source_document_template(filename: str) -> str:
    """Classify a source file as a preface, epilogue, or regular page.
    
    Usage:
        ```python
        source_document_template(filename)
        ```"""
    name = filename.casefold().replace('_', '-')
    if 'preface' in name:
        return 'preface'
    if 'epilogue' in name:
        return 'epilogue'
    return 'source'

def directory_title(path: Path):
    """Derive a readable title from a directory name.
    
    Usage:
        ```python
        directory_title(path)
        ```"""
    return path.name.replace('-', ' ').replace('_', ' ').strip().title()


def collect(product, content: Path, order: int, counters: Counter, template_owners: dict[str, tuple[str, str]], excluded_sources: set[Path] | None = None):
    """Use source metadata Group/Subgroup, never installation directories, for navigation.
    
    Usage:
        ```python
        collect(product, content, order, counters, template_owners)
        ```"""
    source = Path(product['source_dir']).expanduser().resolve()
    if not source.is_dir():
        raise ValueError(f'Missing source directory: {source}')
    product_folder = content / slug(product['id'])
    write_index(product_folder, product['title'], '', order, template='chapter')
    paths = [path for path in source_files(source)
             if path.resolve() not in (excluded_sources or set())]
    records = []
    for path in paths:
        metadata, entries, loc = parse_documented_source(path)
        records.append((path, metadata, entries, loc))
    # Every preface and epilogue is an independent page in its own section:
    # prefaces before ordinary children, epilogues after every ordinary child.
    grouped_records = []
    product_specials = []
    for path, metadata, entries, loc in records:
        language = 'python' if path.suffix.lower() == '.py' else 'bash'
        code, comments = source_line_counts(path)
        counters[f'{language}_files'] += 1
        counters[f'{language}_code_lines'] += code
        counters[f'{language}_comment_lines'] += comments
        counters['files'] += 1
        counters['code_lines'] += code
        counters['comment_lines'] += comments
        counters['lines'] += code + comments
        special = source_document_template(path.name)
        purpose = metadata.get('purpose', '').strip().casefold()
        if special in ('preface', 'epilogue') and purpose == f'product {special}':
            product_specials.append((special, path, metadata))
        else:
            grouped_records.append((path, metadata, entries, loc))
    # Group: / deliberately places a source at the product root, without adding a
    # redundant group level. All other Group/Subgroup values retain their meaning.
    groups = sorted({metadata.get('group', '').strip() or 'Ungrouped' for _, metadata, _, _ in grouped_records}
                    - {'/'}, key=str.casefold)
    if any(metadata.get('group', '').strip() == '/' for _, metadata, _, _ in grouped_records):
        groups.insert(0, '/')
    route_names = set()
    special_pages: dict[Path, dict[str, list[tuple[Path, dict]]]] = {}
    for special, path, metadata in product_specials:
        special_pages.setdefault(product_folder, {'preface': [], 'epilogue': []})[special].append((path, metadata))
    for group_index, group in enumerate(groups, 1):
        group_folder = product_folder if group == '/' else product_folder / slug(group)
        if group != '/':
            # Reserve low chapter navigation orders for authored prefaces and
            # root-level source pages, as in the previous metadata fix.
            write_index(group_folder, group, '', 200 + group_index, template='group')
        group_records = [r for r in grouped_records if (r[1].get('group', '').strip() or 'Ungrouped') == group]
        subgroup_names = {r[1].get('subgroup', '').strip() for r in group_records if r[1].get('subgroup', '').strip()}
        # Numbered console modules define their operator-facing order. Keep the
        # associated role managers in the same subsection without alphabetizing
        # the module categories away from their established registration order.
        subgroup_order = {}
        if group == 'Modules':
            for path, metadata, _, _ in group_records:
                subgroup = metadata.get('subgroup', '').strip()
                match = re.match(r'^(\d+)-', path.name)
                if subgroup and match and metadata.get('type', '').strip().lower() == 'module':
                    subgroup_order[subgroup] = min(subgroup_order.get(subgroup, 1000), int(match.group(1)))
        subgroup_names = sorted(subgroup_names, key=lambda name: (subgroup_order.get(name, 1000), name.casefold()))
        for subgroup_index, subgroup in enumerate(subgroup_names, 1):
            subfolder = group_folder / slug(subgroup)
            write_index(subfolder, subgroup, '', subgroup_index, template='group')
        for path, metadata, entries, loc in group_records:
            subgroup = metadata.get('subgroup', '').strip()
            parent = group_folder / slug(subgroup) if subgroup else group_folder
            rel = path.relative_to(source)
            # Defer section prefaces/epilogues until their siblings are known.
            # Page prefaces are already separate child pages in the source flow.
            special = source_document_template(path.name)
            page_preface = (special == 'preface' and
                            metadata.get('purpose', '').strip().casefold() == 'page preface')
            if special in ('preface', 'epilogue') and not page_preface:
                section_folder = parent
                special_pages.setdefault(section_folder, {'preface': [], 'epilogue': []})[special].append((path, metadata))
                continue
            # Keep one source document per file, with anchored public declarations.
            basename = slug(path.stem)
            source_folder = parent / basename
            if source_folder in route_names:
                source_folder = parent / slug(f'{rel.with_suffix("").as_posix()}-{path.suffix[1:]}')
            if source_folder in route_names or source_folder.exists():
                raise ValueError(f'Route collision: {rel} -> {source_folder}')
            route_names.add(source_folder)
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
            language = 'python' if path.suffix.lower() == '.py' else 'bash'
            function_count = sum(e['kind'].startswith('fn') for e in documented)
            declaration_count = sum(e['kind'] not in ('section', 'narrative') for e in documented)
            counters['functions'] += function_count
            counters['declarations'] += declaration_count
            counters[f'{language}_functions'] += function_count
            counters[f'{language}_declarations'] += declaration_count
            for key in ('version', 'build'):
                if metadata.get(key) and not counters.get(key):
                    counters[key] = metadata[key]
            title = metadata.get('title') or path.stem.replace('-', ' ')
            body = [] if page_preface else [f'**Source:** `{rel.as_posix()}`', '']
            if metadata.get('purpose') and not page_preface:
                body += [metadata['purpose'], '']
            if metadata.get('description'):
                body += [metadata['description'], '']
            public = [e for e in documented if e['kind'].startswith('fn')
                      and e.get('public', not e['name'].startswith('_'))]
            internal = [e for e in documented if e['kind'].startswith('fn')
                        and not e.get('public', not e['name'].startswith('_'))]
            public_classes = [e for e in documented if e['kind'] == 'cls'
                              and e.get('public', not e['name'].startswith('_'))]
            internal_classes = [e for e in documented if e['kind'] == 'cls'
                                and not e.get('public', not e['name'].startswith('_'))]
            if public:
                body += ['## Public functions', '']
                for entry in public:
                    page_slug = slug(entry['name'])
                    body.append(f'- [{entry["title"]}]({page_slug}/)')
                body.append('')
            if public_classes:
                body += ['## Public classes', '']
                for entry in public_classes:
                    body.append(f'- [{entry["title"]}]({slug(entry["name"])}/)')
                body.append('')
            if internal:
                # WCM's native details component renders Markdown inside a
                # closed-by-default disclosure. Keep the internal API table
                # accessible without overwhelming the source overview.
                body += ['::: td-details Internal functions', '',
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
            if internal_classes:
                body += ['::: td-details Internal classes', '',
                         '| Class | Purpose |', '| --- | --- |']
                for entry in internal_classes:
                    lines = entry['lines']
                    purpose = next((value.strip().replace('|', r'\|') for ix, value in enumerate(lines)
                                   if value.strip() and ix >= 2 and lines[ix - 2].strip() == '### Purpose'), '—')
                    body.append(f'| `{entry["name"]}` | {purpose} |')
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
                            body += [f'::: td-details open {entry["title"]}', '',
                                     '::: sgnd-script-metadata', '']
                            body += metadata_lines + ['', ':::', '', ':::', '']
                    else:
                        body += [SCRIPT_SECTION_HEADING + entry['title'], '']
                        body += markdown_documentation(entry['lines']) + ['']
                elif kind in ('fn', 'cls') and not entry.get('public', not entry['name'].startswith('_')):
                    continue
                elif kind.startswith('fn') or kind == 'cls':
                    page_slug = slug(entry['name'])
                    if page_slug in used_public_slugs:
                        raise ValueError(f'Duplicate public declaration route in {rel}: {entry["name"]}')
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
            # Root-level files precede grouped sections in the chapter navigation.
            # Use the real source filename, not its descriptive page title.
            write_index(source_folder, title, '\n'.join(body),
                        order=40 if page_preface else (50 if group == '/' else 1000),
                        summary=(metadata.get('description', '') if page_preface else metadata.get('purpose', '')),
                        template='page' if page_preface else 'source',
                        nav_title=title if page_preface else path.name)
    # Do not merge introductions or closing material into the section index.
    # Stable child nav_order bands guarantee first/last placement at every depth.
    for section_folder, specials in special_pages.items():
        for kind in ('preface', 'epilogue'):
            for number, (path, metadata) in enumerate(specials[kind], 1):
                title, body = render_bundle_document(path, None)
                if not body.strip():
                    continue
                # Preserve the already-published product epilogue route.
                is_product_epilogue = (kind == 'epilogue' and section_folder == product_folder
                                       and metadata.get('purpose', '').strip().casefold() == 'product epilogue')
                page_name = (f'product-epilogue-{slug(title)}' if is_product_epilogue
                             else f'{kind}-{number:02d}-{slug(title)}')
                page_folder = section_folder / page_name
                if page_folder.exists():
                    raise ValueError(f'{kind.title()} route collision: {page_folder}')
                page_order = (-10000 + number) if kind == 'preface' else (10000 + number)
                write_index(page_folder, title, body, page_order,
                            template='page', nav_title=title)
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
    """Only authored repository documents; never generated caches or website output.
    
    Usage:
        ```python
        _product_reference_files(source, name)
        ```"""
    candidates = [source / name, source / 'usr/local/share/doc-sources' / name,
                  source / 'target-root/usr/local/share/doc-sources' / name]
    if name == 'LICENSE':
        candidates += [source / 'usr/local/share/testadura/solidgroundux/LICENSE',
                       source / 'target-root/usr/local/share/testadura/solidgroundux/LICENSE']
    return [candidate for candidate in candidates if candidate.is_file()]


def build_appendices(products: list[dict], content: Path, root: Path, nav_order: int = 9999) -> dict:
    """Build one bundle-level reference index from the actually published pages.
    
    Usage:
        ```python
        build_appendices(products, content, root)
        ```"""
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
            meta, declarations, _ = parse_documented_source(source_path)
            route = '/' + source_page.parent.relative_to(content).as_posix() + '/'
            for item in declarations:
                name = item['name']
                if not name or not item.get('public', not name.startswith('_')):
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
    write_index(appendix, 'Appendices', '', nav_order, template='group')
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
        identities: dict[tuple[str, str], tuple[str, str]] = {}
        for path in source.rglob('*.sh'):
            if any(part in SKIP_DIRS for part in path.relative_to(source).parts):
                continue
            for line in path.read_text(encoding='utf-8', errors='replace').splitlines()[:100]:
                match = re.match(r'^#\s*(Developers?|Company|Copyright)\s*:\s*(.*?)\s*$', line, re.I)
                if not match or not match.group(2) or match.group(2) == '-':
                    continue
                field, value = match.group(1).casefold(), match.group(2).strip()
                if field == 'copyright':
                    # Source headers use ©, (c), and sometimes no copyright
                    # symbol for the same legal notice. Display one canonical
                    # representation per product without altering source files.
                    text = re.sub(r'^(?:\(c\)|©)\s*', '', value, flags=re.I)
                    text = re.sub(r'\s*[-–—]\s*', ' – ', text)
                    text = re.sub(r'\s+', ' ', text).strip()
                    value = '© ' + text
                identities[(field, value.casefold())] = (field, value)
        # Do not list the company a second time as an individual developer.
        company_names = {value.casefold() for field, value in identities.values()
                         if field == 'company'}
        identities = {key: item for key, item in identities.items()
                      if not (item[0] in ('developer', 'developers')
                              and item[1].casefold() in company_names)}
        if identities:
            attribution_lines += ['## ' + product['title'], '']
            attribution_lines.extend(f'- **{field.title()}:** {value}'
                                     for field, value in sorted(identities.values()))
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
    
    Usage:
        ```python
        split_wcm_document(markdown)
        ```"""
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



# Figure numbers are assigned after product and bundle pages are assembled.
# A single ordered walk follows the published section hierarchy, not the
# incidental order of filenames on disk or the sequence in which pages were made.
_STANDALONE_FIGURE = re.compile(
    r'^\s*!\[(?P<alt>[^\]]*)\]\((?P<src>[^)]+)\)'
    r'(?:\{caption=(?P<caption>"(?:[^"\\]|\\.)*")\})?\s*$'
)


def ordered_bundle_pages(content: Path) -> list[Path]:
    """Walk all generated documents in section/navigation order.

    Usage:
        ```python
        for page in ordered_bundle_pages(content):
            print(page)
        ```
    """
    children: dict[Path | None, list[tuple[int, str, Path, Path | None]]] = {}
    pages = sorted(content.rglob('*.md'))
    for page in pages:
        metadata, _ = split_wcm_document(page.read_text(encoding='utf-8'))
        if not metadata:
            continue
        try:
            order = int(metadata.get('nav_order', '1000').strip())
        except ValueError as error:
            raise ValueError(f'Invalid nav_order in {page}') from error
        # The index file is the document representing its directory. Ordinary
        # child pages (e.g. public functions) sit under that directory's index.
        section_index = page.name.endswith('_Index_NL.md')
        section = page.parent if section_index else None
        if section_index:
            parent = page.parent.parent if page.parent != content else None
        else:
            parent = page.parent
        # Documentation home prefaces already reside directly under content.
        # nav_parent '/' reaffirms that logical relationship in the WCM sidebar.
        key = page.relative_to(content).as_posix()
        children.setdefault(parent, []).append((order, key, page, section))
    result: list[Path] = []
    seen: set[Path] = set()

    def visit(parent: Path | None) -> None:
        for _order, _key, page, section in sorted(children.get(parent, [])):
            if page in seen:
                continue
            seen.add(page)
            result.append(page)
            if section is not None:
                visit(section)

    visit(None)
    if len(seen) != sum(len(v) for v in children.values()):
        missing = sorted(str(page.relative_to(content)) for group in children.values()
                         for _, _, page, _ in group if page not in seen)
        raise ValueError('Unreachable generated documentation pages: ' + ', '.join(missing[:5]))
    return result


def number_bundle_figures(content: Path) -> int:
    """Caption figures consecutively and publish a navigable appendix index.

    Standalone Markdown images with an explicit caption use that authored
    caption; other standalone images use their alt text as the caption.
    Code fences and inline images are not altered. Source files stay untouched.

    Usage:
        ```python
        count = number_bundle_figures(content)
        ```
    """
    figures: list[tuple[int, str, str, str]] = []
    for page in ordered_bundle_pages(content):
        original = page.read_text(encoding='utf-8')
        metadata, _body = split_wcm_document(original)
        if not metadata or metadata.get('nav_only', '').strip().lower() == 'true':
            continue
        if page.parent == content / 'appendices' / 'figure-index':
            continue
        # Do not re-interpret YAML metadata as Markdown body.
        lines = original.splitlines(keepends=True)
        body_start = 0
        if lines and lines[0].strip() == '---':
            body_start = next((index + 1 for index in range(1, len(lines))
                               if lines[index].strip() == '---'), 0)
        page_title = metadata.get('title', '').strip().strip('"\'') or page.parent.name
        relative = page.parent.relative_to(content)
        if page.name.endswith('_Index_NL.md'):
            route = '/' if str(relative) == '.' else '/' + relative.as_posix() + '/'
        else:
            stem = page.name.rsplit('_NL.md', 1)[0]
            route = '/' + relative.as_posix().strip('.') + '/' + slug(stem) + '/'
            route = re.sub(r'/+', '/', route)
        in_fence = False
        changed = False
        for index in range(body_start, len(lines)):
            line = lines[index]
            stripped = line.strip()
            if stripped.startswith(('```', '~~~')):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            match = _STANDALONE_FIGURE.fullmatch(stripped)
            if match is None:
                continue
            quoted = match.group('caption')
            if quoted:
                try:
                    caption = json.loads(quoted)
                except ValueError:
                    continue
            else:
                caption = match.group('alt').strip() or Path(match.group('src')).stem.replace('-', ' ').replace('_', ' ')
            caption = str(caption).strip()
            if not caption:
                continue
            caption = re.sub(r'^Figure\s+\d+\s*[:.\-]\s*', '', caption, flags=re.I)
            figure = len(figures) + 1
            label = f'Figure {figure}: {caption}'
            # Preserve the original image path and descriptive alt text.
            image = f'![{match.group("alt")}]({match.group("src")})'
            image += '{caption=' + json.dumps(label, ensure_ascii=False) + '}'
            lines[index] = image + ('\n' if line.endswith('\n') else '')
            figures.append((figure, caption, route + f'#figure-{figure}', page_title))
            changed = True
        if changed:
            page.write_text(''.join(lines), encoding='utf-8')
    sections = [
        f'{len(figures)} figures across the documentation bundle.', '',
        '| Figure | Caption | Page |', '| --- | --- | --- |',
    ]
    for number, caption, target, title in figures:
        # Pipes would otherwise terminate Markdown table cells.
        label = caption.replace('|', r'\|').replace('[', r'\[').replace(']', r'\]')
        location = title.replace('|', r'\|')
        sections.append(f'| [Figure {number}]({target}) | {label} | [{location}]({target}) |')
    if not figures:
        sections = ['No figures were found in this documentation bundle.']
    write_index(content / 'appendices' / 'figure-index', 'Figure Index',
                '\n'.join(sections), 6, template='page')
    return len(figures)


# Bundle-level prefaces/epilogues are independent authored documents, not a
# generated Chapter 0 page. They are listed in the bundle, in display order.
BUNDLE_SPECIAL = re.compile(r'^bundle(?:[-_].+)?[-_](preface|epilogue)\.(?:md|markdown|sh|py)$', re.I)


def bundle_document_selections(bundle: dict, products: list[dict]) -> tuple[list, list]:
    """Read ordered selections, or discover conventional bundle documents.

    Usage:
        ```python
        prefaces, epilogues = bundle_document_selections(bundle, products)
        ```
    """
    def configured(name: str) -> list:
        plural = 'prefaces' if name == 'preface' else 'epilogues'
        for key in ('bundle_' + plural, plural):
            value = bundle.get(key)
            if value is not None:
                if not isinstance(value, list):
                    raise ValueError(f'Bundle {key} must be an ordered list')
                return value
        return []

    prefaces = configured('preface')
    epilogues = configured('epilogue')
    if prefaces or epilogues:
        return prefaces, epilogues

    # Older saved bundles used one generated Chapter 0 document. Interpret it
    # as the sole preface without requiring the user to edit their saved JSON.
    old = bundle.get('chapter0', '')
    if old:
        return [{'path': old, 'title': 'Introduction',
                 'origin': bundle.get('chapter0_origin', '')}], []

    discovered: dict[str, list] = {'preface': [], 'epilogue': []}
    seen: set[Path] = set()
    for product in products:
        source = Path(product['source_dir']).expanduser().resolve()
        directories = (source, source / 'doc-sources',
                       source / 'usr/local/share/doc-sources',
                       source / 'target-root/usr/local/share/doc-sources')
        for directory in directories:
            if not directory.is_dir():
                continue
            # Conventional files live at the documentation root, not somewhere
            # in a generated cache, application source tree or vendor package.
            for path in sorted(directory.iterdir(), key=lambda item: item.name.casefold()):
                if not path.is_file() or path.resolve() in seen:
                    continue
                match = BUNDLE_SPECIAL.fullmatch(path.name)
                if match:
                    seen.add(path.resolve())
                    discovered[match.group(1).lower()].append(str(path.resolve()))
    return discovered['preface'], discovered['epilogue']


def bundle_document_source(item: str | dict, products: list[dict],
                           content: Path) -> tuple[Path, str | None, str]:
    """Resolve an authored bundle document or generated Markdown selection.

    Usage:
        ```python
        path, title, origin = bundle_document_source(item, products, content)
        ```
    """
    if isinstance(item, str):
        reference, title, origin = item, None, ''
    elif isinstance(item, dict):
        reference = item.get('path') or item.get('source') or item.get('file')
        title = item.get('title') or None
        origin = item.get('origin') or ''
    else:
        raise ValueError('Bundle document entries must be filenames or objects')
    if not isinstance(reference, str) or not reference.strip():
        raise ValueError('Bundle document entry has no filename')
    reference = reference.strip()
    if title is not None and not isinstance(title, str):
        raise ValueError('Bundle document title must be text')
    if origin and '/content/' in origin:
        reference = origin
    if reference.startswith('content/') or '/content/' in reference:
        relative = reference.split('/content/', 1)[1] if '/content/' in reference else reference[8:]
        selected = Path(relative)
        if selected.is_absolute() or '..' in selected.parts:
            raise ValueError(f'Invalid bundle generated page: {reference}')
        path = (content / selected).resolve()
        if not path.is_relative_to(content.resolve()):
            raise ValueError(f'Invalid bundle generated page: {reference}')
    elif Path(reference).is_absolute():
        path = Path(reference).expanduser().resolve()
    else:
        selected = Path(reference)
        if '..' in selected.parts:
            raise ValueError(f'Unsafe bundle document path: {reference}')
        matches = [candidate.resolve() for product in products
                   for candidate in [Path(product['source_dir']).expanduser().resolve() / selected]
                   if candidate.is_file()]
        matches = list(dict.fromkeys(matches))
        if len(matches) != 1:
            raise ValueError(f'Bundle document path must match exactly one source: {reference}')
        path = matches[0]
    if not path.is_file() or path.suffix.lower() not in ('.md', '.markdown', '.sh', '.py'):
        raise ValueError(f'Invalid or missing bundle document: {path}')
    return path, title, reference


def bundle_document_metadata(path: Path) -> dict[str, str]:
    """Read authored Markdown navigation metadata without changing its body.

    Usage:
        ```python
        metadata = bundle_document_metadata(path)
        ```
    """
    if path.suffix.lower() not in ('.md', '.markdown'):
        return {}
    metadata, _ = split_wcm_document(path.read_text(encoding='utf-8'))
    return {key.lower(): value.strip().strip('"\'') for key, value in metadata.items()}


def bundle_nav_order(metadata: dict[str, str], fallback: int) -> int:
    """Validate an authored document's order relative to its siblings.

    Usage:
        ```python
        order = bundle_nav_order(metadata, 10)
        ```
    """
    value = metadata.get('nav_order', '').strip()
    if not value:
        return fallback
    if not re.fullmatch(r'\d+', value):
        raise ValueError(f'Invalid bundle document nav_order: {value}')
    order = int(value)
    if order >= 10000:
        raise ValueError('Bundle document nav_order must be below 10000')
    return order


def render_bundle_document(path: Path, title: str | None) -> tuple[str, str]:
    """Convert an authored preface/epilogue without executing source code.

    Usage:
        ```python
        title, body = render_bundle_document(document, None)
        ```
    """
    if path.suffix.lower() in ('.md', '.markdown'):
        metadata, body = split_wcm_document(path.read_text(encoding='utf-8'))
        if not title:
            label = metadata.get('title', '').strip().strip('"')
            heading = re.search(r'^#\s+(.+)$', body, flags=re.M)
            title = label or (heading.group(1).strip() if heading else '')
    else:
        metadata, entries, _ = parse_documented_source(path)
        lines: list[str] = []
        for entry in entries:
            if entry['kind'] == 'def':
                lines.extend(definition_markdown(entry))
            else:
                append_preface(lines, [entry])
        body = '\n'.join(lines)
        if not title:
            title = metadata.get('title', '').strip()
        if metadata.get('purpose') and not body.strip():
            body = metadata['purpose']
    if not body.strip():
        raise ValueError(f'Empty bundle document: {path}')
    if not title:
        title = path.stem.replace('_', ' ').replace('-', ' ').title()
        title = re.sub(r'^Bundle\s+', '', title, flags=re.I)
        title = re.sub(r'\s+(Preface|Epilogue)$', '', title, flags=re.I)
    # WCM owns the document heading. Do not repeat an identical Markdown H1
    # inside the published page body.
    lines = body.strip().splitlines()
    if lines and re.fullmatch(r'#\s+' + re.escape(title.strip()) + r'\s*', lines[0], re.I):
        body = '\n'.join(lines[1:]).strip()
    return title, body.strip()


def rewrite_promoted_links(content: Path, old_page: Path, new_route: str) -> None:
    """Retarget links to an earlier generated route promoted as a bundle preface.

    Usage:
        ```python
        rewrite_promoted_links(content, old_page, '/bundle-preface-01-introduction/')
        ```
    """
    relative = old_page.relative_to(content)
    filename = relative.name
    stem = filename.removesuffix('_Index_NL.md') if filename.endswith('_Index_NL.md') else filename.removesuffix('_NL.md')
    parent_route = '/' + relative.parent.as_posix().strip('.') + '/'
    routes = {parent_route + stem + '/'}
    if filename.endswith('_Index_NL.md'):
        routes.add(parent_route)
    for file in content.rglob('*.md'):
        text = file.read_text(encoding='utf-8')
        revised = text
        for route in routes:
            revised = revised.replace('](' + route + ')', '](' + new_route + ')')
            revised = revised.replace('](' + route + '#', '](' + new_route + '#')
        if revised != text:
            file.write_text(revised, encoding='utf-8')


def publish_bundle_documents(selections: list, label: str, products: list[dict],
                             content: Path, start_order: int) -> tuple[int, list[Path]]:
    """Publish selected documents once, ordered before or after the chapters.

    Usage:
        ```python
        count, sources = publish_bundle_documents(prefaces, 'preface', products, content, 1)
        ```
    """
    used_folders: set[Path] = set()
    used_sources: list[Path] = []
    for number, item in enumerate(selections, 1):
        path, title_override, reference = bundle_document_source(item, products, content)
        metadata = bundle_document_metadata(path)
        title, body = render_bundle_document(path, metadata.get('title') or title_override)
        # An authored document is bundle-wide unless its own metadata explicitly
        # scopes it to a product. A legacy bundle selection can still supply scope.
        chapter_id = (metadata.get('product') or metadata.get('chapter') or '').strip()
        if not chapter_id and isinstance(item, dict):
            chapter_id = str(item.get('product') or item.get('chapter') or '').strip()
        relative_order = bundle_nav_order(metadata, number * 10)
        if chapter_id:
            matches = [product for product in products
                       if chapter_id.casefold() in (str(product['id']).casefold(),
                                                   str(product['title']).casefold())]
            if len(matches) != 1:
                raise ValueError(f'Unknown or ambiguous bundle document product: {chapter_id}')
            chapter = content / slug(matches[0]['id'])
            folder = chapter / f'{label}-{number:02d}-{slug(title)}'
            # A product's own preface/epilogue remains within that chapter.
            page_order = relative_order if label == 'preface' else 10000 + relative_order
        else:
            folder = content / f'bundle-{label}-{number:02d}-{slug(title)}'
            # The bundle home has only its explicitly designated prefaces as
            # children. The product chapters stay as independent top-level entries.
            page_order = relative_order if label == 'preface' else start_order + relative_order
        if folder in used_folders or folder.exists():
            raise ValueError(f'Bundle document route conflict: {folder.name}')
        used_folders.add(folder)
        write_index(folder, title, body, page_order,
                    template='page', summary='', nav_title=title,
                    nav_parent='/' if label == 'preface' and not chapter_id else None)
        used_sources.append(path)
        # A promoted page must not also display its body at the old route.
        if path.is_relative_to(content.resolve()):
            rewrite_promoted_links(content, path, '/' + folder.name + '/')
            children = [child for child in path.parent.rglob('*.md') if child != path]
            if children and path.name.endswith('_Index_NL.md'):
                # A section index may own many child pages. Keep its navigation
                # metadata so the children are not stranded, but remove the
                # promoted body and mark the section navigation-only.
                existing = path.read_text(encoding='utf-8')
                metadata, _ = split_wcm_document(existing)
                if not metadata:
                    raise ValueError(f'Invalid generated page metadata: {path}')
                prefix_end = existing.find('\n---\n', 4)
                prefix = existing[:prefix_end]
                if 'nav_only:' not in prefix:
                    prefix += '\nnav_only: true'
                path.write_text(prefix + '\n---\n', encoding='utf-8')
            else:
                path.unlink()
                parent = path.parent
                while parent != content and not any(parent.iterdir()):
                    parent.rmdir()
                    parent = parent.parent
    return len(selections), used_sources



# --- Public functions ------------------------------------------------------------
def generate(bundle: dict, docs_root: Path | None = None) -> dict:
    """Validate a saved bundle and generate its combined Markdown repository.
    
    Usage:
        ```python
        summary = generate(bundle)  # Writes the configured output directory
        ```"""
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
        prefaces, epilogues = bundle_document_selections(bundle, products)
        # Authored .sh/.py bundle documents are published as introduction or
        # closing pages, not a second time within their source product chapter.
        excluded_sources: set[Path] = set()
        for selection in [*prefaces, *epilogues]:
            reference = selection if isinstance(selection, str) else selection.get('path', selection.get('source', selection.get('file', '')))
            if reference and not (str(reference).startswith('content/') or '/content/' in str(reference)):
                selected, _, _ = bundle_document_source(selection, products, content)
                if selected.suffix.lower() in ('.sh', '.py'):
                    excluded_sources.add(selected.resolve())
        # Product pages are generated before promotion of authored/generator
        # selections; navigation order is independent of creation order.
        # Reserve disjoint ordering bands for products, conclusions and
        # appendices. Bundle prefaces sort as children of the home page, using
        # their own nav_order rather than their selection/list position.
        for i, product in enumerate(products, 1):
            collect(product, content, i * 10000, counts, template_owners, excluded_sources)
        epilogue_base = (len(products) + 1) * 10000
        appendix_order = (len(products) + 2) * 10000
        counts.update(build_appendices(products, content, root, appendix_order))
        # Images referenced by comments belong to each product source tree.
        # Keep /assets/... links valid without depending on an external website.
        for product in products:
            copy_legacy_images(Path(product['source_dir']).expanduser().resolve(), root)
            asset_dir = Path(product['source_dir']).expanduser().resolve() / 'assets'
            copy_assets_checked(asset_dir, root / 'assets')
        # The home/title page is independent of bundle prefaces. It always displays
        # the bundle metrics; the home template supplies its established branding.
        metrics = f'- **Products:** {counts["products"]}\n\n'
        metrics += '| Metric | Bash | Python | Total |\n'
        metrics += '| --- | ---: | ---: | ---: |\n'
        for label, key in (('Source files', 'files'), ('Functions', 'functions'),
                           ('Declarations', 'declarations'), ('Code lines', 'code_lines'),
                           ('Comment and docstring lines', 'comment_lines'),
                           ('Code + comment lines', 'lines')):
            metrics += (f'| {label} | {counts[f"bash_{key}"] if key != "lines" else counts["bash_code_lines"] + counts["bash_comment_lines"]:,}'
                        f' | {counts[f"python_{key}"] if key != "lines" else counts["python_code_lines"] + counts["python_comment_lines"]:,}'
                        f' | {counts[key]:,} |\n')
        metrics += '\n'
        for key in ('version', 'build'):
            if counts.get(key):
                metrics += f'\n- **{key.title()}:** {counts[key]}'
        write_index(content, bundle.get('title', bundle['id']), metrics, 0, template='home')

        # Bundle introduction pages precede the products; bundle conclusions
        # follow the products and precede the technical appendices.
        preface_count, preface_sources = publish_bundle_documents(
            prefaces, 'preface', products, content, 1)
        epilogue_count, epilogue_sources = publish_bundle_documents(
            epilogues, 'epilogue', products, content, epilogue_base)
        counts['bundle_prefaces'] = preface_count
        counts['bundle_epilogues'] = epilogue_count
        # Number figures only after every authored/generated page exists; the
        # figure appendix is generated from the exact published page routes.
        counts['figures'] = number_bundle_figures(content)
        # Bundle defaults come from the selected MCM documentation resources.
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
                # Bundle-wide CSS comes from docs_root. Source products retain
                # their own images and other assets, but cannot silently replace
                # the site's default stylesheets. Product CSS is reserved for a
                # future explicit, chapter-scoped opt-in.
                for resource in ('assets', 'images'):
                    if (candidate / resource).is_dir():
                        copy_assets_checked(candidate / resource, root / resource)
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
    """Load the requested bundle and run the Markdown generator CLI.
    
    Usage:
        ```python
        main()
        ```"""
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
