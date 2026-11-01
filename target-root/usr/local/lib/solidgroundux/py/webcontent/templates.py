"""Minimal template loading, partial expansion, and placeholder rendering."""

from __future__ import annotations

from pathlib import Path
import re
from typing import Any


_PLACEHOLDER_RE = re.compile(r"\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}")
_INCLUDE_RE = re.compile(r"\{%\s*include\s+[\"']([^\"']+)[\"']\s*%\}")



# --- Public functions ------------------------------------------------------------
def load_template(path: Path, templates_root: Path | None = None, _stack: tuple[Path, ...] = ()) -> str:
    """Load a template and recursively expand ``{% include "..." %}`` partials.
        
        Include paths are resolved from the site's template root, not from the current
        partial. This keeps includes predictable for constructs such as
        ``{% include "partials/sidebar.html" %}`` in ``base.html``.
        
        Usage:
        ```python
        template_text = load_template(template_path, templates_root)
        ```"""
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
        """Resolve and expand a template include without escaping its root.
                        
                        Args:
                            match: Regular-expression match for the current substitution.
                        
                        Usage:
                            ```python
                            replace_include(match)
                            ```"""
        include_name = match.group(1).strip()
        include_path = (root / include_name).resolve()
        try:
            include_path.relative_to(root)
        except ValueError as exc:
            raise ValueError(f"Template include escapes template root: {include_name}") from exc
        return load_template(include_path, root, stack)

    return _INCLUDE_RE.sub(replace_include, text)



# --- Internal functions ------------------------------------------------------------
def _resolve(context: dict[str, Any], key: str) -> str:
    """Look up a dotted placeholder key in the supplied template context.
        
        Usage:
            ```python
            _resolve(context, key)
            ```"""
    value: Any = context
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            return ""
        value = value[part]
    if value is None:
        return ""
    return str(value)



# --- Public functions ------------------------------------------------------------
def render_template(template: str, context: dict[str, Any]) -> str:
    """Render a website HTML template with supplied substitutions.
            
            Args:
                template: Template content to render.
                context: Values available for template placeholder substitution.
            
            Usage:
        ```python
        html = render_template(template_text, {"site": {"title": "Documentation"}})
        ```"""
    return _PLACEHOLDER_RE.sub(lambda match: _resolve(context, match.group(1)), template)


def unresolved_placeholders(text: str) -> list[str]:
    """List template placeholders still present after substitution.
        
        Args:
            text: Markdown text to parse or render.
        
        Usage:
            ```python
            unresolved_placeholders(text)
            ```"""
    return sorted(set(_PLACEHOLDER_RE.findall(text)))
