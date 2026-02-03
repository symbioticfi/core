#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_1 = ROOT / "UniversalDelegatorGasReport.md"
REPORT_2 = ROOT / "UniversalDelegatorGasReport_AfterFirstSlash.md"


def fmt(value: int) -> str:
    return f"{value:,}"


def parse_logs(lines: list[str]) -> dict[str, int]:
    log_pattern = re.compile(r'console::log\("([^"]+)",\s*(\d+)')
    logs: dict[str, int] = {}
    for line in lines:
        match = log_pattern.search(line)
        if match:
            logs[match.group(1)] = int(match.group(2))
    return logs


def parse_entries(lines: list[str]) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for line in lines:
        if "├─" not in line and "└─" not in line:
            continue
        idx = line.find("├─")
        if idx == -1:
            idx = line.find("└─")
        prefix = line[:idx]
        depth = len(prefix) // 4
        gas_match = re.search(r"\[(\d+)\]", line[idx:])
        if not gas_match:
            continue
        gas = int(gas_match.group(1))
        after = line[idx:]
        pos = after.find("] ")
        if pos == -1:
            continue
        call = after[pos + 2 :]
        call = re.sub(r"\s*\[(?:delegatecall|staticcall|call)\]$", "", call)
        entries.append({"depth": depth, "gas": gas, "call": call})
    return entries


def norm(call: str) -> str:
    if "::" in call:
        prefix, rest = call.split("::", 1)
        if prefix.startswith("0x"):
            call = rest
        else:
            call = f"{prefix}::{rest}"
    if "(" in call:
        call = call.split("(", 1)[0]
    return call


def collect_children(entries: list[dict[str, object]], prefix: str) -> list[list[tuple[str, int]]]:
    calls: list[list[tuple[str, int]]] = []
    for i, entry in enumerate(entries):
        call = entry["call"]
        if isinstance(call, str) and call.startswith(prefix):
            depth = entry["depth"]
            children: list[tuple[str, int]] = []
            j = i + 1
            while j < len(entries):
                if entries[j]["depth"] <= depth:
                    break
                if entries[j]["depth"] == depth + 1:
                    children.append((norm(entries[j]["call"]), int(entries[j]["gas"])))
                j += 1
            calls.append(children)
    return calls


