"""Safe content deletion and recoverable archive support."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
import shutil
from typing import Any

from .content import ContentItem, discover_content, load_navigation, load_site_config


@dataclass(slots=True)
class DeleteInspection:
    """Describe canonical content files that may be removed safely."""

    success: bool
    options: list[str] = field(default_factory=list)
    protected_count: int = 0
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "options": self.options,
            "protected_count": self.protected_count,
            "warnings": self.warnings,
            "errors": self.errors,
        }


@dataclass(slots=True)
class DeleteResult:
    """Preview or result of one recoverable content deletion."""

    success: bool
    content_file: str = ""
    title: str = ""
    language: str = ""
    route: str = ""
    archive_root: str = ""
    recursive_required: bool = False
    all_languages_required: bool = False
    descendant_count: int = 0
    translation_count: int = 0
    affected_files: list[str] = field(default_factory=list)
    archive_paths: list[str] = field(default_factory=list)
    deleted_count: int = 0
    committed: bool = False
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "content_file": self.content_file,
            "title": self.title,
            "language": self.language,
            "route": self.route,
            "archive_root": self.archive_root,
            "recursive_required": self.recursive_required,
            "all_languages_required": self.all_languages_required,
            "descendant_count": self.descendant_count,
            "translation_count": self.translation_count,
            "affected_files": self.affected_files,
            "archive_paths": self.archive_paths,
            "deleted_count": self.deleted_count,
            "committed": self.committed,
            "warnings": self.warnings,
            "errors": self.errors,
        }


def _base_route(item: ContentItem, default_language: str) -> str:
    """Return the language-neutral route for one discovered content item."""
    if item.language.upper() == default_language.upper():
        return item.route
    prefix = f"/{item.language.lower()}"
    if item.route == f"{prefix}/":
        return "/"
    if item.route.startswith(prefix + "/"):
        return item.route[len(prefix) :]
    return item.route


def _relative_content_path(item: ContentItem, content_dir: Path) -> str:
    return item.source_path.relative_to(content_dir).as_posix()


def _candidate_label(item: ContentItem, content_dir: Path) -> str:
    relative = _relative_content_path(item, content_dir)
    return f"{item.title} | {item.language} | {item.route} [{relative}]"


def inspect_delete(source: str | Path) -> DeleteInspection:
    """List content pages that may be deleted without breaking main navigation.

    The homepage and direct main-navigation section roots are intentionally protected.
    Deleting those requires an explicit navigation change rather than a page-only action.
    """
    try:
        config = load_site_config(Path(source).expanduser().resolve())
        navigation = load_navigation(config.root)
        items = discover_content(config, navigation)
    except Exception as exc:
        return DeleteInspection(False, errors=[str(exc)])

    protected_routes = {"/"}
    protected_routes.update(item.path for item in navigation)
    options: list[str] = []
    protected_count = 0

    for item in items:
        base_route = _base_route(item, config.default_language)
        if item.base_name == "index" and base_route in protected_routes:
            protected_count += 1
            continue
        options.append(_candidate_label(item, config.content_dir))

    options.sort(key=str.casefold)
    warnings: list[str] = []
    if not options:
        warnings.append("No deletable child pages were found. Home and main-navigation section roots are protected.")

    return DeleteInspection(
        success=True,
        options=options,
        protected_count=protected_count,
        warnings=warnings,
    )


def _resolve_item(source: Path, relative_path: str) -> tuple[Any, list[ContentItem], ContentItem]:
    config = load_site_config(source)
    navigation = load_navigation(config.root)
    items = discover_content(config, navigation)

    requested = Path(relative_path)
    if requested.is_absolute() or ".." in requested.parts:
        raise ValueError(f"Content path must be relative to the content directory: {relative_path}")

    content_root = config.content_dir.resolve()
    target = (content_root / requested).resolve()
    try:
        target.relative_to(content_root)
    except ValueError as exc:
        raise ValueError(f"Content path escapes the content directory: {relative_path}") from exc

    for item in items:
        if item.source_path.resolve() == target:
            return config, items, item
    raise ValueError(f"Canonical content file not found: {relative_path}")


def _archive_destination(archive_root: Path, relative_path: Path) -> Path:
    """Return a collision-safe archive path while preserving the content hierarchy."""
    candidate = archive_root / relative_path
    if not candidate.exists():
        return candidate

    index = 2
    while True:
        candidate = archive_root / relative_path.parent / f"{relative_path.stem}-{index}{relative_path.suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def delete_content(
    source: str | Path,
    content_file: str,
    *,
    recursive: bool = False,
    all_languages: bool = False,
    commit: bool = False,
) -> DeleteResult:
    """Preview or archive one canonical content page and optional descendants.

    Deletion is recoverable: committed files are moved to
    ``deleted/YYYY-MM-DD/<original relative content path>``. Main-navigation section
    roots and the site homepage are protected because deleting them requires a matching
    navigation change, which is outside this page-only operation.
    """
    source_path = Path(source).expanduser().resolve()
    try:
        config, items, selected = _resolve_item(source_path, content_file)
    except Exception as exc:
        return DeleteResult(False, content_file=content_file, errors=[str(exc)])

    base_route = _base_route(selected, config.default_language)
    navigation = load_navigation(config.root)
    protected_routes = {"/"}
    protected_routes.update(item.path for item in navigation)
    if selected.base_name == "index" and base_route in protected_routes:
        return DeleteResult(
            False,
            content_file=content_file,
            title=selected.title,
            language=selected.language,
            route=selected.route,
            errors=[
                "Home and main-navigation section indexes are protected. Remove or change the navigation entry before deleting that section root."
            ],
        )

    translations = [
        item
        for item in items
        if item.logical_id == selected.logical_id and item.source_path != selected.source_path
    ]
    translations.sort(key=lambda item: item.language)
    if selected.language == config.default_language and translations and not all_languages:
        return DeleteResult(
            True,
            content_file=_relative_content_path(selected, config.content_dir),
            title=selected.title,
            language=selected.language,
            route=selected.route,
            archive_root=str(source_path / "deleted" / date.today().isoformat()),
            all_languages_required=True,
            translation_count=len(translations),
            affected_files=[_relative_content_path(selected, config.content_dir)],
            committed=False,
            warnings=[
                "The selected default-language page has translations; delete all language versions together to avoid orphaned translations."
            ],
        )

    language_filter = None if all_languages else selected.language
    descendants = [
        item
        for item in items
        if item.source_path != selected.source_path
        and (language_filter is None or item.language == language_filter)
        and _base_route(item, config.default_language) != base_route
        and _base_route(item, config.default_language).startswith(base_route)
    ]
    descendants.sort(key=lambda item: _relative_content_path(item, config.content_dir))

    if descendants and not recursive:
        affected = [_relative_content_path(selected, config.content_dir)]
        affected.extend(_relative_content_path(item, config.content_dir) for item in descendants)
        return DeleteResult(
            True,
            content_file=_relative_content_path(selected, config.content_dir),
            title=selected.title,
            language=selected.language,
            route=selected.route,
            archive_root=str(source_path / "deleted" / date.today().isoformat()),
            recursive_required=True,
            all_languages_required=False,
            descendant_count=len(descendants),
            translation_count=len(translations),
            affected_files=affected,
            committed=False,
            warnings=["The selected page has child content; recursive deletion is required to avoid orphaning descendants."],
        )

    if all_languages:
        affected_items = [item for item in items if item.logical_id == selected.logical_id]
    else:
        affected_items = [selected]
    if recursive:
        existing_paths = {item.source_path for item in affected_items}
        affected_items.extend(item for item in descendants if item.source_path not in existing_paths)

    archive_root = source_path / "deleted" / date.today().isoformat()
    affected_paths = [Path(_relative_content_path(item, config.content_dir)) for item in affected_items]
    archive_paths = [_archive_destination(archive_root, relative) for relative in affected_paths]

    result = DeleteResult(
        True,
        content_file=_relative_content_path(selected, config.content_dir),
        title=selected.title,
        language=selected.language,
        route=selected.route,
        archive_root=str(archive_root),
        recursive_required=False,
        all_languages_required=False,
        descendant_count=len(descendants),
        translation_count=len(translations),
        affected_files=[path.as_posix() for path in affected_paths],
        archive_paths=[str(path) for path in archive_paths],
        committed=commit,
    )
    if not commit:
        return result

    moved: list[tuple[Path, Path]] = []
    try:
        for relative, archive_path in zip(affected_paths, archive_paths, strict=True):
            source_file = (config.content_dir / relative).resolve()
            archive_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source_file), str(archive_path))
            moved.append((archive_path, source_file))
    except Exception as exc:
        rollback_errors: list[str] = []
        for archive_path, original_path in reversed(moved):
            try:
                original_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(archive_path), str(original_path))
            except Exception as rollback_exc:
                rollback_errors.append(str(rollback_exc))
        errors = [f"Could not archive deleted content: {exc}"]
        errors.extend(f"Rollback failed: {message}" for message in rollback_errors)
        result.success = False
        result.deleted_count = 0
        result.errors = errors
        return result

    result.deleted_count = len(affected_paths)
    return result
