import childProcess from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import solc from "solc";
import {
  type Abi,
  type Address,
  type Hex,
  type PublicClient,
  type Transport,
  type WalletClient,
  createPublicClient,
  createWalletClient,
  http,
} from "viem";
import { mnemonicToAccount, type HDAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { beforeAll, afterAll, describe, expect, it, vi } from "vitest";

import { HintSDK, defaults } from "../src/index.js";

vi.setConfig({ testTimeout: 30000 });

const ANVIL_PORT = 9545;
const RPC_URL = `http://127.0.0.1:${ANVIL_PORT}`;
const MNEMONIC = "test test test test test test test test test test test junk";
const SUBNETWORK = `0x${"00".repeat(31)}01` as Hex;

type FoundryWalletClient = WalletClient<Transport, typeof foundry, HDAccount>;
type FoundryPublicClient = PublicClient<Transport, typeof foundry>;

type Compiled = { abi: Abi; bytecode: Hex };

function compileContract(name: string, source: string): Compiled {
  const input = {
    language: "Solidity",
    sources: {
      [`${name}.sol`]: { content: source },
    },
    settings: {
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode.object"],
        },
      },
    },
  };

  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const contract = output.contracts[`${name}.sol`][name];
  return {
    abi: contract.abi,
    bytecode: `0x${contract.evm.bytecode.object}` as Hex,
  };
}

