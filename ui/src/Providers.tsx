import { PrivyProvider } from "@privy-io/react-auth";
import { WagmiProvider } from "@privy-io/wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";

import { wagmiConfig } from "./web3/config";

const queryClient = new QueryClient();

export function Providers({ children }: { children: ReactNode }) {
  const appId = import.meta.env.VITE_PRIVY_APP_ID ?? "cmj9pcima056qjs0chfowelqx";

  return (
    <PrivyProvider appId={appId}>
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>{children}</WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
