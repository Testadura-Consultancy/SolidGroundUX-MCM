"""Static website generation, including navigation and page-context title bars."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from email.utils import format_datetime
from datetime import timezone
from xml.etree import ElementTree as ET
from urllib.parse import urljoin, unquote
import html
import sys
from pathlib import Path
import shutil
import re
import hashlib
from urllib.parse import urlsplit, quote
from typing import Iterable

from .content import (
    ContentItem,
    FeaturedItem,
    NavigationItem,
    discover_content,
    language_route,
    load_featured,
    load_navigation,
    load_site_config,
)
from .markdown import render_markdown
from .templates import load_template, render_template, unresolved_placeholders
from .validation import validate_site


# cls: GenerationResult - Outcome and diagnostics from a website generation run.
@dataclass(slots=True)
class GenerationResult:
    """Outcome and diagnostics from a website generation run."""
    success: bool
    output: str
    pages_generated: int = 0
    articles_generated: int = 0
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    skipped_pages: int = 0
    broken_links: int = 0
    sitemap_generated: bool = False
    rss_generated: bool = False

    # fn: as_dict - Serialize the result to a JSON-compatible mapping.
    def as_dict(self) -> dict[str, object]:
        """Serialize the result to a JSON-compatible mapping.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return {
            "success": self.success,
            "output": self.output,
            "pages_generated": self.pages_generated,
            "articles_generated": self.articles_generated,
            "warnings": self.warnings,
            "errors": self.errors,
            "skipped_pages": self.skipped_pages,
            "broken_links": self.broken_links,
            "sitemap_generated": self.sitemap_generated,
            "rss_generated": self.rss_generated,
        }


# fn: _normalize_languages - Normalize selected languages into canonical language identifiers.
def _normalize_languages(value: str | Iterable[str], supported: list[str]) -> set[str]:
    """Normalize languages to a canonical representation."""
    if isinstance(value, str):
        if value.upper() == "ALL":
            return set(supported)
        raw = [part.strip().upper() for part in value.split(",") if part.strip()]
    else:
        raw = [str(part).strip().upper() for part in value]
    selected = set(raw)
    unknown = selected - set(supported)
    if unknown:
        raise ValueError(f"Unsupported language(s): {', '.join(sorted(unknown))}")
    return selected


# fn: _route_to_output - Map a content route to its destination in the generated website tree.
def _route_to_output(output_root: Path, route: str) -> Path:
    """Handle route to output for the web content workflow."""
    clean = route.strip("/")
    if not clean:
        return output_root / "index.html"
    return output_root / clean / "index.html"


_ROOT_RELATIVE_URL_RE = re.compile(
    r'(?P<prefix>\b(?:href|src)\s*=\s*["\'])(?P<url>/(?!/)[^"\']*)(?P<suffix>["\'])',
    re.IGNORECASE,
)


