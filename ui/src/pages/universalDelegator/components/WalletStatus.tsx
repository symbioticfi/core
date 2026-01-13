type WalletStatusProps = {
  authenticated: boolean;
  walletConnected: boolean;
  shortAccountAddress: string;
  accountAddress?: string | null;
  chainLabel: string;
  actionClass: string;
  onLogin: () => void;
  onLogout: () => void;
};

export function WalletStatus(props: WalletStatusProps) {
  return (
    <div className="flex-none flex items-center gap-3">
      <div className="hidden sm:flex flex-col gap-1 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-xs shadow-sm">
        <div className="flex items-center gap-2 text-[11px] uppercase tracking-wide text-base-content/60">
          <span className={`h-2 w-2 rounded-full ${props.walletConnected ? "bg-success" : "bg-warning"}`} />
          <span>{props.walletConnected ? "Wallet connected" : "Wallet disconnected"}</span>
        </div>
        {props.walletConnected ? (
          <div className="flex items-center gap-2">
            <span className="font-mono text-xs" title={props.accountAddress ?? undefined}>
              {props.shortAccountAddress}
            </span>
            <span className="badge badge-sm border-base-300/80 bg-base-100">{props.chainLabel}</span>
          </div>
        ) : null}
      </div>
      {props.authenticated ? (
        <button className={`btn btn-outline btn-sm min-w-[92px] ${props.actionClass}`} onClick={props.onLogout}>
          Disconnect
        </button>
      ) : (
        <button className={`btn btn-primary btn-sm min-w-[92px] ${props.actionClass}`} onClick={props.onLogin}>
          Connect
        </button>
      )}
    </div>
  );
}
