import type { Address } from "viem";
import { formatAddress } from "../lib/format";

type TopBarProps = {
  connected: boolean;
  address?: Address;
  chainName?: string;
  supportedChain: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  delegatorInput: string;
  onDelegatorChange: (value: string) => void;
  onLoad: () => void;
  loading: boolean;
  canLoad: boolean;
};

export function TopBar({
  connected,
  address,
  chainName,
  supportedChain,
  onConnect,
  onDisconnect,
  delegatorInput,
  onDelegatorChange,
  onLoad,
  loading,
  canLoad,
}: TopBarProps) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-sand-200 bg-white/80 p-4 shadow-panel">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">UniversalDelegator Admin</p>
        <h1 className="font-display text-2xl text-ink">Delegation Ops Console</h1>
        <p className="text-sm text-ink-subtle">
          Wallet RPC only · Explicit ops · Multicall execution
        </p>
      </div>
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-end gap-2 text-sm">
          <span className="tag tag-teal">{chainName ?? "No chain"}</span>
          {!supportedChain && (
            <span className="tag tag-ember">Unsupported chain</span>
          )}
          {connected ? (
            <button type="button" className="button-base" onClick={onDisconnect}>
              {formatAddress(address)} · Disconnect
            </button>
          ) : (
            <button type="button" className="button-base button-ember" onClick={onConnect}>
              Connect wallet
            </button>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <input
            className="input-base min-w-[260px]"
            placeholder="Delegator address"
            value={delegatorInput}
            onChange={(event) => onDelegatorChange(event.target.value)}
          />
          <button
            type="button"
            className="button-base button-ink"
            onClick={onLoad}
            disabled={!connected || loading || !delegatorInput.trim() || !canLoad}
          >
            {loading ? "Loading" : "Load delegator"}
          </button>
        </div>
      </div>
    </div>
  );
}
