"""Static website generation, including navigation and page-context title bars."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from email.utils import format_datetime
from datetime import timezone
from xml.etree import ElementTree as ET
from urllib.parse import urljoin, unquote
import html
from pathlib import Path
import shutil
import re
import hashlib
from urllib.parse import urlsplit
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


def _version_local_assets(document: str, output_root: Path) -> str:
    """Append a content hash to root-relative local .css/.js href/src links.

    Existing query parameters and fragments are preserved. Paths are restricted
    to files inside the generated output root (never arbitrary filesystem paths).
    This is applied before URLs are made relative for file:// preview support.
    """
    resolved_root = output_root.resolve()
    digests: dict[Path, str] = {}

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


def _render_navigation(
    navigation: list[NavigationItem],
    items: list[ContentItem],
    language: str,
    default_language: str,
    current_base_route: str,
) -> str:
    """Build a recursive sidebar from translated page titles and content routes.

    The configured navigation supplies only root ordering. Directories are
    navigation groups even when there is no index page. Hidden index pages
    conceal their entire subtree by CSS until ShowHidden is present; hidden
    ordinary pages conceal only themselves. Private pages require server auth
    and are not protected by navigation metadata.
    """
    # Keep hidden pages in the generated navigation. The existing ShowHidden
    # CSS/JavaScript toggles their visibility at runtime. A hidden index marks
    # its entire folder node as hidden, so all descendants are concealed too.
    # This is presentation only; private access remains enforced by Nginx.
    pages = {
        _base_route_for_item(page, default_language): page
        for page in items
        if page.language == language
    }
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
    # Root entries still follow navigation.cfg; their visibility follows metadata.
    top_by_path = {n.path: n for n in top}

    def label_for(route: str) -> str:
        page = nodes[route]["page"]
        # Root groups keep their explicitly authored navigation labels, even
        # when a translated index page has a different title.
        nav = top_by_path.get(route)
        if nav and nav.labels.get(language):
            return nav.labels[language]
        if page:
            return page.title
        return route.strip("/").split("/")[-1].replace("-", " ").capitalize()

    def render(route: str, ancestors: set[str]) -> str:
        if route in ancestors:
            return ""
        node = nodes[route]
        # Home is its own navigation entry, not a container for every section.
        child_routes = () if route == "/" else node["children"]
        children = sorted(child_routes, key=lambda r: (
            nodes[r]["page"].order if nodes[r]["page"] else 1000,
            label_for(r).casefold(), r,
        ))
        active = current_base_route == route
        expanded = active or (route.endswith("/") and current_base_route.startswith(route))
        classes = ' class="active"' if active else ""
        current = ' aria-current="page"' if active else ""
        label = html.escape(label_for(route))
        page = node["page"]
        link = (f'<a href="{html.escape(page.route, quote=True)}"{classes}{current}>{label}</a>'
                if page else f'<span class="wc-nav-label">{label}</span>')
        # A hidden section index conceals this node and all descendants in
        # normal navigation; ShowHidden reveals the complete subtree. Ordinary
        # hidden pages conceal their own leaf only.
        hidden_class = ' wc-hidden-link' if page is not None and page.hidden else ''
        if not children:
            return '<div class="wc-nav-leaf' + hidden_class + '">' + link + '</div>'
        child_html = "".join(render(child, ancestors | {route}) for child in children)
        return ('<details class="wc-nav-group' + hidden_class + '"' + (' open' if expanded else '') + '>'
                '<summary><span class="wc-nav-arrow" aria-hidden="true"></span>'
                + link + '</summary><div class="wc-nav-children">' + child_html + '</div></details>')

    # Root navigation remains explicitly ordered; nested navigation is automatic.
    return "\n".join(render(route, set()) for route in roots)


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


def _render_breadcrumb(items: list[ContentItem], item: ContentItem, default_language: str) -> str:
    """Render links to existing ancestor index pages in the content hierarchy.

    Folder structure defines page hierarchy. Each ancestor is included only when
    that folder has an ``index_<language>.md`` page. The current page is omitted
    because its h1 is already rendered in the title bar.
    """
    current_base_route = _base_route_for_item(item, default_language)
    current_parts = [part for part in current_base_route.strip("/").split("/") if part]

    ancestor_routes = {
        "/" + "/".join(current_parts[:depth]) + "/"
        for depth in range(1, len(current_parts))
    }
    ancestors = [
        candidate
        for candidate in items
        if candidate.language == item.language
        and candidate.base_name == "index"
        and candidate in items
        and _base_route_for_item(candidate, default_language) in ancestor_routes
    ]
    ancestors.sort(key=lambda candidate: len(_base_route_for_item(candidate, default_language).strip("/").split("/")))

    parts: list[str] = []
    for ancestor in ancestors:
        parts.append(
            '<li><a href="'
            + html.escape(ancestor.route, quote=True)
            + '">'
            + html.escape(ancestor.title)
            + "</a></li>"
        )

    if not parts:
        return ""

    return (
        '<nav class="context-breadcrumb" aria-label="Breadcrumb"><ol>'
        + "".join(parts)
        + "</ol></nav>"
    )


def _context_header(
    breadcrumb_html: str, page_title: str, page_type: str
) -> str:
    """Render page context; language navigation lives in the persistent sidebar."""
    width_class = " context-header-inner-narrow" if page_type in {"page", "article"} else ""
    return (
        '<header class="context-header" id="contextHeader">'
        f'<div class="context-header-inner{width_class}">'
        '<div class="context-header-copy">'
        + breadcrumb_html
        + f'<h1 class="context-title">{html.escape(page_title)}</h1>'
        + "</div>"
        + "</div></header>"
    )


_LANGUAGE_NAMES = {
    "NL": "Nederlands",
    "EN": "English",
    "DE": "Deutsch",
    "IT": "Italiano",
}


def _render_language_selector(
    config,
    item: ContentItem,
    variants: dict[str, dict[str, ContentItem]],
    selected_languages: set[str],
) -> str:
    """Render links only to translation variants present in this output build."""
    available = {
        language: variant
        for language, variant in variants.get(item.logical_id, {}).items()
        if language in selected_languages 
    }
    if len(available) <= 1:
        return ""

    links: list[str] = []
    for language in config.supported_languages:
        variant = available.get(language)
        if variant is None:
            continue

        label = _LANGUAGE_NAMES.get(language, language)
        flag_path = config.images_dir / "flags" / f"{language.lower()}.svg"
        if flag_path.is_file():
            content = (
                f'<img class="language-flag" src="/images/flags/{language.lower()}.svg" '
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
        else:
            links.append(
                f'<a {common} hreflang="{html.escape(language.lower(), quote=True)}" '
                f'href="{html.escape(variant.route, quote=True)}">{content}</a>'
            )

    partial_path = config.templates_dir / "partials" / "language-selector.html"
    if not partial_path.is_file():
        return " ".join(links)
    return render_template(load_template(partial_path, config.templates_dir), {"language_links": "\n".join(links)})


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


def _summary_fragment(item: ContentItem) -> str:
    """Handle summary fragment for the web content workflow."""
    if not item.summary:
        return ""
    return f'<p class="page-summary">{html.escape(item.summary)}</p>'


def _image_for(item: ContentItem, config, output_path: Path) -> str:
    """Prefer index art, then hero art; publish local assets safely."""
    for key in ("index_image", "hero_image"):
        reference = str(item.metadata.get(key) or "").strip()
        if reference:
            return _publish_image(reference, item, config, output_path)
    return ""


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


def _resolve_body_images(body: str, item: ContentItem, config, output_path: Path) -> str:
    """Rewrite local Markdown images before Markdown rendering; leave external URLs intact."""
    pattern = re.compile(r'(!\[[^\]]*\]\()([^\)]+)(\))')
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


def _explicit_indexes(body: str, item: ContentItem, items: list[ContentItem],
                      default_language: str, config, output_path: Path) -> tuple[str, dict[str, str]]:
    """Replace index blocks with inert markers restored after Markdown rendering."""
    replacements: dict[str, str] = {}
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


def _direct_children(item: ContentItem, items: list[ContentItem], default_language: str) -> list[ContentItem]:
    """Return the immediate child pages below an index page.

    A child may be either a sibling Markdown file such as ``installation_NL.md``
    or a nested folder index such as ``documentation/index_NL.md``. Both map to
    exactly one route segment below the parent section.
    """
    if item.base_name != "index":
        return []

    parent_route = _base_route_for_item(item, default_language)
    parent_parts = [part for part in parent_route.strip("/").split("/") if part]
    children: list[ContentItem] = []
    for child in items:
        if child.language != item.language or child not in items or child.logical_id == item.logical_id:
            continue
        child_route = _base_route_for_item(child, default_language)
        child_parts = [part for part in child_route.strip("/").split("/") if part]
        if len(child_parts) != len(parent_parts) + 1:
            continue
        if child_parts[: len(parent_parts)] != parent_parts:
            continue
        children.append(child)

    children.sort(key=lambda child: (child.order, child.title.lower()))
    return children


def _listing_for(item: ContentItem, items: list[ContentItem], default_language: str) -> str:
    """Handle listing for for the web content workflow."""
    children = [child for child in _direct_children(item, items, default_language) if not child.hidden]
    children.sort(key=lambda child: (child.date, child.title.lower()), reverse=True)
    return "\n".join(_card(child) for child in children)


def _section_children_for(item: ContentItem, items: list[ContentItem], default_language: str, config, output_path: Path) -> str:
    """Render local navigation for static section index pages."""
    if item.template != "page" or item.base_name != "index":
        return ""

    children = [child for child in _direct_children(item, items, default_language) if not child.hidden]
    if not children:
        return ""

    labels = {
        "NL": "In deze sectie",
        "EN": "In this section",
    }
    heading = labels.get(item.language, "In this section")
    cards = _render_index(item, items, default_language, config, output_path)
    return (
        '<section class="section-children">'
        f'<h2>{html.escape(heading)}</h2>'
        f"{cards}"
        "</section>"
    )


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
    if image:
        image_html = (
            f'<a class="featured-card-media" href="{html.escape(item.route, quote=True)}" tabindex="-1">'
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
        legacy.sort(key=lambda child: (child.date, child.title.lower()), reverse=True)
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
    navigation = load_navigation(source_path)
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
        shutil.copytree(config.images_dir, output_path / "images")
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
    article_count = 0
    errors: list[str] = []

    for item in items:
        if item.language not in selected_languages:
            continue
        template_path = config.templates_dir / f"{item.template}.html"
        if not template_path.is_file():
            errors.append(f"Template not found for {item.source_path}: {template_path}")
            continue

        current_base_route = _base_route_for_item(item, config.default_language)
        navigation_html = _render_navigation(navigation, items, item.language, config.default_language, current_base_route)
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
        meta_tags = _seo_tags(item, config, absolute_url, description, absolute_hero, mode)
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
        body_html = render_markdown(body)
        for marker, rendered_index in index_replacements.items():
            body_html = body_html.replace(f"<p>{marker}</p>", rendered_index)
        has_explicit_index = bool(index_replacements)
        inner_context = {
            "site": site_context,
            "page": page_context,
            "content": body_html,
            "page_summary": _summary_fragment(item),
            "article_meta": _article_meta(item),
            "article_footer": "",
            "listing": _listing_for(item, items, config.default_language) if item.template == "listing" else "",
            "section_children": "" if has_explicit_index else _section_children_for(item, items, config.default_language, config, output_path),
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
            base_template,
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


def _seo_tags(item: ContentItem, config, canonical: str, description: str, image: str, mode: str) -> str:
    """Return escaped metadata; previews are excluded from indexing regardless of URL."""
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
    if image:
        tags.extend([f'<meta property="og:image" content="{esc(image)}">',
                     f'<meta name="twitter:image" content="{esc(image)}">'])
    if mode == "preview" or item.status != "published" or item.hidden or item.private:
        tags.append('<meta name="robots" content="noindex,nofollow">')
    if item.date and item.template == "article":
        tags.append(f'<meta property="article:published_time" content="{esc(item.date)}">')
    return "\n    ".join(tags)


def _write_sitemap(output: Path, config, items: list[ContentItem], langs: set[str]) -> None:
    """Write sitemap to generated output."""
    ns = "http://www.sitemaps.org/schemas/sitemap/0.9"
    ET.register_namespace("", ns)
    root = ET.Element(f"{{{ns}}}urlset")
    for item in sorted(items, key=lambda value: value.route):
        if item.language not in langs or item.status != "published" or item.hidden or item.private:
            continue
        entry = ET.SubElement(root, f"{{{ns}}}url")
        ET.SubElement(entry, f"{{{ns}}}loc").text = config.base_url.rstrip("/") + item.route
        if item.date and re.fullmatch(r"\d{4}-\d{2}-\d{2}", item.date):
            ET.SubElement(entry, f"{{{ns}}}lastmod").text = item.date
    ET.ElementTree(root).write(output / "sitemap.xml", encoding="utf-8", xml_declaration=True)
    (output / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: " + config.base_url.rstrip("/") + "/sitemap.xml\n", encoding="utf-8")


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
