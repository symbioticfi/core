export type SimulationError = {
  opIndex?: number;
  name?: string;
  data?: string;
  message?: string;
};

export type SimulationState = {
  status: "idle" | "running" | "success" | "error";
  error?: SimulationError;
};

export type SimulationPanelProps = {
  state: SimulationState;
  onSimulate: () => void;
  onExecute: () => void;
  onCopy: () => void;
  hasOps: boolean;
  txHash?: string;
};

export function SimulationPanel({
  state,
  onSimulate,
  onExecute,
  onCopy,
  hasOps,
  txHash,
}: SimulationPanelProps) {
  return (
    <div className="flex flex-col gap-3 rounded-2xl border border-sand-200 bg-white/80 p-4 shadow-panel">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Simulation</p>
          <p className="font-display text-base text-ink">Multicall dry run</p>
        </div>
        <div className="flex gap-2">
          <button type="button" className="button-base" onClick={onSimulate} disabled={!hasOps}>
            {state.status === "running" ? "Running" : "Simulate"}
          </button>
          <button type="button" className="button-base button-ember" onClick={onExecute} disabled={!hasOps}>
            Execute
          </button>
          <button type="button" className="button-base" onClick={onCopy} disabled={!hasOps}>
            Copy calldata
          </button>
        </div>
      </div>

      {state.status === "idle" && (
        <p className="text-sm text-ink-subtle">Run a multicall simulation to surface any revert reasons.</p>
      )}

      {state.status === "running" && (
        <p className="text-sm text-ink-subtle">Simulating multicall against the connected wallet RPC.</p>
      )}

      {state.status === "success" && (
        <div className="rounded-xl border border-tide-400/40 bg-tide-400/10 p-3 text-sm text-ink">
          Simulation succeeded. Multicall executed without reverts.
        </div>
      )}

      {state.status === "error" && state.error && (
        <div className="rounded-xl border border-ember-400/50 bg-ember-400/10 p-3 text-sm text-ink">
          <p className="font-semibold">Simulation failed</p>
          {state.error.opIndex !== undefined && (
            <p className="mt-1 text-xs">First failing op: {state.error.opIndex + 1}</p>
          )}
          {state.error.name && <p className="mt-1 text-xs">Error: {state.error.name}</p>}
          {state.error.message && <p className="mt-1 text-xs">Message: {state.error.message}</p>}
          {state.error.data && (
            <p className="mt-2 break-all font-mono text-xs">{state.error.data}</p>
          )}
        </div>
      )}

      {txHash && (
        <div className="rounded-xl border border-sand-300 bg-sand-50 p-3 text-xs text-ink">
          Last tx hash: <span className="mono">{txHash}</span>
        </div>
      )}
    </div>
  );
}
