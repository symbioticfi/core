import { useEffect, useState } from "react";
import { isAddress, type Address } from "viem";
import type { SlotNode } from "../lib/ops";

export type ActionPanelProps = {
  focus: SlotNode | null;
  disabled?: boolean;
  onCreateSubvault: (size: bigint, isShared: boolean, noPlugins: boolean) => void;
  onCreateNetwork: (network: Address, identifier: bigint, size: bigint) => void;
  onCreateOperator: (operator: Address, size: bigint) => void;
  onSetWithdrawalBuffer: (size: bigint) => void;
  onSetHook: (hook: Address) => void;
};

function parseBigInt(value: string): bigint | null {
  if (!value.trim()) {
    return null;
  }
  try {
    return BigInt(value.trim());
  } catch {
    return null;
  }
}

export function ActionPanel({
  focus,
  disabled = false,
  onCreateSubvault,
  onCreateNetwork,
  onCreateOperator,
  onSetWithdrawalBuffer,
  onSetHook,
}: ActionPanelProps) {
  const [subvaultSize, setSubvaultSize] = useState("");
  const [subvaultShared, setSubvaultShared] = useState(false);
  const [subvaultNoPlugins, setSubvaultNoPlugins] = useState(false);

  const [networkAddress, setNetworkAddress] = useState("");
  const [networkId, setNetworkId] = useState("");
  const [networkSize, setNetworkSize] = useState("");

  const [operatorAddress, setOperatorAddress] = useState("");
  const [operatorSize, setOperatorSize] = useState("");

  const [withdrawalSize, setWithdrawalSize] = useState("");
  const [hookAddress, setHookAddress] = useState("");

  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
  }, [focus?.index]);

  const focusDepth = focus?.depth ?? 0;

  return (
    <div className="panel-surface rounded-2xl p-4">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Actions</p>
        <h2 className="font-display text-base text-ink">Queue ops</h2>
      </div>

      {disabled && <p className="mt-3 text-xs text-ink-subtle">Load a delegator to enable ops creation.</p>}
      {!disabled && error && <p className="mt-3 text-xs text-ember-600">{error}</p>}

      {focusDepth === 0 && (
        <div className="mt-4 space-y-3">
          <p className="text-sm text-ink">Add subvault slot</p>
          <input
            className="input-base"
            placeholder="Size"
            value={subvaultSize}
            onChange={(event) => setSubvaultSize(event.target.value)}
            disabled={disabled}
          />
          <div className="flex gap-3 text-xs">
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={subvaultShared}
                onChange={(event) => setSubvaultShared(event.target.checked)}
                disabled={disabled}
              />
              Shared
            </label>
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={subvaultNoPlugins}
                onChange={(event) => setSubvaultNoPlugins(event.target.checked)}
                disabled={disabled}
              />
              No plugins
            </label>
          </div>
          <button
            type="button"
            className="button-base button-ember"
            onClick={() => {
              const size = parseBigInt(subvaultSize);
              if (size === null) {
                setError("Enter a valid subvault size.");
                return;
              }
              onCreateSubvault(size, subvaultShared, subvaultNoPlugins);
              setError(null);
              setSubvaultSize("");
            }}
            disabled={disabled}
          >
            Queue subvault
          </button>
        </div>
      )}

      {focusDepth === 1 && (
        <div className="mt-4 space-y-3">
          <p className="text-sm text-ink">Add network slot</p>
          <input
            className="input-base"
            placeholder="Network address"
            value={networkAddress}
            onChange={(event) => setNetworkAddress(event.target.value)}
            disabled={disabled}
          />
          <input
            className="input-base"
            placeholder="Network ID (uint96)"
            value={networkId}
            onChange={(event) => setNetworkId(event.target.value)}
            disabled={disabled}
          />
          <input
            className="input-base"
            placeholder="Size"
            value={networkSize}
            onChange={(event) => setNetworkSize(event.target.value)}
            disabled={disabled}
          />
          <button
            type="button"
            className="button-base button-ember"
            onClick={() => {
              if (!isAddress(networkAddress)) {
                setError("Enter a valid network address.");
                return;
              }
              const id = parseBigInt(networkId);
              const size = parseBigInt(networkSize);
              if (id === null || size === null) {
                setError("Enter valid network ID and size.");
                return;
              }
              onCreateNetwork(networkAddress as Address, id, size);
              setError(null);
              setNetworkAddress("");
              setNetworkId("");
              setNetworkSize("");
            }}
            disabled={disabled}
          >
            Queue network
          </button>
        </div>
      )}

      {focusDepth === 2 && (
        <div className="mt-4 space-y-3">
          <p className="text-sm text-ink">Add operator slot</p>
          <input
            className="input-base"
            placeholder="Operator address"
            value={operatorAddress}
            onChange={(event) => setOperatorAddress(event.target.value)}
            disabled={disabled}
          />
          <input
            className="input-base"
            placeholder="Size"
            value={operatorSize}
            onChange={(event) => setOperatorSize(event.target.value)}
            disabled={disabled}
          />
          <button
            type="button"
            className="button-base button-ember"
            onClick={() => {
              if (!isAddress(operatorAddress)) {
                setError("Enter a valid operator address.");
                return;
              }
              const size = parseBigInt(operatorSize);
              if (size === null) {
                setError("Enter a valid size.");
                return;
              }
              onCreateOperator(operatorAddress as Address, size);
              setError(null);
              setOperatorAddress("");
              setOperatorSize("");
            }}
            disabled={disabled}
          >
            Queue operator
          </button>
        </div>
      )}

      <div className="mt-6 space-y-3">
        <p className="text-sm text-ink">Set withdrawal buffer</p>
        <input
          className="input-base"
          placeholder="New buffer size"
          value={withdrawalSize}
          onChange={(event) => setWithdrawalSize(event.target.value)}
          disabled={disabled}
        />
        <button
          type="button"
          className="button-base"
          onClick={() => {
            const size = parseBigInt(withdrawalSize);
            if (size === null) {
              setError("Enter a valid withdrawal buffer size.");
              return;
            }
            onSetWithdrawalBuffer(size);
            setError(null);
            setWithdrawalSize("");
          }}
          disabled={disabled}
        >
          Queue buffer update
        </button>
      </div>

      <div className="mt-6 space-y-3">
        <p className="text-sm text-ink">Set hook</p>
        <input
          className="input-base"
          placeholder="Hook address"
          value={hookAddress}
          onChange={(event) => setHookAddress(event.target.value)}
          disabled={disabled}
        />
        <button
          type="button"
          className="button-base"
          onClick={() => {
            if (!isAddress(hookAddress)) {
              setError("Enter a valid hook address.");
              return;
            }
            onSetHook(hookAddress as Address);
            setError(null);
            setHookAddress("");
          }}
          disabled={disabled}
        >
          Queue hook update
        </button>
      </div>
    </div>
  );
}
