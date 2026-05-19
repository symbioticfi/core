#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Callable
from urllib.parse import urlencode
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
REPORT_1 = ROOT / "UniversalDelegatorGasReport.md"
REPORT_2 = ROOT / "UniversalDelegatorGasReport_AfterFirstSlash.md"
REPORT_SCENARIOS = ROOT / "UniversalDelegatorGasReport_Scenarios.md"


def fmt_usd(value: float) -> str:
    return f"${value:,.2f}"


def fmt_gas_with_usd(value: int, usd_per_gas_90d: float) -> str:
    sign = "-" if value < 0 else ""
    abs_value = abs(value)
    usd_90d = abs_value * usd_per_gas_90d
    return f"{sign}{abs_value:,} ({sign}{fmt_usd(usd_90d)})"


def _fetch_json(url: str) -> dict[str, object]:
    with urlopen(url, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


ETHERSCAN_BASE = "https://api.etherscan.io/v2/api"
COINGECKO_BASE = "https://api.coingecko.com/api/v3/coins/ethereum/market_chart"


def _etherscan_call(params: dict[str, str]) -> dict[str, object]:
    url = f"{ETHERSCAN_BASE}?{urlencode(params)}"
    payload = _fetch_json(url)
    if "status" in payload and payload.get("status") != "1":
        raise ValueError(f"Etherscan API error for {params.get('action')}: {payload.get('message')}")
    if "error" in payload:
        raise ValueError(f"Etherscan API error for {params.get('action')}: {payload.get('error')}")
    return payload


def get_block_number_by_time(timestamp: int, api_key: str) -> int:
    payload = _etherscan_call(
        {
            "chainid": "1",
            "module": "block",
            "action": "getblocknobytime",
            "timestamp": str(timestamp),
            "closest": "before",
            "apikey": api_key,
        }
    )
    result = payload.get("result")
    if result is None:
        raise ValueError("Missing block number from Etherscan.")
    return int(result)


def get_block_base_fee(block_number: int, api_key: str) -> int:
    payload = _etherscan_call(
        {
            "chainid": "1",
            "module": "proxy",
            "action": "eth_getBlockByNumber",
            "tag": hex(block_number),
            "boolean": "false",
            "apikey": api_key,
        }
    )
    result = payload.get("result")
    if not isinstance(result, dict) or "baseFeePerGas" not in result:
        raise ValueError("Missing baseFeePerGas from block response.")
    return int(result["baseFeePerGas"], 16)


def sample_base_fees(days: int, api_key: str, max_samples: int, pause_s: float = 0.12) -> list[int]:
    end = date.today()
    start = end - timedelta(days=days - 1)
    base_fees: list[int] = []
    step = max(1, days // max_samples)
    offsets = list(range(0, days, step))
    if offsets[-1] != days - 1:
        offsets.append(days - 1)
    for offset in offsets:
        day = start + timedelta(days=offset)
        timestamp = int(datetime(day.year, day.month, day.day, tzinfo=timezone.utc).timestamp())
        block_number = get_block_number_by_time(timestamp, api_key)
        time.sleep(pause_s)
        base_fee = get_block_base_fee(block_number, api_key)
        time.sleep(pause_s)
        base_fees.append(base_fee)
    return base_fees


def fetch_eth_prices(days: int) -> list[float]:
    url = f"{COINGECKO_BASE}?{urlencode({'vs_currency': 'usd', 'days': str(days), 'interval': 'daily'})}"
    payload = _fetch_json(url)
    prices = payload.get("prices")
    if not isinstance(prices, list) or not prices:
        raise ValueError("Missing ETH price data from CoinGecko.")
    return [float(point[1]) for point in prices if len(point) > 1]


def compute_usd_per_gas(api_key: str) -> float:
    base_fees_90 = sample_base_fees(90, api_key, max_samples=30)
    if not base_fees_90:
        raise ValueError("Insufficient base fee samples.")
    avg_base_fee_90 = sum(base_fees_90) / len(base_fees_90)

    prices = fetch_eth_prices(90)
    if not prices:
        raise ValueError("Insufficient ETH price samples for 3-month average.")
    avg_price_90 = sum(prices) / len(prices)

    usd_per_gas_90d = avg_base_fee_90 / 1e18 * avg_price_90
    return usd_per_gas_90d


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        os.environ.setdefault(key, value)


def parse_float_env(name: str) -> float | None:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return None
    try:
        return float(raw)
    except ValueError as exc:
        raise SystemExit(f"{name} must be a number, got: {raw}") from exc


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


def _find_next_index(
    children: list[tuple[str, int]],
    start: int,
    names: tuple[str, ...] | str,
) -> int | None:
    if isinstance(names, str):
        names = (names,)
    for i in range(start, len(children)):
        if children[i][0] in names:
            return i
    return None


def map_execute(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    context = "executeSlash"
    mapped: list[tuple[str, int]] = []
    idx = 0

    def _require(names: tuple[str, ...] | str, label: str) -> int:
        nonlocal idx
        found = _find_next_index(children, idx, names)
        if found is None:
            raise ValueError(f"Unexpected {context} trace shape.")
        mapped.append((label, children[found][1]))
        idx = found + 1
        return found

    _require("ReentrancyGuard::_nonReentrantBefore", "ReentrancyGuard::_nonReentrantBefore")
    _require("UniversalSlasher::slashRequests", "UniversalSlasher::slashRequests")
    _require("UniversalSlasher::_checkNetworkMiddleware", "UniversalSlasher::_checkNetworkMiddleware")

    slashable_idx = _find_next_index(
        children,
        idx,
        (
            "UniversalSlasher::slashableStake",
            "UniversalSlasher::_slashableStake",
            "stakeFor",
            "stakeAt",
        ),
    )
    if slashable_idx is None:
        raise ValueError(f"Unexpected {context} trace shape.")

    epoch_fallback_idx = _find_next_index(children, idx, "MigratableEntityProxy::fallback")
    if epoch_fallback_idx is not None and epoch_fallback_idx < slashable_idx:
        mapped.append(("VaultV2::epochDuration (via proxy)", children[epoch_fallback_idx][1]))
    else:
        mapped.append(("VaultV2::epochDuration (via proxy)", 0))

    mapped.append(("UniversalSlasher::slashableStake", children[slashable_idx][1]))
    idx = slashable_idx + 1

    on_slash_idx = _find_next_index(children, idx, ("onSlash", "UniversalDelegator::onSlash"))
    if on_slash_idx is None:
        raise ValueError(f"Unexpected {context} trace shape.")

    delegator_fallback_idx = _find_next_index(children, idx, "MigratableEntityProxy::fallback")
    if delegator_fallback_idx is not None and delegator_fallback_idx < on_slash_idx:
        mapped.append(("VaultV2::delegator (via proxy)", children[delegator_fallback_idx][1]))
    else:
        mapped.append(("VaultV2::delegator (via proxy)", 0))

    mapped.append(("UniversalDelegator::onSlash", children[on_slash_idx][1]))
    idx = on_slash_idx + 1

    burner_idx = _find_next_index(children, idx, "UniversalSlasher::_burnerOnSlash")
    if burner_idx is None:
        raise ValueError(f"Unexpected {context} trace shape.")

    fallbacks_before_burner = [
        i for i in range(idx, burner_idx) if children[i][0] == "MigratableEntityProxy::fallback"
    ]
    if not fallbacks_before_burner:
        raise ValueError(f"Unexpected {context} trace shape.")
    vault_on_slash_fallback_idx = fallbacks_before_burner[-1]
    delegator_for_adapters_idx = fallbacks_before_burner[-2] if len(fallbacks_before_burner) > 1 else None

    if delegator_for_adapters_idx is None:
        mapped.append(("VaultV2::delegator (via proxy, for getIsNoAdapters)", 0))
    else:
        mapped.append(
            (
                "VaultV2::delegator (via proxy, for getIsNoAdapters)",
                children[delegator_for_adapters_idx][1],
            )
        )

    get_is_no_adapters_idx = _find_next_index(
        children,
        idx,
        ("getIsNoAdapters", "UniversalDelegator::getIsNoAdapters"),
    )
    if get_is_no_adapters_idx is None or get_is_no_adapters_idx >= burner_idx:
        mapped.append(("UniversalDelegator::getIsNoAdapters", 0))
    else:
        mapped.append(("UniversalDelegator::getIsNoAdapters", children[get_is_no_adapters_idx][1]))

    mapped.append(("VaultV2::onSlash (via proxy)", children[vault_on_slash_fallback_idx][1]))
    mapped.append(("UniversalSlasher::_burnerOnSlash", children[burner_idx][1]))

    non_reentrant_after_idx = _find_next_index(children, burner_idx + 1, "ReentrancyGuard::_nonReentrantAfter")
    mapped.append(
        (
            "ReentrancyGuard::_nonReentrantAfter",
            children[non_reentrant_after_idx][1] if non_reentrant_after_idx is not None else 0,
        )
    )
    return mapped


def map_vault(children: list[tuple[str, int]]) -> list[tuple[str, int]]:
    context = "VaultV2::onSlash"

    def _gas_by_occurrence(
        names: tuple[str, ...] | str,
        occurrence: int = 0,
        required: bool = True,
    ) -> int:
        if isinstance(names, str):
            names = (names,)
        found = -1
        for name, gas in children:
            if name in names:
                found += 1
                if found == occurrence:
                    return gas
        if required:
            raise ValueError(f"Unexpected {context} trace shape.")
        return 0

    push_values = [gas for name, gas in children if name == "Checkpoints::push"]

    def _push_by_occurrence(occurrence: int) -> int:
        return push_values[occurrence] if occurrence < len(push_values) else 0

    # Newer traces may merge legacy storage/checkpoint subcalls into this one.
    sync_claimable = _gas_by_occurrence("VaultV2::_syncClaimableWithdrawals", required=False)
    active_withdrawals_first = _gas_by_occurrence("VaultV2::activeWithdrawals", occurrence=0, required=False)
    active_withdrawals_second = _gas_by_occurrence("VaultV2::activeWithdrawals", occurrence=1, required=False)
    withdrawals_storage = _gas_by_occurrence("VaultV2Storage::withdrawals", required=False)

    return [
        ("VaultV2::deallocateAdapters", _gas_by_occurrence("VaultV2::deallocateAdapters", required=False)),
        ("ReentrancyGuard::_nonReentrantBefore", _gas_by_occurrence("ReentrancyGuard::_nonReentrantBefore", required=False)),
        ("VaultV2Storage::activeStake", _gas_by_occurrence("VaultV2Storage::activeStake", required=False)),
        ("VaultV2Storage::withdrawalBucket", _gas_by_occurrence("VaultV2Storage::withdrawalBucket", required=False)),
        (
            "Checkpoints::upperLookupRecent",
            _gas_by_occurrence(("Checkpoints::upperLookupRecent", "VaultV2::_activeWithdrawalSharesFor"), required=False),
        ),
        ("Checkpoints::latest", _gas_by_occurrence("Checkpoints::latest", required=False)),
        ("VaultV2::activeWithdrawals", active_withdrawals_first),
        ("VaultV2::activeWithdrawals", active_withdrawals_second),
        # Backward-compatible slot: old traces report VaultV2Storage::withdrawals here,
        # new traces report the merged sync call.
        ("VaultV2Storage::withdrawals", withdrawals_storage if withdrawals_storage > 0 else sync_claimable),
        ("Checkpoints::push", _push_by_occurrence(0)),
        ("Checkpoints::push", _push_by_occurrence(1)),
        ("VaultV2Storage::withdrawalShares", _gas_by_occurrence("VaultV2Storage::withdrawalShares", required=False)),
        ("Checkpoints::push", _push_by_occurrence(2)),
        ("Checkpoints::push", _push_by_occurrence(3)),
        (
            "Math::mulDiv",
            _gas_by_occurrence("Math::mulDiv", required=False),
        ),
        ("Checkpoints::push", _push_by_occurrence(4)),
        ("Checkpoints::push", _push_by_occurrence(5)),
        ("VaultV2::_availableToSlash", _gas_by_occurrence("VaultV2::_availableToSlash", required=False)),
        ("SafeERC20::safeTransfer", _gas_by_occurrence("SafeERC20::safeTransfer", required=False)),
        ("ReentrancyGuard::_nonReentrantAfter", _gas_by_occurrence("ReentrancyGuard::_nonReentrantAfter", required=False)),
    ]


def component_gas(components: list[tuple[str, int]], label: str, context: str) -> int:
    for name, gas in components:
        if name == label:
            return gas
    raise ValueError(f"Missing {context} component: {label}")


def _norm_label(value: str) -> str:
    normalized = value.replace("`", "").strip()
    normalized = normalized.replace("ReentrancyGuardUpgradeable", "ReentrancyGuard")
    normalized = normalized.replace("Plugins", "Adapters")
    normalized = normalized.replace("Plugin", "Adapter")
    normalized = normalized.replace("plugins", "adapters")
    normalized = normalized.replace("plugin", "adapter")
    normalized = normalized.replace("getIsNoPlugins", "getIsNoAdapters")
    return normalized.replace("plugin mode check", "adapter mode check")


def update_table(
    lines: list[str],
    heading: str,
    rows: list[tuple[tuple[str, ...], int]],
    gas_col: int,
    gas_formatter: Callable[[int], str],
) -> None:
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
        parts[gas_col] = gas_formatter(gas)
        lines[idx] = f"| {' | '.join(parts)} |"
        idx += 1


def update_reports(log_path: Path, usd_per_gas_90d: float) -> list[Path]:
    lines = log_path.read_text().splitlines()
    updated: list[Path] = []
    gas_fmt = lambda value: fmt_gas_with_usd(value, usd_per_gas_90d)

    logs = parse_logs(lines)
    scenario_required = [
        "with_capture_isolated_request1",
        "with_capture_isolated_request2",
        "with_capture_isolated_execute1",
        "with_capture_isolated_execute2",
        "with_capture_single_request1",
        "with_capture_single_request2",
        "with_capture_single_execute1",
        "with_capture_single_execute2",
        "with_capture_stake_before",
        "with_capture_stake_after",
        "no_capture_isolated_request1",
        "no_capture_isolated_request2",
        "no_capture_isolated_execute1",
        "no_capture_isolated_execute2",
        "no_capture_single_request1",
        "no_capture_single_request2",
        "no_capture_single_execute1",
        "no_capture_single_execute2",
        "no_capture_stake_before",
        "no_capture_stake_after",
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
        logs["stakeForAt_no_hints"] = logs["with_capture_stake_before"]
        logs["executeSlash_no_hints"] = logs["with_capture_isolated_execute1"]
        logs["requestSlash_no_hints"] = logs["with_capture_isolated_request1"]
        logs["stakeForAt2_no_hints"] = logs["with_capture_stake_after"]
        logs["executeSlash2_no_hints"] = logs["with_capture_isolated_execute2"]
        logs["requestSlash2_no_hints"] = logs["with_capture_isolated_request2"]
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

9 networks, 10 operators in each
Operators to be slashed are first and second to maximize gas costs for slashing call

Notes:
- Different operators, same network.
- “Fully isolated” runs request1, request2, then execute1, execute2, with a block time jump between the phases.
- “Single transaction” uses two transactions: batch two requests, then batch two executes.
- “Stake For Timestamp” measures stakeForAt before any slashing and after the first slash (uses stakeFor when captureTimestamp = 0).
- “Without capture timestamp” passes captureTimestamp = 0 into requestSlash
- USD values show a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## No-capture target (captureTimestamp = 0)

Note: `latest()` state is used.

### Fully isolated and in different blocks

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | {gas_fmt(logs["no_capture_isolated_request1"])} | {gas_fmt(logs["no_capture_isolated_execute1"])} |
| 2nd | {gas_fmt(logs["no_capture_isolated_request2"])} | {gas_fmt(logs["no_capture_isolated_execute2"])} |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | {gas_fmt(logs["no_capture_single_request1"])} | {gas_fmt(logs["no_capture_single_execute1"])} |
| 2nd | {gas_fmt(logs["no_capture_single_request2"])} | {gas_fmt(logs["no_capture_single_execute2"])} |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | {gas_fmt(logs["no_capture_stake_before"])} |
| After slashing | {gas_fmt(logs["no_capture_stake_after"])} |

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
            gas_fmt,
        )
        update_table(
            report_1_lines,
            "## executeSlash components (no hints)",
            [((label,), gas) for label, gas in exec_1],
            1,
            gas_fmt,
        )
        update_table(
            report_1_lines,
            "## executeSlash components (with hints)",
            [((label,), gas) for label, gas in exec_2],
            1,
            gas_fmt,
        )
        update_table(
            report_1_lines,
            "## VaultV2::onSlash breakdown",
            [((label,), gas) for label, gas in vault_1],
            1,
            gas_fmt,
        )
        update_table(
            report_1_lines,
            "## Delta (with hints vs no hints)",
            [
                (
                    ("`UniversalSlasher::slashableStake`",),
                    component_gas(exec_2, "UniversalSlasher::slashableStake", "executeSlash with hints")
                    - component_gas(exec_1, "UniversalSlasher::slashableStake", "executeSlash no hints"),
                ),
                (("Total `executeSlash`",), logs["executeSlash_with_hints"] - logs["executeSlash_no_hints"]),
            ],
            1,
            gas_fmt,
        )
        REPORT_1.write_text("\n".join(report_1_lines) + "\n")
        updated.append(REPORT_1)

        # Report 2
        report_2_lines = REPORT_2.read_text().splitlines()
        update_table(
            report_2_lines,
            "## Summary (same network, second operator)",
            [
                (("`stakeForAt`", "no"), logs["stakeForAt2_no_hints"]),
                (("`stakeForAt`", "yes"), logs["stakeForAt2_with_hints"]),
                (("`requestSlash`", "no"), logs["requestSlash2_no_hints"]),
                (("`requestSlash`", "yes"), logs["requestSlash2_with_hints"]),
                (("`executeSlash`", "no"), logs["executeSlash2_no_hints"]),
                (("`executeSlash`", "yes"), logs["executeSlash2_with_hints"]),
            ],
            2,
            gas_fmt,
        )
        update_table(
            report_2_lines,
            "## executeSlash components (no hints)",
            [((label,), gas) for label, gas in exec_3],
            1,
            gas_fmt,
        )
        update_table(
            report_2_lines,
            "## executeSlash components (with hints)",
            [((label,), gas) for label, gas in exec_4],
            1,
            gas_fmt,
        )
        update_table(
            report_2_lines,
            "## VaultV2::onSlash breakdown (after first slash)",
            [((label,), gas) for label, gas in vault_3],
            1,
            gas_fmt,
        )
        update_table(
            report_2_lines,
            "## Delta (with hints vs no hints)",
            [
                (
                    ("`UniversalSlasher::slashableStake`",),
                    component_gas(exec_4, "UniversalSlasher::slashableStake", "executeSlash2 with hints")
                    - component_gas(exec_3, "UniversalSlasher::slashableStake", "executeSlash2 no hints"),
                ),
                (("Total `executeSlash`",), logs["executeSlash2_with_hints"] - logs["executeSlash2_no_hints"]),
            ],
            1,
            gas_fmt,
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
    load_env_file(ROOT / ".env")
    usd_override_90d = parse_float_env("USD_PER_GAS_90D")
    if usd_override_90d is None:
        usd_override_90d = parse_float_env("USD_PER_GAS")
    api_key = os.getenv("ETHERSCAN_API_KEY")
    if not api_key and usd_override_90d is None:
        raise SystemExit(
            "ETHERSCAN_API_KEY is required to compute USD averages. "
            "Alternatively set USD_PER_GAS_90D (or USD_PER_GAS) to override."
        )
    try:
        if usd_override_90d is not None:
            usd_per_gas_90d = usd_override_90d
        else:
            usd_per_gas_90d = compute_usd_per_gas(api_key)
    except Exception as exc:
        if usd_override_90d is not None:
            usd_per_gas_90d = usd_override_90d
        else:
            raise SystemExit(
                f"Failed to fetch USD averages: {exc}. "
                "Set USD_PER_GAS_90D (or USD_PER_GAS) to override."
            ) from exc
    updated = update_reports(log_path, usd_per_gas_90d)
    for path in updated:
        print(f"Updated: {path}")


if __name__ == "__main__":
    main()