# fn: _make_output_relative_urls - Make site-local root-relative URLs work both over HTTP and ``file://``.
# . Description
#   Generated pages can live at arbitrary route depth. Rewriting ``/css/...``, ``/images/...`` and internal ``href="/..."`` targets to a path relative to
def _make_output_relative_urls(document: str, route: str) -> str:
    """Make site-local root-relative URLs work both over HTTP and ``file://``.

    Generated pages can live at arbitrary route depth. Rewriting ``/css/...``,
    ``/images/...`` and internal ``href="/..."`` targets to a path relative to
    the generated page preserves normal web-server behaviour while also making a
    generated output tree directly browsable from disk. External and protocol-
    relative URLs are left untouched.
    """
    depth = len([part for part in route.strip("/").split("/") if part])
    root_prefix = "../" * depth

    # fn: replace - Substitute the current matched fragment during content rendering.
    # . Description
    #   Args: match: Input used by this operation.
    def replace(match: re.Match[str]) -> str:
        """Handle replace for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        target = match.group("url")
        if target == "/":
            relative = root_prefix or "./"
        else:
            relative = root_prefix + target.lstrip("/")
        return match.group("prefix") + relative + match.group("suffix")

    return _ROOT_RELATIVE_URL_RE.sub(replace, document)


# Fingerprint local CSS/JS assets by their *content* so unchanged resources keep
# a stable URL, while changed resources bypass stale browser cache entries.
_VERSIONED_ASSET_RE = re.compile(
    r'(?P<prefix>\b(?:href|src)\s*=\s*["\'])(?P<url>/(?!/)[^"\']+)(?P<suffix>["\'])',
    re.IGNORECASE,
)


# fn: _version_local_assets - Append a content hash to root-relative local .css/.js href/src links.
# . Description
#   Existing query parameters and fragments are preserved. Paths are restricted to files inside the generated output root (never arbitrary filesystem paths).
def _version_local_assets(document: str, output_root: Path) -> str:
    """Append a content hash to root-relative local .css/.js href/src links.

    Existing query parameters and fragments are preserved. Paths are restricted
    to files inside the generated output root (never arbitrary filesystem paths).
    This is applied before URLs are made relative for file:// preview support.
    """
    resolved_root = output_root.resolve()
    digests: dict[Path, str] = {}

    # fn: replace - Substitute the current matched fragment during content rendering.
    def replace(match: re.Match[str]) -> str:
        url = match.group("url")
        parsed = urlsplit(url)
        if parsed.path.lower().endswith((".css", ".js")):
            target = (resolved_root / unquote(parsed.path).lstrip("/")).resolve()
            if target.is_relative_to(resolved_root) and target.is_file():
                if target not in digests:
                    digests[target] = hashlib.sha256(target.read_bytes()).hexdigest()[:12]
                # Replace any previously generated v= parameter, keeping other
                # query fields. In normal authored assets, v is generator-owned.
                from urllib.parse import parse_qsl, urlencode, urlunsplit
                params = [(k, v) for k, v in parse_qsl(parsed.query, keep_blank_values=True) if k != "v"]
                params.append(("v", digests[target]))
                url = urlunsplit(("", "", parsed.path, urlencode(params), parsed.fragment))
        return match.group("prefix") + url + match.group("suffix")

    return _VERSIONED_ASSET_RE.sub(replace, document)


# fn: _base_route_for_item - Derive the canonical base route of a content item.
def _base_route_for_item(item: ContentItem, default_language: str) -> str:
    """Handle base route for item for the web content workflow."""
    route = item.route
    if item.language == default_language:
        return route
    prefix = f"/{item.language.lower()}"
    if route == f"{prefix}/":
        return "/"
    if route.startswith(prefix + "/"):
        return route[len(prefix) :]
    return route


# fn: _ignore_marked_directories - Exclude marked asset subtrees and the marker itself during copying.
def _ignore_marked_directories(directory: str, names: list[str]) -> set[str]:
    """Exclude marked asset subtrees and the marker itself during copying."""
    root = Path(directory)
    ignored = {".ignore"} if ".ignore" in names else set()
    ignored.update(name for name in names if (root / name).is_dir() and (root / name / ".ignore").is_file())
    return ignored


# fn: _render_navigation - Build a recursive sidebar from translated page titles and content routes.
# . Description
#   Section indexes supply navigation labels and ordering at every depth. Existing intermediate folders can still group ordinary pages until the
def _render_navigation(
    navigation: list[NavigationItem],
    items: list[ContentItem],
    language: str,
    default_language: str,
    current_base_route: str,
    doc_sidebar: bool = False,
) -> str:
    """Build a recursive sidebar from translated page titles and content routes.

    Section indexes supply navigation labels and ordering at every depth.
    Existing intermediate folders can still group ordinary pages until the
    index-only section migration is complete. Hidden index pages
    conceal their entire subtree by CSS until ShowHidden is present; hidden
    ordinary pages conceal only themselves. Private pages require server auth
    and are not protected by navigation metadata.
    """
    # Keep hidden pages in the generated navigation. The existing ShowHidden
    # CSS/JavaScript toggles their visibility at runtime. A hidden index marks
    # its entire folder node as hidden, so all descendants are concealed too.
    # This is presentation only; private access remains enforced by Nginx.
    # Navigation is built from actual published pages. If a page has no
    # translation in the selected language, retain the Dutch page as a
    # navigable fallback; never manufacture a translated URL or hreflang.
    pages = {
        _base_route_for_item(page, default_language): page
        for page in items
        if page.language == default_language
    }
    pages.update({
        _base_route_for_item(page, default_language): page
        for page in items
        if page.language == language
    })
    # Folder nodes keyed by directory route, with optional index-page content.
    nodes: dict[str, dict] = {"/": {"children": set(), "page": pages.get("/")}}
    for route, page in pages.items():
        pieces = [p for p in route.strip("/").split("/") if p]
        # A non-index Markdown file lives below its containing folder.
        folders = pieces if page.base_name == "index" else pieces[:-1]
        parent = "/"
        for depth in range(len(folders)):
            folder = "/" + "/".join(folders[:depth + 1]) + "/"
            nodes.setdefault(folder, {"children": set(), "page": None})
            nodes[parent]["children"].add(folder)
            parent = folder
        if page.base_name == "index":
            nodes.setdefault(route, {"children": set(), "page": None})["page"] = page
        else:
            nodes.setdefault(parent, {"children": set(), "page": None})["children"].add(route)
            nodes[route] = {"children": set(), "page": page}

    top = sorted(navigation, key=lambda n: n.order)
    roots = [n.path for n in top if n.path in nodes and n.labels.get(language)]
    # Root entries are discovered from section indexes, not navigation.cfg.
    top_by_path = {n.path: n for n in top}

    # fn: label_for - Choose the display label for a navigation item.
    def label_for(route: str) -> str:
        page = nodes[route]["page"]
        # Root groups keep their explicitly authored navigation labels, even
        # when a translated index page has a different title.
        nav = top_by_path.get(route)
        if nav and nav.labels.get(language):
            return nav.labels[language]
        if page:
            return str(page.metadata.get("nav_title") or page.title)
        return route.strip("/").split("/")[-1].replace("-", " ").capitalize()

    # fn: render - Render a content item or navigation section using its configured template.
    def render(route: str, ancestors: set[str]) -> str:
        if route in ancestors:
            return ""
        node = nodes[route]
        # Home is its own navigation entry, not a container for every section.
        child_routes = () if route == "/" else node["children"]
        # fn: child_order - Prefer section navigation order over ordinary page ordering.
        def child_order(child_route: str) -> int:
            """Prefer section navigation order over ordinary page ordering."""
            child_page = nodes[child_route]["page"]
            if child_page is None:
                return 1000
            raw_order = child_page.metadata.get("nav_order", child_page.order)
            try:
                return int(raw_order)
            except (TypeError, ValueError):
                return 1000

        children = sorted(child_routes, key=lambda r: (
            child_order(r), label_for(r).casefold(), r,
        ))

        # Resolve an absent section page to its first available descendant.
        # Invisible and navigation-only pages are not valid destinations.
        def first_visible_page(candidate: str, visited: set[str]) -> ContentItem | None:
            if candidate in visited:
                return None
            candidate_node = nodes[candidate]
            candidate_page = candidate_node["page"]
            if candidate_page and not candidate_page.hidden and not candidate_page.metadata.get("nav_only"):
                return candidate_page
            ordered = sorted(candidate_node["children"], key=lambda r: (
                child_order(r), label_for(r).casefold(), r,
            ))
            for descendant in ordered:
                result = first_visible_page(descendant, visited | {candidate})
                if result is not None:
                    return result
            return None

        label = html.escape(label_for(route))
        page = node["page"]
        # Authored indexes are content pages: their section title must remain
        # a route to that content. Navigation-only indexes have no published
        # page of their own, so their title points at the first visible child.
        destination = page if page and not page.metadata.get("nav_only") else None
        alias_child = None
        if destination is None:
            for child in children:
                destination = first_visible_page(child, {route})
                if destination is not None:
                    # Hide only a directly linked leaf. Removing a child group
                    # would also remove the navigation to all its descendants.
                    if (doc_sidebar and not nodes[child]["children"]
                            and nodes[child]["page"] is destination):
                        alias_child = child
                    break
        destination_base_route = (_base_route_for_item(destination, default_language)
                                  if destination is not None else None)
        active = current_base_route == route or (
            alias_child is not None and current_base_route == destination_base_route
        )
        expanded = active or (route.endswith("/") and current_base_route.startswith(route))
        classes = ' class="active"' if active else ""
        current = ' aria-current="page"' if active else ""
        link = (f'<a href="{html.escape(destination.route, quote=True)}"{classes}{current}>{label}</a>'
                if destination is not None else f'<span class="wc-nav-label">{label}</span>')
        # A hidden section index conceals this node and all descendants in
        # normal navigation; ShowHidden reveals the complete subtree. Ordinary
        # hidden pages conceal their own leaf only.
        hidden_class = ' wc-hidden-link' if page is not None and page.hidden else ''
        if not children:
            return '<div class="wc-nav-leaf' + hidden_class + '">' + link + '</div>'
        child_html = "".join(render(child, ancestors | {route}) for child in children if child != alias_child)
        if not doc_sidebar:
            # Preserve the historical WWW markup for sites with their own
            # templates and stylesheets. Only the documentation layout uses
            # the independent title/disclosure presentation.
            return ('<details class="wc-nav-group' + hidden_class + '"'
                    + (' open' if expanded else '') + '>'
                    '<summary><span class="wc-nav-arrow" aria-hidden="true"></span>'
                    + link + '</summary><div class="wc-nav-children">' + child_html
                    + '</div></details>')
        if alias_child is not None and len(children) == 1:
            # A section with one page has nothing left to expand.
            return '<div class="wc-nav-leaf' + hidden_class + '">' + link + '</div>'
        # Put the destination outside <details>. Browsers hide all non-summary
        # descendants of closed <details>, and nested links within <summary>
        # compete with the native disclosure action. The title therefore stays
        # visible and navigates normally; only the chevron toggles children.
        return ('<div class="wc-nav-group' + hidden_class + '">'
                '<div class="wc-nav-heading">' + link + '</div>'
                '<details class="wc-nav-disclosure"' + (' open' if expanded else '') + '>'
                '<summary aria-label="Toggle ' + html.escape(label_for(route), quote=True)
                + '"><span class="wc-nav-arrow" aria-hidden="true"></span></summary>'
                '<div class="wc-nav-children">' + child_html + '</div></details></div>')

    # Root and nested navigation are both derived from index/page metadata.
    return "\n".join(render(route, set()) for route in roots)


# fn: _render_external_links - Render external links for website output.
def _render_external_links(links: dict[str, str]) -> str:
    """Render external links for website output."""
    result: list[str] = []
    labels = {"linkedin": "LinkedIn", "github": "GitHub"}
    for key, url in links.items():
        if not url:
            continue
        result.append(
            f'<a href="{html.escape(url, quote=True)}" rel="me noopener" target="_blank">{html.escape(labels.get(key, key.title()))}</a>'
        )
    return "\n".join(result)


# fn: _source_filename - Return the original source filename for generated documentation pages.
def _source_filename(item: ContentItem) -> str:
    """Use explicit provenance, or the legacy source index's Source line."""
    value = item.metadata.get("source_file")
    if isinstance(value, str) and value.strip():
        # Metadata is display-only; do not allow a path or URL as a label.
        return Path(value.strip().replace("\\", "/")).name
    if item.template == "source":
        match = re.search(r"(?m)^\*\*Source:\*\* `([^`\n]+)`\s*$", item.body)
        if match:
            return Path(match.group(1).replace("\\", "/")).name
    return ""


