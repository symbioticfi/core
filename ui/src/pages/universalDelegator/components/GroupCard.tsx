import type { MouseEvent, ReactNode } from "react";

import type { GroupSlot } from "../logic";
import { SlotIndexBadge } from "./SlotIndexBadge";
import { SlotBalances, SlotFill } from "./SlotVisuals";

type GroupCardProps = {
  group: GroupSlot;
  groupIndex?: bigint;
  allocatedPct: number;
  pendingPct: number;
  allocatedDisplay: string;
  pendingDisplay: string;
  groupGrow: number;
  isFocused: boolean;
  isHovered: boolean;
  sizeInvalid: boolean;
  onCopyIndex: (index: bigint) => void;
  onToggleShared: (next: boolean) => void;
  onSizeChange: (value: string) => void;
  onCardClick: (event: MouseEvent<HTMLDivElement>) => void;
  onCardHover: (event: MouseEvent<HTMLDivElement>) => void;
  onCardLeave: () => void;
  children: ReactNode;
};

export function GroupCard(props: GroupCardProps) {
  const draft = props.group.state.draft;

  return (
    <div
      className={`card shrink-0 min-w-[18rem] bg-base-100 shadow relative overflow-hidden border transition-colors ${
        props.isHovered ? "border-white" : "border-transparent"
      } ${props.isFocused ? "cursor-zoom-out" : "cursor-zoom-in"}`}
      style={{ flexGrow: props.groupGrow, flexBasis: 0 }}
      onClick={props.onCardClick}
      onMouseMove={props.onCardHover}
      onMouseLeave={props.onCardLeave}
    >
      <SlotFill allocatedPct={props.allocatedPct} pendingPct={props.pendingPct} colorVar="--color-primary" />
      <div className="card-body relative z-10 gap-3">
        <div className="grid grid-cols-[minmax(0,1fr)_minmax(6rem,8rem)] items-start gap-3">
          <div className="min-w-0 overflow-hidden">
            <div className="flex items-center gap-2 min-w-0 flex-wrap">
              {props.groupIndex !== undefined ? (
                <SlotIndexBadge index={props.groupIndex} onCopy={props.onCopyIndex} />
              ) : null}
              <div className="font-semibold">Group</div>
            </div>
            <SlotBalances allocated={props.allocatedDisplay} pending={props.pendingDisplay} />
          </div>

          <div className="flex flex-col items-end gap-2 min-w-0">
            <label className="label cursor-pointer gap-2 py-0">
              <span className="label-text text-xs">Shared</span>
              <input
                type="checkbox"
                className="toggle toggle-sm"
                checked={draft.isShared}
                onChange={(e) => props.onToggleShared(e.target.checked)}
              />
            </label>

            <label className="form-control w-full min-w-0">
              <div className="label py-0">
                <span className="label-text text-xs">Size</span>
              </div>
              <input
                className={[
                  "input input-bordered input-sm w-full min-w-0",
                  props.sizeInvalid ? "input-error" : "",
                ].join(" ")}
                value={draft.size}
                onChange={(e) => props.onSizeChange(e.target.value)}
              />
            </label>
          </div>
        </div>

        {props.children}
      </div>
    </div>
  );
}
