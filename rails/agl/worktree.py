"""Shared, provider-independent hashing of Git candidate state."""

from __future__ import annotations

import hashlib
import os
import subprocess
from pathlib import Path, PurePosixPath
from typing import Iterable


class WorktreeHashError(ValueError):
    """The candidate worktree could not be hashed without crossing its boundary."""


def update_hash_frame(digest: object, parts: Iterable[bytes]) -> None:
    """Append unambiguous length-prefixed byte strings to a hash object."""

    for part in parts:
        if not isinstance(part, bytes):
            raise TypeError("hash frames accept bytes only")
        digest.update(len(part).to_bytes(8, "big"))
        digest.update(part)


def symlink_target_bytes(path: str | Path) -> bytes:
    """Return link text bytes without opening or following the target."""

    candidate = Path(path)
    try:
        target = os.readlink(os.fsencode(candidate))
    except (TypeError, ValueError):
        target = os.readlink(candidate)
    return target if isinstance(target, bytes) else os.fsencode(target)


def _within(root: Path, resolved: Path) -> bool:
    try:
        resolved.relative_to(root)
        return True
    except ValueError:
        return False


def safe_workspace_path(
    root: str | Path,
    relative_parts: Iterable[str],
    *,
    allow_final_symlink: bool,
) -> Path:
    """Resolve a lexical child without following a symlinked parent.

    A final symlink may be returned when explicitly allowed; callers may read
    its link text but must not open it. Every ordinary existing component must
    resolve inside the workspace.
    """

    workspace = Path(root).resolve(strict=True)
    parts = tuple(relative_parts)
    if not parts:
        raise WorktreeHashError("workspace-relative path is empty")
    cursor = workspace
    for index, part in enumerate(parts):
        if not part or part in {".", ".."} or os.sep in part or (os.altsep and os.altsep in part):
            raise WorktreeHashError("workspace-relative path contains an unsafe component")
        cursor = cursor / part
        final = index == len(parts) - 1
        if cursor.is_symlink():
            if not final or not allow_final_symlink:
                raise WorktreeHashError(
                    "candidate path crosses a symlinked parent component"
                )
            parent = cursor.parent.resolve(strict=True)
            if not _within(workspace, parent):
                raise WorktreeHashError("candidate symlink parent escapes the workspace")
            return cursor
        if os.path.lexists(cursor):
            resolved = cursor.resolve(strict=True)
            if not _within(workspace, resolved):
                raise WorktreeHashError("candidate path resolves outside the workspace")
        elif not final:
            # A missing non-final component cannot hide a symlink below it;
            # return the lexical path and let the caller report it as missing.
            return workspace.joinpath(*parts)
    return cursor


def _git(root: Path, *args: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=30,
    )
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", "replace").strip()
        raise WorktreeHashError(f"git {' '.join(args)} failed: {message}")
    return completed.stdout


def _untracked_entries(root: Path) -> list[tuple[bytes, bytes, bytes]]:
    exclude = ":(exclude)rails"
    raw = _git(
        root,
        "ls-files",
        "-z",
        "--others",
        "--exclude-standard",
        "--",
        ".",
        exclude,
    )
    entries: list[tuple[bytes, bytes, bytes]] = []
    for relative_bytes in sorted(part for part in raw.split(b"\0") if part):
        relative_text = os.fsdecode(relative_bytes)
        relative = PurePosixPath(relative_text)
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise WorktreeHashError("git returned an unsafe untracked path")
        candidate = safe_workspace_path(
            root,
            relative.parts,
            allow_final_symlink=True,
        )
        if candidate.is_symlink():
            kind = b"symlink"
            data = symlink_target_bytes(candidate)
        elif candidate.is_file():
            kind = b"file"
            data = candidate.read_bytes()
        else:
            raise WorktreeHashError(
                f"untracked path is neither a file nor a symlink: {relative_text}"
            )
        entries.append((relative_bytes, kind, data))
    return entries


def tree_hash(root: str | Path) -> str:
    """Hash HEAD, diffs, and untracked file/link bytes with one shared codec."""

    start = Path(root).resolve(strict=True)
    top_level = _git(start, "rev-parse", "--show-toplevel").rstrip(b"\r\n")
    workspace = Path(os.fsdecode(top_level)).resolve(strict=True)
    exclude = ":(exclude)rails"
    digest = hashlib.sha256()
    update_hash_frame(digest, (b"AGL-WORKTREE-v2",))
    for label, payload in (
        (b"head", _git(workspace, "rev-parse", "HEAD")),
        (b"unstaged", _git(workspace, "diff", "--", ".", exclude)),
        (b"staged", _git(workspace, "diff", "--cached", "--", ".", exclude)),
    ):
        update_hash_frame(digest, (label, payload))
    for relative, kind, data in _untracked_entries(workspace):
        update_hash_frame(digest, (b"untracked", relative, kind, data))
    return digest.hexdigest()
