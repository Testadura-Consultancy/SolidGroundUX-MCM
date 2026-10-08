"""Metadata-driven ingestion of loose Markdown files into a website content tree."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
import re
import shutil
import unicodedata
from typing import Any

from .content import discover_content, load_navigation, load_site_config, parse_front_matter


_VALID_KINDS = {"page", "section", "article"}
_VALID_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_LANGUAGE_SUFFIX_RE = re.compile(r"_(?P<language>[A-Za-z]{2})\.md$")


@dataclass(slots=True)
class IngestInspection:
    success: bool
    input_file: str
    title: str = ""
    language: str = ""
    parent: str = ""
    kind: str = ""
    slug: str = ""
    slug_explicit: bool = False
    summary: str = ""
    supported_languages: list[str] = field(default_factory=list)
    parent_options: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        return {
            "success": self.success,
            "input_file": self.input_file,
            "title": self.title,
            "language": self.language,
            "parent": self.parent,
            "kind": self.kind,
            "slug": self.slug,
            "slug_explicit": self.slug_explicit,
            "summary": self.summary,
            "supported_languages": self.supported_languages,
            "parent_options": self.parent_options,
            "warnings": self.warnings,
            "errors": self.errors,
        }


@dataclass(slots=True)
class IngestResult:
    success: bool
    input_file: str
    destination: str = ""
    route: str = ""
    archive_path: str = ""
    committed: bool = False
    source_archived: bool = False
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        return {
            "success": self.success,
            "input_file": self.input_file,
            "destination": self.destination,
            "route": self.route,
            "archive_path": self.archive_path,
            "committed": self.committed,
            "source_archived": self.source_archived,
            "warnings": self.warnings,
            "errors": self.errors,
        }


def _normalize_route(value: str) -> str:
    route = str(value or "").strip()
    if not route:
        return ""
    if not route.startswith("/"):
        route = "/" + route
    route = re.sub(r"/{2,}", "/", route)
    if route != "/" and not route.endswith("/"):
        route += "/"
    return route


def _base_route(route: str, language: str, default_language: str) -> str:
    if language.upper() == default_language.upper():
        return route
    prefix = f"/{language.lower()}"
    if route == f"{prefix}/":
        return "/"
    if route.startswith(prefix + "/"):
        return route[len(prefix) :]
    return route


def _route_parent_and_slug(route: str) -> tuple[str, str]:
    normalized = _normalize_route(route)
    parts = [part for part in normalized.strip("/").split("/") if part]
    if not parts:
        return "", ""
    slug = parts[-1]
    parent_parts = parts[:-1]
    parent = "/" + "/".join(parent_parts) + "/" if parent_parts else "/"
    return parent, slug


def slugify(value: str) -> str:
    """Create a conservative ASCII URL slug from a title."""
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii").lower()
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value).strip("-")
    return slug


def _infer_language(path: Path, supported: list[str]) -> str:
    match = _LANGUAGE_SUFFIX_RE.search(path.name)
    if not match:
        return ""
    language = match.group("language").upper()
    return language if language in supported else ""


def _infer_kind(metadata: dict[str, Any], path: Path) -> str:
    value = str(metadata.get("kind", metadata.get("type", "")) or "").strip().lower()
    if value in _VALID_KINDS:
        return value
    template = str(metadata.get("template", "") or "").strip().lower()
    if template == "article":
        return "article"
    if re.match(r"^index_[A-Za-z]{2}\.md$", path.name):
        return "section"
    return ""


def _index_options(source: Path, language: str) -> list[tuple[str, str]]:
    config = load_site_config(source)
    navigation = load_navigation(config.root)
    items = discover_content(config, navigation)
    indexes: dict[str, str] = {}

    for item in items:
        if item.language != language or item.draft or item.base_name != "index":
            continue
        route = _base_route(item.route, item.language, config.default_language)
        indexes[route] = item.title

    options: list[tuple[str, str]] = []
    for route in sorted(indexes, key=lambda value: (value.count("/"), value)):
        if route == "/":
            label = indexes[route]
        else:
            parts = [part for part in route.strip("/").split("/") if part]
            labels: list[str] = []
            for depth in range(1, len(parts) + 1):
                ancestor = "/" + "/".join(parts[:depth]) + "/"
                title = indexes.get(ancestor)
                if title:
                    labels.append(title)
            label = " > ".join(labels) if labels else indexes[route]
        options.append((route, label))
    return options


def inspect_ingest(source: str | Path, input_file: str | Path, language_override: str = "") -> IngestInspection:
    source_path = Path(source).expanduser().resolve()
    input_path = Path(input_file).expanduser().resolve()
    errors: list[str] = []
    warnings: list[str] = []

    if not input_path.is_file():
        return IngestInspection(False, str(input_path), errors=[f"Input Markdown file not found: {input_path}"])
    if input_path.suffix.lower() != ".md":
        return IngestInspection(False, str(input_path), errors=[f"Input file is not Markdown: {input_path}"])

    try:
        config = load_site_config(source_path)
        metadata, _ = parse_front_matter(input_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return IngestInspection(False, str(input_path), errors=[str(exc)])

    title = str(metadata.get("title", "") or "").strip()
    summary = str(metadata.get("summary", "") or "").strip()

    raw_language = language_override or str(metadata.get("language", "") or "").strip() or _infer_language(input_path, config.supported_languages)
    language = raw_language.upper() if raw_language else ""
    if language and language not in config.supported_languages:
        warnings.append(f"Unsupported language in ingest metadata: {language}; select a supported language.")
        language = ""

    kind = _infer_kind(metadata, input_path)
    raw_kind = str(metadata.get("kind", metadata.get("type", "")) or "").strip().lower()
    if raw_kind and raw_kind not in _VALID_KINDS:
        warnings.append(f"Unknown content kind in ingest metadata: {raw_kind}; select page, section, or article.")
        kind = ""

    parent = _normalize_route(str(metadata.get("parent", metadata.get("parent_route", "")) or ""))
    slug = str(metadata.get("slug", "") or "").strip().lower()
    route = _normalize_route(str(metadata.get("route", "") or ""))
    slug_explicit = bool(slug or route)
    if route:
        route_parent, route_slug = _route_parent_and_slug(route)
        if not parent:
            parent = route_parent
        if not slug:
            slug = route_slug
    if not slug and title:
        slug = slugify(title)

    parent_options: list[str] = []
    if language:
        try:
            options = _index_options(source_path, language)
            valid_parents = {route for route, _ in options}
            if parent and parent not in valid_parents:
                warnings.append(f"Parent route does not exist as a {language} section index: {parent}")
                parent = ""
            parent_options = [f"{label} [{route}]" for route, label in options]
        except Exception as exc:
            errors.append(str(exc))

    return IngestInspection(
        success=not errors,
        input_file=str(input_path),
        title=title,
        language=language,
        parent=parent,
        kind=kind,
        slug=slug,
        slug_explicit=slug_explicit,
        summary=summary,
        supported_languages=list(config.supported_languages),
        parent_options=parent_options,
        warnings=warnings,
        errors=errors,
    )


def _route_to_content_dir(content_dir: Path, parent_route: str) -> Path:
    parts = [part for part in parent_route.strip("/").split("/") if part]
    return content_dir.joinpath(*parts) if parts else content_dir


def _archive_destination(source: Path, input_file: Path) -> Path:
    """Return a collision-safe canonical archive path for an ingested source file."""
    archive_dir = source / "ingested" / date.today().isoformat()
    candidate = archive_dir / input_file.name
    if not candidate.exists():
        return candidate

    stem = input_file.stem
    suffix = input_file.suffix
    index = 2
    while True:
        candidate = archive_dir / f"{stem}-{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def _plain_scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if text == "":
        return '""'
    lower = text.lower()
    if (
        lower in {"true", "false", "yes", "no", "on", "off", "null", "none", "~"}
        or re.fullmatch(r"-?[0-9]+", text)
        or text != text.strip()
        or (len(text) >= 2 and text[0] == text[-1] and text[0] in {"'", '"'})
    ):
        if "'" not in text:
            return f"'{text}'"
        if '"' not in text:
            return f'"{text}"'
    return text


def _serialize_mapping(mapping: dict[str, Any], indent: int = 0) -> list[str]:
    lines: list[str] = []
    prefix = " " * indent
    for key, value in mapping.items():
        if isinstance(value, dict):
            lines.append(f"{prefix}{key}:")
            lines.extend(_serialize_mapping(value, indent + 2))
        elif isinstance(value, list):
            lines.append(f"{prefix}{key}:")
            for item in value:
                lines.append(f"{' ' * (indent + 2)}- {_plain_scalar(item)}")
        elif isinstance(value, str) and "\n" in value:
            lines.append(f"{prefix}{key}: |")
            lines.extend(f"{' ' * (indent + 2)}{part}" for part in value.splitlines())
        else:
            lines.append(f"{prefix}{key}: {_plain_scalar(value)}")
    return lines


def _canonical_metadata(
    existing: dict[str, Any],
    *,
    title: str,
    kind: str,
    summary: str,
) -> dict[str, Any]:
    """Return front matter for the canonical repository copy.

    Ingestion-only placement metadata (language, parent, slug, route, and kind)
    is consumed while the loose file is imported. The canonical content tree and
    filename then carry that information, avoiding redundant metadata that could
    drift out of sync after later repository edits.
    """
    metadata = dict(existing)
    for key in ("language", "kind", "type", "parent", "parent_route", "slug", "route"):
        metadata.pop(key, None)

    canonical: dict[str, Any] = {"title": title}
    if summary:
        canonical["summary"] = summary
    else:
        metadata.pop("summary", None)

    # Explicit templates keep the generator deterministic when an article is
    # ingested below a static section or a normal page below a listing section.
    canonical["template"] = "article" if kind == "article" else "page"

    preferred = ["order", "date", "draft", "featured", "tags", "social", "social_intro"]
    for key in preferred:
        if key in metadata:
            canonical[key] = metadata.pop(key)
    for key, value in metadata.items():
        if key not in canonical:
            canonical[key] = value
    return canonical


def ingest_content(
    source: str | Path,
    input_file: str | Path,
    *,
    title: str,
    language: str,
    parent: str,
    kind: str,
    slug: str,
    summary: str = "",
    commit: bool = True,
) -> IngestResult:
    source_path = Path(source).expanduser().resolve()
    input_path = Path(input_file).expanduser().resolve()
    config = load_site_config(source_path)

    title = title.strip()
    language = language.strip().upper()
    parent = _normalize_route(parent)
    kind = kind.strip().lower()
    slug = slug.strip().lower()
    summary = summary.strip()

    errors: list[str] = []
    if not input_path.is_file():
        errors.append(f"Input Markdown file not found: {input_path}")
    if not title:
        errors.append("Title is required for ingestion.")
    if language not in config.supported_languages:
        errors.append(f"Unsupported language: {language}")
    if kind not in _VALID_KINDS:
        errors.append(f"Unsupported content kind: {kind}")
    if not _VALID_SLUG_RE.fullmatch(slug):
        errors.append(f"Invalid slug '{slug}'. Use lowercase letters, numbers, and hyphens.")

    try:
        valid_parent_routes = {route for route, _ in _index_options(source_path, language)} if language in config.supported_languages else set()
    except Exception as exc:
        valid_parent_routes = set()
        errors.append(str(exc))
    if parent not in valid_parent_routes:
        errors.append(f"Parent route is not a live {language} section index: {parent or '<empty>'}")

    parent_dir = _route_to_content_dir(config.content_dir, parent)
    route = _normalize_route(parent.rstrip("/") + "/" + slug + "/")
    if kind == "section":
        destination = parent_dir / slug / f"index_{language}.md"
    else:
        destination = parent_dir / f"{slug}_{language}.md"
    archive_path = _archive_destination(source_path, input_path)

    if destination.exists() and destination.resolve() != input_path:
        errors.append(f"Destination already exists: {destination}")
    if errors:
        return IngestResult(
            False,
            str(input_path),
            str(destination),
            route,
            str(archive_path),
            errors=errors,
        )

    if not commit:
        return IngestResult(
            True,
            str(input_path),
            str(destination),
            route,
            str(archive_path),
            committed=False,
        )

    metadata, body = parse_front_matter(input_path.read_text(encoding="utf-8"))
    canonical = _canonical_metadata(
        metadata,
        title=title,
        kind=kind,
        summary=summary,
    )
    rendered = "---\n" + "\n".join(_serialize_mapping(canonical)) + "\n---\n\n" + body.rstrip() + "\n"

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered, encoding="utf-8")

    source_archived = False
    if input_path.resolve() != destination.resolve():
        try:
            archive_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(input_path), str(archive_path))
            source_archived = True
        except Exception:
            # Keep ingestion transactional: if the original cannot be archived,
            # remove the newly written canonical copy and leave the input in place.
            destination.unlink(missing_ok=True)
            raise

    return IngestResult(
        True,
        str(input_path),
        str(destination),
        route,
        str(archive_path),
        committed=True,
        source_archived=source_archived,
    )