# fn: _render_breadcrumb - Show the section hierarchy down to the actual source file.
# . Description
#   Link publishable ancestor indexes. Navigation-only chapters remain plain text.
#   Source pages use their original filename, not their display title.
def _render_breadcrumb(items: list[ContentItem], item: ContentItem, default_language: str) -> str:
    """Show available ancestors and, for generated pages, the source filename.

    Prefer same-language section indexes, with the published default-language
    index as a fallback. Never synthesize a URL for a navigation-only section.
    """
    current_base_route = _base_route_for_item(item, default_language)
    current_parts = [part for part in current_base_route.strip("/").split("/") if part]
    ancestor_routes = [
        "/" + "/".join(current_parts[:depth]) + "/"
        for depth in range(1, len(current_parts))
    ]
    indexes: dict[tuple[str, str], ContentItem] = {
        (_base_route_for_item(candidate, default_language), candidate.language): candidate
        for candidate in items
        if candidate.base_name == "index"
    }
    parts: list[str] = []
    last_source_filename = ""
    for route in ancestor_routes:
        ancestor = (indexes.get((route, item.language))
                    or indexes.get((route, default_language)))
        if ancestor is None:
            continue
        filename = _source_filename(ancestor)
        label = html.escape(filename or str(ancestor.metadata.get("nav_title") or ancestor.title))
        if ancestor.metadata.get("nav_only"):
            parts.append(f"<li><span>{label}</span></li>")
        else:
            parts.append(
                '<li><a href="'
                + html.escape(ancestor.route, quote=True)
                + '">'
                + label
                + "</a></li>"
            )
        if filename:
            last_source_filename = filename

    # Source overviews and standalone prefaces do not have a source-file
    # ancestor. Function pages already link to their source overview.
    filename = _source_filename(item)
    if filename and filename != last_source_filename:
        parts.append(f'<li><span aria-current="location">{html.escape(filename)}</span></li>')
    if not parts:
        return ""
    return (
        '<nav class="context-breadcrumb" aria-label="Breadcrumb"><ol>'
        + "".join(parts)
        + "</ol></nav>"
    )


# fn: _context_header - Render page context; language navigation lives in the persistent sidebar.
def _context_header(
    breadcrumb_html: str, page_title: str, page_type: str
) -> str:
    """Render the page title and breadcrumb in the documentation header."""
    width_class = " context-header-inner-narrow" if page_type in {"page", "article"} else ""
    return (
        '<div class="context-header" id="contextHeader">'
        f'<div class="context-header-inner{width_class}">'
        '<div class="context-header-copy">'
        + breadcrumb_html
        + f'<h1 class="context-title">{html.escape(page_title)}</h1>'
        + "</div>"
        + "</div></div>"
    )


_LANGUAGE_NAMES = {
    "NL": "Nederlands",
    "EN": "English",
    "DE": "Deutsch",
    "IT": "Italiano",
}


# fn: _render_language_selector - Show enabled languages, linking missing translations to the real Dutch page.
# . Description
#   A fallback link is navigation, not a translation: do not mark it hreflang. Only published/preview-visible variants supplied by the caller are eligible.
def _render_language_selector(
    config,
    item: ContentItem,
    variants: dict[str, dict[str, ContentItem]],
    selected_languages: set[str],
) -> str:
    """Show enabled languages, linking missing translations to the real Dutch page.

    A fallback link is navigation, not a translation: do not mark it hreflang.
    Only published/preview-visible variants supplied by the caller are eligible.
    """
    available = {
        language: variant
        for language, variant in variants.get(item.logical_id, {}).items()
        if language in selected_languages
    }
    fallback = available.get(config.default_language)
    if not available:
        return ""

    links: list[str] = []
    for language in config.supported_languages:
        if language not in selected_languages:
            continue
        variant = available.get(language)
        target = variant or fallback
        if target is None:
            # No translated page and no default-language page to link to.
            continue

        label = _LANGUAGE_NAMES.get(language, language)
        png_name = f"flag_{language.upper()}.png"
        flag_url = f"/images/{png_name}" if (config.images_dir / png_name).is_file() else ""
        if flag_url:
            content = (
                f'<img class="language-flag" src="{html.escape(flag_url, quote=True)}" '
                f'alt="" aria-hidden="true">'
            )
        else:
            content = f'<span class="language-code">{html.escape(language)}</span>'

        common = (
            f'class="language-option" lang="{html.escape(language.lower(), quote=True)}" '
            f'title="{html.escape(label, quote=True)}" aria-label="{html.escape(label, quote=True)}"'
        )
        if language == item.language:
            links.append(f'<span {common} aria-current="page">{content}</span>')
        elif variant is not None:
            links.append(
                f'<a {common} hreflang="{html.escape(language.lower(), quote=True)}" '
                f'href="{html.escape(target.route, quote=True)}">{content}</a>'
            )
        else:
            # Missing translation: link to Dutch content without claiming that
            # it is a page in the requested language.
            links.append(
                f'<a {common} href="{html.escape(target.route, quote=True)}">{content}</a>'
            )

    partial_path = config.templates_dir / "partials" / "language-selector.html"
    if not partial_path.is_file():
        return " ".join(links)
    return render_template(load_template(partial_path, config.templates_dir), {"language_links": "\n".join(links)})


