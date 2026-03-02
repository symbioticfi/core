import { useEffect, useState } from "react";
import { isAddress, type Address } from "viem";
import type { SlotNode } from "../lib/ops";
import { SlotCard } from "./SlotCard";
import { formatToken, parseToken } from "../lib/format";

export type SlotBoardProps = {
  focus: SlotNode;
  onSelect: (index: bigint) => void;
  onQueueSize: (index: bigint, size: bigint) => void;
  onQueueSwap: (index1: bigint, index2: bigint) => void;
  onQueueRemove: (index: bigint) => void;
  onCreateSubvault: (size: bigint, isShared: boolean, noPlugins: boolean) => void;
  onCreateNetwork: (network: Address, identifier: bigint, size: bigint) => void;
  onCreateOperator: (operator: Address, size: bigint) => void;
  onSetWithdrawalBuffer: (size: bigint) => void;
  withdrawalBuffer?: bigint;
  tokenDecimals?: number;
  disabled?: boolean;
};

export function SlotBoard({
  focus,
  onSelect,
  onQueueSize,
  onQueueSwap,
  onQueueRemove,
  onCreateSubvault,
  onCreateNetwork,
  onCreateOperator,
  onSetWithdrawalBuffer,
  withdrawalBuffer,
  tokenDecimals,
  disabled = false,
}: SlotBoardProps) {
  const children = focus.children;
  const totalSize = children.reduce((sum, child) => sum + child.size, 0n);
  const orientation = focus.isShared ? "vertical" : "horizontal";

  const fallbackRatio = children.length > 0 ? 1 / children.length : 1;

  const [subvaultSize, setSubvaultSize] = useState("");
  const [subvaultShared, setSubvaultShared] = useState(false);
  const [subvaultNoPlugins, setSubvaultNoPlugins] = useState(false);

  const [networkAddress, setNetworkAddress] = useState("");
  const [networkId, setNetworkId] = useState("");
  const [networkSize, setNetworkSize] = useState("");

  const [operatorAddress, setOperatorAddress] = useState("");
  const [operatorSize, setOperatorSize] = useState("");
  const [bufferInput, setBufferInput] = useState(
    withdrawalBuffer !== undefined ? formatToken(withdrawalBuffer, tokenDecimals) : "",
  );
  const [bufferQueued, setBufferQueued] = useState<bigint | null>(
    withdrawalBuffer !== undefined ? withdrawalBuffer : null,
  );

  useEffect(() => {
    if (withdrawalBuffer !== undefined) {
      setBufferInput(formatToken(withdrawalBuffer, tokenDecimals));
      setBufferQueued(withdrawalBuffer);
    }
  }, [withdrawalBuffer, tokenDecimals]);

  const renderAddCard = () => {
    if (disabled) {
      return null;
    }

    if (focus.depth === 0) {
      return null;
    }

    if (focus.depth === 1) {
      return (
        <div className="min-w-[360px] flex-1 rounded-2xl border border-dashed border-sand-300 bg-white/70 p-4">
          <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Add network</p>
          <div className="mt-3 flex flex-col gap-2 text-xs">
            <input
              className="input-base w-full"
              placeholder="Network address"
              value={networkAddress}
              onChange={(event) => setNetworkAddress(event.target.value)}
            />
            <input
              className="input-base w-full"
              placeholder="Network ID (uint96)"
              value={networkId}
              onChange={(event) => setNetworkId(event.target.value)}
            />
            <input
              className="input-base w-full"
              placeholder="Size"
              value={networkSize}
              onChange={(event) => setNetworkSize(event.target.value)}
            />
            <button
              type="button"
              className="button-base button-ember whitespace-nowrap"
              onClick={() => {
                if (!isAddress(networkAddress)) {
                  return;
                }
                try {
                  const id = BigInt(networkId.trim());
                  const size = parseToken(networkSize, tokenDecimals);
                  if (size === null) {
                    return;
                  }
                  onCreateNetwork(networkAddress as Address, id, size);
                  setNetworkAddress("");
                  setNetworkId("");
                  setNetworkSize("");
                } catch {
                  // ignore invalid
                }
              }}
            >
              Queue network
            </button>
          </div>
        </div>
      );
    }

    if (focus.depth === 2) {
      return (
        <div className="min-w-[360px] flex-1 rounded-2xl border border-dashed border-sand-300 bg-white/70 p-4">
          <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Add operator</p>
          <div className="mt-3 flex flex-col gap-2 text-xs">
            <input
              className="input-base w-full"
              placeholder="Operator address"
              value={operatorAddress}
              onChange={(event) => setOperatorAddress(event.target.value)}
            />
            <input
              className="input-base w-full"
              placeholder="Size"
              value={operatorSize}
              onChange={(event) => setOperatorSize(event.target.value)}
            />
            <button
              type="button"
              className="button-base button-ember whitespace-nowrap"
              onClick={() => {
                if (!isAddress(operatorAddress)) {
                  return;
                }
                try {
                  const size = parseToken(operatorSize, tokenDecimals);
                  if (size === null) {
                    return;
                  }
                  onCreateOperator(operatorAddress as Address, size);
                  setOperatorAddress("");
                  setOperatorSize("");
                } catch {
                  // ignore invalid
                }
              }}
            >
              Queue operator
            </button>
          </div>
        </div>
      );
    }

    return null;
  };

  const addCard = renderAddCard();
  const showWithdrawalBuffer = focus.depth === 0 && withdrawalBuffer !== undefined;

  return (
    <div
      className={`flex h-[520px] max-h-[520px] w-full gap-4 overflow-auto rounded-3xl border border-sand-200 bg-white/60 p-4 shadow-panel ${
        orientation === "horizontal" ? "flex-row" : "flex-col"
      }`}
    >
      {children.length === 0 && !addCard && !showWithdrawalBuffer && (
        <div className="flex h-full w-full items-center justify-center text-sm text-ink-subtle">
          No children in this scope.
        </div>
      )}
      {children.map((child, idx) => {
        const ratio = totalSize > 0n ? Number((child.size * 10000n) / totalSize) / 10000 : fallbackRatio;
        const prev = idx > 0 ? children[idx - 1] : null;
        const next = idx < children.length - 1 ? children[idx + 1] : null;

        return (
          <div
            key={child.index.toString()}
            className="min-w-[360px] flex-1"
            style={{
              flexGrow: Math.max(ratio, 0.05),
              flexBasis: 0,
            }}
          >
            <SlotCard
              node={child}
              orientation={orientation}
              onSelect={() => onSelect(child.index)}
              onQueueSize={(size) => onQueueSize(child.index, size)}
              onQueueSwapPrev={prev ? () => onQueueSwap(prev.index, child.index) : undefined}
              onQueueSwapNext={next ? () => onQueueSwap(child.index, next.index) : undefined}
              onQueueRemove={child.depth >= 1 ? () => onQueueRemove(child.index) : undefined}
              onSelectChild={onSelect}
              tokenDecimals={tokenDecimals}
            />
          </div>
        );
      })}

      {addCard}

      {showWithdrawalBuffer && (
        <div className="min-w-[360px] flex-1 rounded-2xl border border-sand-200 bg-white/80 p-4 shadow-card">
          <div className="flex h-full flex-col justify-between">
            <div className="flex items-center justify-between">
              <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Withdrawal Buffer</p>
              <span className="tag tag-ember">Buffer</span>
            </div>
            <div className="mt-4 text-sm">
              <p className="text-ink-subtle">Allocated</p>
              <p className="mono text-ink">{withdrawalBuffer ? formatToken(withdrawalBuffer, tokenDecimals) : "0"}</p>
            </div>
            {!disabled && (
              <div className="mt-2 text-xs">
                <input
                  className="input-base w-full"
                  placeholder="Set buffer size"
                  value={bufferInput}
                  onChange={(event) => setBufferInput(event.target.value)}
                  onBlur={(event) => {
                    const parsed = parseToken(event.target.value, tokenDecimals);
                    if (parsed === null) {
                      setBufferInput(formatToken(withdrawalBuffer ?? 0n, tokenDecimals));
                      return;
                    }
                    if (parsed === withdrawalBuffer || parsed === bufferQueued) {
                      return;
                    }
                    setBufferQueued(parsed);
                    onSetWithdrawalBuffer(parsed);
                  }}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      event.currentTarget.blur();
                    }
                  }}
                />
              </div>
            )}
          </div>
        </div>
      )}

      {focus.depth === 0 && !disabled && (
        <div className="min-w-[360px] flex-1 rounded-2xl border border-dashed border-sand-300 bg-white/70 p-4">
          <div className="flex h-full flex-col items-center justify-center gap-4 text-center">
            <div className="w-full text-xs">
              <div className="mb-2 flex items-center gap-2">
                <label className="flex items-center gap-2 whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={subvaultShared}
                    onChange={(event) => setSubvaultShared(event.target.checked)}
                    className="h-5 w-5"
                  />
                  Shared
                </label>
                <label className="flex items-center gap-2 whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={subvaultNoPlugins}
                    onChange={(event) => setSubvaultNoPlugins(event.target.checked)}
                    className="h-5 w-5"
                  />
                  No plugins
                </label>
              </div>
              <input
                className="input-base w-full"
                placeholder="Size"
                value={subvaultSize}
                onChange={(event) => setSubvaultSize(event.target.value)}
              />
              <button
                type="button"
                className="button-base button-ember mt-2 w-full whitespace-nowrap"
                onClick={() => {
                  const value = subvaultSize.trim();
                  if (!value) {
                    return;
                  }
                  try {
                    const parsed = parseToken(value, tokenDecimals);
                    if (parsed === null) {
                      return;
                    }
                    onCreateSubvault(parsed, subvaultShared, subvaultNoPlugins);
                    setSubvaultSize("");
                  } catch {
                    // ignore invalid
                  }
                }}
              >
                Add subvault
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
