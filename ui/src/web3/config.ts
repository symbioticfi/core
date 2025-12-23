import { createConfig } from "@privy-io/wagmi";
import { http } from "wagmi";
import { anvil, mainnet, sepolia } from "wagmi/chains";

const httpTransport = (url?: string) => (url ? http(url) : http());

export const wagmiConfig = createConfig({
  chains: [anvil, sepolia, mainnet],
  batch: {
    multicall: {
      batchSize: 16_384,
      deployless: true,
    },
  },
  transports: {
    [anvil.id]: httpTransport(
      import.meta.env.VITE_ANVIL_RPC_URL ?? import.meta.env.VITE_RPC_URL ?? "http://127.0.0.1:8545",
    ),
    [sepolia.id]: httpTransport(import.meta.env.VITE_SEPOLIA_RPC_URL ?? import.meta.env.VITE_RPC_URL),
    [mainnet.id]: httpTransport(import.meta.env.VITE_MAINNET_RPC_URL ?? import.meta.env.VITE_RPC_URL),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
