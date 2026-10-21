#!/usr/bin/env python3
"""Rename CP/M 8.3 filenames unsuitable for ProDOS using Zapple-II base-69.

By default, PREVIEW ONLY. Add --apply to rename files.

Examples:
    python3 hash_filenames.py /path/to/directory
    python3 hash_filenames.py /path/to/directory --apply
    python3 hash_filenames.py /path/to/directory --recursive --apply
    python3 hash_filenames.py /path/to/directory --decode    # preview reversal
    python3 hash_filenames.py /path/to/directory --decode --apply

Uses the exact encoding/alphabet of the Zapple-II base-69 prototype.
Accepts canonical uppercase CP/M 8.3 names, optionally spelled in lowercase
on the host (folded to uppercase like CP/M). Other filenames are NOT truncated
or changed: they are reported as unsupported, if not already ProDOS-safe.

Operates on regular files only; never follows symlinks or renames directories.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

# ASCII 32..96, 123..126, exactly matching Zapple-II's B69ENC routine.
ALPHABET69 = "".join(chr(n) for n in range(32, 127)
                     if not (97 <= n <= 122))
BASE36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CPM_FORBIDDEN = set('<>.,;:=?*[]')  # period is only the 8.3 separator
ALIAS = re.compile(r"Z\.[0-9A-Z]{13}\Z")
assert len(ALPHABET69) == 69
assert 69 ** 11 <= 36 ** 13


def fcb_from_name(name: str) -> str:
    """11 padded FCB bytes, after normal CP/M uppercase folding."""
    if not name.isascii():
        raise ValueError("non-ASCII name")
    name = name.upper()
    if name.count(".") > 1:
        raise ValueError("more than one period")
    stem, sep, ext = name.partition(".")
    if not 1 <= len(stem) <= 8 or len(ext) > 3:
        raise ValueError("not an 8.3 filename")
    if sep and not ext:
        raise ValueError("trailing period")
    if any(char not in ALPHABET69 or char in CPM_FORBIDDEN or char == ' '
           for char in stem + ext):
        raise ValueError("not a valid CP/M filename")
    return stem.ljust(8) + ext.ljust(3)


def name_from_fcb(fcb: str) -> str:
    stem = fcb[:8].rstrip(' ')
    ext = fcb[8:].rstrip(' ')
    return stem + ('.' + ext if ext else '')


def prodos_safe(fcb: str) -> bool:
    stem = fcb[:8].rstrip(' ')
    ext = fcb[8:].rstrip(' ')
    return (bool(stem) and 'A' <= stem[0] <= 'Z'
            and all(c in BASE36 for c in stem + ext)
            and fcb[:8] == stem.ljust(8)
            and fcb[8:] == ext.ljust(3))


def encode_fcb(fcb: str) -> str:
    """Exact Z.<13 base36> encoding from 11 uppercase printable FCB bytes."""
    n = 0
    for c in fcb:
        n = n * 69 + ALPHABET69.index(c)
    out = ['0'] * 13
    for i in range(12, -1, -1):
        n, digit = divmod(n, 36)
        out[i] = BASE36[digit]
    if n:
        raise ValueError("encoding overflow")
    return 'Z.' + ''.join(out)


def decode_alias(name: str) -> str | None:
    """Reverse only well-formed, canonical Zapple-II aliases."""
    if not ALIAS.fullmatch(name):
        return None
    n = 0
    for c in name[2:]:
        n = n * 36 + BASE36.index(c)
    if n >= 69 ** 11:
        return None
    chars = [' '] * 11
    for i in range(10, -1, -1):
        n, r = divmod(n, 69)
        chars[i] = ALPHABET69[r]
    fcb = ''.join(chars)
    display = name_from_fcb(fcb)
    try:
        if fcb_from_name(display) != fcb or prodos_safe(fcb):
            return None
    except ValueError:
        return None
    return display


def plan_one(name: str, decode: bool) -> tuple[str | None, str | None]:
    if decode:
        original = decode_alias(name)
        return (original, None) if original else (None, None)
    try:
        fcb = fcb_from_name(name)
    except ValueError as exc:
        # A normal native ProDOS name need not be a CP/M 8.3 name.
        if (1 <= len(name) <= 15 and 'A' <= name[:1].upper() <= 'Z'
                and all(c in BASE36 + '.' for c in name.upper())):
            return None, None
        return None, str(exc)
    if prodos_safe(fcb):
        return None, None
    alias = encode_fcb(fcb)
    assert decode_alias(alias) == name.upper()
    return alias, None


def process_directory(directory: Path, *, decode: bool, apply: bool) -> Counter:
    counts: Counter = Counter()
    try:
        entries = list(directory.iterdir())
    except OSError as exc:
        print(f"ERROR {directory}: {exc}", file=sys.stderr)
        counts['errors'] += 1
        return counts
    # ProDOS names are case insensitive; check ALL existing names as blockers.
    existing = {p.name.upper() for p in entries}
    proposed: dict[Path, str] = {}
    for entry in sorted(entries, key=lambda p: p.name.upper()):
        if entry.is_symlink() or not entry.is_file():
            continue
        dest, reason = plan_one(entry.name, decode)
        if reason:
            print(f"SKIP    {entry}: {reason}")
            counts['skipped'] += 1
        elif dest:
            proposed[entry] = dest
    target_count = Counter(s.upper() for s in proposed.values())
    for src, dst in proposed.items():
        if dst.upper() in existing or target_count[dst.upper()] > 1:
            print(f"CONFLICT {src.name} -> {dst}  (destination already in use)")
            counts['conflicts'] += 1
            continue
        if not apply:
            print(f"WOULD   {src.name} -> {dst}   [{directory}]")
            counts['planned'] += 1
            continue
        try:
            # The recheck is useful on local disks; don't run against a
            # directory concurrently modified by another process.
            if (directory / dst).exists():
                raise FileExistsError(dst)
            src.rename(directory / dst)
            print(f"RENAMED {src.name} -> {dst}   [{directory}]")
            counts['renamed'] += 1
        except OSError as exc:
            print(f"ERROR   {src}: {exc}", file=sys.stderr)
            counts['errors'] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('directory', type=Path, help='Directory to process')
    parser.add_argument('--apply', action='store_true',
                        help='Really rename; without this, preview only')
    parser.add_argument('--recursive', action='store_true',
                        help='Also process subdirectories (without renaming them)')
    parser.add_argument('--decode', action='store_true',
                        help='Reverse existing Z.<13> aliases to CP/M names')
    args = parser.parse_args()
    root = args.directory
    if not root.is_dir():
        parser.error(f'not a directory: {root}')
    import os
    stats: Counter = Counter()
    if args.recursive:
        for folder, dirs, _ in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(folder) / d).is_symlink()]
            stats.update(process_directory(Path(folder), decode=args.decode, apply=args.apply))
    else:
        stats.update(process_directory(root, decode=args.decode, apply=args.apply))
    print(f"\n{'Applied' if args.apply else 'Preview'}: "
          f"{stats['renamed']} renamed, {stats['planned']} proposed, "
          f"{stats['conflicts']} conflicts, {stats['skipped']} unsupported, "
          f"{stats['errors']} errors")
    if not args.apply:
        print('No files changed. Add --apply to rename them.')
    return 1 if stats['errors'] or stats['conflicts'] else 0


if __name__ == '__main__':
    sys.exit(main())