async function deployContract(
  wallet: FoundryWalletClient,
  publicClient: FoundryPublicClient,
  compiled: Compiled,
  args: readonly unknown[] = [],
): Promise<Address> {
  const hash = await wallet.deployContract({
    abi: compiled.abi,
    bytecode: compiled.bytecode,
    account: wallet.account!,
    chain: foundry,
    args,
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return receipt.contractAddress as Address;
}

async function waitForAnvil(proc: childProcess.ChildProcess, logBuffer: { data: string[] }): Promise<void> {
  const healthClient: FoundryPublicClient = createPublicClient({ chain: foundry, transport: http(RPC_URL) });

  for (let i = 0; i < 150; i++) {
    if (proc.exitCode !== null) {
      throw new Error(`anvil exited early: ${logBuffer.data.join("")}`);
    }
    try {
      await healthClient.getChainId();
      return;
    } catch {
      /* retry */
    }
    // Intentional await inside loop to keep the retry cadence predictable.
    await delay(100);
  }
  throw new Error(`anvil did not start: ${logBuffer.data.join("")}`);
}

const source = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StubHints {
    bytes public stored;

    constructor(bytes memory hint) {
        stored = hint;
    }

    function activeBalanceOfHints(address, address, uint48) external view returns (bytes memory) { return stored; }
    function stakeHints(address, bytes32, address, uint48) external view returns (bytes memory) { return stored; }
    function slashHints(address, bytes32, address, uint48) external view returns (bytes memory) { return stored; }
    function requestSlashHints(address, bytes32, address, uint48) external view returns (bytes memory) { return stored; }
    function executeSlashHints(address, uint256) external view returns (bytes memory) { return stored; }
    function vetoSlashHints(address, uint256) external view returns (bytes memory) { return stored; }
    function setResolverHints(address, bytes32, uint48) external view returns (bytes memory) { return stored; }
    function optInHint(address, address, address, uint48) external view returns (bytes memory) { return stored; }
}

contract HintConsumer {
    function consumeExpect(bytes memory hint, bytes memory required) external pure returns (uint256) {
        require(keccak256(hint) == keccak256(required), "bad hint");
        return hint.length;
    }
}
`;

describe("HintSDK integration (anvil)", () => {
  const hintValue = "0x1234" as Hex;
  let anvil: childProcess.ChildProcess;
  let wallet: FoundryWalletClient;
  let client: FoundryPublicClient;
  let stubHintsAddress: Address;
  let consumerAddress: Address;
  let consumerAbi: Abi;

  beforeAll(async () => {
    const logBuffer = { data: [] as string[] };
    anvil = childProcess.spawn("anvil", ["-p", `${ANVIL_PORT}`, "--mnemonic", MNEMONIC, "--base-fee", "0", "-q"], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    anvil.stdout?.on("data", (data) => logBuffer.data.push(data.toString()));
    anvil.stderr?.on("data", (data) => logBuffer.data.push(data.toString()));

    await waitForAnvil(anvil, logBuffer);

    const account = mnemonicToAccount(MNEMONIC);
    wallet = createWalletClient({
      account,
      chain: foundry,
      transport: http(RPC_URL),
    }) as FoundryWalletClient;
    client = createPublicClient({
      chain: foundry,
      transport: http(RPC_URL),
    }) as FoundryPublicClient;

    const compiledHints = compileContract("StubHints", source);
    const compiledConsumer = compileContract("HintConsumer", source);

    stubHintsAddress = await deployContract(wallet, client, compiledHints, [hintValue]);
    consumerAddress = await deployContract(wallet, client, compiledConsumer, []);
    consumerAbi = compiledConsumer.abi;
  });

  afterAll(async () => {
    if (anvil && !anvil.killed) {
      anvil.kill("SIGTERM");
    }
    await delay(200);
  });

  it("fetchers surface on-chain hints", async () => {
    const sdk = new HintSDK(client, {
      vaultHints: stubHintsAddress,
      baseDelegatorHints: stubHintsAddress,
      slasherHints: stubHintsAddress,
      vetoSlasherHints: stubHintsAddress,
      optInServiceHints: stubHintsAddress,
    });

    const stakeCandidates = await sdk.stakeCandidates({
      delegator: stubHintsAddress,
      subnetwork: SUBNETWORK,
      operator: stubHintsAddress,
      timestamp: 1,
    });

    expect(stakeCandidates.find((c) => c.label === "delegator-hints")).toEqual({
      label: "delegator-hints",
      value: hintValue,
    });

    const vetoCandidates = await sdk.vetoSlashRequestCandidates({
      slasher: stubHintsAddress,
      subnetwork: SUBNETWORK,
      operator: stubHintsAddress,
      captureTimestamp: 1,
    });
    expect(vetoCandidates[0]).toEqual({ label: "veto-requestSlashHints", value: hintValue });

    const resolverCandidates = await sdk.resolverCandidates({
      slasher: stubHintsAddress,
      subnetwork: SUBNETWORK,
      timestamp: 1,
    });
    expect(resolverCandidates[0]).toEqual({ label: "veto-setResolverHints", value: hintValue });

    const optInCandidates = await sdk.optInCandidates({
      optInService: stubHintsAddress,
      who: stubHintsAddress,
      where: stubHintsAddress,
      timestamp: 1,
    });
    expect(optInCandidates[0]).toEqual({ label: "opt-in-hints", value: hintValue });
  });

  it("selectBestHint succeeds against a real contract call", async () => {
    const sdk = new HintSDK(client, {
      baseDelegatorHints: stubHintsAddress,
    });
    const candidates = await sdk.stakeCandidates({
      delegator: stubHintsAddress,
      subnetwork: SUBNETWORK,
      operator: stubHintsAddress,
      timestamp: 1,
    });

    const selection = await sdk.selectBestHint({
      candidates,
      buildCall: (hint) => ({
        address: consumerAddress,
        abi: consumerAbi,
        functionName: "consumeExpect",
        args: [hint, hintValue],
        account: wallet.account!,
        chain: foundry,
      }),
    });

    expect(selection.best?.candidate.value).toBe(hintValue);
    expect(selection.best?.success).toBe(true);
    expect(selection.best?.result).toBe(2n); // consumeExpect returns hint.length (bytes)
    expect(selection.evaluations.some((ev) => !ev.success)).toBe(true);
  });
});