# fn: _article_meta - Collect metadata for RSS and article-page generation.
def _article_meta(item: ContentItem) -> str:
    """Handle article meta for the web content workflow."""
    parts: list[str] = []
    if item.date:
        parts.append(f'<time datetime="{html.escape(item.date, quote=True)}">{html.escape(item.date)}</time>')
    if item.tags:
        parts.append('<span class="article-tags">' + " · ".join(html.escape(tag) for tag in item.tags) + "</span>")
    if not parts:
        return ""
    return '<div class="article-meta">' + "\n".join(parts) + "</div>"


# fn: _summary_fragment - Render the visible excerpt of a content summary.
def _summary_fragment(item: ContentItem) -> str:
    """Handle summary fragment for the web content workflow."""
    if not item.summary:
        return ""
    return f'<p class="page-summary">{html.escape(item.summary)}</p>'


# fn: _image_for - Prefer index art, then hero art; publish local assets safely.
def _image_for(item: ContentItem, config, output_path: Path) -> str:
    """Prefer index art, then hero art; publish local assets safely."""
    for key in ("index_image", "hero_image"):
        reference = str(item.metadata.get(key) or "").strip()
        if reference:
            return _publish_image(reference, item, config, output_path)
    return ""


# fn: _publish_image - Resolve relative author images beside Markdown, without escaping content root.
def _publish_image(reference: str, item: ContentItem, config, output_path: Path) -> str:
    """Resolve relative author images beside Markdown, without escaping content root."""
    parsed = urlsplit(reference)
    if parsed.scheme in ("http", "https") or reference.startswith("//"):
        return reference
    if parsed.scheme or reference.startswith("#"):
        return ""
    if reference.startswith("/"):
        return reference
    candidate = (item.source_path.parent / parsed.path).resolve()
    allowed = (config.content_dir.resolve(), config.images_dir.resolve())
    if not candidate.is_file() or not any(candidate.is_relative_to(root) for root in allowed):
        return ""
    digest = hashlib.sha256(str(candidate).encode("utf-8")).hexdigest()[:12]
    destination = output_path / "images" / "content" / f"{digest}-{candidate.name}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidate, destination)
    return "/images/content/" + destination.name + ("?" + parsed.query if parsed.query else "")


# fn: _publish_local_resource - Publish a relative content-local download, retaining its resource filename.
# . Description
#   Only regular files inside the source content tree are eligible. Resources are published under a dedicated directory, avoiding collisions with shared assets.
def _publish_local_resource(reference: str, item: ContentItem, config, output_path: Path) -> str:
    """Publish a relative content-local download, retaining its resource filename.

    Only regular files inside the source content tree are eligible. Resources are
    published under a dedicated directory, avoiding collisions with shared assets.
    """
    parsed = urlsplit(reference)
    if parsed.scheme or parsed.netloc or reference.startswith(("/", "#")):
        return reference
    if not parsed.path or not parsed.path.lower().startswith("resources/") and "/resources/" not in parsed.path.lower():
        return reference
    root = config.content_dir.resolve()
    candidate = (item.source_path.parent / parsed.path).resolve()
    if not candidate.is_file() or not candidate.is_relative_to(root):
        return reference
    relative = candidate.relative_to(root)
    destination = output_path / "content-resources" / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidate, destination)
    encoded = "/content-resources/" + "/".join(quote(part) for part in relative.parts)
    return encoded + ("?" + parsed.query if parsed.query else "") + ("#" + parsed.fragment if parsed.fragment else "")


# fn: _resolve_body_resources - Rewrite Markdown download links to published local resource URLs.
# . Description
#   Image links continue to be handled by _resolve_body_images. Existing remote, absolute and anchor links remain unchanged.
def _resolve_body_resources(body: str, item: ContentItem, config, output_path: Path) -> str:
    """Rewrite Markdown download links to published local resource URLs.

    Image links continue to be handled by _resolve_body_images. Existing remote,
    absolute and anchor links remain unchanged.
    """
    pattern = re.compile(r'(?<!!)\[([^\]]+)\]\(([^)]+)\)')
    # fn: replace - Substitute the current matched fragment during content rendering.
    def replace(match: re.Match[str]) -> str:
        reference = match.group(2)
        published = _publish_local_resource(reference, item, config, output_path)
        return match.group(0) if published == reference else f'[{match.group(1)}]({published})'
    return pattern.sub(replace, body)


