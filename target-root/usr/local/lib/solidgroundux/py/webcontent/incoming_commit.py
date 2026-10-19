"""Plan and commit staged WCM packages into content without overwriting files.

The first implementation supports abort/skip conflicts. Incoming files remain
untouched. ZIP entries are inspected and streamed, never extracted wholesale.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import shutil

from .incoming_plan import inspect_incoming_package


@dataclass
class ContentCommitPlan:
    """Immutable-intent preview; revalidated immediately before committing."""
    source: str
    content: str
    files: list[str] = field(default_factory=list)
    conflicts: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    policy: str = 'abort'

    @property
    def valid(self) -> bool:
        return not self.errors and (not self.conflicts or self.policy == 'skip')


def plan_content_ingest(source: str | Path, content: str | Path,
                        policy: str = 'abort') -> ContentCommitPlan:
    """Preview destination paths and collisions without modifying content."""
    src_input = Path(source).expanduser()
    dst_input = Path(content).expanduser()
    src, dst = src_input.resolve(), dst_input.resolve()
    plan = ContentCommitPlan(str(src), str(dst), policy=policy)
    if policy not in ('abort', 'skip'):
        plan.errors.append('Unsupported conflict policy')
        return plan
    if src_input.is_symlink() or dst_input.is_symlink():
        plan.errors.append('Symlink source or destination is not allowed')
        return plan
    if src == dst or src in dst.parents or dst in src.parents:
        plan.errors.append('Source and content must not overlap')
        return plan
    if dst.exists() and not dst.is_dir():
        plan.errors.append('Content destination is not a directory')
        return plan
    inspection = inspect_incoming_package(src_input)
    plan.errors.extend(inspection.errors)
    if not inspection.valid:
        return plan
    plan.files = inspection.files
    for rel in plan.files:
        target = dst.joinpath(*PurePosixPath(rel).parts)
        parents = [p for p in target.parents if p == dst or dst in p.parents]
        if any(p.is_symlink() or (p.exists() and not p.is_dir()) for p in parents):
            plan.errors.append(f'Unsafe destination parent: {rel}')
        if target.exists() or target.is_symlink():
            plan.conflicts.append(rel)
    return plan


def commit_content_ingest(plan: ContentCommitPlan) -> list[str]:
    """Commit reviewed entries with exclusive file creation and rollback.

    Abort if the inventory or conflicts have changed since the preview.
    """
    if not plan.valid:
        raise ValueError('Unresolved ingestion plan')
    fresh = plan_content_ingest(plan.source, plan.content, plan.policy)
    if not fresh.valid or (fresh.files, fresh.conflicts) != (plan.files, plan.conflicts):
        raise ValueError('Ingestion plan changed; review again')
    source, dest = Path(plan.source), Path(plan.content)
    archive = source.is_file() and source.suffix.lower() == '.zip'
    created: list[Path] = []
    try:
        with ZipFile(source) if archive else _NullContext() as zip_file:
            for rel in plan.files:
                if rel in plan.conflicts and plan.policy == 'skip':
                    continue
                target = dest.joinpath(*PurePosixPath(rel).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                if any(p.is_symlink() for p in target.parents if p == dest or dest in p.parents):
                    raise ValueError('Destination parent became a symlink')
                if archive:
                    reader = zip_file.open(rel)
                else:
                    reader = (source / rel if source.is_dir() else source).open('rb')
                with reader, target.open('xb') as writer:
                    created.append(target)
                    shutil.copyfileobj(reader, writer)
        return [str(p) for p in created]
    except Exception:
        for path in reversed(created):
            path.unlink(missing_ok=True)
        raise


class _NullContext:
    """Context manager for non-ZIP inputs."""
    def __enter__(self):
        return None

    def __exit__(self, *_args):
        return False
