"""Archive fully accepted incoming packages without deleting the original bytes.

Only call this after a successful content commit with no skipped/conflicting files.
The archive is deliberately outside the selectable top-level incoming packages.
"""

from __future__ import annotations

from pathlib import Path
import os
import uuid


def archive_ingested_package(package: Path, incoming: Path) -> Path:
    """Move a single, fully ingested top-level package to a unique archive slot."""
    incoming = incoming.resolve(strict=True)
    package = Path(package)
    if package.is_symlink() or package.parent.resolve(strict=True) != incoming:
        raise ValueError("Only a non-symlink top-level incoming package may be archived")
    if not package.exists() or package.name.startswith(".") or package.name == "archive":
        raise ValueError("Invalid incoming package")
    archive = incoming / "archive"
    if archive.is_symlink():
        raise ValueError("Archive directory must not be a symlink")
    archive.mkdir(mode=0o700, exist_ok=True)
    if not archive.is_dir():
        raise ValueError("Archive destination is not a directory")
    # A fresh exclusive directory prevents overwriting previous packages, even
    # when their filenames are identical. The original basename is preserved.
    for _ in range(10):
        slot = archive / uuid.uuid4().hex
        try:
            slot.mkdir(mode=0o700)
            break
        except FileExistsError:
            continue
    else:
        raise RuntimeError("Unable to reserve an archive slot")
    destination = slot / package.name
    try:
        os.rename(package, destination)
    except Exception:
        slot.rmdir()
        raise
    return destination