# fn: _resolve_body_images - Rewrite local Markdown images before Markdown rendering; leave external URLs intact.
def _resolve_body_images(body: str, item: ContentItem, config, output_path: Path) -> str:
    """Rewrite local Markdown images before Markdown rendering; leave external URLs intact."""
    pattern = re.compile(r'(!\[[^\]]*\]\()([^\)]+)(\))')
    # fn: replace - Substitute the current matched fragment during content rendering.
    # . Description
    #   Args: match: Input used by this operation.
    def replace(match: re.Match[str]) -> str:
        """Handle replace for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        reference = match.group(2)
        resolved = _publish_image(reference, item, config, output_path)
        return match.group(1) + (resolved or reference) + match.group(3)
    return pattern.sub(replace, body)


# fn: _card - Render an existing section card, optionally with its identifying image.
def _card(item: ContentItem, heading_level: int = 2, image: str = "") -> str:
    """Render an existing section card, optionally with its identifying image."""
    heading_level = 2 if heading_level not in {2, 3} else heading_level
    summary = f"<p>{html.escape(item.summary)}</p>" if item.summary else ""
    date = f'<time datetime="{html.escape(item.date, quote=True)}">{html.escape(item.date)}</time>' if item.date else ""
    media = (f'<a class="index-card-media" href="{html.escape(item.route, quote=True)}">'
             f'<img src="{html.escape(image, quote=True)}" alt="" loading="lazy"></a>') if image else ""
    return ('<article class="article-card">' + media
            + f'<h{heading_level}><a href="{html.escape(item.route, quote=True)}">{html.escape(item.title)}</a></h{heading_level}>'
            + date + summary + '</article>')


# fn: _index_row - Build the structured row for a generated content index.
def _index_row(item: ContentItem, image: str, *, article: bool) -> str:
    """Handle index row for the web content workflow."""
    media = (f'<img src="{html.escape(image, quote=True)}" alt="" loading="lazy">') if image else ""
    date = (f'<time datetime="{html.escape(item.date, quote=True)}">{html.escape(item.date)}</time>'
            if article and item.date else "")
    summary = f'<p>{html.escape(item.summary)}</p>' if item.summary else ""
    return (f'<a class="index-row" href="{html.escape(item.route, quote=True)}">'
            + (f'<span class="index-row-image">{media}</span>' if media else '')
            + f'<span class="index-row-content">{date}<strong>{html.escape(item.title)}</strong>{summary}'
            + '</span><span class="index-row-arrow" aria-hidden="true">›</span></a>')


# fn: _render_index - Render index for website output.
def _render_index(item: ContentItem, items: list[ContentItem], default_language: str,
                  config, output_path: Path, kind: str = "auto", sort: str = "") -> str:
    """Render index for website output."""
    children = [child for child in _direct_children(item, items, default_language) if not child.hidden]
    if not children:
        return ""
    kind = kind if kind in {"auto", "cards", "list", "articles"} else "auto"
    if kind == "auto":
        kind = "cards" if len(children) <= 4 else "list"
    if sort == "newest" or (kind == "articles" and sort != "order"):
        children.sort(key=lambda child: (child.date, child.title.lower()), reverse=True)
    if kind == "cards":
        content = '\n'.join(_card(child, 3, _image_for(child, config, output_path)) for child in children)
        return f'<div class="article-list index-cards">{content}</div>'
    content = '\n'.join(_index_row(child, _image_for(child, config, output_path), article=(kind == "articles")) for child in children)
    return f'<div class="index-rows index-{kind}">{content}</div>'


_INDEX_BLOCK_RE = re.compile(r'^\s*:::\s+(?:index|td-index)([^\n]*)\n\s*:::\s*$', re.MULTILINE)
_INDEX_OPTION_RE = re.compile(r'(type|sort)\s*=\s*["\']?([A-Za-z]+)')


# fn: _explicit_indexes - Replace index blocks with inert markers restored after Markdown rendering.
def _explicit_indexes(body: str, item: ContentItem, items: list[ContentItem],
                      default_language: str, config, output_path: Path) -> tuple[str, dict[str, str]]:
    """Replace index blocks with inert markers restored after Markdown rendering."""
    replacements: dict[str, str] = {}
    # fn: replace - Substitute the current matched fragment during content rendering.
    # . Description
    #   Args: match: Input used by this operation.
    def replace(match: re.Match[str]) -> str:
        """Handle replace for the web content workflow.
        
        Args:
            match: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        options = dict(_INDEX_OPTION_RE.findall(match.group(1)))
        marker = f"WCINDEXPLACEHOLDER{len(replacements)}END"
        replacements[marker] = _render_index(item, items, default_language, config, output_path,
                                              options.get("type", "auto"), options.get("sort", ""))
        return "\n\n" + marker + "\n\n"
    return _INDEX_BLOCK_RE.sub(replace, body), replacements


# fn: _direct_children - Find immediate children, preferring the page language and then Dutch.
# . Description
#   A language-specific listing may reference a Dutch-only child directly. Resolve each logical page once so translations never create duplicate cards
def _direct_children(item: ContentItem, items: list[ContentItem], default_language: str) -> list[ContentItem]:
    """Find immediate children, preferring the page language and then Dutch.

    A language-specific listing may reference a Dutch-only child directly.
    Resolve each logical page once so translations never create duplicate cards
    or links to pages that were not generated.
    """
    if item.base_name != "index":
        return []

    parent_route = _base_route_for_item(item, default_language)
    parent_parts = [part for part in parent_route.strip("/").split("/") if part]
    variants: dict[str, dict[str, ContentItem]] = {}
    for child in items:
        if child.logical_id == item.logical_id:
            continue
        child_route = _base_route_for_item(child, default_language)
        child_parts = [part for part in child_route.strip("/").split("/") if part]
        if len(child_parts) != len(parent_parts) + 1 or child_parts[:len(parent_parts)] != parent_parts:
            continue
        variants.setdefault(child.logical_id, {})[child.language] = child

    children = []
    for available in variants.values():
        chosen = available.get(item.language) or available.get(default_language)
        if chosen is not None:
            children.append(chosen)
    children.sort(key=lambda child: (child.order, child.title.lower()))
    return children


# fn: _featured_card - Render one curated Featured tile using target-page metadata.
def _featured_card(item: ContentItem, image: str = "") -> str:
    """Render one curated Featured tile using target-page metadata."""
    # Explicit curated image wins; otherwise use article metadata or a section default.
    if not image:
        image = str(item.metadata.get("featured_image") or item.metadata.get("image") or item.metadata.get("index_image") or "")
    if not image:
        if item.route.startswith("/tales/"):
            image = "/images/trenchtales-default.jpg"
        elif item.route.startswith("/overpeinzingen/"):
            image = "/images/overpeinzingen-default.png"
        elif item.route.startswith("/sages/"):
            image = "/images/sageslegendes-default.png"
    image_html = ""
    fit = str(item.metadata.get("featured_image_fit") or "cover").strip().lower()
    if fit not in {"cover", "contain"}:
        fit = "cover"
    if image:
        image_html = (
            f'<a class="featured-card-media featured-card-media--{fit}" href="{html.escape(item.route, quote=True)}" tabindex="-1">'
            f'<img src="{html.escape(image, quote=True)}" alt="">'
            "</a>"
        )

    labels = {
        "NL": "Lees meer",
        "EN": "Read more",
        "DE": "Mehr lesen",
        "IT": "Leggi di piu",
    }
    read_more = labels.get(item.language, "Read more")
    summary = (
        f'<p class="featured-card-summary"><em>{html.escape(item.summary)}</em></p>'
        if item.summary
        else ""
    )
    return (
        '<article class="featured-card" role="listitem">'
        + image_html
        + '<div class="featured-card-body">'
        + f'<h3><a href="{html.escape(item.route, quote=True)}">{html.escape(item.title)}</a></h3>'
        + summary
        + f'<a class="featured-card-more" href="{html.escape(item.route, quote=True)}">'
        + f'{html.escape(read_more)} <span aria-hidden="true">→</span></a>'
        + "</div></article>"
    )


