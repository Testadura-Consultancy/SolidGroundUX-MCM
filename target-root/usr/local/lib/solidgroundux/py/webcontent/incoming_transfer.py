"""Review and copy server-local files to incoming without modifying website content.

Only explicit 'abort' and 'skip' conflict policies are supported. The default
'abort' policy protects staged files. ZIP files remain intact for ingestion.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import shutil

from .incoming_plan import inspect_incoming_package


@dataclass
class TransferPlan:
    """Read-only preview of a proposed transfer and its conflicts."""
    source: str
    incoming: str
    files: list[tuple[str, str]] = field(default_factory=list)
    conflicts: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    conflict_policy: str = 'abort'

    @property
    def valid(self) -> bool:
        """Whether the reviewed plan is eligible for execution."""
        return not self.errors and (not self.conflicts or self.conflict_policy == 'skip')

    @property
    def copy_count(self) -> int:
        """Number of files eligible for copying under the selected policy."""
        return len(self.files) - (len(self.conflicts) if self.conflict_policy == 'skip' else 0)


def plan_local_import(source: str | Path, incoming: str | Path,
                      conflict_policy: str = 'abort') -> TransferPlan:
    """Plan a local file, directory, or ZIP transfer; never modify either tree."""
    src_input = Path(source).expanduser()
    dst_input = Path(incoming).expanduser()
    src = src_input.resolve()
    dst = dst_input.resolve()
    plan = TransferPlan(str(src), str(dst), conflict_policy=conflict_policy)
    if conflict_policy not in ('abort', 'skip'):
        plan.errors.append(f'Unsupported conflict policy: {conflict_policy}')
        return plan
    inspection = inspect_incoming_package(src_input)
    plan.errors.extend(inspection.errors)
    if not inspection.valid:
        return plan
    if src == dst or dst.is_relative_to(src) or src.is_relative_to(dst):
        plan.errors.append('Source and incoming directories must not overlap')
        return plan
    if dst_input.is_symlink() or dst.is_symlink():
        plan.errors.append('Incoming must not be a symlink')
        return plan
    if dst.exists() and not dst.is_dir():
        plan.errors.append('Incoming destination is not a directory')
        return plan
    rels = inspection.files if src.is_dir() else [src.name]
    for rel in rels:
        target = dst / rel
        if any(p.is_symlink() or (p.exists() and not p.is_dir())
               for p in (target.parent, *target.parent.parents)
               if p == dst or dst in p.parents):
            plan.errors.append(f'Unsafe destination parent: {rel}')
        if target.exists() or target.is_symlink():
            plan.conflicts.append(rel)
        plan.files.append((str(src / rel if src.is_dir() else src), str(target)))
    return plan


def copy_local_to_incoming(plan: TransferPlan) -> list[str]:
    """Copy reviewed files exclusively; skip only pre-reviewed conflicts.

    Recheck conflicts before writing. If a planned destination changes after
    review, abort rather than silently skipping a newly created file.
    """
    if not plan.valid:
        raise ValueError('Transfer plan has errors or unresolved conflicts')
    fresh = plan_local_import(plan.source, plan.incoming, plan.conflict_policy)
    if not fresh.valid or fresh.files != plan.files or fresh.conflicts != plan.conflicts:
        raise ValueError('Transfer plan changed; review again')
    conflicts = set(plan.conflicts) if plan.conflict_policy == 'skip' else set()
    created: list[Path] = []
    incoming = Path(plan.incoming)
    try:
        for source, target in plan.files:
            src, dst = Path(source), Path(target)
            rel = dst.relative_to(incoming).as_posix()
            if rel in conflicts:
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            if any(p.is_symlink() for p in (dst.parent, *dst.parent.parents)
                   if p == incoming or incoming in p.parents):
                raise ValueError(f'Unsafe destination directory: {dst.parent}')
            with src.open('rb') as reader, dst.open('xb') as writer:
                created.append(dst)
                shutil.copyfileobj(reader, writer)
        return [str(p) for p in created]
    except Exception:
        for path in reversed(created):
            path.unlink(missing_ok=True)
        raise
