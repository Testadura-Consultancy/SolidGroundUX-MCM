"""Minimal template loading, partial expansion, and placeholder rendering."""

from __future__ import annotations

from pathlib import Path
import re
from typing import Any


_PLACEHOLDER_RE = re.compile(r"\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}")
_INCLUDE_RE = re.compile(r"\{%\s*include\s+[\"']([^\"']+)[\"']\s*%\}")


def load_template(path: Path, templates_root: Path | None = None, _stack: tuple[Path, ...] = ()) -> str:
    """Load a template and recursively expand ``{% include \"...\" %}`` partials.

    Include paths are resolved from the site's template root, not from the current
    partial. This keeps includes predictable for constructs such as
    ``{% include \"partials/sidebar.html\" %}`` in ``base.html``.
    """
    path = path.resolve()
    if not path.is_file():
        raise ValueError(f"Template not found: {path}")

    root = templates_root.resolve() if templates_root is not None else path.parent
    if path in _stack:
        chain = " -> ".join(str(entry) for entry in (*_stack, path))
        raise ValueError(f"Circular template include detected: {chain}")

    text = path.read_text(encoding="utf-8")
    stack = (*_stack, path)

    def replace_include(match: re.Match[str]) -> str:
        include_name = match.group(1).strip()
        include_path = (root / include_name).resolve()
        try:
            include_path.relative_to(root)
        except ValueError as exc:
            raise ValueError(f"Template include escapes template root: {include_name}") from exc
        return load_template(include_path, root, stack)

    return _INCLUDE_RE.sub(replace_include, text)


def _resolve(context: dict[str, Any], key: str) -> str:
    value: Any = context
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            return ""
        value = value[part]
    if value is None:
        return ""
    return str(value)


def render_template(template: str, context: dict[str, Any]) -> str:
    return _PLACEHOLDER_RE.sub(lambda match: _resolve(context, match.group(1)), template)


def unresolved_placeholders(text: str) -> list[str]:
    return sorted(set(_PLACEHOLDER_RE.findall(text)))