def map_execute(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    expected = [
        ("ReentrancyGuardUpgradeable::_nonReentrantBefore", "ReentrancyGuardUpgradeable::_nonReentrantBefore"),
        ("UniversalSlasher::slashRequests", "UniversalSlasher::slashRequests"),
        ("UniversalSlasher::_checkNetworkMiddleware", "UniversalSlasher::_checkNetworkMiddleware"),
        ("MigratableEntityProxy::fallback", "VaultV2::epochDuration (via proxy)"),
        ("UniversalSlasher::_slashableStake", "UniversalSlasher::_slashableStake"),
        ("UniversalSlasher::cumulativeSlash", "UniversalSlasher::cumulativeSlash"),
        ("Checkpoints::push", "Checkpoints::push"),
        ("UniversalSlasher::groupCumulativeSlash", "UniversalSlasher::groupCumulativeSlash"),
        ("Checkpoints::push", "Checkpoints::push"),
        ("MigratableEntityProxy::fallback", "VaultV2::onSlash (via proxy)"),
        ("MigratableEntityProxy::fallback", "VaultV2::delegator (via proxy)"),
        ("onSlash", "UniversalDelegator::onSlash"),
        ("UniversalSlasher::_burnerOnSlash", "UniversalSlasher::_burnerOnSlash"),
        ("ReentrancyGuardUpgradeable::_nonReentrantAfter", "ReentrancyGuardUpgradeable::_nonReentrantAfter"),
    ]
    if len(children) < len(expected):
        raise ValueError("Unexpected executeSlash trace shape.")
    mapped: list[tuple[str, int]] = []
    for (expected_name, label), (actual_name, gas) in zip(expected, children):
        if actual_name != expected_name:
            raise ValueError(f"executeSlash child mismatch: expected {expected_name}, got {actual_name}")
        mapped.append((label, gas))
    return mapped


def map_vault(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    expected = [
        "ReentrancyGuardUpgradeable::_nonReentrantBefore",
        "Checkpoints::latest",
        "Checkpoints::latest",
        "Checkpoints::latest",
        "Checkpoints::upperLookupRecent",
        "Checkpoints::latest",
        "VaultV2Storage::activeStake",
        "Checkpoints::push",
        "Checkpoints::push",
        "Checkpoints::push",
        "Checkpoints::push",
        "FixedPointMathLib::mulDiv",
        "Checkpoints::push",
        "Checkpoints::push",
        "Token::balanceOf",
        "SafeTransferLib::safeTransfer",
        "ReentrancyGuardUpgradeable::_nonReentrantAfter",
    ]
    if len(children) < len(expected):
        raise ValueError("Unexpected VaultV2::onSlash trace shape.")
    mapped: list[tuple[str, int]] = []
    for expected_name, (actual_name, gas) in zip(expected, children):
        if actual_name != expected_name:
            raise ValueError(f"VaultV2::onSlash child mismatch: expected {expected_name}, got {actual_name}")
        mapped.append((actual_name, gas))
    return mapped


def _norm_label(value: str) -> str:
    return value.replace("`", "").strip()


def update_table(lines: list[str], heading: str, rows: list[tuple[tuple[str, ...], int]], gas_col: int) -> None:
    heading_idx = None
    for i, line in enumerate(lines):
        if line.strip() == heading:
            heading_idx = i
            break
    if heading_idx is None:
        raise ValueError(f"Heading not found: {heading}")

    idx = heading_idx + 1
    table_start = None
    while idx < len(lines):
        if lines[idx].lstrip().startswith("|"):
            if idx + 1 < len(lines) and lines[idx + 1].lstrip().startswith("|"):
                table_start = idx
                break
        idx += 1
    if table_start is None:
        raise ValueError(f"Table header not found after heading: {heading}")
    idx = table_start + 2  # skip header + separator

    for expected_cols, gas in rows:
        while idx < len(lines) and not lines[idx].lstrip().startswith("|"):
            idx += 1
        if idx >= len(lines):
            raise ValueError(f"Ran out of table rows under heading: {heading}")
        parts = [p.strip() for p in lines[idx].split("|")[1:-1]]
        normalized_parts = [_norm_label(item) for item in parts[: len(expected_cols)]]
        normalized_expected = [_norm_label(item) for item in expected_cols]
        if normalized_parts != normalized_expected:
            raise ValueError(
                f"Row mismatch under {heading}: expected {expected_cols}, got {parts[:len(expected_cols)]}"
            )
        parts[gas_col] = fmt(gas)
        lines[idx] = f"| {parts[0]} | {parts[1]} | {parts[2]} |" if len(parts) == 3 else f"| {parts[0]} | {parts[1]} |"
        idx += 1


def update_reports(log_path: Path) -> None:
    lines = log_path.read_text().splitlines()

    logs = parse_logs(lines)
    required = [
        "stakeForAt_no_hints",
        "stakeForAt_with_hints",
        "executeSlash_no_hints",
        "executeSlash_with_hints",
        "stakeForAt2_no_hints",
        "stakeForAt2_with_hints",
        "executeSlash2_no_hints",
        "executeSlash2_with_hints",
    ]
    missing = [key for key in required if key not in logs]
    if missing:
        raise ValueError(f"Missing gas logs: {', '.join(missing)}")

    entries = parse_entries(lines)
    execute_calls = collect_children(entries, "UniversalSlasher::executeSlash(")
    vault_calls = collect_children(entries, "VaultV2::onSlash(")

    if len(execute_calls) < 4 or len(vault_calls) < 4:
        raise ValueError("Not enough executeSlash/VaultV2::onSlash traces found.")

    exec_1 = map_execute(execute_calls[0])
    exec_2 = map_execute(execute_calls[1])
    exec_3 = map_execute(execute_calls[2])
    exec_4 = map_execute(execute_calls[3])

    vault_1 = map_vault(vault_calls[0])
    vault_3 = map_vault(vault_calls[2])

    # Report 1
    report_1_lines = REPORT_1.read_text().splitlines()
    update_table(
        report_1_lines,
        "## Summary (worst-case position)",
        [
            (("`stakeForAt`", "no"), logs["stakeForAt_no_hints"]),
            (("`stakeForAt`", "yes"), logs["stakeForAt_with_hints"]),
            (("`executeSlash`", "no"), logs["executeSlash_no_hints"]),
            (("`executeSlash`", "yes"), logs["executeSlash_with_hints"]),
        ],
        2,
    )
    update_table(
        report_1_lines,
        "## executeSlash components (no hints)",
        [((label,), gas) for label, gas in exec_1],
        1,
    )
    update_table(
        report_1_lines,
        "## executeSlash components (with hints)",
        [((label,), gas) for label, gas in exec_2],
        1,
    )
    update_table(
        report_1_lines,
        "## VaultV2::onSlash breakdown",
        [((label,), gas) for label, gas in vault_1],
        1,
    )
    update_table(
        report_1_lines,
        "## Delta (with hints vs no hints)",
        [
            (("`UniversalSlasher::_slashableStake`",), exec_2[4][1] - exec_1[4][1]),
            (("Total `executeSlash`",), logs["executeSlash_with_hints"] - logs["executeSlash_no_hints"]),
        ],
        1,
    )
    REPORT_1.write_text("\n".join(report_1_lines) + "\n")

    # Report 2
    report_2_lines = REPORT_2.read_text().splitlines()
    update_table(
        report_2_lines,
        "## Summary (same group/network, second operator)",
        [
            (("`stakeForAt`", "no"), logs["stakeForAt2_no_hints"]),
            (("`stakeForAt`", "yes"), logs["stakeForAt2_with_hints"]),
            (("`executeSlash`", "no"), logs["executeSlash2_no_hints"]),
            (("`executeSlash`", "yes"), logs["executeSlash2_with_hints"]),
        ],
        2,
    )
    update_table(
        report_2_lines,
        "## executeSlash components (no hints)",
        [((label,), gas) for label, gas in exec_3],
        1,
    )
    update_table(
        report_2_lines,
        "## executeSlash components (with hints)",
        [((label,), gas) for label, gas in exec_4],
        1,
    )
    update_table(
        report_2_lines,
        "## VaultV2::onSlash breakdown (after first slash)",
        [((label,), gas) for label, gas in vault_3],
        1,
    )
    update_table(
        report_2_lines,
        "## Delta (with hints vs no hints)",
        [
            (("`UniversalSlasher::_slashableStake`",), exec_4[4][1] - exec_3[4][1]),
            (("Total `executeSlash`",), logs["executeSlash2_with_hints"] - logs["executeSlash2_no_hints"]),
        ],
        1,
    )
    REPORT_2.write_text("\n".join(report_2_lines) + "\n")


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 script/update_gas_reports.py /path/to/udgas.txt")
        raise SystemExit(2)
    log_path = Path(sys.argv[1]).expanduser().resolve()
    if not log_path.exists():
        raise SystemExit(f"Log file not found: {log_path}")
    update_reports(log_path)
    print(f"Updated: {REPORT_1}")
    print(f"Updated: {REPORT_2}")


if __name__ == "__main__":
    main()
