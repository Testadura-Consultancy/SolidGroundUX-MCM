"""Content discovery, front-matter parsing, and site configuration helpers."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import configparser
import json
import re
from typing import Any


_CONTENT_FILE_RE = re.compile(r"^(?P<name>.+)_(?P<language>[A-Za-z]{2})\.md$")
_INDEX_FILE_RE = re.compile(r"^.+_Index_(?P<language>[A-Za-z]{2})\.md$")


# fn: section_index - Find the one descriptive index for a section/language.
def section_index(directory: Path, language: str) -> Path | None:
    """Find the one descriptive index for a section/language."""
    matches = sorted(path for path in directory.glob(f"*_Index_{language}.md") if _INDEX_FILE_RE.fullmatch(path.name))
    if len(matches) > 1:
        raise ValueError(f"Multiple {language} section indexes in {directory}: " + ", ".join(p.name for p in matches))
    return matches[0] if matches else None



# cls: SiteConfig - Resolved website source paths and site configuration settings.
@dataclass(slots=True)
class SiteConfig:
    """Resolved website source paths and site configuration settings."""
    root: Path
    title: str
    description: str
    base_url: str
    default_language: str
    supported_languages: list[str]
    content_style_prefix: str
    content_dir: Path
    templates_dir: Path
    css_dir: Path
    images_dir: Path
    logo: str
    links: dict[str, str] = field(default_factory=dict)


# cls: NavigationItem - One configured navigation entry and its display information.
@dataclass(slots=True)
class NavigationItem:
    """One configured navigation entry and its display information."""
    key: str
    order: int
    path: str
    template: str
    labels: dict[str, str]


# cls: FeaturedItem - One curated route shown in the home-page Featured slider.
@dataclass(slots=True)
class FeaturedItem:
    """One curated route shown in the home-page Featured slider."""

    key: str
    order: int
    route: str
    image: str = ""


# cls: ContentItem - Discovered Markdown page with route, language, and metadata.
@dataclass(slots=True)
class ContentItem:
    """Discovered Markdown page with route, language, and metadata."""
    source_path: Path
    logical_id: str
    base_name: str
    language: str
    metadata: dict[str, Any]
    body: str
    route: str
    template: str = "page"

    # fn: title - Return the effective title from the content item metadata.
    @property
    def title(self) -> str:
        """Handle title for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return str(self.metadata.get("title", self.base_name))

    # fn: summary - Return the effective summary from the content item metadata.
    @property
    def summary(self) -> str:
        """Handle summary for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return str(self.metadata.get("summary", ""))

    # fn: date - Read the effective article date from content metadata.
    @property
    def date(self) -> str:
        """Handle date for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return str(self.metadata.get("published") or self.metadata.get("date") or "")

    # fn: tags - Return the normalized tags associated with the content item.
    @property
    def tags(self) -> list[str]:
        """Handle tags for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        value = self.metadata.get("tags", [])
        if isinstance(value, list):
            return [str(v) for v in value]
        if value in (None, ""):
            return []
        return [part.strip() for part in str(value).split(",") if part.strip()]

    # fn: draft - Determine whether the content item is marked as draft.
    @property
    def draft(self) -> bool:
        """Handle draft for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return self.status == "draft"

    # fn: status - Return the effective publication status of the content item.
    @property
    def status(self) -> str:
        """Handle status for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        value = str(self.metadata.get("status", "")).strip().lower()
        return value if value in {"draft", "preview", "published"} else ("draft" if self.metadata.get("draft", False) else "published")

    # fn: hidden - Whether a published page is omitted from normal discovery/navigation.
    # . Description
    #   Hidden is not an access-control mechanism: generated pages remain public.
    @property
    def hidden(self) -> bool:
        """Whether a published page is omitted from normal discovery/navigation.

        Hidden is not an access-control mechanism: generated pages remain public.
        """
        return str(self.metadata.get("hidden", False)).strip().lower() in {"true", "yes", "1"}

    # fn: private - Declare a URL requiring server-side access control.
    # . Description
    #   Metadata alone never creates authentication; the generator checks protected URL placement, and the web server must enforce the guard.
    @property
    def private(self) -> bool:
        """Declare a URL requiring server-side access control.

        Metadata alone never creates authentication; the generator checks
        protected URL placement, and the web server must enforce the guard.
        """
        return str(self.metadata.get("private", False)).strip().lower() in {"true", "yes", "1"}

    # fn: featured - Determine whether the content item appears in Featured content.
    @property
    def featured(self) -> bool:
        """Handle featured for the web content workflow.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return bool(self.metadata.get("featured", False))

    # fn: order - Return the optional sibling-order hint used for section navigation.
    @property
    def order(self) -> int:
        """Return the optional sibling-order hint used for section navigation."""
        value = self.metadata.get("order", 1000)
        try:
            return int(value)
        except (TypeError, ValueError):
            return 1000


