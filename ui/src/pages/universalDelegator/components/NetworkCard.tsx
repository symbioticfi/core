import type { MouseEvent, ReactNode } from "react";

import type { NetworkSlot } from "../logic";
import { SlotIndexBadge } from "./SlotIndexBadge";
import { SlotBalances, SlotFill } from "./SlotVisuals";

type NetworkCardProps = {
  network: NetworkSlot;
  networkIndex?: bigint;
  allocatedPct: number;
  pendingPct: number;
  allocatedDisplay: string;
  pendingDisplay: string;
  isShared: boolean;
  isFocused: boolean;
  isHovered: boolean;
  zoomable: boolean;
  networkGrow: number;
  networkWidthPct: number;
  sizeInvalid: boolean;
  subnetworkInvalid: boolean;
  onCopyIndex: (index: bigint) => void;
  onSubnetworkChange: (value: string) => void;
  onSizeChange: (value: string) => void;
  onCardClick: (event: MouseEvent<HTMLDivElement>) => void;
  onCardHover: (event: MouseEvent<HTMLDivElement>) => void;
  onCardLeave: () => void;
  children: ReactNode;
};

export function NetworkCard(props: NetworkCardProps) {
  const draft = props.network.state.draft;
  const baseClass = props.isShared
    ? "card bg-base-200 border shadow relative overflow-hidden transition-colors"
    : "card shrink-0 min-w-[18rem] bg-base-200 border shadow relative overflow-hidden transition-colors";
  const borderClass = props.zoomable ? (props.isHovered ? "border-white" : "border-base-300") : "border-base-300";
  const cursorClass = props.zoomable ? (props.isFocused ? "cursor-zoom-out" : "cursor-zoom-in") : "";

  return (
    <div
      data-network-card
      className={`${baseClass} ${borderClass} ${cursorClass}`}
      style={props.isShared ? { width: `${props.networkWidthPct}%` } : { flexGrow: props.networkGrow, flexBasis: 0 }}
      onClick={props.onCardClick}
      onMouseMove={props.onCardHover}
      onMouseLeave={props.onCardLeave}
    >
      <SlotFill allocatedPct={props.allocatedPct} pendingPct={props.pendingPct} colorVar="--color-secondary" />
      <div className="card-body relative z-10 gap-3">
        <div className="grid grid-cols-[minmax(0,1fr)_minmax(4.5rem,6rem)] items-start gap-3">
          <div className="min-w-0 overflow-hidden">
            <div className="flex items-center gap-2 min-w-0 flex-wrap">
              {props.networkIndex !== undefined ? (
                <SlotIndexBadge index={props.networkIndex} onCopy={props.onCopyIndex} />
              ) : null}
              <div className="font-semibold">Network</div>
            </div>
            <SlotBalances allocated={props.allocatedDisplay} pending={props.pendingDisplay} />
            <input
              className={[
                "input input-bordered input-sm font-mono mt-2 w-full max-w-[66ch]",
                props.subnetworkInvalid ? "input-error" : "",
              ].join(" ")}
              placeholder="0x…"
              value={draft.subnetwork}
              onChange={(e) => props.onSubnetworkChange(e.target.value)}
            />
          </div>

          <label className="form-control w-full min-w-0 overflow-hidden">
            <div className="label py-0">
              <span className="label-text text-xs">Size</span>
            </div>
            <input
              className={["input input-bordered input-sm w-full min-w-0", props.sizeInvalid ? "input-error" : ""].join(
                " ",
              )}
              value={draft.size}
              onChange={(e) => props.onSizeChange(e.target.value)}
            />
          </label>
        </div>

        {props.children}
      </div>
    </div>
  );
}
