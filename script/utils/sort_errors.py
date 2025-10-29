#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


def _error_sort_key(error_line: str) -> str:
    signature = error_line.strip()[len("error ") :]
    name = signature.split("(", 1)[0].strip()
    return name


def _extract_entries(block_text: str) -> List[Tuple[int, int, str, int]]:
    entries: List[Tuple[int, int, str, int]] = []
    offset = 0
    entry_start: Optional[int] = None
    last_content_end: Optional[int] = None
    current_error: Optional[str] = None

    def finalize() -> None:
        nonlocal entry_start, last_content_end, current_error
        if entry_start is None or last_content_end is None or current_error is None:
            return
        entries.append((entry_start, last_content_end, _error_sort_key(current_error), len(entries)))
        entry_start = None
        last_content_end = None
        current_error = None

    while offset < len(block_text):
        newline_idx = block_text.find("\n", offset)
        if newline_idx == -1:
            line_end = len(block_text)
        else:
            line_end = newline_idx + 1
        line = block_text[offset:line_end]
        stripped = line.strip()

        if stripped == "":
            if entry_start is not None:
                last_content_end = line_end
            offset = line_end
            continue

        if stripped.startswith("/**") or stripped.startswith("///"):
            if current_error is not None:
                finalize()
            if entry_start is None:
                entry_start = offset
            last_content_end = line_end
            offset = line_end
            continue

        if stripped.startswith("*") or stripped.startswith("*/"):
            if entry_start is not None:
                last_content_end = line_end
            offset = line_end
            continue

        if stripped.startswith("error ") and stripped.endswith(";"):
            if current_error is not None:
                finalize()
            if entry_start is None:
                entry_start = offset
            current_error = line.strip()
            last_content_end = line_end
            offset = line_end
            continue

        if stripped.startswith("//"):
            if entry_start is None:
                entry_start = offset
            last_content_end = line_end
            offset = line_end
            continue

        finalize()
        break

    finalize()
    return entries


def _sort_error_block(text: str) -> Tuple[str, bool]:
    marker = "/* ERRORS */"
    search_pos = 0
    changed = False

    while True:
        marker_idx = text.find(marker, search_pos)
        if marker_idx == -1:
            break

        block_start = text.find("\n", marker_idx)
        if block_start == -1:
            break
        block_start += 1

        cursor = block_start
        first_block_idx: Optional[int] = None
        last_block_idx = block_start

        while cursor < len(text):
            newline_idx = text.find("\n", cursor)
            if newline_idx == -1:
                line_end = len(text)
            else:
                line_end = newline_idx + 1
            line = text[cursor:line_end]
            stripped = line.strip()

            if first_block_idx is None and stripped == "":
                cursor = line_end
                continue

            if (
                stripped == ""
                or (stripped.startswith("error ") and stripped.endswith(";"))
                or stripped.startswith("//")
                or stripped.startswith("///")
                or stripped.startswith("/*")
                or stripped.startswith("*")
                or stripped.startswith("*/")
            ):
                if first_block_idx is None:
                    first_block_idx = cursor
                last_block_idx = line_end
                cursor = line_end
                continue

            break

        if first_block_idx is None:
            search_pos = cursor
            continue

        block_text = text[first_block_idx:last_block_idx]
        entries = _extract_entries(block_text)
        if len(entries) <= 1:
            search_pos = last_block_idx
            continue

        prefix = block_text[:entries[0][0]]
        suffix = block_text[entries[-1][1]:]
        sorted_entries = sorted(entries, key=lambda item: (item[2], item[3]))
        sorted_chunks = [block_text[start:end].rstrip("\n") for start, end, _, _ in sorted_entries]

        new_block = prefix + "\n\n".join(sorted_chunks)

        stripped_suffix = suffix.lstrip("\n")
        if stripped_suffix:
            new_block += "\n\n" + stripped_suffix
        else:
            new_block += suffix

        if block_text != new_block:
            text = text[:first_block_idx] + new_block + text[last_block_idx:]
            changed = True
            search_pos = first_block_idx + len(new_block)
        else:
            search_pos = last_block_idx

    return text, changed


def sort_errors_in_file(path: Path):
    original = path.read_text(encoding="utf-8")
    updated, changed = _sort_error_block(original)
    if changed:
        path.write_text(updated, encoding="utf-8")


def iter_solidity_files(targets: Iterable[Path]) -> Iterable[Path]:
    for target in targets:
        if target.is_dir():
            yield from target.rglob("*.sol")
            continue
        if target.is_file() and target.suffix == ".sol":
            yield target


def resolve_targets(path_args: Iterable[str]) -> List[Path]:
    if path_args:
        return [Path(arg) for arg in path_args]

    defaults = [Path(name) for name in ("src", "examples") if Path(name).exists()]
    return defaults or [Path("src")]


def sort_from_stdin() -> None:
    errors = sys.stdin.read()
    sorted_errors = sorted(x.strip() for x in errors.splitlines())
    print("\n".join(line for line in sorted_errors if line))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sort error declarations within Solidity files."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Solidity files or directories to process.",
    )
    parser.add_argument(
        "--stdin",
        action="store_true",
        help="Read errors from stdin and output the sorted list (legacy helper).",
    )
    args = parser.parse_args()

    if args.stdin:
        sort_from_stdin()
        return 0

    targets = resolve_targets(args.paths)

    for file_path in iter_solidity_files(targets):
        sort_errors_in_file(file_path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