# fn: _parse_scalar - Parse a front-matter scalar value into its structured representation.
def _parse_scalar(value: str) -> Any:
    """Handle parse scalar for the web content workflow."""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    lower = value.lower()
    if lower in {"true", "yes", "on"}:
        return True
    if lower in {"false", "no", "off"}:
        return False
    if lower in {"null", "none", "~"}:
        return None
    if re.fullmatch(r"-?[0-9]+", value):
        try:
            return int(value)
        except ValueError:
            pass
    return value


# fn: _indent_of - Measure the indentation of a Markdown metadata line.
def _indent_of(line: str) -> int:
    """Handle indent of for the web content workflow."""
    return len(line) - len(line.lstrip(" "))


# fn: _parse_mapping - Parse a nested front-matter mapping and preserve its hierarchy.
def _parse_mapping(lines: list[str], start: int = 0, indent: int = 0) -> tuple[dict[str, Any], int]:
    """Handle parse mapping for the web content workflow."""
    result: dict[str, Any] = {}
    index = start

    while index < len(lines):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue
        current_indent = _indent_of(raw)
        if current_indent < indent:
            break
        if current_indent > indent:
            raise ValueError(f"Unexpected indentation in metadata: {raw}")

        text = raw.strip()
        if text.startswith("-"):
            raise ValueError(f"Unexpected list item in metadata: {raw}")
        if ":" not in text:
            raise ValueError(f"Invalid metadata line: {raw}")

        key, value_text = text.split(":", 1)
        key = key.strip()
        value_text = value_text.strip()
        if not key:
            raise ValueError(f"Empty metadata key: {raw}")

        if value_text in {">", "|"}:
            style = value_text
            index += 1
            block: list[str] = []
            while index < len(lines):
                candidate = lines[index]
                if candidate.strip() and _indent_of(candidate) <= indent:
                    break
                if candidate.strip():
                    block.append(candidate[indent + 2 :] if len(candidate) >= indent + 2 else candidate.strip())
                else:
                    block.append("")
                index += 1
            if style == ">":
                result[key] = " ".join(part.strip() for part in block if part.strip())
            else:
                result[key] = "\n".join(block).rstrip()
            continue

        if value_text:
            result[key] = _parse_scalar(value_text)
            index += 1
            continue

        # Empty value: inspect the next meaningful indented line to determine list or mapping.
        probe = index + 1
        while probe < len(lines) and (not lines[probe].strip() or lines[probe].lstrip().startswith("#")):
            probe += 1
        if probe >= len(lines) or _indent_of(lines[probe]) <= indent:
            result[key] = ""
            index += 1
            continue

        child_indent = _indent_of(lines[probe])
        if lines[probe].strip().startswith("-"):
            values: list[Any] = []
            index = probe
            while index < len(lines):
                candidate = lines[index]
                if not candidate.strip():
                    index += 1
                    continue
                if _indent_of(candidate) < child_indent:
                    break
                if _indent_of(candidate) != child_indent or not candidate.strip().startswith("-"):
                    raise ValueError(f"Nested list structures are not supported: {candidate}")
                values.append(_parse_scalar(candidate.strip()[1:].strip()))
                index += 1
            result[key] = values
        else:
            child, index = _parse_mapping(lines, probe, child_indent)
            result[key] = child

    return result, index


