"""Small, dependency-free Markdown subset used by the WebContent engine.

The renderer intentionally supports a compact Testadura extension syntax using
``::: class-name`` component blocks. Component blocks may be nested, which lets
site authors compose reusable layout primitives such as grids containing tiles
without dropping down to raw HTML.
"""

from __future__ import annotations

import html
import re
from urllib.parse import urlparse


_STYLE_CLASS_RE = re.compile(r"\.([A-Za-z_][A-Za-z0-9_-]*)")
_BLOCK_CLASS_RE = re.compile(r"^:::\s+(.+)$", re.MULTILINE)
_CLASS_NAME_RE = re.compile(r"\.?([A-Za-z_][A-Za-z0-9_-]*)")


# fn: referenced_style_classes - Find td- prefixed CSS class references in authored Markdown.
# . Description
#   Args: markdown_text: Input used by this operation.
def referenced_style_classes(markdown_text: str, prefix: str) -> set[str]:
    """Handle referenced style classes for the web content workflow.
    
    Args:
        markdown_text: Input used by this operation.
        prefix: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    classes = {name for name in _STYLE_CLASS_RE.findall(markdown_text) if name.startswith(prefix)}
    for block_spec in _BLOCK_CLASS_RE.findall(markdown_text):
        if block_spec.startswith("td-image-text "):
            classes.add("td-image-text")
            continue
        classes.update(
            name for name in _CLASS_NAME_RE.findall(block_spec)
            if name.startswith(prefix)
        )
    return classes


# fn: _safe_url - Validate and escape a link target for generated markup.
def _safe_url(value: str) -> str:
    """Handle safe url for the web content workflow."""
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() in {"javascript", "data"}:
        return "#"
    return value


# fn: _image_dimensions - Return safe inline image sizing; omit invalid or absent dimensions.
# . Description
#   Image size attributes use positive pixel counts. A single dimension keeps the intrinsic aspect ratio; both dimensions use contain to avoid cropping.
def _image_dimensions(options: str) -> str:
    """Return safe inline image sizing; omit invalid or absent dimensions.

    Image size attributes use positive pixel counts. A single dimension keeps
    the intrinsic aspect ratio; both dimensions use contain to avoid cropping.
    """
    dimensions: dict[str, int] = {}
    for key, raw in re.findall(r"(?<![\w-])(width|height)\s*=\s*([^\s}]+)", options):
        if raw.isdecimal() and 0 < int(raw) <= 10000:
            dimensions[key] = int(raw)
    if not dimensions:
        return ""
    rules = [f"{key}: {dimensions[key]}px" for key in ("width", "height") if key in dimensions]
    if "width" not in dimensions:
        rules.append("width: auto")
    if "height" not in dimensions:
        rules.append("height: auto")
    rules += ["max-width: 100%", "object-fit: contain"]
    return f' style="{html.escape("; ".join(rules), quote=True)}"'


# fn: _render_inline - Render inline Markdown constructs into HTML while escaping content.
def _render_inline(text: str) -> str:
    """Render inline Markdown constructs into HTML while escaping content."""
    escaped = html.escape(text, quote=False)
    tokens: dict[str, str] = {}

    # fn: stash - Preserve an embedded fragment while Markdown text is transformed.
    # . Description
    #   Args: fragment: Input used by this operation.
    def stash(fragment: str) -> str:
        """Handle stash for the web content workflow.
        
        Args:
            fragment: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        key = f"\x00WC{len(tokens)}\x00"
        tokens[key] = fragment
        return key

    # fn: code_repl - Replace a Markdown code-span match with protected HTML output.
    # . Description
    #   Args: match: Input used by this operation.
    def code_repl(match: re.Match[str]) -> str:
        """Handle code repl for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return stash(f"<code>{html.escape(match.group(1), quote=False)}</code>")

    escaped = re.sub(r"`([^`]+)`", code_repl, escaped)

    image_pattern = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)(?:\{([^}]+)\})?")

    # fn: image_repl - Replace a Markdown image reference with rendered image markup.
    # . Description
    #   Args: match: Input used by this operation.
    def image_repl(match: re.Match[str]) -> str:
        """Handle image repl for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        alt = match.group(1)
        src = html.escape(_safe_url(html.unescape(match.group(2))), quote=True)
        classes = " ".join(_STYLE_CLASS_RE.findall(match.group(3) or ""))
        class_attr = f' class="{html.escape(classes, quote=True)}"' if classes else ""
        size_attr = _image_dimensions(match.group(3) or "")
        return stash(f'<img src="{src}" alt="{alt}"{class_attr}{size_attr}>')

    escaped = image_pattern.sub(image_repl, escaped)

    # Optional {download} suffix forces a local link to download as a file.
    link_pattern = re.compile(r"\[([^\]]+)\]\(([^)]+)\)(?:\{(download)\})?")

    # fn: link_repl - Render a Markdown link after checking and escaping its target.
    # . Description
    #   Args: match: Input used by this operation.
    def link_repl(match: re.Match[str]) -> str:
        """Handle link repl for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        label = match.group(1)
        href = html.escape(_safe_url(html.unescape(match.group(2))), quote=True)
        download_attr = " download" if match.group(3) and href != "#" else ""
        return stash(f'<a href="{href}"{download_attr}>{label}</a>')

    escaped = link_pattern.sub(link_repl, escaped)

    style_pattern = re.compile(r"\[([^\]]+)\]\{([^}]+)\}")

    # fn: style_repl - Render supported inline style attributes on Markdown spans.
    # . Description
    #   Args: match: Input used by this operation.
    def style_repl(match: re.Match[str]) -> str:
        """Handle style repl for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        label = match.group(1)
        classes = " ".join(_STYLE_CLASS_RE.findall(match.group(2)))
        if not classes:
            return label
        return stash(f'<span class="{html.escape(classes, quote=True)}">{label}</span>')

    escaped = style_pattern.sub(style_repl, escaped)

    # Angle-bracket autolinks use the same URL safety policy as ordinary links.
    # fn: autolink_repl - Convert a recognized automatic URL to a link.
    def autolink_repl(match: re.Match[str]) -> str:
        url = html.unescape(match.group(1))
        href = html.escape(_safe_url(url), quote=True)
        return stash(f'<a href="{href}">{html.escape(url, quote=False)}</a>')

    escaped = re.sub(r"&lt;(https?://[^\s<>]+|mailto:[^\s<>]+)&gt;", autolink_repl, escaped)
    escaped = re.sub(r"~~(.+?)~~", r"<del>\1</del>", escaped)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", escaped)

    # Later tokens may contain earlier placeholders (e.g. a link wrapping code).
    # Resolve outer fragments first so nested inline markup is restored.
    for key, fragment in reversed(list(tokens.items())):
        escaped = escaped.replace(key, fragment)
    return escaped


