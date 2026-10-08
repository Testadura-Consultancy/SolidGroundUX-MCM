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


def referenced_style_classes(markdown_text: str, prefix: str) -> set[str]:
    classes = {name for name in _STYLE_CLASS_RE.findall(markdown_text) if name.startswith(prefix)}
    for block_spec in _BLOCK_CLASS_RE.findall(markdown_text):
        classes.update(
            name for name in _CLASS_NAME_RE.findall(block_spec)
            if name.startswith(prefix)
        )
    return classes


def _safe_url(value: str) -> str:
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() in {"javascript", "data"}:
        return "#"
    return value


def _render_inline(text: str) -> str:
    escaped = html.escape(text, quote=False)
    tokens: dict[str, str] = {}

    def stash(fragment: str) -> str:
        key = f"\x00WC{len(tokens)}\x00"
        tokens[key] = fragment
        return key

    def code_repl(match: re.Match[str]) -> str:
        return stash(f"<code>{html.escape(match.group(1), quote=False)}</code>")

    escaped = re.sub(r"`([^`]+)`", code_repl, escaped)

    image_pattern = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)(?:\{([^}]+)\})?")

    def image_repl(match: re.Match[str]) -> str:
        alt = match.group(1)
        src = html.escape(_safe_url(html.unescape(match.group(2))), quote=True)
        classes = " ".join(_STYLE_CLASS_RE.findall(match.group(3) or ""))
        class_attr = f' class="{html.escape(classes, quote=True)}"' if classes else ""
        return stash(f'<img src="{src}" alt="{alt}"{class_attr}>')

    escaped = image_pattern.sub(image_repl, escaped)

    link_pattern = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

    def link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        href = html.escape(_safe_url(html.unescape(match.group(2))), quote=True)
        return stash(f'<a href="{href}">{label}</a>')

    escaped = link_pattern.sub(link_repl, escaped)

    style_pattern = re.compile(r"\[([^\]]+)\]\{([^}]+)\}")

    def style_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        classes = " ".join(_STYLE_CLASS_RE.findall(match.group(2)))
        if not classes:
            return label
        return stash(f'<span class="{html.escape(classes, quote=True)}">{label}</span>')

    escaped = style_pattern.sub(style_repl, escaped)

    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", escaped)

    for key, fragment in tokens.items():
        escaped = escaped.replace(key, fragment)
    return escaped


def _is_table_separator(line: str) -> bool:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def _table_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _starts_block(lines: list[str], index: int) -> bool:
    line = lines[index]
    stripped = line.strip()
    if not stripped:
        return True
    if stripped.startswith("```") or stripped.startswith(":::"):
        return True
    if re.match(r"^#{2,3}\s+", stripped):
        return True
    if re.fullmatch(r"-{3,}", stripped):
        return True
    if stripped.startswith(">"):
        return True
    if re.match(r"^[-*+]\s+", stripped) or re.match(r"^\d+[.)]\s+", stripped):
        return True
    if "|" in line and index + 1 < len(lines) and _is_table_separator(lines[index + 1]):
        return True
    return False


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
            classes = " ".join(_CLASS_NAME_RE.findall(stripped[3:].strip()))
            index += 1
            inner, index, _closed = _render_lines(
                lines,
                index,
                stop_at_component_end=True,
            )
            class_attr = f' class="{html.escape(classes, quote=True)}"' if classes else ""
            output.append(f"<div{class_attr}>\n{inner}\n</div>")
            continue

        heading = re.match(r"^(#{2,3})\s+(.+)$", stripped)
        if heading:
            level = len(heading.group(1))
            output.append(f"<h{level}>{_render_inline(heading.group(2))}</h{level}>")
            index += 1
            continue

        if re.fullmatch(r"-{3,}", stripped):
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

        if re.match(r"^[-*+]\s+", stripped):
            items: list[str] = []
            while index < len(lines):
                match = re.match(r"^[-*+]\s+(.+)$", lines[index].strip())
                if not match:
                    break
                items.append(f"<li>{_render_inline(match.group(1))}</li>")
                index += 1
            output.append("<ul>\n" + "\n".join(items) + "\n</ul>")
            continue

        if re.match(r"^\d+[.)]\s+", stripped):
            items = []
            while index < len(lines):
                match = re.match(r"^\d+[.)]\s+(.+)$", lines[index].strip())
                if not match:
                    break
                items.append(f"<li>{_render_inline(match.group(1))}</li>")
                index += 1
            output.append("<ol>\n" + "\n".join(items) + "\n</ol>")
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

            head_cells: list[str] = []
            for i, cell in enumerate(headers):
                style = f' style="text-align: {alignments[i]}"' if i < len(alignments) and alignments[i] else ""
                head_cells.append(f"<th{style}>{_render_inline(cell)}</th>")
            body_rows: list[str] = []
            for row in rows:
                rendered_cells: list[str] = []
                for i in range(len(headers)):
                    value = row[i] if i < len(row) else ""
                    style = f' style="text-align: {alignments[i]}"' if i < len(alignments) and alignments[i] else ""
                    rendered_cells.append(f"<td{style}>{_render_inline(value)}</td>")
                body_rows.append("<tr>" + "".join(rendered_cells) + "</tr>")
            output.append(
                '<div class="table-scroll"><table><thead><tr>'
                + "".join(head_cells)
                + "</tr></thead><tbody>"
                + "".join(body_rows)
                + "</tbody></table></div>"
            )
            continue

        paragraph: list[str] = [stripped]
        index += 1
        while index < len(lines) and lines[index].strip() and not _starts_block(lines, index):
            paragraph.append(lines[index].strip())
            index += 1
        output.append(f"<p>{_render_inline(' '.join(paragraph))}</p>")

    return "\n".join(output), index, False


def render_markdown(markdown_text: str) -> str:
    """Render Markdown plus the nestable Testadura ``:::`` component extension."""
    lines = markdown_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    rendered, _index, _closed = _render_lines(lines)
    return rendered
