import type { Op } from "../lib/ops";
import { encodeOp, summarizeOp } from "../lib/ops";
import { formatToken } from "../lib/format";

export type OpsListProps = {
  ops: Op[];
  tokenDecimals?: number;
};

export function OpsList({ ops, tokenDecimals }: OpsListProps) {
  if (ops.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-sand-300 bg-white/70 p-6 text-sm text-ink-subtle">
        No ops queued. Use the controls to model changes before running multicall.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      {ops.map((op, idx) => (
        <div key={op.id} className="rounded-2xl border border-sand-200 bg-white/80 p-4 shadow-panel">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Op {idx + 1}</p>
              <p className="font-display text-base text-ink">
                {summarizeOp(op, (value) => formatToken(value, tokenDecimals))}
              </p>
            </div>
            <div />
          </div>
          <div className="mt-3 rounded-xl border border-sand-200 bg-sand-50 p-3">
            <p className="text-xs text-ink-subtle">Calldata</p>
            <p className="mt-1 break-all font-mono text-xs text-ink">{encodeOp(op)}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