# fn: _render_paragraph - Join soft lines and preserve CommonMark space/backslash hard breaks.
def _render_paragraph(lines: list[str]) -> str:
    """Join soft lines and preserve CommonMark space/backslash hard breaks."""
    parts: list[str] = []
    for line in lines[:-1]:
        hard_spaces = len(line) - len(line.rstrip(" ")) >= 2
        trimmed = line.rstrip(" ")
        # An odd number of trailing backslashes escapes the line ending.
        backslashes = len(trimmed) - len(trimmed.rstrip("\\"))
        hard_slash = bool(backslashes % 2)
        if hard_slash:
            trimmed = trimmed[:-1]
        parts.append(trimmed + ("\n" if hard_spaces or hard_slash else " "))
    parts.append(lines[-1].strip())
    return _render_inline("".join(parts)).replace("\n", "<br>\n")


# fn: _heading_id - Create a predictable Unicode-friendly anchor from a heading's plain text.
def _heading_id(title: str) -> str:
    """Create a predictable Unicode-friendly anchor from a heading's plain text."""
    plain = re.sub(r"[`*_~]", "", re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", title)).lower()
    plain = re.sub(r"[^\w\s-]", "", plain, flags=re.UNICODE)
    return re.sub(r"[\s_-]+", "-", plain).strip("-")


_LIST_RE = re.compile(r"^(?P<indent>[ ]*)(?P<marker>[-*+]|[0-9]+[.)])\s+(?P<body>.*)$")


# fn: _render_list - Render nested ordered/unordered lists using indentation and item boundaries.
def _render_list(lines: list[str], start: int) -> tuple[str, int]:
    """Render nested ordered/unordered lists using indentation and item boundaries."""
    initial = _LIST_RE.match(lines[start])
    assert initial is not None
    base = len(initial.group("indent"))
    kind = "ol" if initial.group("marker")[0].isdigit() else "ul"
    start_value = int(re.match(r"\d+", initial.group("marker")).group()) if kind == "ol" else 1
    opening = f'<ol start="{start_value}">' if kind == "ol" and start_value != 1 else f"<{kind}>"
    result = [opening]
    index = start
    while index < len(lines):
        match = _LIST_RE.match(lines[index])
        if not match or len(match.group("indent")) != base:
            break
        item_kind = "ol" if match.group("marker")[0].isdigit() else "ul"
        if item_kind != kind:
            break
        body = [match.group("body")]
        index += 1
        nested: list[str] = []
        while index < len(lines):
            follow = lines[index]
            if not follow.strip():
                # Preserve blank lines between items, but do not swallow a block after a list.
                if index + 1 < len(lines) and _LIST_RE.match(lines[index + 1]) and len(_LIST_RE.match(lines[index + 1]).group("indent")) >= base:
                    index += 1
                    continue
                break
            sub = _LIST_RE.match(follow)
            indent = len(follow) - len(follow.lstrip(" "))
            if indent <= base:
                break
            if sub and indent > base:
                child, index = _render_list(lines, index)
                nested.append(child)
                continue
            body.append(follow.strip())
            index += 1
        result.append("<li>" + _render_paragraph(body) + ("\n" + "\n".join(nested) if nested else "") + "</li>")
    result.append(f"</{kind}>")
    return "\n".join(result), index


# fn: _is_table_separator - Recognize the delimiter row that separates Markdown table headers.
def _is_table_separator(line: str) -> bool:
    """Handle is table separator for the web content workflow."""
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


# fn: _table_cells - Split one Markdown table row into its cell values.
def _table_cells(line: str) -> list[str]:
    """Split Markdown table cells without splitting escaped literal pipes.

    A Bash definition such as label|icon|symbol belongs in one cell, even
    though the source Markdown escapes each separator as \\|.
    """
    content = line.strip()
    if content.startswith('|'):
        content = content[1:]
    if content.endswith('|'):
        content = content[:-1]
    cells: list[str] = []
    current: list[str] = []
    index = 0
    while index < len(content):
        char = content[index]
        if char == "\\" and index + 1 < len(content) and content[index + 1] == '|':
            current.append('|')
            index += 2
            continue
        if char == '|':
            cells.append(''.join(current).strip())
            current = []
        else:
            current.append(char)
        index += 1
    cells.append(''.join(current).strip())
    return cells


# fn: _starts_block - Check whether a Markdown line begins a block-level construct.
def _starts_block(lines: list[str], index: int) -> bool:
    """Handle starts block for the web content workflow."""
    line = lines[index]
    stripped = line.strip()
    if not stripped:
        return True
    if stripped.startswith("```") or stripped.startswith(":::"):
        return True
    if re.match(r"^#{1,6}\s+", stripped):
        return True
    if re.fullmatch(r"(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,}", stripped):
        return True
    if stripped.startswith(">"):
        return True
    if re.match(r"^[-*+]\s+", stripped) or re.match(r"^\d+[.)]\s+", stripped):
        return True
    if "|" in line and index + 1 < len(lines) and _is_table_separator(lines[index + 1]):
        return True
    return False


# fn: _render_lines - Render a line range and optionally stop at the matching ``:::`` marker.
# . Description
#   Component rendering is recursive. A nested opener therefore consumes its own closing marker before control returns to the containing component, while
def _render_lines(
    lines: list[str],
    start: int = 0,
    *,
    stop_at_component_end: bool = False,
) -> tuple[str, int, bool]:
    """Render a line range and optionally stop at the matching ``:::`` marker.

    Component rendering is recursive. A nested opener therefore consumes its own
    closing marker before control returns to the containing component, while
    fenced code blocks continue to treat ``:::`` as ordinary code text.
    """
    output: list[str] = []
    index = start

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped:
            index += 1
            continue

        if stripped.startswith("```"):
            language = stripped[3:].strip()
            index += 1
            block: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                block.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            class_attr = f' class="language-{html.escape(language, quote=True)}"' if language else ""
            output.append(f"<pre><code{class_attr}>{html.escape(chr(10).join(block), quote=False)}</code></pre>")
            continue

        if stripped == ":::":
            if stop_at_component_end:
                return "\n".join(output), index + 1, True
            # A stray closing marker at top level is kept visible rather than
            # silently discarding author content.
            output.append("<p>:::</p>")
            index += 1
            continue

        if stripped.startswith(":::"):
            component_spec = stripped[3:].strip()
            # Do not turn component option values or details titles into CSS classes.
            classes = " ".join(_CLASS_NAME_RE.findall(component_spec)) if not component_spec.startswith("td-details") else "td-details"
            index += 1
            body_start = index
            inner, index, closed = _render_lines(
                lines,
                index,
                stop_at_component_end=True,
            )
            class_attr = f' class="{html.escape(classes, quote=True)}"' if classes else ""
            if component_spec.startswith("td-image-text "):
                # A single image path and optional `right` are layout arguments,
                # not CSS classes. Render the body using normal nested Markdown.
                options = component_spec.split()
                if len(options) >= 2 and options[1].startswith("/") and all(
                    opt == "right" or re.fullmatch(r"(?:width|height)=[0-9]+", opt)
                    for opt in options[2:]
                ) and options[2:].count("right") <= 1:
                    image_src = html.escape(_safe_url(options[1]), quote=True)
                    side_class = " td-image-text-right" if "right" in options[2:] else ""
                    size_attr = _image_dimensions(" ".join(options[2:]))
                    if size_attr and "width:" in size_attr and "width: auto" not in size_attr:
                        side_class += " td-image-text-sized"
                    output.append(
                        f'<div class="td-image-text{side_class}">'
                        f'<div class="td-image-text-image"><img src="{image_src}" alt=""{size_attr}></div>'
                        f'<div class="td-image-text-content">{inner}</div></div>'
                    )
                else:
                    # Invalid syntax must be visible rather than silently ignored.
                    output.append(f'<p>{html.escape(stripped)}</p>\n{inner}')
            elif component_spec.startswith("td-details") and (component_spec == "td-details" or component_spec.startswith("td-details ")):
                # Native accessible disclosure, with nested Markdown in its body.
                options = component_spec[len("td-details"):].strip()
                is_open = bool(re.search(r"(?:^|\s)open(?:=true)?(?:\s|$)", options, re.I))
                options = re.sub(r"(?:^|\s)open(?:=true)?(?:\s|$)", " ", options, flags=re.I).strip()
                # An optional heading level makes the disclosure label part of
                # the document outline while keeping it clickable and closed
                # by default. Existing td-details syntax is unchanged.
                heading_match = re.match(r"^heading=([2-6])(?:\s+|$)", options, re.I)
                heading_level = int(heading_match.group(1)) if heading_match else None
                title = options[heading_match.end():].strip() if heading_match else options
                title = title or "Meer informatie"
                open_attr = " open" if is_open else ""
                if heading_level is None:
                    summary = html.escape(title)
                    css_class = "td-details"
                else:
                    summary = f'<h{heading_level}>{html.escape(title)}</h{heading_level}>'
                    css_class = "td-details td-details-heading"
                output.append(f'<details class="{css_class}"{open_attr}><summary>{summary}</summary>\n<div class="td-details-body">{inner}</div></details>')
            elif "td-example" in classes.split():
                # The displayed Markdown is extracted from the actual example
                # body, so examples cannot drift away from their source.
                source_end = index - 1 if closed else index
                source = "\n".join(lines[body_start:source_end]).strip("\n")
                escaped_source = html.escape(source, quote=False)
                output.append(
                    f'<div{class_attr}>\n{inner}\n'
                    '<details class="td-example-source">'
                    '<summary>Bekijk Markdown</summary>'
                    f'<pre><code class="language-markdown">{escaped_source}</code></pre>'
                    '</details></div>'
                )
            else:
                output.append(f"<div{class_attr}>\n{inner}\n</div>")
            continue

        heading = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        if heading:
            level = len(heading.group(1))
            anchor = html.escape(_heading_id(heading.group(2)), quote=True)
            output.append(f'<h{level} id="{anchor}">{_render_inline(heading.group(2))}</h{level}>')
            index += 1
            continue

        if re.fullmatch(r"(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,}", stripped):
            output.append("<hr>")
            index += 1
            continue

        if stripped.startswith(">"):
            quote_lines: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote_lines.append(lines[index].strip()[1:].lstrip())
                index += 1
            output.append(f"<blockquote><p>{_render_inline(' '.join(quote_lines))}</p></blockquote>")
            continue

        if _LIST_RE.match(line):
            rendered_list, index = _render_list(lines, index)
            output.append(rendered_list)
            continue

        if "|" in line and index + 1 < len(lines) and _is_table_separator(lines[index + 1]):
            headers = _table_cells(line)
            separators = _table_cells(lines[index + 1])
            alignments: list[str] = []
            for cell in separators:
                if cell.startswith(":") and cell.endswith(":"):
                    alignments.append("center")
                elif cell.endswith(":"):
                    alignments.append("right")
                elif cell.startswith(":"):
                    alignments.append("left")
                else:
                    alignments.append("")
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and lines[index].strip() and "|" in lines[index]:
                rows.append(_table_cells(lines[index]))
                index += 1

            # Opt-in merged group column, used by generated # def: tables.
            # Leave every other Markdown table unchanged, including empty cells.
            grouped = bool(headers and headers[0].strip() == 'Group {rowspan}')
            if grouped:
                headers[0] = 'Group'
            head_cells: list[str] = []
            for i, cell in enumerate(headers):
                style = f' style="text-align: {alignments[i]}"' if i < len(alignments) and alignments[i] else ""
                head_cells.append(f"<th{style}>{_render_inline(cell)}</th>")
            body_rows: list[str] = []
            for row_index, row in enumerate(rows):
                # A new group starts at each nonempty group cell. Mark its row
                # so the documentation stylesheet can draw a single subtle
                # separator across the group without boxing every cell.
                group_start = grouped and bool(row and row[0])
                rendered_cells: list[str] = []
                for i in range(len(headers)):
                    value = row[i] if i < len(row) else ""
                    if grouped and i == 0:
                        # A blank first cell continues the preceding group's rowspan.
                        if row_index > 0 and not value and rows[row_index - 1][0]:
                            continue
                        if row_index > 0 and not value:
                            continue
                        span = 1
                        while row_index + span < len(rows) and not rows[row_index + span][0]:
                            span += 1
                        attrs = (f' rowspan="{span}"' if span > 1 else '') + ' class="doc-def-group" style="text-align:center;vertical-align:middle"'
                        rendered_cells.append(f"<td{attrs}>{_render_inline(value)}</td>")
                        continue
                    style = f' style="text-align: {alignments[i]}"' if i < len(alignments) and alignments[i] else ""
                    rendered_cells.append(f"<td{style}>{_render_inline(value)}</td>")
                row_class = ' class="doc-def-group-start"' if group_start else ''
                body_rows.append("<tr" + row_class + ">" + "".join(rendered_cells) + "</tr>")
            table_class = ' class="doc-def-table"' if grouped else ''
            output.append(
                '<div class="table-scroll"><table' + table_class + '><thead><tr>'
                + "".join(head_cells)
                + "</tr></thead><tbody>"
                + "".join(body_rows)
                + "</tbody></table></div>"
            )
            continue

        paragraph: list[str] = [line]
        index += 1
        while index < len(lines) and lines[index].strip() and not _starts_block(lines, index):
            paragraph.append(lines[index])
            index += 1
        output.append(f"<p>{_render_paragraph(paragraph)}</p>")

    return "\n".join(output), index, False


# fn: render_markdown - Render Markdown plus the nestable Testadura ``:::`` component extension.
def render_markdown(markdown_text: str) -> str:
    """Render Markdown plus the nestable Testadura ``:::`` component extension."""
    lines = markdown_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    rendered, _index, _closed = _render_lines(lines)
    return rendered
