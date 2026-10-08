"""Static website generation, including navigation and page-context title bars."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
import html
from pathlib import Path
import shutil
import re
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
    success: bool
    output: str
    pages_generated: int = 0
    articles_generated: int = 0
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        return {
            "success": self.success,
            "output": self.output,
            "pages_generated": self.pages_generated,
            "articles_generated": self.articles_generated,
            "warnings": self.warnings,
            "errors": self.errors,
        }


def _normalize_languages(value: str | Iterable[str], supported: list[str]) -> set[str]:
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
        target = match.group("url")
        if target == "/":
            relative = root_prefix or "./"
        else:
            relative = root_prefix + target.lstrip("/")
        return match.group("prefix") + relative + match.group("suffix")

    return _ROOT_RELATIVE_URL_RE.sub(replace, document)


def _base_route_for_item(item: ContentItem, default_language: str) -> str:
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
    """Render main navigation entries that exist in the current language.

    Translations may be introduced section by section. A navigation label alone
    must therefore never create a link to a route that has no translated section
    index page yet.
    """
    available_paths = {
        _base_route_for_item(candidate, default_language)
        for candidate in items
        if candidate.language == language and candidate.base_name == "index" and not candidate.draft
    }

    links: list[str] = []
    for item in navigation:
        label = item.labels.get(language)
        if not label or item.path not in available_paths:
            continue
        href = language_route(item.path, language, default_language)
        active = current_base_route == item.path or (item.path != "/" and current_base_route.startswith(item.path))
        class_attr = ' class="active" aria-current="page"' if active else ""
        links.append(f'<a href="{html.escape(href, quote=True)}"{class_attr}>{html.escape(label)}</a>')
    return "\n".join(links)


def _render_external_links(links: dict[str, str]) -> str:
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
        and not candidate.draft
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
    breadcrumb_html: str, page_title: str, page_type: str, language_selector_html: str
) -> str:
    """Render the compact page title bar, ancestors, and available languages."""
    width_class = " context-header-inner-narrow" if page_type in {"page", "article"} else ""
    return (
        '<header class="context-header" id="contextHeader">'
        f'<div class="context-header-inner{width_class}">'
        '<div class="context-header-copy">'
        + breadcrumb_html
        + f'<h1 class="context-title">{html.escape(page_title)}</h1>'
        + "</div>"
        + language_selector_html
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
        if language in selected_languages and not variant.draft
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
    parts: list[str] = []
    if item.date:
        parts.append(f'<time datetime="{html.escape(item.date, quote=True)}">{html.escape(item.date)}</time>')
    if item.tags:
        parts.append('<span class="article-tags">' + " · ".join(html.escape(tag) for tag in item.tags) + "</span>")
    if not parts:
        return ""
    return '<div class="article-meta">' + "\n".join(parts) + "</div>"


def _summary_fragment(item: ContentItem) -> str:
    if not item.summary:
        return ""
    return f'<p class="page-summary">{html.escape(item.summary)}</p>'


def _card(item: ContentItem, heading_level: int = 2) -> str:
    heading_level = 2 if heading_level not in {2, 3} else heading_level
    summary = f"<p>{html.escape(item.summary)}</p>" if item.summary else ""
    date = f'<time datetime="{html.escape(item.date, quote=True)}">{html.escape(item.date)}</time>' if item.date else ""
    return (
        '<article class="article-card">'
        f'<h{heading_level}><a href="{html.escape(item.route, quote=True)}">{html.escape(item.title)}</a></h{heading_level}>'
        f"{date}{summary}"
        "</article>"
    )


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
        if child.language != item.language or child.draft or child.logical_id == item.logical_id:
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
    children = _direct_children(item, items, default_language)
    children.sort(key=lambda child: (child.date, child.title.lower()), reverse=True)
    return "\n".join(_card(child) for child in children)


def _section_children_for(item: ContentItem, items: list[ContentItem], default_language: str) -> str:
    """Render local navigation for static section index pages."""
    if item.template != "page" or item.base_name != "index":
        return ""

    children = _direct_children(item, items, default_language)
    if not children:
        return ""

    labels = {
        "NL": "In deze sectie",
        "EN": "In this section",
    }
    heading = labels.get(item.language, "In this section")
    cards = "\n".join(_card(child, 3) for child in children)
    return (
        '<section class="section-children">'
        f'<h2>{html.escape(heading)}</h2>'
        f'<div class="article-list">{cards}</div>'
        "</section>"
    )


def _featured_card(item: ContentItem, image: str = "") -> str:
    """Render one curated Featured tile using target-page metadata."""
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
            if candidate.language == item.language and not candidate.draft
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
            and not child.draft
            and child.logical_id != item.logical_id
        ]
        legacy.sort(key=lambda child: (child.date, child.title.lower()), reverse=True)
        cards.extend(_featured_card(child) for child in legacy[:3])

    if not cards:
        return ""

    return (
        '<section class="featured-content" aria-labelledby="featured-title">'
        '<h2 id="featured-title">Featured</h2>'
        '<div class="featured-slider" role="list" aria-label="Featured content">'
        + "\n".join(cards)
        + "</div></section>"
    )


def generate_site(source: str | Path, output: str | Path, languages: str | Iterable[str] = "ALL") -> GenerationResult:
    source_path = Path(source).resolve()
    output_path = Path(output).expanduser().resolve()

    validation = validate_site(source_path)
    if not validation.success:
        return GenerationResult(False, str(output_path), warnings=validation.warnings, errors=validation.errors)

    config = load_site_config(source_path)
    navigation = load_navigation(source_path)
    featured_items = load_featured(source_path)
    featured_configured = (source_path / "config" / "featured.cfg").is_file()
    items = discover_content(config, navigation)
    try:
        selected_languages = _normalize_languages(languages, config.supported_languages)
    except ValueError as exc:
        return GenerationResult(False, str(output_path), errors=[str(exc)])

    if output_path == source_path or output_path == Path("/"):
        return GenerationResult(False, str(output_path), errors=["Refusing to generate into the source root or filesystem root."])

    if output_path.exists():
        shutil.rmtree(output_path)
    output_path.mkdir(parents=True, exist_ok=True)

    if config.css_dir.is_dir():
        shutil.copytree(config.css_dir, output_path / "css")
    if config.images_dir.is_dir():
        shutil.copytree(config.images_dir, output_path / "images")

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
        if item.draft or item.language not in selected_languages:
            continue
        template_path = config.templates_dir / f"{item.template}.html"
        if not template_path.is_file():
            errors.append(f"Template not found for {item.source_path}: {template_path}")
            continue

        current_base_route = _base_route_for_item(item, config.default_language)
        navigation_html = _render_navigation(navigation, items, item.language, config.default_language, current_base_route)
        breadcrumb_html = _render_breadcrumb(items, item, config.default_language)
        language_selector = _render_language_selector(config, item, variants, selected_languages)
        context_header_html = _context_header(
            breadcrumb_html, item.title, item.template, language_selector
        )
        external_links = _render_external_links(config.links)

        site_context = {
            "title": html.escape(config.title),
            "description": html.escape(config.description),
            "logo": html.escape(config.logo, quote=True),
        }
        page_context = {
            "title": html.escape(item.title),
            "summary": html.escape(item.summary, quote=True),
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

        body_html = render_markdown(item.body)
        inner_context = {
            "site": site_context,
            "page": page_context,
            "content": body_html,
            "page_summary": _summary_fragment(item),
            "article_meta": _article_meta(item),
            "article_footer": "",
            "listing": _listing_for(item, items, config.default_language) if item.template == "listing" else "",
            "section_children": _section_children_for(item, items, config.default_language),
            "featured_content": (
                _featured_for(
                    item,
                    items,
                    featured_items,
                    config.default_language,
                    featured_configured,
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
            },
        )
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

    if errors:
        return GenerationResult(False, str(output_path), page_count, article_count, validation.warnings, errors)

    return GenerationResult(True, str(output_path), page_count, article_count, validation.warnings, [])
