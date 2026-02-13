import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePrivy, useWallets } from "@privy-io/react-auth";
import { useSetActiveWallet } from "@privy-io/wagmi";
import { useAccount, useWalletClient } from "wagmi";
import {
  decodeErrorResult,
  getAddress,
  publicActions,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";
import { universalDelegatorAbi } from "./abi/universalDelegator";
import { vaultV2Abi } from "./abi/vaultV2";
import { erc20Abi } from "./abi/erc20";
import { Breadcrumbs } from "./components/Breadcrumbs";
import { ContextPanel } from "./components/ContextPanel";
import { OpsList } from "./components/OpsList";
import { SimulationPanel, type SimulationState } from "./components/SimulationPanel";
import { SlotBoard } from "./components/SlotBoard";
import { TopBar } from "./components/TopBar";
import { formatIndex } from "./lib/format";
import {
  applyOps,
  encodeMulticall,
  encodeOp,
  type Metrics,
  type Op,
  type SlotNode,
} from "./lib/ops";
import { encodeOperator, encodeSubnetwork } from "./lib/subnetwork";
import { WITHDRAWAL_BUFFER_CHILD_INDEX, createIndex } from "./lib/indexing";

const STANDARD_ERRORS = [
  {
    type: "error",
    name: "Error",
    inputs: [{ name: "message", type: "string" }],
  },
  {
    type: "error",
    name: "Panic",
    inputs: [{ name: "code", type: "uint256" }],
  },
] as const;

const SUPPORTED_CHAIN_IDS = new Set([1, 11155111, 17000, 31337]);

type SlotSnapshot = {
  exists: boolean;
  nextSlot: number;
  prevSlot: number;
  totalChildren: number;
  existChildren: number;
  firstChild: number;
  lastChild: number;
  isShared: boolean;
  noPlugins: boolean;
  size: bigint;
  prevSum: bigint;
  subnetworkOrOperator: Hex;
};

function normalizeSlot(slot: any): SlotSnapshot {
  return {
    exists: Boolean(slot.exists),
    nextSlot: Number(slot.nextSlot),
    prevSlot: Number(slot.prevSlot),
    totalChildren: Number(slot.totalChildren),
    existChildren: Number(slot.existChildren),
    firstChild: Number(slot.firstChild),
    lastChild: Number(slot.lastChild),
    isShared: Boolean(slot.isShared),
    noPlugins: Boolean(slot.noPlugins),
    size: BigInt(slot.size ?? 0),
    prevSum: BigInt(slot.prevSum ?? 0),
    subnetworkOrOperator: slot.subnetworkOrOperator as Hex,
  };
}

function findPath(root: SlotNode, target: bigint): SlotNode[] | null {
  if (root.index === target) {
    return [root];
  }
  for (const child of root.children) {
    const result = findPath(child, target);
    if (result) {
      return [root, ...result];
    }
  }
  return null;
}

function extractErrorData(error: unknown): Hex | undefined {
  const err = error as any;
  return (
    err?.data ??
    err?.cause?.data ??
    err?.details?.data ??
    err?.error?.data ??
    err?.cause?.error?.data
  );
}

function extractErrorMessage(error: unknown): string | undefined {
  const err = error as any;
  return err?.shortMessage ?? err?.message ?? err?.cause?.message;
}

function buildMetrics(values: {
  allocated: bigint;
  pending: bigint;
  available: bigint;
  balance: bigint;
  childrenPending: bigint;
}): Metrics {
  return { ...values };
}

export default function App() {
  const { authenticated, login, logout } = usePrivy();
  const { wallets } = useWallets();
  const { setActiveWallet } = useSetActiveWallet();
  const { address, chainId } = useAccount();
  const { data: walletClient } = useWalletClient();

  const [delegatorInput, setDelegatorInput] = useState("");
  const [delegatorAddress, setDelegatorAddress] = useState<Address | undefined>();
  const [vaultAddress, setVaultAddress] = useState<Address | undefined>();
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [rootTree, setRootTree] = useState<SlotNode | null>(null);
  const [focusIndex, setFocusIndex] = useState<bigint>(0n);
  const [ops, setOps] = useState<Op[]>([]);

  const [vaultInfo, setVaultInfo] = useState<{
    epochDuration?: bigint;
    allocatable?: bigint;
    activeStake?: bigint;
    activeWithdrawals?: bigint;
    noPluginsSize?: bigint;
    withdrawalBuffer?: bigint;
    collateral?: Address;
    slasher?: Address;
    collateralDecimals?: number;
  }>({});

  const [simulation, setSimulation] = useState<SimulationState>({ status: "idle" });
  const [txHash, setTxHash] = useState<string | undefined>();

  const opCounter = useRef(0);

  const supportedChain = chainId ? SUPPORTED_CHAIN_IDS.has(chainId) : true;
  const chainName = supportedChain
    ? chainId === 1
      ? "Mainnet"
      : chainId === 11155111
        ? "Sepolia"
        : chainId === 17000
          ? "Holesky"
          : chainId === 31337
            ? "Anvil"
          : "Unknown"
    : "Unsupported";

  const publicClient = useMemo(() => {
    if (!walletClient) {
      return null;
    }
    return walletClient.extend(publicActions) as PublicClient;
  }, [walletClient]);

  useEffect(() => {
    if (!authenticated || wallets.length === 0 || address) {
      return;
    }
    setActiveWallet(wallets[0]).catch(() => {
      // Ignore auto-activation errors; user can retry via wallet connect.
    });
  }, [authenticated, wallets, address, setActiveWallet]);

  const nextOpId = () => {
    opCounter.current += 1;
    return `op-${Date.now()}-${opCounter.current}`;
  };

  const readContract = useCallback(
    async ({
      address,
      abi,
      functionName,
      args,
    }: {
      address: Address;
      abi: any;
      functionName: string;
      args?: readonly unknown[];
    }) => {
      if (!publicClient) {
        throw new Error("Wallet client unavailable");
      }
      return publicClient.readContract({ address, abi, functionName, args });
    },
    [publicClient]
  );

  const buildTree = useCallback(
    async (index: bigint, delegator: Address, depth = 0): Promise<SlotNode> => {
      const slotRaw = await readContract({
        address: delegator,
        abi: universalDelegatorAbi,
        functionName: "getSlot",
        args: [index],
      });
      const slot = normalizeSlot(slotRaw);

      let allocated: bigint;
      let pending: bigint;
      let available: bigint;
      let balance: bigint;
      let childrenPending: bigint;

      if (index === 0n) {
        [pending, available, balance, childrenPending] = (await Promise.all([
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getPending",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getAvailable",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getBalance",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getChildrenPending",
            args: [index, 0],
          }),
        ])) as [bigint, bigint, bigint, bigint];
        allocated = balance;
      } else {
        [allocated, pending, available, balance, childrenPending] = (await Promise.all([
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getAllocated",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getPending",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getAvailable",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getBalance",
            args: [index, 0],
          }),
          readContract({
            address: delegator,
            abi: universalDelegatorAbi,
            functionName: "getChildrenPending",
            args: [index, 0],
          }),
        ])) as [bigint, bigint, bigint, bigint, bigint];
      }

      const node: SlotNode = {
        index,
        depth,
        size: slot.size,
        isShared: slot.isShared,
        noPlugins: slot.noPlugins,
        totalChildren: slot.totalChildren,
        existChildren: slot.existChildren,
        firstChild: slot.firstChild,
        lastChild: slot.lastChild,
        nextSlot: slot.nextSlot,
        prevSlot: slot.prevSlot,
        children: [],
        metrics: buildMetrics({
          allocated: BigInt(allocated ?? 0),
          pending: BigInt(pending ?? 0),
          available: BigInt(available ?? 0),
          balance: BigInt(balance ?? 0),
          childrenPending: BigInt(childrenPending ?? 0),
        }),
      };

      const subHex = slot.subnetworkOrOperator === "0x" ? "0x0" : slot.subnetworkOrOperator;
      const subValue = BigInt(subHex);
      if (depth === 2 && subValue !== 0n) {
        const network = getAddress(`0x${(subValue >> 96n).toString(16).padStart(40, "0")}`);
        const identifier = subValue & ((1n << 96n) - 1n);
        node.subnetwork = {
          network,
          identifier,
          bytes32: slot.subnetworkOrOperator,
        };
      }

      if (depth === 3 && subValue !== 0n) {
        const raw = subValue & ((1n << 160n) - 1n);
        node.operator = getAddress(`0x${raw.toString(16).padStart(40, "0")}`);
      }

      let childLocal = slot.firstChild;
      let guard = 0;
      while (childLocal !== 0 && childLocal !== WITHDRAWAL_BUFFER_CHILD_INDEX && guard < 128) {
        const childIndex = createIndex(index, childLocal);
        const childNode = await buildTree(childIndex, delegator, depth + 1);
        node.children.push(childNode);
        childLocal = childNode.nextSlot;
        guard += 1;
      }

      return node;
    },
    [readContract]
  );

  const loadDelegator = useCallback(async () => {
    if (!delegatorInput.trim()) {
      return;
    }
    if (!walletClient) {
      setLoadError("Wallet client unavailable. Connect a wallet and try again.");
      return;
    }
    setLoading(true);
    setLoadError(null);
    setSimulation({ status: "idle" });

    try {
      const delegator = getAddress(delegatorInput.trim());
      const tree = await buildTree(0n, delegator, 0);
      const [vault, noPluginsSize, withdrawalBuffer] = await Promise.all([
        readContract({
          address: delegator,
          abi: universalDelegatorAbi,
          functionName: "vault",
        }),
        readContract({
          address: delegator,
          abi: universalDelegatorAbi,
          functionName: "getNoPluginsSize",
        }),
        readContract({
          address: delegator,
          abi: universalDelegatorAbi,
          functionName: "getWithdrawalBuffer",
        }),
      ]);

      const vaultAddr = getAddress(vault as Address);
      const [epochDuration, allocatable, activeStake, activeWithdrawals, collateral, slasher] =
        await Promise.all([
          readContract({ address: vaultAddr, abi: vaultV2Abi, functionName: "epochDuration" }),
          readContract({ address: vaultAddr, abi: vaultV2Abi, functionName: "allocatable" }),
          readContract({ address: vaultAddr, abi: vaultV2Abi, functionName: "activeStake" }),
          readContract({
            address: vaultAddr,
            abi: vaultV2Abi,
            functionName: "activeWithdrawalsFor",
            args: [0],
          }),
          readContract({ address: vaultAddr, abi: vaultV2Abi, functionName: "collateral" }),
          readContract({ address: vaultAddr, abi: vaultV2Abi, functionName: "slasher" }),
        ]);

      let collateralDecimals: number | undefined;
      try {
        collateralDecimals = Number(
          await readContract({
            address: collateral as Address,
            abi: erc20Abi,
            functionName: "decimals",
          })
        );
      } catch {
        collateralDecimals = undefined;
      }

      setDelegatorAddress(delegator);
      setVaultAddress(vaultAddr);
      setVaultInfo({
        epochDuration: BigInt(epochDuration ?? 0),
        allocatable: BigInt(allocatable ?? 0),
        activeStake: BigInt(activeStake ?? 0),
        activeWithdrawals: BigInt(activeWithdrawals ?? 0),
        noPluginsSize: BigInt(noPluginsSize ?? 0),
        withdrawalBuffer: BigInt(withdrawalBuffer ?? 0),
        collateral: collateral as Address,
        slasher: slasher as Address,
        collateralDecimals,
      });

      setRootTree(tree);
      setFocusIndex(0n);
      setOps([]);
    } catch (error) {
      setLoadError(extractErrorMessage(error) ?? "Failed to load delegator");
    } finally {
      setLoading(false);
    }
  }, [walletClient, delegatorInput, buildTree, readContract]);

  const workingTree = useMemo(() => applyOps(rootTree, ops), [rootTree, ops]);

  const focusPath = useMemo(() => {
    if (!workingTree) {
      return [];
    }
    return findPath(workingTree, focusIndex) ?? [workingTree];
  }, [workingTree, focusIndex]);

  const focusNode = focusPath[focusPath.length - 1] ?? null;

  useEffect(() => {
    if (!workingTree) {
      return;
    }
    const path = findPath(workingTree, focusIndex);
    if (!path) {
      setFocusIndex(0n);
    }
  }, [workingTree, focusIndex]);

  const queueSetSize = (index: bigint, size: bigint) => {
    setOps((prev) => [...prev, { id: nextOpId(), kind: "setSize", index, size }]);
  };

  const queueSwap = (index1: bigint, index2: bigint) => {
    setOps((prev) => [...prev, { id: nextOpId(), kind: "swapSlots", index1, index2 }]);
  };

  const queueRemove = (index: bigint) => {
    setOps((prev) => [...prev, { id: nextOpId(), kind: "removeSlot", index }]);
  };

  const queueCreateGroup = (size: bigint, isShared: boolean, noPlugins: boolean) => {
    setOps((prev) => [
      ...prev,
      {
        id: nextOpId(),
        kind: "createSlot",
        parentIndex: 0n,
        subnetworkOrOperator: "0x".padEnd(66, "0") as Hex,
        isShared,
        noPlugins,
        size,
      },
    ]);
  };

  const queueCreateNetwork = (network: Address, identifier: bigint, size: bigint) => {
    if (!focusNode || focusNode.depth !== 1) {
      return;
    }
    setOps((prev) => [
      ...prev,
      {
        id: nextOpId(),
        kind: "createSlot",
        parentIndex: focusNode.index,
        subnetworkOrOperator: encodeSubnetwork(network, identifier),
        isShared: false,
        noPlugins: false,
        size,
      },
    ]);
  };

  const queueCreateOperator = (operator: Address, size: bigint) => {
    if (!focusNode || focusNode.depth !== 2) {
      return;
    }
    setOps((prev) => [
      ...prev,
      {
        id: nextOpId(),
        kind: "createSlot",
        parentIndex: focusNode.index,
        subnetworkOrOperator: encodeOperator(operator),
        isShared: false,
        noPlugins: false,
        size,
      },
    ]);
  };

  const queueWithdrawalBuffer = (size: bigint) => {
    setOps((prev) => [...prev, { id: nextOpId(), kind: "setWithdrawalBufferSize", size }]);
  };


  const simulateMulticall = async () => {
    if (!walletClient || !delegatorAddress || ops.length === 0) {
      return;
    }
    setSimulation({ status: "running" });

    const simulatePrefix = async (count: number) => {
      const data = encodeMulticall(ops.slice(0, count));
      try {
        const callParams: Record<string, unknown> = { to: delegatorAddress, data };
        if (address) {
          callParams.from = address;
        }
        await walletClient.request({
          method: "eth_call",
          params: [callParams, "latest"],
        });
        return { ok: true } as const;
      } catch (error) {
        return {
          ok: false,
          data: extractErrorData(error),
          message: extractErrorMessage(error),
        } as const;
      }
    };

    const full = await simulatePrefix(ops.length);
    if (full.ok) {
      setSimulation({ status: "success" });
      return;
    }

    let left = 1;
    let right = ops.length;
    let firstFail = ops.length;
    let failureData: Hex | undefined;
    let failureMessage: string | undefined;

    while (left <= right) {
      const mid = Math.floor((left + right) / 2);
      const res = await simulatePrefix(mid);
      if (res.ok) {
        left = mid + 1;
      } else {
        firstFail = mid;
        failureData = res.data;
        failureMessage = res.message;
        right = mid - 1;
      }
    }

    let errorName: string | undefined;
    if (failureData) {
      try {
        const decoded = decodeErrorResult({
          abi: [...universalDelegatorAbi, ...STANDARD_ERRORS],
          data: failureData,
        });
        errorName = decoded.errorName;
      } catch {
        errorName = undefined;
      }
    }

    setSimulation({
      status: "error",
      error: {
        opIndex: firstFail - 1,
        name: errorName,
        data: failureData,
        message: failureMessage,
      },
    });
  };

  const executeMulticall = async () => {
    if (!walletClient || !delegatorAddress || ops.length === 0) {
      return;
    }
    try {
      const hash = await walletClient.writeContract({
        address: delegatorAddress,
        abi: universalDelegatorAbi,
        functionName: "multicall",
        args: [ops.map(encodeOp)],
      });
      setTxHash(hash);
    } catch (error) {
      setSimulation({
        status: "error",
        error: {
          message: extractErrorMessage(error) ?? "Transaction failed",
          data: extractErrorData(error),
        },
      });
    }
  };

  const copyCalldata = async () => {
    if (ops.length === 0) {
      return;
    }
    await navigator.clipboard.writeText(encodeMulticall(ops));
  };

  return (
    <div className="mx-auto flex max-w-[1400px] flex-col gap-6 px-6 py-8">
      <TopBar
        connected={Boolean(authenticated)}
        address={address as Address}
        chainName={chainName}
        supportedChain={supportedChain}
        onConnect={() => login()}
        onDisconnect={() => logout()}
        delegatorInput={delegatorInput}
        onDelegatorChange={setDelegatorInput}
        onLoad={loadDelegator}
        loading={loading}
        canLoad={Boolean(walletClient)}
      />

      {loadError && (
        <div className="rounded-2xl border border-ember-400/50 bg-ember-400/10 p-3 text-sm text-ink">
          {loadError}
        </div>
      )}

      {!authenticated && (
        <div className="rounded-2xl border border-sand-200 bg-white/70 p-4 text-sm text-ink-subtle">
          Connect a wallet to unlock reads. Wallet RPC is used for both view calls and execution.
        </div>
      )}

      {authenticated && !walletClient && (
        <div className="rounded-2xl border border-sand-200 bg-white/70 p-4 text-sm text-ink-subtle">
          Wallet connected via Privy but wagmi has no active wallet yet. Select a wallet in Privy
          or reconnect to enable reads.
        </div>
      )}

      <ContextPanel
        vault={vaultAddress}
        delegator={delegatorAddress}
        epochDuration={vaultInfo.epochDuration}
        allocatable={vaultInfo.allocatable}
        activeStake={vaultInfo.activeStake}
        activeWithdrawals={vaultInfo.activeWithdrawals}
        noPluginsSize={vaultInfo.noPluginsSize}
        withdrawalBuffer={vaultInfo.withdrawalBuffer}
        collateral={vaultInfo.collateral}
        slasher={vaultInfo.slasher}
        tokenDecimals={vaultInfo.collateralDecimals}
        disabled={!delegatorAddress}
      />

      <div className="panel-surface rounded-2xl p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Slot Tree</p>
            <p className="font-display text-lg text-ink">
              Focus: {focusNode ? (focusNode.depth === 0 ? "Root" : formatIndex(focusNode.index)) : "-"}
            </p>
          </div>
          <Breadcrumbs path={focusPath} onSelect={setFocusIndex} />
        </div>
      </div>

      {workingTree && focusNode ? (
        <SlotBoard
          focus={focusNode}
          onSelect={setFocusIndex}
          onQueueSize={queueSetSize}
          onQueueSwap={queueSwap}
          onQueueRemove={queueRemove}
          onCreateGroup={queueCreateGroup}
          onCreateNetwork={queueCreateNetwork}
          onCreateOperator={queueCreateOperator}
          onSetWithdrawalBuffer={queueWithdrawalBuffer}
          withdrawalBuffer={vaultInfo.withdrawalBuffer}
          tokenDecimals={vaultInfo.collateralDecimals}
          disabled={!delegatorAddress}
        />
      ) : (
        <div className="panel-surface flex min-h-[320px] items-center justify-center rounded-2xl p-6 text-sm text-ink-subtle">
          Load a delegator to render the slot board.
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-[1.2fr_0.8fr]">
        <div className="flex flex-col gap-6">
          <div className="panel-surface rounded-2xl p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Ops</p>
                <p className="font-display text-lg text-ink">Action-first ops list</p>
              </div>
              <span className="tag tag-teal">{ops.length} queued</span>
            </div>
          </div>
          <OpsList ops={ops} tokenDecimals={vaultInfo.collateralDecimals} />
        </div>

        <div className="flex flex-col gap-6">
          <SimulationPanel
            state={simulation}
            onSimulate={simulateMulticall}
            onExecute={executeMulticall}
            onCopy={copyCalldata}
            hasOps={ops.length > 0 && Boolean(delegatorAddress) && Boolean(walletClient)}
            txHash={txHash}
          />

          <div className="panel-surface rounded-2xl p-4">
            <p className="text-xs uppercase tracking-[0.2em] text-ink-subtle">Multicall</p>
            <p className="font-display text-lg text-ink">Encoded calldata</p>
            <div className="mt-3 rounded-xl border border-sand-200 bg-sand-50 p-3">
              <p className="break-all font-mono text-xs text-ink">
                {ops.length > 0 ? encodeMulticall(ops) : "Queue ops to generate multicall data."}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