# fn: parse_front_matter - Parse a Markdown document into front-matter metadata and body.
# . Description
#   Args: text: Input used by this operation.
def parse_front_matter(text: str) -> tuple[dict[str, Any], str]:
    """Parse a Markdown document into front-matter metadata and body.
    
    Args:
        text: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, normalized

    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise ValueError("Metadata block starts with '---' but has no closing '---'.")

    metadata, _ = _parse_mapping(lines[1:end])
    body = "\n".join(lines[end + 1 :]).lstrip("\n")
    return metadata, body


# fn: load_site_config - Read and resolve website configuration from a source repository.
# . Description
#   Args: root: Input used by this operation.
def load_site_config(root: Path) -> SiteConfig:
    """Read and resolve website configuration from a source repository.
    
    Args:
        root: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    root = root.resolve()
    cfg_path = root / "config" / "site.cfg"
    if not cfg_path.is_file():
        raise ValueError(f"Site configuration not found: {cfg_path}")

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read(cfg_path, encoding="utf-8")

    if "site" not in parser or "paths" not in parser:
        raise ValueError("site.cfg must contain [site] and [paths] sections.")

    site = parser["site"]
    paths = parser["paths"]
    branding = parser["branding"] if "branding" in parser else {}
    links_section = parser["links"] if "links" in parser else {}

    default_language = site.get("default_language", "NL").strip().upper()
    # Index filenames must be descriptive; the legacy index_XX.md convention is unsupported.
    old_indexes = sorted(content for content in (root / paths.get("content", "content").strip()).rglob("index_*.md") if re.fullmatch(r"index_[A-Za-z]{2}\.md", content.name))
    if old_indexes:
        raise ValueError("Legacy section indexes are unsupported: " + ", ".join(str(p) for p in old_indexes[:5]))

    # Root index files are the authoritative language registry. Other Markdown
    # files do not enable languages, and site.cfg does not duplicate this list.
    content_dir = root / paths.get("content", "content").strip()
    supported = sorted({
        match.group("language").upper()
        for path in content_dir.glob("*_Index_*.md")
        if (match := _CONTENT_FILE_RE.fullmatch(path.name))
        and _INDEX_FILE_RE.fullmatch(path.name)
    })
    if not supported:
        raise ValueError(f"No root *_Index_XX.md language files found in {content_dir}")
    if default_language not in supported:
        raise ValueError(
            f"Default language {default_language} has no root *_Index_{default_language}.md in {content_dir}"
        )
    supported.remove(default_language)
    supported.insert(0, default_language)

    return SiteConfig(
        root=root,
        title=site.get("title", root.name).strip(),
        description=site.get("description", "").strip(),
        base_url=site.get("base_url", "").strip().rstrip("/"),
        default_language=default_language,
        supported_languages=supported,
        content_style_prefix=site.get("content_style_prefix", "td-").strip(),
        content_dir=root / paths.get("content", "content").strip(),
        templates_dir=root / paths.get("templates", "templates").strip(),
        css_dir=root / paths.get("css", "css").strip(),
        images_dir=root / paths.get("images", "images").strip(),
        logo=str(branding.get("logo", "")).strip(),
        links={str(k).lower(): str(v).strip() for k, v in links_section.items() if str(v).strip()},
    )


# fn: is_ignored - Whether a source path is beneath a directory containing `.ignore`.
# . Description
#   The boundary is included, but ancestors outside it are never inspected.
def is_ignored(path: Path, boundary: Path) -> bool:
    """Whether a source path is beneath a directory containing `.ignore`.

    The boundary is included, but ancestors outside it are never inspected.
    """
    boundary = boundary.resolve()
    current = path.resolve() if path.is_dir() else path.resolve().parent
    if not current.is_relative_to(boundary):
        raise ValueError(f"Source path outside ignore boundary: {path}")
    while True:
        if (current / ".ignore").is_file():
            return True
        if current == boundary:
            return False
        current = current.parent


