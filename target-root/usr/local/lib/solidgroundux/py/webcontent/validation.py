"""Repository and content validation for the WebContent engine."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re

from .content import discover_content, load_featured, load_navigation, load_site_config
from .markdown import referenced_style_classes


@dataclass(slots=True)
class ValidationResult:
    success: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    content_files: int = 0
    style_classes: int = 0

    def as_dict(self) -> dict[str, object]:
        return {
            "success": self.success,
            "errors": self.errors,
            "warnings": self.warnings,
            "content_files": self.content_files,
            "style_classes": self.style_classes,
        }


def _available_style_classes(css_dir: Path, prefix: str) -> set[str]:
    classes: set[str] = set()
    pattern = re.compile(r"\.([A-Za-z_][A-Za-z0-9_-]*)")
    if not css_dir.is_dir():
        return classes
    for path in css_dir.rglob("*.css"):
        text = path.read_text(encoding="utf-8")
        classes.update(name for name in pattern.findall(text) if name.startswith(prefix))
    return classes


def validate_site(source: str | Path) -> ValidationResult:
    errors: list[str] = []
    warnings: list[str] = []

    try:
        config = load_site_config(Path(source))
    except Exception as exc:  # validation must aggregate a clean caller-facing error
        return ValidationResult(False, [str(exc)])

    required_dirs = [config.content_dir, config.templates_dir, config.css_dir]
    for path in required_dirs:
        if not path.is_dir():
            errors.append(f"Required directory not found: {path}")

    required_templates = ["base.html", "home.html", "page.html", "article.html", "listing.html"]
    for name in required_templates:
        if not (config.templates_dir / name).is_file():
            errors.append(f"Required template not found: {config.templates_dir / name}")

    if errors:
        return ValidationResult(False, errors, warnings)

    try:
        navigation = load_navigation(config.root)
        featured_items = load_featured(config.root)
        items = discover_content(config, navigation)
    except Exception as exc:
        errors.append(str(exc))
        return ValidationResult(False, errors, warnings)

    if not items:
        errors.append("No strongly named Markdown content files were found.")
        return ValidationResult(False, errors, warnings)

    available_styles = _available_style_classes(config.css_dir, config.content_style_prefix)
    used_styles: set[str] = set()
    logical_languages: dict[str, set[str]] = {}
    live_routes: dict[str, Path] = {}

    for item in items:
        logical_languages.setdefault(item.logical_id, set()).add(item.language)
        if not item.metadata.get("title"):
            errors.append(f"Missing required metadata 'title': {item.source_path}")
        used_styles.update(referenced_style_classes(item.body, config.content_style_prefix))

        if not item.draft:
            previous = live_routes.get(item.route)
            if previous is not None:
                errors.append(
                    f"Multiple content files generate the same route {item.route}: "
                    f"{previous} and {item.source_path}"
                )
            else:
                live_routes[item.route] = item.source_path

    # Main navigation points at section roots. Each section root must therefore
    # be backed by an index page in the default language; child-page hierarchy
    # and breadcrumbs are derived from these index pages rather than navigation.cfg.
    default_index_routes = {
        item.route
        for item in items
        if item.language == config.default_language and item.base_name == "index" and not item.draft
    }
    for nav_item in navigation:
        if nav_item.path not in default_index_routes:
            errors.append(
                f"Navigation section '{nav_item.key}' has no {config.default_language} index page "
                f"for route {nav_item.path}"
            )

    # Featured content is a curated list of language-neutral routes. Require
    # every configured target to exist in the default language so a typo cannot
    # silently remove a promoted item. Other language variants may be absent;
    # the generator simply omits that tile until a translation exists.
    default_live_base_routes = {
        item.route
        for item in items
        if item.language == config.default_language and not item.draft
    }
    seen_featured_routes: set[str] = set()
    for featured in featured_items:
        if featured.route in seen_featured_routes:
            errors.append(f"Featured route is configured more than once: {featured.route}")
        seen_featured_routes.add(featured.route)
        if featured.route not in default_live_base_routes:
            errors.append(
                f"Featured item '{featured.key}' has no live {config.default_language} page "
                f"for route {featured.route}"
            )
        if featured.image and not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", featured.image):
            image_path = config.root / featured.image.lstrip("/")
            if not image_path.is_file():
                errors.append(f"Featured image not found for '{featured.key}': {image_path}")

    # Content folders are sections. Every live page must therefore have a live
    # index page for its language at each folder level up to the content root.
    # This keeps local navigation and breadcrumb ancestry complete and explicit.
    live_source_paths = {item.source_path for item in items if not item.draft}
    missing_section_indexes: set[Path] = set()
    for item in items:
        if item.draft:
            continue
        directory = item.source_path.parent
        while True:
            expected_index = directory / f"index_{item.language}.md"
            if expected_index not in live_source_paths:
                missing_section_indexes.add(expected_index)
            if directory == config.content_dir:
                break
            directory = directory.parent

    for path in sorted(missing_section_indexes):
        errors.append(f"Content section has no live index page: {path}")

    missing_styles = sorted(used_styles - available_styles)
    for name in missing_styles:
        errors.append(f"Content references unknown CSS class: {name}")

    for item in items:
        if item.language == config.default_language:
            continue
        if config.default_language not in logical_languages.get(item.logical_id, set()):
            warnings.append(
                f"Translation {item.source_path.name} has no {config.default_language} source variant."
            )

    return ValidationResult(
        success=not errors,
        errors=errors,
        warnings=warnings,
        content_files=len(items),
        style_classes=len(available_styles),
    )
