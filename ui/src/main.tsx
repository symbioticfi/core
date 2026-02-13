import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { PrivyProvider } from "@privy-io/react-auth";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig } from "@privy-io/wagmi";
import { custom, type EIP1193Provider } from "viem";
import { holesky, mainnet, sepolia } from "viem/chains";
import App from "./App";
import "./index.css";

const anvil = {
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://localhost:3000"] },
    public: { http: ["http://localhost:3000"] },
  },
} as const;

const chains = [mainnet, sepolia, holesky, anvil] as const;

const fallbackProvider: EIP1193Provider = {
  request: async () => {
    throw new Error("Wallet provider not available");
  },
};

const transport = () => {
  if (typeof window === "undefined") {
    return custom(fallbackProvider);
  }
  const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum;
  return custom(provider ?? fallbackProvider);
};

const wagmiConfig = createConfig({
  chains,
  transports: Object.fromEntries(chains.map((chain) => [chain.id, transport()])),
  ssr: false,
});

const queryClient = new QueryClient();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <PrivyProvider
        appId={import.meta.env.VITE_PRIVY_APP_ID as string}
        config={{
          appearance: {
            theme: "light",
            accentColor: "#e4572e",
          },
          loginMethods: ["wallet"],
          defaultChain: mainnet,
          supportedChains: chains,
        }}
      >
        <WagmiProvider config={wagmiConfig}>
          <App />
        </WagmiProvider>
      </PrivyProvider>
    </QueryClientProvider>
  </StrictMode>
);