# fn: load_navigation - Discover root navigation from section indexes, never navigation.cfg.
# . Description
#   Dutch index metadata provides structural defaults; translated indexes supply translated labels. A section without an index is not navigation.
def load_navigation(root: Path, *, include_drafts: bool = False) -> list[NavigationItem]:
    """Discover root navigation from section indexes, never navigation.cfg.

    Dutch index metadata provides structural defaults; translated indexes
    supply translated labels. A section without an index is not navigation.
    Preview mode includes draft-only sections; public mode excludes them.
    """
    config = load_site_config(root)
    entries: list[NavigationItem] = []
    index_dirs = [config.content_dir] + sorted(
        path for path in config.content_dir.iterdir() if path.is_dir() and not is_ignored(path, config.content_dir)
    )
    for directory in index_dirs:
        variants = {}
        for language in config.supported_languages:
            path = section_index(directory, language)
            if path is not None:
                metadata, _ = parse_front_matter(path.read_text(encoding="utf-8"))
                variants[language] = metadata
        if not variants:
            continue
        # Draft-only section indexes do not establish public navigation roots.
        if not include_drafts and not any(
            str(meta.get("status", "")).lower() == "published" or (
                not meta.get("draft", False) and str(meta.get("status", "")).lower() not in {"draft", "preview"}
            ) for meta in variants.values()
        ):
            continue
        defaults = variants.get(config.default_language, {})
        primary = defaults or next(iter(variants.values()))
        relative = directory.relative_to(config.content_dir).as_posix()
        route = "/" if relative == "." else f"/{relative}/"
        labels = {
            lang: str(meta.get("nav_title") or meta.get("title") or relative)
            for lang, meta in variants.items()
        }
        for lang in config.supported_languages:
            if lang not in labels and config.default_language in labels:
                labels[lang] = labels[config.default_language]
        try:
            order = int(primary.get("nav_order", primary.get("order", 1000)))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Invalid nav_order in {directory}") from exc
        entries.append(NavigationItem(
            key=relative if relative != "." else "home",
            order=order,
            path=route,
            template=str(primary.get("template") or ("home" if route == "/" else "page")),
            labels=labels,
        ))
    return sorted(entries, key=lambda item: (item.order, item.key))


# fn: load_featured - Load curated Featured routes from ``config/featured.cfg``.
# . Description
#   The configured route is language-neutral. During generation the route is resolved to the matching page in the language currently being rendered.
def load_featured(root: Path) -> list[FeaturedItem]:
    """Load curated Featured routes from ``config/featured.cfg``.

    The configured route is language-neutral. During generation the route is
    resolved to the matching page in the language currently being rendered.
    Optional images are presentation hints; title and summary always come from
    the target page metadata so translations stay authoritative.
    """
    cfg_path = root.resolve() / "config" / "featured.cfg"
    if not cfg_path.is_file():
        return []

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read(cfg_path, encoding="utf-8")

    items: list[FeaturedItem] = []
    for section in parser.sections():
        values = parser[section]
        route = values.get("route", "").strip()
        if not route:
            raise ValueError(f"Featured item '{section}' has no route.")
        if not route.startswith("/"):
            route = "/" + route
        if route != "/" and not route.endswith("/"):
            route += "/"
        try:
            order = int(values.get("order", "1000"))
        except ValueError as exc:
            raise ValueError(f"Featured item '{section}' has an invalid order.") from exc
        items.append(
            FeaturedItem(
                key=section,
                order=order,
                route=route,
                image=values.get("image", "").strip(),
            )
        )
    return sorted(items, key=lambda item: (item.order, item.key))


# fn: _base_route - Calculate the canonical public route for the chosen content item.
def _base_route(relative_path: Path, base_name: str) -> str:
    """Handle base route for the web content workflow."""
    parent = relative_path.parent.as_posix()
    if parent == ".":
        parent = ""

    if base_name == "index":
        route = f"/{parent}/" if parent else "/"
    else:
        route = f"/{parent}/{base_name}/" if parent else f"/{base_name}/"
    route = re.sub(r"/{2,}", "/", route)
    return route


