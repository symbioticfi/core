import { useMemo } from "react";

export type TxStatus = {
  state: "idle" | "pending" | "confirming" | "success" | "error";
  show: boolean;
  message: string;
  tone: "info" | "success" | "error";
};

type TxStatusParams = {
  isPending: boolean;
  isConfirming: boolean;
  isConfirmed: boolean;
  error?: { message?: string } | null;
};

export function useTxStatus(params: TxStatusParams): TxStatus {
  return useMemo(() => {
    if (params.error) {
      return {
        state: "error",
        show: true,
        message: params.error.message ?? "Transaction failed.",
        tone: "error",
      };
    }
    if (params.isConfirmed) {
      return { state: "success", show: true, message: "Confirmed", tone: "success" };
    }
    if (params.isConfirming) {
      return { state: "confirming", show: true, message: "Waiting for confirmation...", tone: "info" };
    }
    if (params.isPending) {
      return { state: "pending", show: true, message: "Waiting for wallet approval...", tone: "info" };
    }
    return { state: "idle", show: false, message: "", tone: "info" };
  }, [params.error, params.isConfirmed, params.isConfirming, params.isPending]);
}
