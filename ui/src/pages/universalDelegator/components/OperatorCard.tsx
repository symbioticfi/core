import type { OperatorSlot } from "../logic";
import { SlotIndexBadge } from "./SlotIndexBadge";
import { SlotBalances, SlotFill } from "./SlotVisuals";

type OperatorCardProps = {
  operator: OperatorSlot;
  operatorIndex?: bigint;
  allocatedPct: number;
  pendingPct: number;
  allocatedDisplay: string;
  pendingDisplay: string;
  operatorGrow: number;
  sizeInvalid: boolean;
  operatorInvalid: boolean;
  onCopyIndex: (index: bigint) => void;
  onOperatorChange: (value: string) => void;
  onSizeChange: (value: string) => void;
};

export function OperatorCard(props: OperatorCardProps) {
  const draft = props.operator.state.draft;

  return (
    <div
      className="card shrink-0 min-w-[18rem] bg-base-100 border border-base-300 shadow relative overflow-hidden cursor-default"
      style={{ flexGrow: props.operatorGrow, flexBasis: 0 }}
      data-no-zoom
    >
      <SlotFill allocatedPct={props.allocatedPct} pendingPct={props.pendingPct} colorVar="--color-accent" />
      <div className="card-body relative z-10 gap-2">
        <div className="grid grid-cols-[minmax(0,1fr)_minmax(4.5rem,6rem)] items-start gap-3">
          <div className="min-w-0 overflow-hidden">
            <div className="flex items-center gap-2 min-w-0 flex-wrap">
              {props.operatorIndex !== undefined ? (
                <SlotIndexBadge index={props.operatorIndex} onCopy={props.onCopyIndex} />
              ) : null}
              <div className="font-semibold">Operator</div>
            </div>
            <SlotBalances allocated={props.allocatedDisplay} pending={props.pendingDisplay} />
            <input
              className={[
                "input input-bordered input-sm font-mono mt-2 w-full max-w-[42ch]",
                props.operatorInvalid ? "input-error" : "",
              ].join(" ")}
              placeholder="0x…"
              value={draft.operator}
              onChange={(e) => props.onOperatorChange(e.target.value)}
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
      </div>
    </div>
  );
}
