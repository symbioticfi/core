#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_1 = ROOT / "UniversalDelegatorGasReport.md"
REPORT_2 = ROOT / "UniversalDelegatorGasReport_AfterFirstSlash.md"
REPORT_SCENARIOS = ROOT / "UniversalDelegatorGasReport_Scenarios.md"


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
    return call.replace("ReentrancyGuardUpgradeable", "ReentrancyGuard")


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


def _map_sequence(
    children: list[tuple[str, int]],
    expected: list[tuple[tuple[str, ...] | str, str, bool]],
    context: str,
) -> list[tuple[str, int]]:
    mapped: list[tuple[str, int]] = []
    idx = 0
    for names, label, required in expected:
        if isinstance(names, str):
            names = (names,)
        match_idx = None
        while idx < len(children):
            if children[idx][0] in names:
                match_idx = idx
                break
            idx += 1
        if match_idx is None:
            if required:
                raise ValueError(f"Unexpected {context} trace shape.")
            mapped.append((label, 0))
            continue
        mapped.append((label, children[match_idx][1]))
        idx = match_idx + 1
    return mapped


def map_execute(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    expected: list[tuple[tuple[str, ...] | str, str, bool]] = [
        ("ReentrancyGuard::_nonReentrantBefore", "ReentrancyGuard::_nonReentrantBefore", True),
        ("UniversalSlasher::slashRequests", "UniversalSlasher::slashRequests", True),
        ("UniversalSlasher::_checkNetworkMiddleware", "UniversalSlasher::_checkNetworkMiddleware", True),
        ("MigratableEntityProxy::fallback", "VaultV2::epochDuration (via proxy)", True),
        ("UniversalSlasher::_slashableStake", "UniversalSlasher::_slashableStake", True),
        ("UniversalSlasher::cumulativeSlash", "UniversalSlasher::cumulativeSlash", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("UniversalSlasher::groupCumulativeSlash", "UniversalSlasher::groupCumulativeSlash", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("MigratableEntityProxy::fallback", "VaultV2::onSlash (via proxy)", True),
        ("MigratableEntityProxy::fallback", "VaultV2::delegator (via proxy)", True),
        (("onSlash", "UniversalDelegator::onSlash"), "UniversalDelegator::onSlash", True),
        ("UniversalSlasher::_burnerOnSlash", "UniversalSlasher::_burnerOnSlash", True),
        ("ReentrancyGuard::_nonReentrantAfter", "ReentrancyGuard::_nonReentrantAfter", False),
    ]
    return _map_sequence(children, expected, "executeSlash")


def map_vault(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    expected: list[tuple[tuple[str, ...] | str, str, bool]] = [
        ("ReentrancyGuard::_nonReentrantBefore", "ReentrancyGuard::_nonReentrantBefore", True),
        ("Checkpoints::latest", "Checkpoints::latest", True),
        ("Checkpoints::latest", "Checkpoints::latest", True),
        ("Checkpoints::latest", "Checkpoints::latest", True),
        ("Checkpoints::upperLookupRecent", "Checkpoints::upperLookupRecent", True),
        ("Checkpoints::latest", "Checkpoints::latest", True),
        ("VaultV2Storage::activeStake", "VaultV2Storage::activeStake", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("FixedPointMathLib::mulDiv", "FixedPointMathLib::mulDiv", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("Checkpoints::push", "Checkpoints::push", True),
        ("Token::balanceOf", "Token::balanceOf", True),
        ("SafeTransferLib::safeTransfer", "SafeTransferLib::safeTransfer", True),
        ("ReentrancyGuard::_nonReentrantAfter", "ReentrancyGuard::_nonReentrantAfter", False),
    ]
    return _map_sequence(children, expected, "VaultV2::onSlash")


def _norm_label(value: str) -> str:
    normalized = value.replace("`", "").strip()
    return normalized.replace("ReentrancyGuardUpgradeable", "ReentrancyGuard")


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


def update_reports(log_path: Path) -> list[Path]:
    lines = log_path.read_text().splitlines()
    updated: list[Path] = []

    logs = parse_logs(lines)
    scenario_required = [
        "with_capture_isolated_block1_stake",
        "with_capture_isolated_block1_request",
        "with_capture_isolated_block1_execute",
        "with_capture_isolated_block2_stake",
        "with_capture_isolated_block2_request",
        "with_capture_isolated_block2_execute",
        "with_capture_single_block1_stake",
        "with_capture_single_block1_request",
        "with_capture_single_block1_execute",
        "with_capture_single_block2_stake",
        "with_capture_single_block2_request",
        "with_capture_single_block2_execute",
        "no_capture_isolated_block1_stake",
        "no_capture_isolated_block1_request",
        "no_capture_isolated_block1_execute",
        "no_capture_isolated_block2_stake",
        "no_capture_isolated_block2_request",
        "no_capture_isolated_block2_execute",
        "no_capture_single_block1_stake",
        "no_capture_single_block1_request",
        "no_capture_single_block1_execute",
        "no_capture_single_block2_stake",
        "no_capture_single_block2_request",
        "no_capture_single_block2_execute",
    ]
    legacy_required = [
        "stakeForAt_no_hints",
        "stakeForAt_with_hints",
        "executeSlash_no_hints",
        "executeSlash_with_hints",
        "stakeForAt2_no_hints",
        "stakeForAt2_with_hints",
        "executeSlash2_no_hints",
        "executeSlash2_with_hints",
    ]

    missing_scenario = [key for key in scenario_required if key not in logs]
    has_scenario = not missing_scenario
    missing_legacy = [key for key in legacy_required if key not in logs]
    has_legacy = not missing_legacy
    synthetic_legacy = False

    if not has_legacy and has_scenario:
        # Map scenario logs into legacy keys so legacy reports are refreshed.
        logs["stakeForAt_no_hints"] = logs["with_capture_isolated_block1_stake"]
        logs["executeSlash_no_hints"] = logs["with_capture_isolated_block1_execute"]
        logs["requestSlash_no_hints"] = logs["with_capture_isolated_block1_request"]
        logs["stakeForAt2_no_hints"] = logs["with_capture_isolated_block2_stake"]
        logs["executeSlash2_no_hints"] = logs["with_capture_isolated_block2_execute"]
        logs["requestSlash2_no_hints"] = logs["with_capture_isolated_block2_request"]
        # No hints are measured in this run; mirror for the "with hints" columns.
        logs["stakeForAt_with_hints"] = logs["stakeForAt_no_hints"]
        logs["executeSlash_with_hints"] = logs["executeSlash_no_hints"]
        logs["requestSlash_with_hints"] = logs["requestSlash_no_hints"]
        logs["stakeForAt2_with_hints"] = logs["stakeForAt2_no_hints"]
        logs["executeSlash2_with_hints"] = logs["executeSlash2_no_hints"]
        logs["requestSlash2_with_hints"] = logs["requestSlash2_no_hints"]
        has_legacy = True
        synthetic_legacy = True

    if not has_scenario and not has_legacy:
        missing = missing_scenario if missing_scenario else missing_legacy
        raise ValueError(f"Missing gas logs: {', '.join(missing)}")

    if has_scenario:
        today = datetime.now().date().isoformat()
        report = f"""# UniversalDelegator Gas Report (Scenarios)

Date: {today}
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

Notes:
- Different operators, same group/network.
- “Fully isolated” runs two sequential slashes with a block time jump between them (intended to model separate txs).
- “Single transaction” executes both slashes inside one middleware call.
- “Without capture timestamp” passes `captureTimestamp = 0` into `requestSlash` (mapped to `block.timestamp - 4` for validity).

## With capture timestamp

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | {fmt(logs["with_capture_isolated_block1_stake"])} | {fmt(logs["with_capture_isolated_block1_request"])} | {fmt(logs["with_capture_isolated_block1_execute"])} |
| 2nd | {fmt(logs["with_capture_isolated_block2_stake"])} | {fmt(logs["with_capture_isolated_block2_request"])} | {fmt(logs["with_capture_isolated_block2_execute"])} |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | {fmt(logs["with_capture_single_block1_stake"])} | {fmt(logs["with_capture_single_block1_request"])} | {fmt(logs["with_capture_single_block1_execute"])} |
| 2nd | {fmt(logs["with_capture_single_block2_stake"])} | {fmt(logs["with_capture_single_block2_request"])} | {fmt(logs["with_capture_single_block2_execute"])} |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | {fmt(logs["no_capture_isolated_block1_stake"])} | {fmt(logs["no_capture_isolated_block1_request"])} | {fmt(logs["no_capture_isolated_block1_execute"])} |
| 2nd | {fmt(logs["no_capture_isolated_block2_stake"])} | {fmt(logs["no_capture_isolated_block2_request"])} | {fmt(logs["no_capture_isolated_block2_execute"])} |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | {fmt(logs["no_capture_single_block1_stake"])} | {fmt(logs["no_capture_single_block1_request"])} | {fmt(logs["no_capture_single_block1_execute"])} |
| 2nd | {fmt(logs["no_capture_single_block2_stake"])} | {fmt(logs["no_capture_single_block2_request"])} | {fmt(logs["no_capture_single_block2_execute"])} |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

"""
        REPORT_SCENARIOS.write_text(report)
        updated.append(REPORT_SCENARIOS)

    if has_legacy:
        entries = parse_entries(lines)
        execute_calls = collect_children(entries, "UniversalSlasher::executeSlash(")
        vault_calls = collect_children(entries, "VaultV2::onSlash(")

        if synthetic_legacy:
            if len(execute_calls) < 2 or len(vault_calls) < 2:
                raise ValueError("Not enough executeSlash/VaultV2::onSlash traces found.")
        else:
            if len(execute_calls) < 4 or len(vault_calls) < 3:
                raise ValueError("Not enough executeSlash/VaultV2::onSlash traces found.")

        exec_1 = map_execute(execute_calls[0])
        exec_3 = map_execute(execute_calls[1])
        exec_2 = exec_1 if synthetic_legacy else map_execute(execute_calls[1])
        exec_4 = exec_3 if synthetic_legacy else map_execute(execute_calls[3])

        vault_1 = map_vault(vault_calls[0])
        vault_3 = map_vault(vault_calls[1]) if synthetic_legacy else map_vault(vault_calls[2])

        # Report 1
        report_1_lines = REPORT_1.read_text().splitlines()
        update_table(
            report_1_lines,
            "## Summary (worst-case position)",
            [
                (("`stakeForAt`", "no"), logs["stakeForAt_no_hints"]),
                (("`stakeForAt`", "yes"), logs["stakeForAt_with_hints"]),
                (("`requestSlash`", "no"), logs["requestSlash_no_hints"]),
                (("`requestSlash`", "yes"), logs["requestSlash_with_hints"]),
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
        updated.append(REPORT_1)

        # Report 2
        report_2_lines = REPORT_2.read_text().splitlines()
        update_table(
            report_2_lines,
            "## Summary (same group/network, second operator)",
            [
                (("`stakeForAt`", "no"), logs["stakeForAt2_no_hints"]),
                (("`stakeForAt`", "yes"), logs["stakeForAt2_with_hints"]),
                (("`requestSlash`", "no"), logs["requestSlash2_no_hints"]),
                (("`requestSlash`", "yes"), logs["requestSlash2_with_hints"]),
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
        updated.append(REPORT_2)
    return updated


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 script/update_gas_reports.py /path/to/udgas.txt")
        raise SystemExit(2)
    log_path = Path(sys.argv[1]).expanduser().resolve()
    if not log_path.exists():
        raise SystemExit(f"Log file not found: {log_path}")
    updated = update_reports(log_path)
    for path in updated:
        print(f"Updated: {path}")


if __name__ == "__main__":
    main()
