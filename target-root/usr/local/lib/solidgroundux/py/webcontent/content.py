"""Content discovery, front-matter parsing, and site configuration helpers."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import configparser
import re
from typing import Any


_CONTENT_FILE_RE = re.compile(r"^(?P<name>.+)_(?P<language>[A-Za-z]{2})\.md$")


@dataclass(slots=True)
class SiteConfig:
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


@dataclass(slots=True)
class NavigationItem:
    key: str
    order: int
    path: str
    template: str
    labels: dict[str, str]


@dataclass(slots=True)
class FeaturedItem:
    """One curated route shown in the home-page Featured slider."""

    key: str
    order: int
    route: str
    image: str = ""


@dataclass(slots=True)
class ContentItem:
    source_path: Path
    logical_id: str
    base_name: str
    language: str
    metadata: dict[str, Any]
    body: str
    route: str
    template: str = "page"

    @property
    def title(self) -> str:
        return str(self.metadata.get("title", self.base_name))

    @property
    def summary(self) -> str:
        return str(self.metadata.get("summary", ""))

    @property
    def date(self) -> str:
        return str(self.metadata.get("date", ""))

    @property
    def tags(self) -> list[str]:
        value = self.metadata.get("tags", [])
        if isinstance(value, list):
            return [str(v) for v in value]
        if value in (None, ""):
            return []
        return [part.strip() for part in str(value).split(",") if part.strip()]

    @property
    def draft(self) -> bool:
        return bool(self.metadata.get("draft", False))

    @property
    def featured(self) -> bool:
        return bool(self.metadata.get("featured", False))

    @property
    def order(self) -> int:
        """Return the optional sibling-order hint used for section navigation."""
        value = self.metadata.get("order", 1000)
        try:
            return int(value)
        except (TypeError, ValueError):
            return 1000


def _parse_scalar(value: str) -> Any:
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


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _parse_mapping(lines: list[str], start: int = 0, indent: int = 0) -> tuple[dict[str, Any], int]:
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


def parse_front_matter(text: str) -> tuple[dict[str, Any], str]:
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


def load_site_config(root: Path) -> SiteConfig:
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
    supported = [part.strip().upper() for part in site.get("supported_languages", default_language).split(",") if part.strip()]
    if default_language not in supported:
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


def load_navigation(root: Path) -> list[NavigationItem]:
    cfg_path = root.resolve() / "config" / "navigation.cfg"
    if not cfg_path.is_file():
        return []

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read(cfg_path, encoding="utf-8")

    items: list[NavigationItem] = []
    for section in parser.sections():
        values = parser[section]
        labels = {key.upper(): value.strip() for key, value in values.items() if re.fullmatch(r"[A-Za-z]{2}", key)}
        path = values.get("path", "/").strip() or "/"
        if not path.startswith("/"):
            path = "/" + path
        if path != "/" and not path.endswith("/"):
            path += "/"
        items.append(
            NavigationItem(
                key=section,
                order=int(values.get("order", "1000")),
                path=path,
                template=values.get("template", "page").strip() or "page",
                labels=labels,
            )
        )
    return sorted(items, key=lambda item: (item.order, item.key))


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


def _base_route(relative_path: Path, base_name: str) -> str:
    parent = relative_path.parent.as_posix()
    if parent == ".":
        parent = ""

    if base_name == "index":
        route = f"/{parent}/" if parent else "/"
    else:
        route = f"/{parent}/{base_name}/" if parent else f"/{base_name}/"
    route = re.sub(r"/{2,}", "/", route)
    return route


def language_route(base_route: str, language: str, default_language: str) -> str:
    if language.upper() == default_language.upper():
        return base_route
    if base_route == "/":
        return f"/{language.lower()}/"
    return f"/{language.lower()}{base_route}"


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


def discover_content(config: SiteConfig, navigation: list[NavigationItem]) -> list[ContentItem]:
    if not config.content_dir.is_dir():
        raise ValueError(f"Content directory not found: {config.content_dir}")

    nav_by_path = {item.path: item for item in navigation}
    items: list[ContentItem] = []

    for path in sorted(config.content_dir.rglob("*.md")):
        match = _CONTENT_FILE_RE.match(path.name)
        if not match:
            continue
        language = match.group("language").upper()
        if language not in config.supported_languages:
            continue
        base_name = match.group("name")
        relative = path.relative_to(config.content_dir)
        logical_path = relative.with_name(base_name).as_posix()
        base_route = _base_route(relative, base_name)
        route = language_route(base_route, language, config.default_language)

        metadata, body = parse_front_matter(path.read_text(encoding="utf-8"))
        template = str(metadata.get("template", "")).strip()
        if not template:
            nav_item = nav_by_path.get(base_route)
            if nav_item is not None:
                template = nav_item.template
            elif base_route == "/":
                template = "home"
            else:
                # Child content inherits the nature of its main section. Static
                # sections use normal pages; listing sections use listing indexes
                # with articles below them. Front matter can always override this.
                owner = _owning_navigation_item(base_route, navigation)
                if owner is not None and owner.template == "listing":
                    template = "listing" if base_name == "index" else "article"
                else:
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
