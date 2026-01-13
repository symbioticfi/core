import type { Hex } from "viem";

import { formatOp, type UdOperation } from "../logic";
import type { TxStatus } from "../useTxStatus";

type MulticallPanelProps = {
  encodedCallsCount: number;
  selectedCandidateLabel: string;
  primaryCandidateLabel: string;
  isValidatingMulticall: boolean;
  canExecute: boolean;
  isPending: boolean;
  onExecute: () => void;
  multicallWarning: string | null;
  txHash: Hex | null | undefined;
  txStatus: TxStatus;
  selectedOps: UdOperation[];
  multicallErrorOp: { index: number; op: UdOperation } | null;
  multicallError: string | null;
  multicallCalldata: string | null;
  onCopyCalldata: () => void;
  hoverActionClass: string;
};

export function MulticallPanel(props: MulticallPanelProps) {
  const statusToneClass =
    props.txStatus.tone === "error" ? "text-error" : props.txStatus.tone === "success" ? "text-success" : "";

  return (
    <div className="card bg-base-200 shadow">
      <div className="card-body gap-3">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold">Multicall</div>
            <div className="text-xs opacity-70">{props.encodedCallsCount} call(s) queued</div>
            <div className="text-xs opacity-70">
              Strategy: {props.selectedCandidateLabel}
              {props.selectedCandidateLabel !== props.primaryCandidateLabel ? " (fallback)" : null}
            </div>
          </div>
          <div className="flex items-center gap-3">
            {props.isValidatingMulticall ? (
              <div className="text-xs opacity-70 whitespace-nowrap">Validating multicall against on-chain state...</div>
            ) : null}
            <button className="btn btn-primary btn-sm" disabled={!props.canExecute} onClick={props.onExecute}>
              {props.isPending ? "Submitting..." : "Execute"}
            </button>
          </div>
        </div>

        {props.multicallWarning ? (
          <div className="alert alert-warning text-xs">
            <span>{props.multicallWarning}</span>
          </div>
        ) : null}

        {props.txStatus.show ? (
          <div className="rounded-lg bg-base-100 p-3 text-sm">
            {props.txHash ? <div className="font-mono text-xs break-all">{props.txHash}</div> : null}
            <div className={`mt-2 ${statusToneClass}`}>{props.txStatus.message}</div>
          </div>
        ) : null}

        <div className="divider my-0">Ops</div>
        <div className="max-h-[28rem] overflow-auto rounded-lg bg-base-100 p-3">
          {props.selectedOps.length === 0 ? (
            <div className="text-sm opacity-70">No operations yet.</div>
          ) : (
            <ol className="list-decimal pl-4 text-xs font-mono">
              {props.selectedOps.map((op, i) => (
                <li
                  key={i}
                  className={`mb-1 ${
                    props.multicallErrorOp && props.multicallErrorOp.index === i ? "text-error font-semibold" : ""
                  }`}
                >
                  {formatOp(op)}
                </li>
              ))}
            </ol>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            className={`btn btn-ghost btn-sm ${props.hoverActionClass}`}
            disabled={!props.multicallCalldata}
            onClick={props.onCopyCalldata}
          >
            Copy Calldata
          </button>
          {props.multicallError ? <div className="ml-auto text-right text-xs text-error">{props.multicallError}</div> : null}
        </div>
      </div>
    </div>
  );
}