# fn: _featured_for - Render the home-page Featured slider.
# . Description
#   ``featured.cfg`` is authoritative when present. Routes are resolved against the current language and silently omitted when that translation does not yet
def _featured_for(
    item: ContentItem,
    items: list[ContentItem],
    featured_items: list[FeaturedItem],
    default_language: str,
    configured: bool,
    autoplay_interval: int = 0,
) -> str:
    """Render the home-page Featured slider.

    ``featured.cfg`` is authoritative when present. Routes are resolved against
    the current language and silently omitted when that translation does not yet
    exist. Sites without ``featured.cfg`` keep the historical front-matter
    ``featured: true`` behavior as a compatibility fallback.
    """
    cards: list[str] = []

    if configured:
        by_route = {
            _base_route_for_item(candidate, default_language): candidate
            for candidate in items
            if candidate.language == item.language and candidate in items
        }
        for featured in featured_items:
            target = by_route.get(featured.route)
            if target is None or target.logical_id == item.logical_id:
                continue
            cards.append(_featured_card(target, featured.image))
    else:
        legacy = [
            child
            for child in items
            if child.language == item.language
            and child.featured
            and child in items
            and child.logical_id != item.logical_id
        ]
        # Explicit featured_order takes precedence; unnumbered items follow
        # alphabetically. Keep this independent of navigation and publication dates.
        # fn: featured_sort_key - Order featured pages by explicit sort order and fallback title.
        def featured_sort_key(child: ContentItem) -> tuple[int, int, str, str]:
            raw_order = child.metadata.get("featured_order")
            if raw_order is None or str(raw_order).strip() == "":
                return (1, 0, child.title.casefold(), child.route)
            try:
                order = int(str(raw_order).strip())
            except (TypeError, ValueError):
                # Malformed metadata is treated as unspecified for sorting.
                return (1, 0, child.title.casefold(), child.route)
            return (0, order, child.title.casefold(), child.route)

        legacy.sort(key=featured_sort_key)
        cards.extend(_featured_card(child) for child in legacy)

    if not cards:
        return ""

    heading = "Uitgelicht" if item.language == "NL" else "Featured"
    interval = max(0, autoplay_interval)
    return (
        f'<section class="featured-content" aria-labelledby="featured-title" data-autoplay-interval="{interval}">'
        '<div class="featured-heading">'
        f'<h2 id="featured-title">{heading}</h2>'
        '<div class="featured-controls">'
        '<button type="button" class="featured-prev" aria-label="Previous featured items">‹</button>'
        '<button type="button" class="featured-next" aria-label="Next featured items">›</button>'
        '</div></div>'
        '<div class="featured-slider" role="list" aria-label="Featured content">'
        + "\n".join(cards)
        + "</div></section>"
        + r'''<script>(function(){
          const section=document.currentScript.previousElementSibling;
          const slider=section.querySelector('.featured-slider');
          const cards=Array.from(slider.querySelectorAll('.featured-card'));
          const prev=section.querySelector('.featured-prev');
          const next=section.querySelector('.featured-next');
          const interval=Number(section.dataset.autoplayInterval)||0;
          const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
          let timer=null;
          let hovering=false;
          let focusWithin=false;
          function step(direction){
            if(!cards.length)return;
            const positions=cards.map(card=>card.offsetLeft-cards[0].offsetLeft);
            const position=slider.scrollLeft;
            const maxScroll=Math.max(0,slider.scrollWidth-slider.clientWidth);
            const tolerance=3;
            let target;
            // The viewport reaches its end before the last card's offset can
            // reach the left edge when several cards are visible at once.
            // Wrap at the actual scroll boundary instead of the final offset.
            if(direction>0 && position>=maxScroll-tolerance){
              target=0;
            }else if(direction<0 && position<=tolerance){
              target=maxScroll;
            }else if(direction>0){
              const index=positions.findIndex(x=>x>position+tolerance);
              target=index<0?0:Math.min(positions[index],maxScroll);
            }else{
              let index=-1;
              for(let i=positions.length-1;i>=0;i--){
                if(positions[i]<position-tolerance){index=i;break;}
              }
              target=index<0?maxScroll:positions[index];
            }
            slider.scrollTo({left:target,behavior:reduced.matches?'instant':'smooth'});
          }
          function stop(){if(timer!==null){window.clearInterval(timer);timer=null;}}
          function allowed(){return interval>0&&cards.length>1&&!reduced.matches&&!document.hidden&&!hovering&&!focusWithin;}
          function start(){stop();if(allowed())timer=window.setInterval(()=>step(1),interval);}
          function manual(direction){step(direction);start();}
          prev.addEventListener('click',()=>manual(-1));
          next.addEventListener('click',()=>manual(1));
          section.addEventListener('mouseenter',()=>{hovering=true;stop();});
          section.addEventListener('mouseleave',()=>{hovering=false;start();});
          section.addEventListener('focusin',()=>{focusWithin=true;stop();});
          section.addEventListener('focusout',event=>{if(!section.contains(event.relatedTarget)){focusWithin=false;start();}});
          document.addEventListener('visibilitychange',start);
          if(reduced.addEventListener)reduced.addEventListener('change',start);
          else if(reduced.addListener)reduced.addListener(start);
          start();
        })();</script>''' 
    )


