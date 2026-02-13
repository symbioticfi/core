import type { Address } from "viem";
import { formatAddress, formatBigInt, formatToken } from "../lib/format";

export type ContextPanelProps = {
  vault?: Address;
  delegator?: Address;
  epochDuration?: bigint;
  allocatable?: bigint;
  activeStake?: bigint;
  activeWithdrawals?: bigint;
  noPluginsSize?: bigint;
  withdrawalBuffer?: bigint;
  collateral?: Address;
  slasher?: Address;
  tokenDecimals?: number;
  disabled?: boolean;
};

export function ContextPanel({
  vault,
  delegator,
  epochDuration,
  allocatable,
  activeStake,
  activeWithdrawals,
  noPluginsSize,
  withdrawalBuffer,
  collateral,
  slasher,
  tokenDecimals,
  disabled = false,
}: ContextPanelProps) {
  return (
    <div className="panel-surface rounded-2xl p-4">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Context</p>
          <p className="font-display text-base text-ink">Vault + Delegator</p>
        </div>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
        <div>
          <p className="text-ink-subtle">Delegator</p>
          <p className="mono text-ink">{formatAddress(delegator)}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Vault</p>
          <p className="mono text-ink">{formatAddress(vault)}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Collateral</p>
          <p className="mono text-ink">{formatAddress(collateral)}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Slasher</p>
          <p className="mono text-ink">{formatAddress(slasher)}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Epoch Duration</p>
          <p className="mono text-ink">{epochDuration ? formatBigInt(epochDuration) : "-"}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Allocatable</p>
          <p className="mono text-ink">{allocatable !== undefined ? formatToken(allocatable, tokenDecimals) : "-"}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Active Stake</p>
          <p className="mono text-ink">{activeStake !== undefined ? formatToken(activeStake, tokenDecimals) : "-"}</p>
        </div>
        <div>
          <p className="text-ink-subtle">Active Withdrawals</p>
          <p className="mono text-ink">
            {activeWithdrawals !== undefined ? formatToken(activeWithdrawals, tokenDecimals) : "-"}
          </p>
        </div>
        <div>
          <p className="text-ink-subtle">No-Plugins Size</p>
          <p className="mono text-ink">
            {noPluginsSize !== undefined ? formatToken(noPluginsSize, tokenDecimals) : "-"}
          </p>
        </div>
        <div>
          <p className="text-ink-subtle">Withdrawal Buffer</p>
          <p className="mono text-ink">
            {withdrawalBuffer !== undefined ? formatToken(withdrawalBuffer, tokenDecimals) : "-"}
          </p>
        </div>
      </div>
    </div>
  );
}
