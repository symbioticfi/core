import { useEffect, useRef, useState } from "react";
import type { SlotNode } from "../lib/ops";
import { formatAddress, formatToken, parseToken } from "../lib/format";

export type SlotCardProps = {
  node: SlotNode;
  orientation: "horizontal" | "vertical";
  onSelect: () => void;
  onQueueSize: (size: bigint) => void;
  onQueueSwapPrev?: () => void;
  onQueueSwapNext?: () => void;
  onQueueRemove?: () => void;
  onSelectChild?: (index: bigint) => void;
  tokenDecimals?: number;
};

export function SlotCard({
  node,
  orientation,
  onSelect,
  onQueueSize,
  onQueueSwapPrev,
  onQueueSwapNext,
  onQueueRemove,
  onSelectChild,
  tokenDecimals,
}: SlotCardProps) {
  const [sizeInput, setSizeInput] = useState(formatToken(node.size, tokenDecimals));
  const lastQueued = useRef(node.size);

  useEffect(() => {
    setSizeInput(formatToken(node.size, tokenDecimals));
    lastQueued.current = node.size;
  }, [node.size, tokenDecimals]);
  const depthLabel = node.depth === 1 ? "Subvault" : node.depth === 2 ? "Network" : "Operator";
  const childIndex = Number((node.index >> BigInt(32 * (3 - node.depth))) & 0xffffffffn);
  const childIndexOf = (index: bigint, depth: number) => Number((index >> BigInt(32 * (3 - depth))) & 0xffffffffn);
  const hoverClass = "hover:border-black/35";

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelect();
        }
      }}
      className={`relative flex h-full min-h-[210px] flex-col justify-between gap-3 rounded-2xl border border-sand-200 bg-white/80 p-4 shadow-card transition hover:-translate-y-1 ${hoverClass}`}
    >
      <div className="w-full text-left">
        <div className="flex items-start justify-between gap-3 pr-8">
          <div className="min-w-0">
            <div className="flex items-center gap-2 whitespace-nowrap">
              <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">{depthLabel}</p>
              <span className="tag">{childIndex}</span>
            </div>
          </div>
          {(node.subnetwork || node.operator) && (
            <div className="min-w-0 text-right text-xs">
              {node.subnetwork && (
                <>
                  <div className="mono whitespace-nowrap text-ink-muted">
                    <span className="text-ink-subtle">Network:</span> {formatAddress(node.subnetwork.network)}
                  </div>
                  <div className="mono whitespace-nowrap text-ink-muted">
                    <span className="text-ink-subtle">Subnet:</span> {node.subnetwork.identifier.toString()}
                  </div>
                </>
              )}
              {node.operator && (
                <div className="mono whitespace-nowrap text-ink-muted">
                  <span className="text-ink-subtle">Operator:</span> {formatAddress(node.operator)}
                </div>
              )}
            </div>
          )}
        </div>
        <div className="mt-2 text-xs">
          <div className="mono text-ink whitespace-nowrap">
            <span className="text-ink-subtle">Avail</span> {formatToken(node.metrics.available, tokenDecimals)}
          </div>
          <div className="mono text-ink whitespace-nowrap">
            <span className="text-ink-subtle">Pend</span> {formatToken(node.metrics.pending, tokenDecimals)}
          </div>
          <div className="mono text-ink whitespace-nowrap">
            <span className="text-ink-subtle">Alloc</span> {formatToken(node.metrics.allocated, tokenDecimals)}
          </div>
        </div>
        {node.depth === 1 ? (
          <div className="mt-2 flex items-center gap-2 text-xs whitespace-nowrap">
            <span className={`tag ${node.isShared ? "tag-teal" : "tag-ember"}`}>
              Shared: {node.isShared ? "on" : "off"}
            </span>
            <span className={`tag ${node.noPlugins ? "tag-teal" : "tag-ember"}`}>
              No Plugins: {node.noPlugins ? "on" : "off"}
            </span>
          </div>
        ) : (
          (node.isShared || node.noPlugins) && (
            <div className="mt-2 flex items-center gap-2 text-xs whitespace-nowrap">
              {node.isShared && <span className="tag tag-teal">Shared</span>}
              {node.noPlugins && <span className="tag tag-ember">No Plugins</span>}
            </div>
          )
        )}
        <div className="mt-2 flex flex-col gap-2 text-xs">
          <input
            value={sizeInput}
            onChange={(event) => setSizeInput(event.target.value)}
            className="input-base w-[160px]"
            placeholder="Size"
            onClick={(event) => event.stopPropagation()}
            onKeyDown={(event) => {
              event.stopPropagation();
              if (event.key === "Enter") {
                event.preventDefault();
                event.currentTarget.blur();
              }
            }}
            onBlur={(event) => {
              const parsed = parseToken(event.target.value, tokenDecimals);
              if (parsed === null) {
                setSizeInput(formatToken(node.size, tokenDecimals));
                return;
              }
              if (parsed === node.size || parsed === lastQueued.current) {
                return;
              }
              lastQueued.current = parsed;
              onQueueSize(parsed);
            }}
          />
          <div className="flex items-center gap-2">
            {onQueueSwapPrev && (
              <button
                type="button"
                className="button-base whitespace-nowrap"
                onClick={(event) => {
                  event.stopPropagation();
                  onQueueSwapPrev();
                }}
              >
                Swap {orientation === "horizontal" ? "Left" : "Up"}
              </button>
            )}
            {onQueueSwapNext && (
              <button
                type="button"
                className="button-base whitespace-nowrap"
                onClick={(event) => {
                  event.stopPropagation();
                  onQueueSwapNext();
                }}
              >
                Swap {orientation === "horizontal" ? "Right" : "Down"}
              </button>
            )}
          </div>
        </div>

        {node.depth === 1 && node.children.length > 0 && (
          <div className="mt-3">
            <p className="text-[10px] uppercase tracking-[0.2em] text-ink-subtle">Networks</p>
            <div className="mt-2 flex gap-2 overflow-x-auto pb-2">
              {node.children.map((child) => {
                const childIdx = childIndexOf(child.index, child.depth);
                const previewOperators = child.children.slice(0, 3);
                return (
                  <button
                    key={child.index.toString()}
                    type="button"
                    className="min-w-[140px] rounded-xl border border-sand-200 bg-white/80 px-3 py-2 text-left text-xs transition hover:border-black/35"
                    onClick={(event) => {
                      event.stopPropagation();
                      onSelectChild?.(child.index);
                    }}
                  >
                    <div className="flex items-center justify-between">
                      <span className="tag tag-teal">Net {childIdx}</span>
                    </div>
                    <div className="mt-2">
                      <div className="mono text-[11px] text-ink">
                        Avail {formatToken(child.metrics.available, tokenDecimals)}
                      </div>
                      <div className="mono text-[11px] text-ink">
                        Alloc {formatToken(child.metrics.allocated, tokenDecimals)}
                      </div>
                    </div>
                    <div className="mt-2 border-t border-sand-200 pt-1">
                      <p className="text-[10px] uppercase tracking-[0.16em] text-ink-subtle">Operators</p>
                      {previewOperators.length > 0 ? (
                        <div className="mt-1 space-y-1">
                          {previewOperators.map((operatorNode) => (
                            <div key={operatorNode.index.toString()} className="mono text-[10px] text-ink-muted">
                              Op {childIndexOf(operatorNode.index, operatorNode.depth)}:{" "}
                              {operatorNode.operator ? formatAddress(operatorNode.operator) : "-"}
                            </div>
                          ))}
                          {child.children.length > previewOperators.length && (
                            <div className="mono text-[10px] text-ink-subtle">
                              +{child.children.length - previewOperators.length} more
                            </div>
                          )}
                        </div>
                      ) : (
                        <div className="mono text-[10px] text-ink-subtle">None</div>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {node.depth === 2 && node.children.length > 0 && (
          <div className="mt-3">
            <p className="text-[10px] uppercase tracking-[0.2em] text-ink-subtle">Operators</p>
            <div className="mt-2 flex gap-2 overflow-x-auto pb-2">
              {node.children.map((child) => {
                const childIdx = childIndexOf(child.index, child.depth);
                return (
                  <button
                    key={child.index.toString()}
                    type="button"
                    className="min-w-[170px] rounded-xl border border-sand-200 bg-white/80 px-3 py-2 text-left text-xs transition hover:border-black/35"
                    onClick={(event) => {
                      event.stopPropagation();
                      onSelectChild?.(child.index);
                    }}
                  >
                    <div className="flex items-center justify-between">
                      <span className="tag tag-ember">Op {childIdx}</span>
                    </div>
                    <div className="mt-2 mono text-[11px] text-ink-muted">
                      {child.operator ? formatAddress(child.operator) : "-"}
                    </div>
                    <div className="mt-1 mono text-[11px] text-ink">
                      Alloc {formatToken(child.metrics.allocated, tokenDecimals)}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}
        {onQueueRemove && (
          <button
            type="button"
            className="button-base button-outline absolute right-2 top-2 z-10 h-7 w-7 p-0"
            onClick={(event) => {
              event.stopPropagation();
              onQueueRemove();
            }}
            aria-label="Remove slot"
            title="Remove slot"
          >
            ×
          </button>
        )}
      </div>

      <div className="mt-auto" />
    </div>
  );
}