# fn: language_route - Build the localized public route for a content item.
# . Description
#   Args: base_route: Input used by this operation.
def language_route(base_route: str, language: str, default_language: str) -> str:
    """Handle language route for the web content workflow.
    
    Args:
        base_route: Input used by this operation.
        language: Input used by this operation.
        default_language: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    if language.upper() == default_language.upper():
        return base_route
    if base_route == "/":
        return f"/{language.lower()}/"
    return f"/{language.lower()}{base_route}"


# fn: _owning_navigation_item - Return the most specific main-navigation section that owns a content route.
def _owning_navigation_item(base_route: str, navigation: list[NavigationItem]) -> NavigationItem | None:
    """Return the most specific main-navigation section that owns a content route."""
    matches = [
        item
        for item in navigation
        if item.path != "/" and (base_route == item.path or base_route.startswith(item.path))
    ]
    if not matches:
        return None
    return max(matches, key=lambda item: (len(item.path), -item.order, item.key))


# fn: discover_content - Discover content pages and resolve their routes and languages.
# . Description
#   Args: config: Input used by this operation.
def discover_content(config: SiteConfig, navigation: list[NavigationItem]) -> list[ContentItem]:
    """Discover content pages and resolve their routes and languages.
    
    Args:
        config: Input used by this operation.
        navigation: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    if not config.content_dir.is_dir():
        raise ValueError(f"Content directory not found: {config.content_dir}")

    # Documentation bundles store ordering for copied Markdown in a separate
    # manifest. This keeps authored Markdown files byte-for-byte unchanged.
    order_file = config.content_dir.parent / 'config' / 'doc-nav-orders.json'
    doc_order = json.loads(order_file.read_text(encoding='utf-8')) if order_file.is_file() else {}
    if not isinstance(doc_order, dict):
        raise ValueError(f'Invalid documentation order manifest: {order_file}')

    # Check for ambiguous index pages before resolving routes.
    for directory in [config.content_dir] + [d for d in config.content_dir.rglob("*") if d.is_dir() and not is_ignored(d, config.content_dir)]:
        for language in config.supported_languages:
            section_index(directory, language)

    # Every directory containing publishable Markdown must be a section with
    # an index for at least one enabled language. Ancestor directories must
    # likewise be sections, so navigation cannot contain index-less gaps.
    # Root content is exempt because the root index is handled separately.
    indexed_dirs = {
        path.parent
        for path in config.content_dir.rglob("*_Index_*.md")
        if not is_ignored(path, config.content_dir)
        and (match := _CONTENT_FILE_RE.match(path.name)) is not None
        and _INDEX_FILE_RE.fullmatch(path.name)
        and match.group("language").upper() in config.supported_languages
    }
    for path in sorted(config.content_dir.rglob("*.md")):
        if is_ignored(path, config.content_dir):
            continue
        match = _CONTENT_FILE_RE.match(path.name)
        if match is None or match.group("language").upper() not in config.supported_languages:
            continue
        current = path.parent
        while current != config.content_dir:
            if current not in indexed_dirs:
                raise ValueError(
                    f"Missing section *_Index_XX.md in '{current.relative_to(config.content_dir)}' "
                    f"(required by '{path.relative_to(config.content_dir)}')"
                )
            current = current.parent

    nav_by_path = {item.path: item for item in navigation}
    items: list[ContentItem] = []

    for path in sorted(config.content_dir.rglob("*.md")):
        if is_ignored(path, config.content_dir):
            continue
        match = _CONTENT_FILE_RE.match(path.name)
        if not match:
            continue
        language = match.group("language").upper()
        if language not in config.supported_languages:
            continue
        base_name = "index" if _INDEX_FILE_RE.fullmatch(path.name) else match.group("name")
        relative = path.relative_to(config.content_dir)
        logical_path = relative.with_name(base_name).as_posix()
        base_route = _base_route(relative, base_name)
        route = language_route(base_route, language, config.default_language)

        metadata, body = parse_front_matter(path.read_text(encoding="utf-8"))
        selected_order = doc_order.get(relative.as_posix())
        if selected_order is not None:
            metadata['nav_order'] = int(selected_order)
            if not metadata.get('title'):
                heading = re.search(r'^#\s+(.+?)\s*$', body, re.M)
                if heading:
                    metadata['title'] = heading.group(1).strip()
        template = str(metadata.get("template", "")).strip()
        if not template:
            nav_item = nav_by_path.get(base_route)
            if nav_item is not None:
                template = nav_item.template
            elif base_route == "/":
                template = "home"
            else:
                # Page presentation is independent of section membership.
                # Authors opt in to child indexes using ::: td-index.
                template = "page"

        items.append(
            ContentItem(
                source_path=path,
                logical_id=logical_path,
                base_name=base_name,
                language=language,
                metadata=metadata,
                body=body,
                route=route,
                template=template,
            )
        )

    return items
