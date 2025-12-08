# Symbiotic hints SDK (TS)

Small helper layer around the on-chain hint contracts to make it easy to fetch, combine, and test hint payloads from TypeScript. It relies on `viem` for RPC interactions and uses simulations to pick the cheapest working hint.

## Quick start

```ts
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { HintSDK } from "@symbioticfi/hints-sdk";
import { slasherAbi } from "./abi/Slasher"; // consumer-provided ABI

const client = createPublicClient({ chain: mainnet, transport: http(process.env.RPC_URL!) });

const hints = new HintSDK(client, {
  slasherHints: "0xSlasherHints",
  baseDelegatorHints: "0xBaseDelegatorHints",
  vaultHints: "0xVaultHints"
});

const candidates = await hints.slashCandidates({
  slasher: "0xSlasher",
  subnetwork: "0xSubnetworkBytes32",
  operator: "0xOperator",
  captureTimestamp: BigInt(Math.floor(Date.now() / 1000))
});

const selection = await hints.selectBestHint({
  candidates,
  buildCall: (hint) => ({
    address: "0xSlasher",
    abi: slasherAbi,
    functionName: "slash",
    args: ["0xSubnetworkBytes32", "0xOperator", 1_000_000n, BigInt(Math.floor(Date.now() / 1000)), hint],
    account: "0xCaller"
  })
});

console.log("best hint", selection.best?.candidate.label, selection.best?.gas?.toString());
```

## What it does

- Fetches hints from the deployed helpers in `src/contracts/hints` (vault, delegators, slasher, veto slasher, opt-in).
- Adds the default `0x` fallback so that empty bytes can be compared against on-chain hints.
- Runs `simulateContract` + `estimateContractGas` for each candidate and picks the lowest-gas successful option.

You can also bypass the prebuilt fetchers and call `selectBestHint` directly with your own candidate list if you want to try custom combinations (e.g., mixing nested structs or precomputed hints).

## Available fetchers

- `vaultActiveBalanceOfCandidates`
- `stakeCandidates`
- `slashCandidates`
- `vetoSlashRequestCandidates` / `vetoSlashExecuteCandidates` / `vetoSlashVetoCandidates` / `vetoSlashResolverCandidates`
- `resolverCandidates` (alias of `vetoSlashResolverCandidates`)
- `optInCandidates`
- `defaultStakerRewardsDistributeCandidates` (builds the `data` payload with activeShares/activeStake hints)
- `defaultStakerRewardsClaimCandidates` (builds the `data` payload with per-reward activeSharesOf hints)

Each fetcher returns an ordered array of `{ label, value }` that you can feed into `selectBestHint`.
