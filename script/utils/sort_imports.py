#!/usr/bin/env python3

import argparse
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence


FROM_IMPORT_RE = re.compile(r'from\s+["\']([^"\']+)["\']', re.IGNORECASE | re.MULTILINE)
DIRECT_IMPORT_RE = re.compile(r'import\s+["\']([^"\']+)["\']', re.IGNORECASE | re.MULTILINE)
WHITESPACE_RE = re.compile(r"\s+")


@dataclass
class ImportEntry:
    start: int
    end: int
    text: str
    path: str
    order: int


def extract_path(import_text: str) -> str:
    match = FROM_IMPORT_RE.search(import_text)
    if match:
        return match.group(1)

    match = DIRECT_IMPORT_RE.search(import_text)
    if match:
        return match.group(1)

    raise ValueError(f"Unable to parse import path from: {import_text}")


def collect_import_entries(lines: Sequence[str]) -> List[ImportEntry]:
    entries: List[ImportEntry] = []
    index = 0

    while index < len(lines):
        stripped = lines[index].lstrip()
        if not stripped.startswith("import "):
            index += 1
            continue

        start = index
        statement_lines = [lines[index].rstrip()]

        while ";" not in lines[index]:
            index += 1
            if index >= len(lines):
                break
            statement_lines.append(lines[index].rstrip())

        end = index
        text = "\n".join(statement_lines)
        path = extract_path(text)
        entries.append(ImportEntry(start=start, end=end, text=text, path=path, order=len(entries)))
        index += 1

    return entries


def normalize_import_text(import_text: str) -> str:
    """Flatten whitespace so multi-line imports sort identically to single-line ones."""
    compact = WHITESPACE_RE.sub(" ", import_text.strip())
    compact = compact.replace("{ ", "{").replace(" }", "}")
    compact = compact.replace("( ", "(").replace(" )", ")")
    return compact


def classify_import(path: str) -> str:
    normalized = path.lstrip("./")
    lower = normalized.lower()

    if path.startswith(".") or path.startswith("src") or path.startswith("examples"):
        if "interfac" in lower:
            return "own_interface"
        if "librar" in lower or "logic" in lower:
            return "own_library"
        return "own_contract"

    library = normalized.split("/", 1)[0]
    return f"external:{library}"


def build_sorted_block(entries: Sequence[ImportEntry]) -> List[str]:
    grouped: Dict[str, List[ImportEntry]] = defaultdict(list)
    for entry in entries:
        grouped[classify_import(entry.path)].append(entry)

    ordered_groups: List[List[ImportEntry]] = []

    for key in ("own_contract", "own_library", "own_interface"):
        if key in grouped:
            ordered_groups.append(
                sorted(grouped[key], key=lambda item: (normalize_import_text(item.text), item.order))
            )

    external_groups = sorted(
        (key, value) for key, value in grouped.items() if key.startswith("external:")
    )
    for _, group in external_groups:
        ordered_groups.append(
            sorted(group, key=lambda item: (normalize_import_text(item.text), item.order))
        )

    if not ordered_groups:
        return [entry.text for entry in entries]

    block_text = "\n\n".join("\n".join(entry.text for entry in group) for group in ordered_groups)
    return block_text.split("\n")


def sort_imports_in_file(path: Path) -> None:
    original_text = path.read_text(encoding="utf-8")
    has_trailing_newline = original_text.endswith("\n")
    lines = original_text.splitlines()

    entries = collect_import_entries(lines)
    if not entries:
        return

    block_start = entries[0].start
    block_end = entries[-1].end
    covered_indexes = set()
    for entry in entries:
        covered_indexes.update(range(entry.start, entry.end + 1))

    for idx in range(block_start, block_end + 1):
        if idx not in covered_indexes and lines[idx].strip() != "":
            return

    new_block_lines = build_sorted_block(entries)
    new_lines = lines[:block_start] + new_block_lines + lines[block_end + 1 :]
    new_text = "\n".join(new_lines)

    if has_trailing_newline:
        new_text += "\n"

    if new_text != original_text:
        path.write_text(new_text, encoding="utf-8")


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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Normalize and sort Solidity imports following project conventions."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Solidity files or directories to process.",
    )
    args = parser.parse_args()

    targets = resolve_targets(args.paths)

    for file_path in iter_solidity_files(targets):
        sort_imports_in_file(file_path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
