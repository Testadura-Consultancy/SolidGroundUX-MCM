"""Read-only inventory and safety checks for WCM incoming directory packages.

This module deliberately does not commit files to content or extract archives.
The caller must explicitly resolve conflicts before a later ingestion step.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from zipfile import ZipFile, BadZipFile
import re

_INDEX_RE = re.compile(r"^.+_Index_[A-Za-z]{2}\.md$", re.I)
_PAGE_RE = re.compile(r"^.+_[A-Za-z]{2}\.md$", re.I)


@dataclass
class IncomingPlan:
    """Portable inventory of one incoming package, without side effects."""
    source: str
    files: list[str] = field(default_factory=list)
    sections: list[str] = field(default_factory=list)
    resources: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        """Whether the package passed the path and file checks."""
        return not self.errors


def _check_path(name: str) -> str | None:
    """Reject paths that could escape staging or have ambiguous separators."""
    if not name or "\\" in name or "\x00" in name:
        return "invalid or ambiguous path"
    if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
        return "absolute path"
    parts = PurePosixPath(name).parts
    if any(part in (".", "..") for part in name.split("/")):
        return "path traversal"
    if not parts or any(part == "" for part in parts):
        return "invalid path"
    return None


def _classify(plan: IncomingPlan, names: list[str]) -> None:
    """Classify Markdown section indexes and associated resource files."""
    plan.files = sorted(names)
    for name in plan.files:
        path = PurePosixPath(name)
        if _INDEX_RE.fullmatch(path.name):
            section = str(path.parent)
            plan.sections.append("" if section == "." else section)
        elif not _PAGE_RE.fullmatch(path.name):
            plan.resources.append(name)
    plan.sections = sorted(set(plan.sections))


def inspect_incoming_package(path: str | Path) -> IncomingPlan:
    """Inspect a local file, directory or ZIP without modifying the filesystem.

    ZIP entries are not extracted. Symlinks and nonregular archive entries are
    rejected. Directories are traversed without following symlinked entries.
    """
    source = Path(path).expanduser()
    plan = IncomingPlan(str(source))
    if not source.exists():
        plan.errors.append(f"Input not found: {source}")
        return plan
    names: list[str] = []
    if source.is_symlink():
        plan.errors.append("Symlink input is not allowed")
        return plan
    if source.is_dir():
        for child in sorted(source.rglob("*")):
            if child.is_symlink():
                plan.errors.append(f"Symlink is not allowed: {child.relative_to(source)}")
            elif child.is_file():
                rel = child.relative_to(source).as_posix()
                problem = _check_path(rel)
                if problem:
                    plan.errors.append(f"{rel}: {problem}")
                else:
                    names.append(rel)
            elif not child.is_dir():
                plan.errors.append(f"Unsupported filesystem entry: {child}")
    elif source.is_file() and source.suffix.lower() == ".zip":
        try:
            with ZipFile(source) as archive:
                seen: set[str] = set()
                for entry in archive.infolist():
                    name = entry.filename
                    problem = _check_path(name)
                    mode = (entry.external_attr >> 16) & 0o170000
                    if problem:
                        plan.errors.append(f"{name}: {problem}")
                    elif mode not in (0, 0o100000, 0o040000):
                        plan.errors.append(f"{name}: unsupported ZIP entry type")
                    elif not entry.is_dir():
                        if name in seen:
                            plan.errors.append(f"{name}: duplicate ZIP entry")
                        seen.add(name)
                        names.append(name)
        except (BadZipFile, OSError) as exc:
            plan.errors.append(f"Cannot read ZIP: {exc}")
    elif source.is_file():
        names.append(source.name)
    else:
        plan.errors.append("Unsupported input type")
    _classify(plan, names)
    if not names and not plan.errors:
        plan.warnings.append("Package contains no files")
    return plan