# fn: generate_site - Generate static pages, assets, navigation, and discovery files.
# . Description
#   Args: source: Input used by this operation.
def generate_site(source: str | Path, output: str | Path, languages: str | Iterable[str] = "ALL", *, mode: str = "public", rss: bool = False) -> GenerationResult:
    """Generate static pages, assets, navigation, and discovery files.
    
    Args:
        source: Input used by this operation.
        output: Input used by this operation.
        languages: Input used by this operation.
        mode: Input used by this operation.
        rss: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    source_path = Path(source).resolve()
    output_path = Path(output).expanduser().resolve()

    if mode not in {"public", "preview"}:
        return GenerationResult(False, str(output_path), errors=["mode must be public or preview"])
    validation = validate_site(source_path)
    if not validation.success:
        return GenerationResult(False, str(output_path), warnings=validation.warnings, errors=validation.errors)

    config = load_site_config(source_path)
    # Preview includes draft-only section indexes in its navigation.
    navigation = load_navigation(source_path, include_drafts=(mode == "preview"))
    featured_items = load_featured(source_path)
    featured_configured = (source_path / "config" / "featured.cfg").is_file()
    # Presentation settings belong to the slider, not to individual articles.
    slider_config = source_path / "config" / "featured-slider.cfg"
    featured_autoplay_interval = 0
    if slider_config.is_file():
        for line in slider_config.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if separator and key.strip() == "autoplay_interval":
                try:
                    featured_autoplay_interval = max(0, int(value.strip()))
                except ValueError:
                    return GenerationResult(False, str(output_path), errors=["Invalid autoplay_interval in config/featured-slider.cfg (expected milliseconds as a non-negative integer)"])

    all_items = discover_content(config, navigation)
    # A private page must live below an explicitly configured server-protected
    # route. This is a publication guard, NOT evidence that Nginx is configured.
    import configparser
    security_cfg = configparser.ConfigParser(interpolation=None)
    security_cfg.read(source_path / "config" / "site.cfg", encoding="utf-8")
    protected = [part.strip() for part in security_cfg.get("security", "protected_prefixes", fallback="").split(",") if part.strip()]
    protected = [part for part in protected if part.startswith("/") and part.endswith("/") and ".." not in part]
    unprotected = [page.route for page in all_items if page.private and not any(page.route.startswith(prefix) for prefix in protected)]
    if unprotected and mode == "public":
        return GenerationResult(False, str(output_path), errors=[
            "Private page outside configured protected_prefixes: " + ", ".join(unprotected)
            + ". Configure server-side authentication before publishing."
        ])
    items = [item for item in all_items if mode == "preview" or item.status == "published"]
    skipped_count = len(all_items) - len(items)
    try:
        selected_languages = _normalize_languages(languages, config.supported_languages)
    except ValueError as exc:
        return GenerationResult(False, str(output_path), errors=[str(exc)])

    if output_path == source_path or output_path == Path("/") or output_path == source_path.parent or source_path.is_relative_to(output_path) or output_path.is_relative_to(source_path):
        return GenerationResult(False, str(output_path), errors=["Refusing to generate into the source root or filesystem root."])

    if output_path.exists():
        shutil.rmtree(output_path)
    output_path.mkdir(parents=True, exist_ok=True)

    if config.css_dir.is_dir():
        shutil.copytree(config.css_dir, output_path / "css")
    if config.images_dir.is_dir():
        shutil.copytree(config.images_dir, output_path / "images", ignore=_ignore_marked_directories)
    # Publish repository-level assets without rewriting authored asset URLs.
    assets_dir = source_path / "assets"
    if assets_dir.is_dir():
        shutil.copytree(assets_dir, output_path / "assets", ignore=_ignore_marked_directories)
    # JavaScript is a first-class site resource, copied before content hashes are computed.
    js_dir = source_path / "js"
    if js_dir.is_dir():
        shutil.copytree(js_dir, output_path / "js")

    variants: dict[str, dict[str, ContentItem]] = {}
    for content_item in items:
        variants.setdefault(content_item.logical_id, {})[content_item.language] = content_item

    base_template = load_template(config.templates_dir / "base.html", config.templates_dir)
    sidebar_template = load_template(config.templates_dir / "partials" / "sidebar.html", config.templates_dir)
    footer_template = load_template(config.templates_dir / "partials" / "footer.html", config.templates_dir)

    page_count = 0
    render_total = sum(page.language in selected_languages and not page.metadata.get("nav_only") for page in items)
    render_processed = 0
    render_step = max(1, render_total // 20)
    print(f"WCM: Rendering {render_total} pages", file=sys.stderr, flush=True)
    article_count = 0
    errors: list[str] = []

    for item in items:
        if item.language not in selected_languages:
            continue
        if item.metadata.get('nav_only'):
            continue
        render_processed += 1
        if render_processed == 1 or render_processed % render_step == 0 or render_processed == render_total:
            print(f"WCM: Rendering {render_processed}/{render_total} ({render_processed * 100 // max(1, render_total)}%)", file=sys.stderr, flush=True)
        # Documentation chapters may provide scoped templates. All ordinary
        # sites keep using the root-level templates unchanged.
        chapter = item.source_path.relative_to(config.content_dir).parts[0] if item.source_path != config.content_dir else ''
        chapter_root = config.templates_dir / chapter
        override = chapter_root / f"{item.template}.html"
        template_path = override if chapter and override.is_file() else config.templates_dir / f"{item.template}.html"
        chapter_base_path = chapter_root / 'base.html'
        current_base_template = (load_template(chapter_base_path, chapter_root)
                                 if chapter and chapter_base_path.is_file() else base_template)
        if not template_path.is_file() and item.template not in ('base', 'home', 'page', 'article'):
            # Custom templates are optional; leave WCM general-purpose.
            template_path = config.templates_dir / 'page.html'
        if not template_path.is_file():
            errors.append(f"Template not found for {item.source_path}: {template_path}")
            continue

        current_base_route = _base_route_for_item(item, config.default_language)
        navigation_html = _render_navigation(
            navigation, items, item.language, config.default_language,
            current_base_route, doc_sidebar='class="doc-nav"' in current_base_template,
        )
        breadcrumb_html = _render_breadcrumb(items, item, config.default_language)
        language_selector = _render_language_selector(config, item, variants, selected_languages)
        # Landing pages can intentionally omit the contextual title bar.
        # Default remains unchanged for existing content.
        hide_title = item.metadata.get("hide_title", False) is True
        context_header_html = "" if hide_title else _context_header(
            breadcrumb_html, item.title, item.template
        )
        external_links = _render_external_links(config.links)

        site_context = {
            "title": html.escape(config.title),
            "description": html.escape(config.description),
            "logo": html.escape(config.logo, quote=True),
        }
        absolute_url = config.base_url.rstrip("/") + item.route
        description = str(item.metadata.get("description") or item.summary or config.description)
        hero = _publish_image(str(item.metadata.get("hero_image") or item.metadata.get("index_image") or config.logo), item, config, output_path)
        absolute_hero = urljoin(config.base_url.rstrip("/") + "/", hero.lstrip("/")) if hero and not hero.startswith(("https:", "http:")) else hero
        # Only actual, generated translations qualify for hreflang. A Dutch
        # fallback navigation target is not an alternate-language document.
        actual_variants = {
            language: variant
            for language, variant in variants.get(item.logical_id, {}).items()
            if language in selected_languages
            and (mode == "preview" or variant.status == "published")
            and not variant.private and not variant.hidden
        }
        meta_tags = _seo_tags(item, config, absolute_url, description, absolute_hero, mode, actual_variants)
        page_context = {
            "title": html.escape(item.title),
            "summary": html.escape(description, quote=True),
            "language": item.language.lower(),
            "type": html.escape(item.template, quote=True),
        }

        sidebar_html = render_template(
            sidebar_template,
            {
                "site": site_context,
                "navigation": navigation_html,
                "language_selector": language_selector,
                "external_links": external_links,
            },
        )
        footer_html = render_template(
            footer_template,
            {"site": site_context, "current_year": str(datetime.now().year)},
        )

        body, index_replacements = _explicit_indexes(item.body, item, items, config.default_language, config, output_path)
        body = _resolve_body_images(body, item, config, output_path)
        body = _resolve_body_resources(body, item, config, output_path)
        body_html = render_markdown(body)
        for marker, rendered_index in index_replacements.items():
            body_html = body_html.replace(f"<p>{marker}</p>", rendered_index)
        inner_context = {
            "site": site_context,
            "page": page_context,
            "content": body_html,
            "page_summary": _summary_fragment(item),
            "article_meta": _article_meta(item),
            "article_footer": "",
            "featured_content": (
                _featured_for(
                    item,
                    items,
                    featured_items,
                    config.default_language,
                    featured_configured,
                    featured_autoplay_interval,
                )
                if item.template == "home"
                else ""
            ),
        }
        inner_html = render_template(load_template(template_path, config.templates_dir), inner_context)
        final_html = render_template(
            current_base_template,
            {
                "site": site_context,
                "page": page_context,
                "navigation": navigation_html,
                "language_selector": language_selector,
                "external_links": external_links,
                "current_year": str(datetime.now().year),
                "sidebar": sidebar_html,
                "breadcrumb": breadcrumb_html,
                "context_header": context_header_html,
                "content": inner_html,
                "footer": footer_html,
                "seo_tags": meta_tags,
            },
        )
        # The uploader is a page-specific enhancement, not a Markdown feature.
        # Inject its existing script only on the upload route, including translated
        # variants. Fail generation if the asset is absent instead of publishing
        # an apparently functional page without its upload controls.
        if current_base_route == "/over-deze-website/upload/":
            uploader = output_path / "js" / "markdown-upload.js"
            if not uploader.is_file():
                errors.append(f"Required upload script missing: {uploader}")
                continue
            if "</body>" not in final_html:
                errors.append(f"Missing </body> for upload page: {item.source_path}")
                continue
            final_html = final_html.replace(
                "</body>",
                '<script src="/js/markdown-upload.js" defer></script>\n</body>',
                1,
            )

        # Version assets after rendering (including the upload script),
        # before rewriting root-relative URLs for local file previews.
        final_html = _version_local_assets(final_html, output_path)
        final_html = _make_output_relative_urls(final_html, item.route)

        unresolved = unresolved_placeholders(final_html)
        if unresolved:
            errors.append(f"Unresolved template placeholder(s) in {item.source_path}: {', '.join(unresolved)}")
            continue

        target = _route_to_output(output_path, item.route)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(final_html.rstrip() + "\n", encoding="utf-8")
        page_count += 1
        if item.template == "article":
            article_count += 1

    warnings = list(validation.warnings)
    print("WCM: Validating generated links", file=sys.stderr, flush=True)
    broken = _check_internal_links(output_path, warnings)
    sitemap_written = False
    rss_written = False
    if not errors and mode == "public":
        _write_sitemap(output_path, config, items, selected_languages)
        sitemap_written = True
        if rss:
            rss_written = _write_rss(output_path, config, items, selected_languages)
    return GenerationResult(not errors, str(output_path), page_count, article_count, warnings, errors,
                            skipped_count, broken, sitemap_written, rss_written)


# fn: _seo_tags - Return escaped metadata; previews are excluded from indexing regardless of URL.
def _seo_tags(item: ContentItem, config, canonical: str, description: str, image: str, mode: str, actual_variants: dict[str, ContentItem] | None = None) -> str:
    """Return escaped metadata; previews are excluded from indexing regardless of URL."""
    # fn: esc - Escape content for inclusion in generated XML or HTML.
    # . Description
    #   Args: value: Input used by this operation.
    def esc(value: str) -> str:
        """Handle esc for the web content workflow.
        
        Args:
            value: Input used by this operation.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return html.escape(str(value), quote=True)
    tags = [f'<link rel="canonical" href="{esc(canonical)}">',
            f'<meta property="og:type" content="{"article" if item.template == "article" else "website"}">',
            f'<meta property="og:title" content="{esc(item.title)}">',
            f'<meta property="og:description" content="{esc(description)}">',
            f'<meta property="og:url" content="{esc(canonical)}">',
            f'<meta property="og:site_name" content="{esc(config.title)}">',
            f'<meta name="twitter:card" content="{"summary_large_image" if image else "summary"}">']
    # Emit alternate links only for real language versions, not fallback
    # navigation links. Require two variants to avoid redundant self-links.
    if actual_variants and len(actual_variants) > 1:
        for language, variant in sorted(actual_variants.items()):
            alternate_url = config.base_url.rstrip("/") + variant.route
            tags.append(f'<link rel="alternate" hreflang="{esc(language.lower())}" href="{esc(alternate_url)}">')
    if image:
        tags.extend([f'<meta property="og:image" content="{esc(image)}">',
                     f'<meta name="twitter:image" content="{esc(image)}">'])
    if mode == "preview" or item.status != "published" or item.hidden or item.private:
        tags.append('<meta name="robots" content="noindex,nofollow">')
    if item.date and item.template == "article":
        tags.append(f'<meta property="article:published_time" content="{esc(item.date)}">')
    return "\n    ".join(tags)


# fn: _write_sitemap - Write sitemap to generated output.
def _write_sitemap(output: Path, config, items: list[ContentItem], langs: set[str]) -> None:
    """Write sitemap to generated output."""
    ns = "http://www.sitemaps.org/schemas/sitemap/0.9"
    ET.register_namespace("", ns)
    root = ET.Element(f"{{{ns}}}urlset")
    for item in sorted(items, key=lambda value: value.route):
        if (item.language not in langs or item.status != "published" or item.hidden
                or item.private or item.metadata.get('nav_only')):
            continue
        entry = ET.SubElement(root, f"{{{ns}}}url")
        ET.SubElement(entry, f"{{{ns}}}loc").text = config.base_url.rstrip("/") + item.route
        if item.date and re.fullmatch(r"\d{4}-\d{2}-\d{2}", item.date):
            ET.SubElement(entry, f"{{{ns}}}lastmod").text = item.date
    ET.ElementTree(root).write(output / "sitemap.xml", encoding="utf-8", xml_declaration=True)
    (output / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: " + config.base_url.rstrip("/") + "/sitemap.xml\n", encoding="utf-8")


# fn: _write_rss - Write rss to generated output.
def _write_rss(output: Path, config, items: list[ContentItem], langs: set[str]) -> bool:
    """Write rss to generated output."""
    articles = sorted((i for i in items if i.template == "article" and i.date and i.language in langs and i.status == "published" and not i.hidden and not i.private), key=lambda i: i.date, reverse=True)
    if not articles:
        return False
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    for name, value in (("title", config.title), ("link", config.base_url), ("description", config.description)):
        ET.SubElement(channel, name).text = value
    for item in articles[:50]:
        entry = ET.SubElement(channel, "item")
        url = config.base_url.rstrip("/") + item.route
        for key, value in (("title", item.title), ("link", url), ("guid", url), ("description", item.summary)):
            ET.SubElement(entry, key).text = value
        try:
            dt = datetime.fromisoformat(item.date).replace(tzinfo=timezone.utc)
            ET.SubElement(entry, "pubDate").text = format_datetime(dt)
        except ValueError:
            pass
    ET.ElementTree(rss).write(output / "rss.xml", encoding="utf-8", xml_declaration=True)
    return True


# fn: _check_internal_links - Inspect rendered href/src URLs against the generated output tree.
def _check_internal_links(output: Path, warnings: list[str]) -> int:
    """Inspect rendered href/src URLs against the generated output tree."""
    count = 0
    regex = re.compile(r'\b(?:href|src)=["\']([^"\']+)["\']', re.IGNORECASE)
    for page in output.rglob("*.html"):
        for reference in regex.findall(page.read_text(encoding="utf-8")):
            reference = html.unescape(reference)
            parsed = urlsplit(reference)
            if parsed.scheme or reference.startswith(("//", "#", "mailto:", "tel:", "data:")):
                continue
            relative = unquote(parsed.path)
            if not relative:
                continue
            target = (output / relative.lstrip("/")) if relative.startswith("/") else page.parent / relative
            if target.is_dir():
                target = target / "index.html"
            if not target.exists() and not (target / "index.html").exists():
                warnings.append(f"Broken local link in {page.relative_to(output)}: {reference}")
                count += 1
    return count
