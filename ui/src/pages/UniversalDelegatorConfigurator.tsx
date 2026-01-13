import { usePrivy } from "@privy-io/react-auth";
import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent } from "react";
import { useAccount, usePublicClient, useReadContracts, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { type Address, BaseError, type Hex, encodeFunctionData, isAddress } from "viem";

import { universalDelegatorAbi } from "../contracts/universalDelegator";
import { formatIndex, getChildIndex } from "../utils/universalDelegatorIndex";
import { GroupCard } from "./universalDelegator/components/GroupCard";
import { MulticallPanel } from "./universalDelegator/components/MulticallPanel";
import { NetworkCard } from "./universalDelegator/components/NetworkCard";
import { OperatorCard } from "./universalDelegator/components/OperatorCard";
import { StatusBanner } from "./universalDelegator/components/StatusBanner";
import { AddSlotButton } from "./universalDelegator/components/SlotVisuals";
import { WalletStatus } from "./universalDelegator/components/WalletStatus";
import {
  type GroupConstructor,
  type GroupDraft,
  type GroupSlot,
  type MulticallCandidate,
  type NetworkDraft,
  type NetworkSlot,
  type OperatorDraft,
  type OperatorSlot,
  type UdOperation,
  type UniversalDelegatorModel,
  type ZoomState,
  autoSyncAll,
  bigintCompare,
  buildMulticallCandidates,
  cloneModel,
  cloneOps,
  compileOpsFromModels,
  computePendingByIndexFromOps,
  computeSimulatedAllocations,
  computeSimulatedAllocationsWithPending,
  computeSlotIdToIndex,
  describeNotEnoughAvailable,
  effectiveSize,
  encodeOpsToCalls,
  extractRevertName,
  findFailingOp,
  flexGrowFromSize,
  formatOp,
  formatShortAddress,
  formatViemError,
  maxBigint,
  mergeOps,
  opsBaselineModel,
  opsKey,
  orderMulticallCandidates,
  parseBytes32,
  parsePositiveInt,
  parseUint,
  percentWidthFromSize,
  reconstructModelFromChain,
  saturatingSub,
  shallowOptimizeOps,
  simulateMulticall,
  simulateMulticallCandidates,
  sumBigints,
} from "./universalDelegator/logic";
import { useTxStatus } from "./universalDelegator/useTxStatus";

type SlotMetrics = {
  allocatedValue: bigint;
  pendingValue: bigint;
  allocatedPct: number;
  pendingPct: number;
};

function isInteractiveTarget(target: EventTarget | null): boolean {
  const element = target as HTMLElement | null;
  if (!element || typeof element.closest !== "function") return false;
  return Boolean(element.closest("button, input, textarea, select, label, a, [data-no-zoom]"));
}

function computeSlotMetrics(params: {
  index?: bigint;
  size: bigint;
  allocationsByIndex: Map<string, bigint>;
  pendingByIndex: Map<string, bigint>;
}): SlotMetrics {
  const key = params.index !== undefined ? params.index.toString() : null;
  const allocatedRaw = key ? params.allocationsByIndex.get(key) ?? 0n : 0n;
  const pendingRaw = key ? params.pendingByIndex.get(key) ?? 0n : 0n;
  const pendingValue = pendingRaw > allocatedRaw ? allocatedRaw : pendingRaw;
  const allocatedValue = saturatingSub(allocatedRaw, pendingValue);
  const allocatedPct = params.size > 0n ? Math.min(100, Number((allocatedValue * 10000n) / params.size) / 100) : 0;
  const pendingPctRaw = params.size > 0n ? Number((pendingValue * 10000n) / params.size) / 100 : 0;
  const pendingPct = Math.max(0, Math.min(100 - allocatedPct, pendingPctRaw));

  return { allocatedValue, pendingValue, allocatedPct, pendingPct };
}

function formatBalanceDisplay(params: {
  canReadBalances: boolean;
  hasRootBalance: boolean;
  indexDefined: boolean;
  loading: boolean;
  value: bigint;
}): string {
  if (!params.canReadBalances || !params.hasRootBalance || !params.indexDefined) return "—";
  if (params.loading) return "loading…";
  return params.value.toString();
}

function hasReadError(data: readonly unknown[] | undefined): boolean {
  if (!data) return false;
  return data.some((item) => {
    if (!item || typeof item !== "object") return false;
    if (!("error" in item)) return false;
    return Boolean((item as { error?: unknown }).error);
  });
}

export function UniversalDelegatorConfigurator() {
  const { login, logout, authenticated } = usePrivy();
  const { address: accountAddress, isConnected, chain } = useAccount();
  const publicClient = usePublicClient();

  const { writeContractAsync, data: txHash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });
  const txStatus = useTxStatus({ isPending, isConfirming, isConfirmed, error });
  const handledTxHashRef = useRef<Hex | null>(null);

  const nextId = useRef(1);
  const newId = (prefix: string) => `${prefix}-${nextId.current++}`;

  const [delegatorAddress, setDelegatorAddress] = useState<string>("");
  const [model, setModel] = useState<UniversalDelegatorModel>({ groups: [] });
  const [ops, setOps] = useState<UdOperation[]>([]);
  const [history, setHistory] = useState<Array<{ model: UniversalDelegatorModel; ops: UdOperation[] }>>([]);
  const [zoom, setZoom] = useState<ZoomState>({ kind: "all" });
  const [hoveredGroupId, setHoveredGroupId] = useState<string | null>(null);
  const [groupConstructor, setGroupConstructor] = useState<GroupConstructor>("shared-multi");
  const [groupNetworksInput, setGroupNetworksInput] = useState("2");
  const [groupOperatorsInput, setGroupOperatorsInput] = useState("2");
  const [swapCandidateId, setSwapCandidateId] = useState("");
  const [isReconstructing, setIsReconstructing] = useState(false);
  const [reconstructError, setReconstructError] = useState<string | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const [selectedOps, setSelectedOps] = useState<UdOperation[]>([]);
  const [selectedCandidateLabel, setSelectedCandidateLabel] = useState<string>("optimized");
  const [multicallWarning, setMulticallWarning] = useState<string | null>(null);
  const [multicallError, setMulticallError] = useState<string | null>(null);
  const [multicallErrorOp, setMulticallErrorOp] = useState<{ index: number; op: UdOperation } | null>(null);
  const [isValidatingMulticall, setIsValidatingMulticall] = useState(false);
  const [reconstructNonce, setReconstructNonce] = useState(0);
  const toastTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const baselineModelRef = useRef<UniversalDelegatorModel | null>(null);
  const rootBalanceRef = useRef<bigint | null>(null);

  const baselineModel = useMemo(() => opsBaselineModel({ model, ops, history }), [history, model, ops]);
  baselineModelRef.current = baselineModel;

  const multicallCandidates = useMemo(() => buildMulticallCandidates({ ops, baselineModel }), [baselineModel, ops]);
  const orderedMulticallCandidates = useMemo(
    () => orderMulticallCandidates(multicallCandidates),
    [multicallCandidates],
  );

  const flashToast = useCallback((message: string) => {
    setToastMessage(message);
    if (toastTimeoutRef.current) clearTimeout(toastTimeoutRef.current);
    toastTimeoutRef.current = setTimeout(() => setToastMessage(null), 1500);
  }, []);

  useEffect(
    () => () => {
      if (toastTimeoutRef.current) clearTimeout(toastTimeoutRef.current);
    },
    [],
  );

  useEffect(() => {
    if (!isConfirmed || !txHash) return;
    if (handledTxHashRef.current === txHash) return;
    handledTxHashRef.current = txHash;

    setOps([]);
    setHistory([]);
    setSelectedOps([]);
    setSelectedCandidateLabel("optimized");
    setMulticallWarning(null);
    setMulticallError(null);
    setMulticallErrorOp(null);
    setIsValidatingMulticall(false);
  }, [isConfirmed, txHash]);

  const copyIndexToClipboard = useCallback(
    (index: bigint) => {
      const text = formatIndex(index);
      void navigator.clipboard.writeText(text).catch(() => {});
      flashToast("Index copied!");
    },
    [flashToast],
  );

  useEffect(() => {
    let cancelled = false;

    const validate = async () => {
      setMulticallWarning(null);
      setMulticallError(null);
      setMulticallErrorOp(null);
      setIsValidatingMulticall(false);

      if (orderedMulticallCandidates.length === 0) {
        setSelectedOps([]);
        setSelectedCandidateLabel("optimized");
        return;
      }

      const primary = orderedMulticallCandidates[0];
      setSelectedOps(primary.ops);
      setSelectedCandidateLabel(primary.label);

      if (!publicClient || !isAddress(delegatorAddress)) {
        return;
      }

      if (!accountAddress || !isAddress(accountAddress)) {
        if (primary.ops.length > 0) {
          setMulticallWarning("Connect wallet to validate multicall execution.");
        }
        return;
      }

      setIsValidatingMulticall(true);
      let lastError: unknown = null;

      try {
        const applyCandidate = (candidate: MulticallCandidate) => {
          setSelectedOps(candidate.ops);
          setSelectedCandidateLabel(candidate.label);
          setMulticallWarning(
            candidate.label === primary.label
              ? null
              : `Using fallback strategy: ${candidate.label}. Optimal strategy reverted during simulation.`,
          );
          setMulticallError(null);
          setMulticallErrorOp(null);
        };

        let candidateResults: Awaited<ReturnType<typeof simulateMulticallCandidates>> | null = null;
        try {
          candidateResults = await simulateMulticallCandidates({
            publicClient,
            delegatorAddress: delegatorAddress as Address,
            account: accountAddress as Address,
            candidates: orderedMulticallCandidates,
          });
        } catch (error) {
          lastError = error;
        }

        if (candidateResults) {
          const success = candidateResults.find((result) => result.status === "success");
          if (success) {
            if (cancelled) return;
            applyCandidate(success.candidate);
            return;
          }
          const primaryResult = candidateResults[0];
          if (primaryResult?.status === "failure") {
            lastError = primaryResult.error;
          } else {
            lastError = candidateResults.find((result) => result.status === "failure")?.error ?? lastError;
          }
        } else {
          for (const candidate of orderedMulticallCandidates) {
            const calls = encodeOpsToCalls(candidate.ops);
            if (calls.length === 0) {
              if (cancelled) return;
              applyCandidate(candidate);
              return;
            }

            try {
              await simulateMulticall({
                publicClient,
                delegatorAddress: delegatorAddress as Address,
                account: accountAddress as Address,
                calls,
              });
              if (cancelled) return;
              applyCandidate(candidate);
              return;
            } catch (error) {
              lastError = error;
            }
          }
        }

        const failure = await findFailingOp({
          publicClient,
          delegatorAddress: delegatorAddress as Address,
          account: accountAddress as Address,
          ops: primary.ops,
        });
        if (cancelled) return;

        const baseError = failure?.error ?? lastError;
        const errorName = extractRevertName(baseError);
        const baselineSnapshot = baselineModelRef.current;
        const rootBalanceSnapshot = rootBalanceRef.current;
        const detailed =
          failure && baselineSnapshot
            ? describeNotEnoughAvailable({
                ops: primary.ops,
                failureIndex: failure.index,
                baselineModel: baselineSnapshot,
                rootBalance: rootBalanceSnapshot,
              })
            : null;
        const fallbackReason = formatViemError(baseError);
        const useDetailed =
          Boolean(detailed) &&
          (errorName === "NotEnoughAvailable" || (errorName === null && fallbackReason.includes("multicall")));
        const reason = useDetailed ? detailed! : fallbackReason;
        if (failure && primary.ops[failure.index]) {
          setMulticallErrorOp({ index: failure.index, op: primary.ops[failure.index]! });
          setMulticallError(
            `Op #${failure.index + 1} ${formatOp(primary.ops[failure.index]!)} would revert: ${reason}`,
          );
        } else {
          setMulticallError(`Multicall would revert: ${reason}`);
        }
      } finally {
        if (!cancelled) setIsValidatingMulticall(false);
      }
    };

    void validate();
    return () => {
      cancelled = true;
    };
  }, [accountAddress, delegatorAddress, orderedMulticallCandidates, publicClient]);

  const balanceIndices = useMemo(() => [0n], []);

  const canReadBalances = isAddress(delegatorAddress) && balanceIndices.length > 0;
  const balanceReads = useMemo(() => {
    if (!canReadBalances) return [];
    const address = delegatorAddress as Address;
    return balanceIndices.map((index) => ({
      address,
      abi: universalDelegatorAbi,
      functionName: "getBalance" as const,
      args: [index] as const,
    }));
  }, [balanceIndices, canReadBalances, delegatorAddress]);

  const { data: balancesData, isLoading: balancesLoading } = useReadContracts({
    allowFailure: true,
    contracts: balanceReads,
    query: { enabled: canReadBalances, refetchInterval: 5000 },
  });

  const balancesByIndex = useMemo(() => {
    const map = new Map<string, bigint>();
    if (!balancesData) return map;
    for (let i = 0; i < balancesData.length; i += 1) {
      const item = balancesData[i];
      if (!item) continue;
      if ("result" in item && item.result !== undefined) {
        map.set(balanceIndices[i]!.toString(), item.result as bigint);
      }
    }
    return map;
  }, [balanceIndices, balancesData]);

  const rootBalance = balancesByIndex.get("0") ?? null;
  rootBalanceRef.current = rootBalance;
  const slotIdToIndex = useMemo(() => computeSlotIdToIndex(model), [model]);
  const baselineSlotIdToIndex = useMemo(() => computeSlotIdToIndex(baselineModel), [baselineModel]);
  const allocationIndices = useMemo(() => {
    const seen = new Set<string>();
    const out: bigint[] = [];
    for (const index of slotIdToIndex.values()) {
      if (index === 0n) continue;
      const key = index.toString();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(index);
    }
    out.sort(bigintCompare);
    return out;
  }, [slotIdToIndex]);

  const canReadOnchainAllocations = isAddress(delegatorAddress) && allocationIndices.length > 0;
  const allocationReads = useMemo(() => {
    if (!canReadOnchainAllocations) return [];
    const address = delegatorAddress as Address;
    return allocationIndices.map((index) => ({
      address,
      abi: universalDelegatorAbi,
      functionName: "getAllocated" as const,
      args: [index] as const,
    }));
  }, [allocationIndices, canReadOnchainAllocations, delegatorAddress]);

  const { data: allocatedData, isLoading: allocatedLoading } = useReadContracts({
    allowFailure: true,
    contracts: allocationReads,
    query: { enabled: canReadOnchainAllocations, refetchInterval: 5000 },
  });

  const onchainAllocationsByIndex = useMemo(() => {
    const map = new Map<string, bigint>();
    if (!allocatedData) return map;
    for (let i = 0; i < allocatedData.length; i += 1) {
      const item = allocatedData[i];
      if (!item) continue;
      if ("result" in item && item.result !== undefined) {
        const index = allocationIndices[i];
        if (index === undefined) continue;
        map.set(index.toString(), item.result as bigint);
      }
    }
    return map;
  }, [allocatedData, allocationIndices]);

  const availableIndices = useMemo(() => [0n, ...allocationIndices], [allocationIndices]);
  const canReadAvailable = isAddress(delegatorAddress) && availableIndices.length > 0;
  const availableReads = useMemo<
    Array<{
      address: Address;
      abi: typeof universalDelegatorAbi;
      functionName: "getAvailable";
      args: readonly [bigint];
    }>
  >(() => {
    if (!canReadAvailable) return [];
    const address = delegatorAddress as Address;
    return availableIndices.map((index) => ({
      address,
      abi: universalDelegatorAbi,
      functionName: "getAvailable" as const,
      args: [index] as const,
    }));
  }, [availableIndices, canReadAvailable, delegatorAddress]);

  const { data: availableData, isLoading: availableLoading } = useReadContracts({
    allowFailure: true,
    contracts: availableReads,
    query: { enabled: canReadAvailable, refetchInterval: 5000 },
  }) as {
    data?: Array<{ result?: bigint } | { error?: BaseError } | null>;
    isLoading: boolean;
  };

  const onchainPendingByIndex = useMemo(() => {
    const map = new Map<string, bigint>();
    if (!availableData) return map;
    for (let i = 0; i < availableData.length; i += 1) {
      const item = availableData[i];
      if (!item) continue;
      if ("result" in item && item.result !== undefined) {
        const index = availableIndices[i];
        if (index === undefined) continue;
        const available = item.result as bigint;
        const balance = index === 0n ? rootBalance ?? 0n : onchainAllocationsByIndex.get(index.toString()) ?? 0n;
        map.set(index.toString(), saturatingSub(balance, available));
      }
    }
    return map;
  }, [availableData, availableIndices, onchainAllocationsByIndex, rootBalance]);

  const baselineAllocationsByIndex = useMemo(
    () => computeSimulatedAllocations(baselineModel, baselineSlotIdToIndex, rootBalance),
    [baselineModel, baselineSlotIdToIndex, rootBalance],
  );
  const candidateOpsKeys = useMemo(
    () => new Set(orderedMulticallCandidates.map((candidate) => opsKey(candidate.ops))),
    [orderedMulticallCandidates],
  );
  const pendingOpsForSimulation = useMemo(() => {
    if (orderedMulticallCandidates.length === 0) return [];
    if (selectedOps.length > 0 && candidateOpsKeys.has(opsKey(selectedOps))) return selectedOps;
    return orderedMulticallCandidates[0]?.ops ?? [];
  }, [candidateOpsKeys, orderedMulticallCandidates, selectedOps]);
  const simulatedPendingByIndexOverride = useMemo(
    () =>
      computePendingByIndexFromOps({
        baselineModel,
        ops: pendingOpsForSimulation,
        rootActiveStake: rootBalance,
        baselinePendingByIndex: onchainPendingByIndex,
      }),
    [baselineModel, onchainPendingByIndex, pendingOpsForSimulation, rootBalance],
  );
  const simulatedAllocations = useMemo(
    () =>
      computeSimulatedAllocationsWithPending({
        model,
        slotIdToIndex,
        baselineSlotIdToIndex,
        baselineAllocationsByIndex,
        rootActiveStake: rootBalance,
        pendingByIndexOverride: simulatedPendingByIndexOverride,
      }),
    [
      baselineAllocationsByIndex,
      baselineSlotIdToIndex,
      model,
      rootBalance,
      simulatedPendingByIndexOverride,
      slotIdToIndex,
    ],
  );
  const simulatedAllocationsByIndex = simulatedAllocations.allocatedByIndex;
  const simulatedPendingByIndex = simulatedAllocations.pendingByIndex;
  const visibleGroups = useMemo(() => {
    if (zoom.kind === "all") return model.groups;
    const group = model.groups.find((g) => g.id === zoom.groupId);
    if (!group) return [];
    if (zoom.kind === "group") return [group];
    const network = group.networks.find((n) => n.id === zoom.networkId);
    if (!network) return [];
    return [{ ...group, networks: [network] }];
  }, [model.groups, zoom]);

  useEffect(() => {
    if (zoom.kind === "all") return;
    const group = model.groups.find((g) => g.id === zoom.groupId);
    if (!group) {
      setZoom({ kind: "all" });
      return;
    }
    if (zoom.kind === "network") {
      const network = group.networks.find((n) => n.id === zoom.networkId);
      if (!network) setZoom({ kind: "group", groupId: group.id });
    }
  }, [model.groups, zoom]);
  const shouldUseOnchainAllocations =
    isAddress(delegatorAddress) && (pendingOpsForSimulation.length === 0 || orderedMulticallCandidates.length === 0);

  const allocationsByIndex = shouldUseOnchainAllocations ? onchainAllocationsByIndex : simulatedAllocationsByIndex;
  const pendingByIndex = shouldUseOnchainAllocations ? onchainPendingByIndex : simulatedPendingByIndex;
  const hasRootBalance = rootBalance !== null;
  const allocationsLoading = shouldUseOnchainAllocations
    ? allocatedLoading
    : canReadBalances && balancesLoading && rootBalance === null;
  const pendingLoading = shouldUseOnchainAllocations ? availableLoading || allocatedLoading : false;
  const onchainReadActive = canReadBalances || canReadOnchainAllocations || canReadAvailable;
  const hasReadErrors = useMemo(
    () => hasReadError(balancesData) || hasReadError(allocatedData) || hasReadError(availableData),
    [allocatedData, availableData, balancesData],
  );
  const statusBanner = useMemo(() => {
    if (hasReadErrors) {
      return { tone: "error" as const, message: "Some on-chain reads failed. Check RPC endpoints or retry." };
    }
    if (isReconstructing || (onchainReadActive && (balancesLoading || allocatedLoading || availableLoading))) {
      return { tone: "info" as const, message: "Loading on-chain data..." };
    }
    return null;
  }, [allocatedLoading, availableLoading, balancesLoading, hasReadErrors, isReconstructing, onchainReadActive]);

  const encodedCalls = useMemo(() => encodeOpsToCalls(selectedOps), [selectedOps]);

  const multicallCalldata = useMemo(() => {
    if (encodedCalls.length === 0) return null;
    return encodeFunctionData({
      abi: universalDelegatorAbi,
      functionName: "multicall",
      args: [encodedCalls],
    });
  }, [encodedCalls]);
  const handleCopyCalldata = useCallback(() => {
    if (!multicallCalldata) return;
    void navigator.clipboard.writeText(multicallCalldata).then(() => flashToast("Calldata copied!"));
  }, [flashToast, multicallCalldata]);

  const pushHistorySnapshot = useCallback(() => {
    setHistory((prev) => [...prev, { model: cloneModel(model), ops: cloneOps(ops) }]);
  }, [model, ops]);

  const applyModelUpdate = useCallback(
    (updater: (current: UniversalDelegatorModel) => UniversalDelegatorModel) => {
      pushHistorySnapshot();
      setModel((prev) => {
        const updated = updater(prev);
        const auto = autoSyncAll(updated);
        setOps((prevOps) => {
          const compiled = compileOpsFromModels({ baselineModel, nextModel: auto.model });
          if (compiled) return compiled;
          if (auto.ops.length === 0) return prevOps;
          return shallowOptimizeOps(mergeOps(prevOps, auto.ops));
        });
        return auto.model;
      });
    },
    [baselineModel, pushHistorySnapshot],
  );

  const undo = useCallback(() => {
    setHistory((prev) => {
      const last = prev[prev.length - 1];
      if (!last) return prev;
      setModel(last.model);
      setOps(last.ops);
      return prev.slice(0, -1);
    });
  }, []);

  const resetToOnchain = useCallback(() => {
    setOps([]);
    setHistory([]);
    setSelectedOps([]);
    setSelectedCandidateLabel("optimized");
    setMulticallWarning(null);
    setMulticallError(null);
    setMulticallErrorOp(null);
    setIsValidatingMulticall(false);
    setReconstructNonce((prev) => prev + 1);
  }, []);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.defaultPrevented) return;
      if (!(e.ctrlKey || e.metaKey)) return;
      if (e.shiftKey) return;
      if (e.key.toLowerCase() !== "z") return;

      const target = e.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      const isTextInput =
        tag === "input" ||
        tag === "textarea" ||
        tag === "select" ||
        Boolean(target && "isContentEditable" in target && (target as HTMLElement).isContentEditable);
      if (isTextInput) return;

      e.preventDefault();
      undo();
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [undo]);

  useEffect(() => {
    const trimmed = delegatorAddress.trim();
    if (!publicClient) return;
    if (!isAddress(trimmed)) {
      setIsReconstructing(false);
      setReconstructError(null);
      return;
    }

    let cancelled = false;
    setIsReconstructing(true);
    setReconstructError(null);
    (async () => {
      try {
        const onchainModel = await reconstructModelFromChain({
          delegatorAddress: trimmed as Address,
          publicClient,
        });
        if (cancelled) return;
        setModel(onchainModel);
        setOps([]);
        setHistory([]);
      } catch (e) {
        if (cancelled) return;
        setReconstructError(e instanceof Error ? e.message : String(e));
      } finally {
        if (!cancelled) setIsReconstructing(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [delegatorAddress, publicClient, reconstructNonce]);

  function addDraftGroup() {
    const group: GroupSlot = {
      id: newId("group"),
      index: null,
      state: { draft: { size: "", isShared: false }, synced: null },
      networks: [],
    };
    applyModelUpdate((prev) => ({ ...prev, groups: [...prev.groups, group] }));
  }

  function addGroupFromTemplate() {
    if (!addGroupValid) return;
    const makeOperator = (): OperatorSlot => ({
      id: newId("operator"),
      index: null,
      state: { draft: { size: "", operator: "" }, synced: null },
    });
    const makeNetwork = (operatorCount: number): NetworkSlot => ({
      id: newId("network"),
      index: null,
      state: { draft: { size: "", subnetwork: "" }, synced: null },
      operators: Array.from({ length: operatorCount }, makeOperator),
    });

    const isShared = groupConstructor === "shared-multi" || groupConstructor === "shared-single";
    let networks: NetworkSlot[] = [];
    if (groupConstructor === "shared-multi") {
      const netCount = groupNetworksCount ?? 0;
      const opCount = groupOperatorsCount ?? 0;
      networks = Array.from({ length: netCount }, () => makeNetwork(opCount));
    } else if (groupConstructor === "shared-single") {
      const netCount = groupNetworksCount ?? 0;
      networks = Array.from({ length: netCount }, () => makeNetwork(1));
    } else if (groupConstructor === "single-multi") {
      const opCount = groupOperatorsCount ?? 0;
      networks = [makeNetwork(opCount)];
    } else {
      networks = [makeNetwork(1)];
    }

    const group: GroupSlot = {
      id: newId("group"),
      index: null,
      state: { draft: { size: "", isShared }, synced: null },
      networks,
    };
    applyModelUpdate((prev) => ({ ...prev, groups: [...prev.groups, group] }));
  }

  function swapNeighborSlots() {
    const candidate = swapCandidates.find((item) => item.id === swapCandidateId);
    if (!candidate) return;
    pushHistorySnapshot();
    setModel((prev) => {
      let didSwap = false;
      let nextModel: UniversalDelegatorModel = prev;

      if (zoom.kind === "all") {
        const leftIndex = prev.groups.findIndex((g) => g.id === candidate.leftId);
        const rightIndex = prev.groups.findIndex((g) => g.id === candidate.rightId);
        if (leftIndex === -1 || rightIndex === -1) return prev;
        const groups = prev.groups.slice();
        [groups[leftIndex], groups[rightIndex]] = [groups[rightIndex]!, groups[leftIndex]!];
        nextModel = { ...prev, groups };
        didSwap = true;
      } else if (zoom.kind === "group") {
        const groups = prev.groups.map((g) => {
          if (g.id !== zoom.groupId) return g;
          const leftIndex = g.networks.findIndex((n) => n.id === candidate.leftId);
          const rightIndex = g.networks.findIndex((n) => n.id === candidate.rightId);
          if (leftIndex === -1 || rightIndex === -1) return g;
          const networks = g.networks.slice();
          [networks[leftIndex], networks[rightIndex]] = [networks[rightIndex]!, networks[leftIndex]!];
          didSwap = true;
          return { ...g, networks };
        });
        nextModel = didSwap ? { ...prev, groups } : prev;
      } else {
        const groups = prev.groups.map((g) => {
          if (g.id !== zoom.groupId) return g;
          return {
            ...g,
            networks: g.networks.map((n) => {
              if (n.id !== zoom.networkId) return n;
              const leftIndex = n.operators.findIndex((o) => o.id === candidate.leftId);
              const rightIndex = n.operators.findIndex((o) => o.id === candidate.rightId);
              if (leftIndex === -1 || rightIndex === -1) return n;
              const operators = n.operators.slice();
              [operators[leftIndex], operators[rightIndex]] = [operators[rightIndex]!, operators[leftIndex]!];
              didSwap = true;
              return { ...n, operators };
            }),
          };
        });
        nextModel = didSwap ? { ...prev, groups } : prev;
      }

      if (!didSwap) return prev;

      setOps((prevOps) => {
        const compiled = compileOpsFromModels({ baselineModel, nextModel });
        return compiled ?? prevOps;
      });
      return nextModel;
    });
  }

  function updateGroupDraft(groupId: string, patch: Partial<GroupDraft>) {
    applyModelUpdate((prev) => ({
      ...prev,
      groups: prev.groups.map((g) =>
        g.id === groupId ? { ...g, state: { ...g.state, draft: { ...g.state.draft, ...patch } } } : g,
      ),
    }));
  }

  function addDraftNetwork(groupId: string) {
    const network: NetworkSlot = {
      id: newId("network"),
      index: null,
      state: { draft: { size: "", subnetwork: "" }, synced: null },
      operators: [],
    };

    applyModelUpdate((prev) => ({
      ...prev,
      groups: prev.groups.map((g) => (g.id === groupId ? { ...g, networks: [...g.networks, network] } : g)),
    }));
  }

  function updateNetworkDraft(groupId: string, networkId: string, patch: Partial<NetworkDraft>) {
    applyModelUpdate((prev) => ({
      ...prev,
      groups: prev.groups.map((g) => {
        if (g.id !== groupId) return g;
        return {
          ...g,
          networks: g.networks.map((n) =>
            n.id === networkId ? { ...n, state: { ...n.state, draft: { ...n.state.draft, ...patch } } } : n,
          ),
        };
      }),
    }));
  }

  function addDraftOperator(groupId: string, networkId: string) {
    const group = model.groups.find((g) => g.id === groupId);
    const network = group?.networks.find((n) => n.id === networkId);
    if (!network) return;

    const slot: OperatorSlot = {
      id: newId("operator"),
      index: null,
      state: { draft: { size: "", operator: "" }, synced: null },
    };

    applyModelUpdate((prev) => ({
      ...prev,
      groups: prev.groups.map((g) => {
        if (g.id !== groupId) return g;
        return {
          ...g,
          networks: g.networks.map((n) => (n.id === networkId ? { ...n, operators: [...n.operators, slot] } : n)),
        };
      }),
    }));
  }

  function updateOperatorDraft(groupId: string, networkId: string, operatorId: string, patch: Partial<OperatorDraft>) {
    applyModelUpdate((prev) => ({
      ...prev,
      groups: prev.groups.map((g) => {
        if (g.id !== groupId) return g;
        return {
          ...g,
          networks: g.networks.map((n) => {
            if (n.id !== networkId) return n;
            return {
              ...n,
              operators: n.operators.map((o) =>
                o.id === operatorId ? { ...o, state: { ...o.state, draft: { ...o.state.draft, ...patch } } } : o,
              ),
            };
          }),
        };
      }),
    }));
  }

  async function executeMulticall() {
    if (!isConnected || !accountAddress) return;
    if (!isAddress(delegatorAddress)) return;
    if (encodedCalls.length === 0) return;

    try {
      await writeContractAsync({
        abi: universalDelegatorAbi,
        address: delegatorAddress as Address,
        functionName: "multicall",
        args: [encodedCalls],
      });
    } catch {
      // error state handled by wagmi hook
    }
  }

  const primaryCandidateLabel = orderedMulticallCandidates[0]?.label ?? "optimized";

  const canExecute =
    isConnected &&
    isAddress(delegatorAddress) &&
    encodedCalls.length > 0 &&
    !isPending &&
    !isConfirming &&
    !isValidatingMulticall &&
    !multicallError;

  const groupSizeValues = visibleGroups.map((group) => effectiveSize(group.state));
  const groupTotalSize = sumBigints(groupSizeValues);
  const walletConnected = Boolean(authenticated && isConnected && accountAddress);
  const shortAccountAddress = accountAddress ? formatShortAddress(accountAddress) : "";
  const chainLabel = chain?.name ?? "Unknown chain";
  const delegatorTrimmed = delegatorAddress.trim();
  const isDelegatorInvalid = delegatorTrimmed.length > 0 && !isAddress(delegatorTrimmed);
  const zoomCrumbs = useMemo(() => {
    const crumbs: Array<
      | { kind: "groups"; label: string }
      | { kind: "group"; label: string; groupId: string }
      | { kind: "network"; label: string; groupId: string; networkId: string }
    > = [{ kind: "groups", label: "Groups" }];

    if (zoom.kind === "all") return crumbs;
    const group = model.groups.find((g) => g.id === zoom.groupId);
    if (!group) return crumbs;

    const groupIndex = slotIdToIndex.get(group.id);
    const groupLabel = groupIndex !== undefined ? `Group ${getChildIndex(groupIndex)}` : "Group";
    crumbs.push({ kind: "group", label: groupLabel, groupId: group.id });

    if (zoom.kind !== "network") return crumbs;
    const network = group.networks.find((n) => n.id === zoom.networkId);
    if (!network) return crumbs;
    const networkIndex = slotIdToIndex.get(network.id);
    const networkLabel = networkIndex !== undefined ? `Network ${getChildIndex(networkIndex)}` : "Network";
    crumbs.push({ kind: "network", label: networkLabel, groupId: group.id, networkId: network.id });
    return crumbs;
  }, [model.groups, slotIdToIndex, zoom]);
  const hoverActionClass =
    "transition-colors hover:bg-primary/10 hover:border-primary/30 hover:text-base-content hover:shadow-sm " +
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary";
  const groupNetworksCount = parsePositiveInt(groupNetworksInput);
  const groupOperatorsCount = parsePositiveInt(groupOperatorsInput);
  const needsNetworks = groupConstructor === "shared-multi" || groupConstructor === "shared-single";
  const needsOperators = groupConstructor === "shared-multi" || groupConstructor === "single-multi";

  const addGroupValid =
    needsNetworks && needsOperators
      ? Boolean(groupNetworksCount && groupOperatorsCount)
      : needsNetworks
      ? Boolean(groupNetworksCount)
      : needsOperators
      ? Boolean(groupOperatorsCount)
      : true;

  const swapScope = useMemo((): { label: string; items: Array<GroupSlot | NetworkSlot | OperatorSlot> } => {
    if (zoom.kind === "all") return { label: "Groups", items: model.groups };
    const group = model.groups.find((g) => g.id === zoom.groupId);
    if (!group) return { label: "Groups", items: [] as GroupSlot[] };
    if (zoom.kind === "group") return { label: "Networks", items: group.networks };
    const network = group.networks.find((n) => n.id === zoom.networkId);
    if (!network) return { label: "Networks", items: [] as NetworkSlot[] };
    return { label: "Operators", items: network.operators };
  }, [model.groups, zoom]);

  const swapCandidates = useMemo(() => {
    const items = swapScope.items;
    if (items.length < 2) return [];
    const out: Array<{
      id: string;
      label: string;
      leftId: string;
      rightId: string;
      leftIndex: bigint | null;
      rightIndex: bigint | null;
    }> = [];
    for (let i = 0; i < items.length - 1; i += 1) {
      const left = items[i];
      const right = items[i + 1];
      if (!left || !right) continue;
      const leftIndex = left.index ?? null;
      const rightIndex = right.index ?? null;
      const leftDisplay = slotIdToIndex.get(left.id);
      const rightDisplay = slotIdToIndex.get(right.id);
      const leftLabel = leftDisplay ? getChildIndex(leftDisplay).toString() : `${i + 1}`;
      const rightLabel = rightDisplay ? getChildIndex(rightDisplay).toString() : `${i + 2}`;
      out.push({
        id: `${left.id}:${right.id}`,
        label: `${swapScope.label.slice(0, -1)} ${leftLabel} <-> ${swapScope.label.slice(0, -1)} ${rightLabel}`,
        leftId: left.id,
        rightId: right.id,
        leftIndex,
        rightIndex,
      });
    }
    return out;
  }, [slotIdToIndex, swapScope.items, swapScope.label]);

  useEffect(() => {
    if (swapCandidates.length === 0) {
      setSwapCandidateId("");
      return;
    }
    if (!swapCandidates.find((candidate) => candidate.id === swapCandidateId)) {
      setSwapCandidateId(swapCandidates[0]!.id);
    }
  }, [swapCandidates, swapCandidateId]);

  return (
    <div className="min-h-screen bg-base-100 text-base-content">
      {toastMessage ? (
        <div className="toast toast-top toast-end z-50">
          <div className="alert alert-success">
            <span>{toastMessage}</span>
          </div>
        </div>
      ) : null}
      <div className="navbar bg-base-200">
        <div className="flex-1">
          <div className="text-lg font-semibold">UniversalDelegator Configurator</div>
        </div>
        <WalletStatus
          authenticated={authenticated}
          walletConnected={walletConnected}
          accountAddress={accountAddress}
          shortAccountAddress={shortAccountAddress}
          chainLabel={chainLabel}
          actionClass={hoverActionClass}
          onLogin={login}
          onLogout={logout}
        />
      </div>

      <div className="mx-auto w-full max-w-[120rem] px-2 py-4 sm:px-3 lg:px-4">
        <div className="flex flex-col gap-4">
          {statusBanner ? <StatusBanner tone={statusBanner.tone} message={statusBanner.message} /> : null}
          <MulticallPanel
            encodedCallsCount={encodedCalls.length}
            selectedCandidateLabel={selectedCandidateLabel}
            primaryCandidateLabel={primaryCandidateLabel}
            isValidatingMulticall={isValidatingMulticall}
            canExecute={canExecute}
            isPending={isPending}
            onExecute={executeMulticall}
            multicallWarning={multicallWarning}
            txHash={txHash}
            txStatus={txStatus}
            selectedOps={selectedOps}
            multicallErrorOp={multicallErrorOp}
            multicallError={multicallError}
            multicallCalldata={multicallCalldata}
            onCopyCalldata={handleCopyCalldata}
            hoverActionClass={hoverActionClass}
          />

          <div className="card bg-base-200 shadow">
            <div className="card-body gap-4">
              <div className="flex flex-col gap-2 md:flex-row md:items-end md:justify-between">
                <div className="flex-1">
                  <div className="text-sm font-semibold">Delegator Address</div>
                  <input
                    className={`input input-bordered w-full max-w-[42ch] font-mono ${
                      isDelegatorInvalid ? "input-error" : ""
                    }`}
                    placeholder="0x…"
                    value={delegatorAddress}
                    onChange={(e) => setDelegatorAddress(e.target.value)}
                  />
                  {isReconstructing ? (
                    <div className="mt-2 flex items-center gap-2 text-xs opacity-70">
                      <span className="loading loading-spinner loading-xs" />
                      Loading on-chain slots…
                    </div>
                  ) : null}
                  {reconstructError ? <div className="mt-2 text-xs text-error">{reconstructError}</div> : null}
                </div>
              </div>

              <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
                <div className="card bg-base-200 border border-base-300 shadow">
                  <div className="card-body gap-3">
                    <div className="text-sm font-semibold">Add Group</div>
                    <div className="flex flex-col gap-2 text-xs">
                      <label className="form-control flex flex-col">
                        <div className="label py-0">
                          <span className="label-text text-xs">Constructor</span>
                        </div>
                        <select
                          className="select select-bordered select-sm"
                          value={groupConstructor}
                          onChange={(e) => setGroupConstructor(e.target.value as GroupConstructor)}
                        >
                          <option value="shared-multi">Shared Networks with Multiple Operators</option>
                          <option value="shared-single">Shared Networks with Single Operator</option>
                          <option value="single-multi">Single Network with Multiple Operators</option>
                          <option value="single-single">Single Network with Single Operator</option>
                        </select>
                      </label>

                      {needsNetworks ? (
                        <label className="form-control flex flex-col">
                          <div className="label py-0">
                            <span className="label-text text-xs">Networks</span>
                          </div>
                          <input
                            className={`input input-bordered input-sm w-24 ${
                              groupNetworksInput.trim() !== "" && !groupNetworksCount ? "input-error" : ""
                            }`}
                            value={groupNetworksInput}
                            onChange={(e) => setGroupNetworksInput(e.target.value)}
                          />
                        </label>
                      ) : null}

                      {needsOperators ? (
                        <label className="form-control flex flex-col">
                          <div className="label py-0">
                            <span className="label-text text-xs">Operators</span>
                          </div>
                          <input
                            className={`input input-bordered input-sm w-24 ${
                              groupOperatorsInput.trim() !== "" && !groupOperatorsCount ? "input-error" : ""
                            }`}
                            value={groupOperatorsInput}
                            onChange={(e) => setGroupOperatorsInput(e.target.value)}
                          />
                        </label>
                      ) : null}
                    </div>
                    <button
                      className={`btn btn-ghost btn-sm w-24 self-center ${hoverActionClass}`}
                      disabled={!addGroupValid}
                      onClick={addGroupFromTemplate}
                    >
                      Add group
                    </button>
                  </div>
                </div>

                <div className="card bg-base-200 border border-base-300 shadow">
                  <div className="card-body gap-3">
                    <div className="text-sm font-semibold">Swap Slots</div>
                    <div className="text-xs opacity-70">Scope: {swapScope.label}</div>
                    {swapCandidates.length === 0 ? (
                      <div className="text-xs opacity-70">No neighbor slots to swap.</div>
                    ) : (
                      <label className="form-control flex flex-col">
                        <div className="label py-0">
                          <span className="label-text text-xs">Neighbor pair</span>
                        </div>
                        <select
                          className="select select-bordered select-sm"
                          value={swapCandidateId}
                          onChange={(e) => setSwapCandidateId(e.target.value)}
                        >
                          {swapCandidates.map((candidate) => (
                            <option key={candidate.id} value={candidate.id}>
                              {candidate.label}
                            </option>
                          ))}
                        </select>
                      </label>
                    )}
                    <button
                      className={`btn btn-ghost btn-sm w-24 self-center ${hoverActionClass}`}
                      disabled={!swapCandidateId || swapCandidates.length === 0}
                      onClick={swapNeighborSlots}
                    >
                      Swap
                    </button>
                  </div>
                </div>
              </div>

              <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                <div className="flex items-center gap-2">
                  {zoomCrumbs.length > 0 ? (
                    <div className="flex items-center gap-1 text-xs">
                      <span className="opacity-70">Viewing</span>
                      {zoomCrumbs.map((crumb, idx) => {
                        const isCurrent =
                          (crumb.kind === "groups" && zoom.kind === "all") ||
                          (crumb.kind === "group" && zoom.kind === "group") ||
                          (crumb.kind === "network" && zoom.kind === "network");
                        const label = isCurrent ? (
                          <span className="text-base-content">{crumb.label}</span>
                        ) : (
                          <button
                            type="button"
                            className="cursor-pointer bg-transparent p-0 text-base-content/60 transition-colors hover:text-base-content focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                            onClick={() => {
                              if (crumb.kind === "groups") {
                                setZoom({ kind: "all" });
                              } else if (crumb.kind === "group") {
                                setZoom({ kind: "group", groupId: crumb.groupId });
                              }
                            }}
                          >
                            {crumb.label}
                          </button>
                        );
                        return (
                          <span key={`${crumb.kind}-${crumb.label}`} className="flex items-center gap-1">
                            {idx > 0 ? <span className="opacity-60">/</span> : null}
                            {label}
                          </span>
                        );
                      })}
                      {zoom.kind === "all" ? <span className="opacity-60">/</span> : null}
                    </div>
                  ) : null}
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    className={`btn btn-ghost btn-sm ${hoverActionClass}`}
                    disabled={history.length === 0}
                    onClick={undo}
                  >
                    Back
                  </button>
                  <button className={`btn btn-ghost btn-sm ${hoverActionClass}`} onClick={resetToOnchain}>
                    Reset
                  </button>
                </div>
              </div>

              <div className="divider my-0">
                <div className="text-xs opacity-70 whitespace-nowrap">
                  <div>
                    Allocated: {canReadBalances ? rootBalance?.toString() ?? (balancesLoading ? "loading…" : "—") : "—"}
                  </div>
                  <div>
                    Pending:{" "}
                    {!canReadBalances || !hasRootBalance
                      ? "—"
                      : pendingLoading
                      ? "loading…"
                      : (pendingByIndex.get("0") ?? 0n).toString()}
                  </div>
                </div>
              </div>

              <div className="flex flex-col gap-3">
                <div className="flex flex-row flex-nowrap gap-3 overflow-x-auto pb-2">
                  {visibleGroups.map((group, groupPos) => {
                    const draft = group.state.draft;
                    const groupIndex = slotIdToIndex.get(group.id);
                    const sizeValid = parseUint(draft.size) !== null;
                    const widthSizeValue = groupSizeValues[groupPos] ?? 0n;
                    const groupGrow = flexGrowFromSize(widthSizeValue, groupTotalSize);
                    const fillSizeValue = effectiveSize(group.state);
                    const metrics = computeSlotMetrics({
                      index: groupIndex,
                      size: fillSizeValue,
                      allocationsByIndex,
                      pendingByIndex,
                    });
                    const { allocatedValue, pendingValue, allocatedPct, pendingPct } = metrics;
                    const allocatedDisplay = formatBalanceDisplay({
                      canReadBalances,
                      hasRootBalance,
                      indexDefined: groupIndex !== undefined,
                      loading: allocationsLoading || pendingLoading,
                      value: allocatedValue,
                    });
                    const pendingDisplay = formatBalanceDisplay({
                      canReadBalances,
                      hasRootBalance,
                      indexDefined: groupIndex !== undefined,
                      loading: pendingLoading,
                      value: pendingValue,
                    });
                    const isGroupFocused = zoom.kind !== "all" && zoom.groupId === group.id;
                    const isGroupHovered = hoveredGroupId === group.id;
                    const handleGroupClick = (event: MouseEvent<HTMLDivElement>) => {
                      if (isInteractiveTarget(event.target)) return;
                      setZoom((prev) =>
                        prev.kind === "group" && prev.groupId === group.id
                          ? { kind: "all" }
                          : { kind: "group", groupId: group.id },
                      );
                    };
                    const handleGroupHover = (event: MouseEvent<HTMLDivElement>) => {
                      const target = event.target as HTMLElement | null;
                      const isOverNetwork = Boolean(target && target.closest("[data-network-card]"));
                      if (isOverNetwork) {
                        setHoveredGroupId((prev) => (prev === group.id ? null : prev));
                        return;
                      }
                      setHoveredGroupId((prev) => (prev === group.id ? prev : group.id));
                    };
                    const handleGroupLeave = () => {
                      setHoveredGroupId((prev) => (prev === group.id ? null : prev));
                    };

                    return (
                      <GroupCard
                        key={group.id}
                        group={group}
                        groupIndex={groupIndex}
                        allocatedPct={allocatedPct}
                        pendingPct={pendingPct}
                        allocatedDisplay={allocatedDisplay}
                        pendingDisplay={pendingDisplay}
                        groupGrow={groupGrow}
                        isFocused={isGroupFocused}
                        isHovered={isGroupHovered}
                        sizeInvalid={draft.size.trim() !== "" && !sizeValid}
                        onCopyIndex={copyIndexToClipboard}
                        onToggleShared={(next) => updateGroupDraft(group.id, { isShared: next })}
                        onSizeChange={(value) => updateGroupDraft(group.id, { size: value })}
                        onCardClick={handleGroupClick}
                        onCardHover={handleGroupHover}
                        onCardLeave={handleGroupLeave}
                      >
                        <NetworksRow
                          group={group}
                          slotIdToIndex={slotIdToIndex}
                          allocatedByIndex={allocationsByIndex}
                          pendingByIndex={pendingByIndex}
                          allocationsLoading={allocationsLoading}
                          pendingLoading={pendingLoading}
                          canReadBalances={canReadBalances}
                          hasRootBalance={hasRootBalance}
                          onCopyIndex={copyIndexToClipboard}
                          onAddNetwork={() => addDraftNetwork(group.id)}
                          showAddNetwork={zoom.kind !== "network"}
                          focusedNetworkId={zoom.kind === "network" ? zoom.networkId : null}
                          onZoomNetwork={(networkId) =>
                            setZoom((prev) =>
                              prev.kind === "network" && prev.networkId === networkId
                                ? { kind: "group", groupId: group.id }
                                : { kind: "network", groupId: group.id, networkId },
                            )
                          }
                          onUpdateNetworkDraft={(networkId, patch) => updateNetworkDraft(group.id, networkId, patch)}
                          onAddOperator={(networkId) => addDraftOperator(group.id, networkId)}
                          onUpdateOperatorDraft={(networkId, operatorId, patch) =>
                            updateOperatorDraft(group.id, networkId, operatorId, patch)
                          }
                        />
                      </GroupCard>
                    );
                  })}

                  {zoom.kind === "all" ? (
                    <AddSlotButton
                      key="add-group"
                      label="Add group"
                      className="flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
                      onClick={addDraftGroup}
                    />
                  ) : null}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function NetworksRow(props: {
  group: GroupSlot;
  slotIdToIndex: Map<string, bigint>;
  allocatedByIndex: Map<string, bigint>;
  pendingByIndex: Map<string, bigint>;
  allocationsLoading: boolean;
  pendingLoading: boolean;
  canReadBalances: boolean;
  hasRootBalance: boolean;
  onCopyIndex: (index: bigint) => void;
  onAddNetwork: () => void;
  showAddNetwork?: boolean;
  focusedNetworkId?: string | null;
  onZoomNetwork?: (networkId: string) => void;
  onUpdateNetworkDraft: (networkId: string, patch: Partial<NetworkDraft>) => void;
  onAddOperator: (networkId: string) => void;
  onUpdateOperatorDraft: (networkId: string, operatorId: string, patch: Partial<OperatorDraft>) => void;
}) {
  const isShared = props.group.state.draft.isShared;
  const hasNetworks = props.group.networks.length > 0;
  const showAddNetwork = props.showAddNetwork ?? true;
  const focusedNetworkId = props.focusedNetworkId ?? null;
  const [hoveredNetworkId, setHoveredNetworkId] = useState<string | null>(null);
  const networksLayoutClass = isShared
    ? "flex flex-col items-start gap-3"
    : "flex flex-row flex-nowrap gap-3 overflow-x-auto pb-2";

  const networkSizeValues = props.group.networks.map((network) => effectiveSize(network.state));
  const networksTotalSize = sumBigints(networkSizeValues);
  const networksMaxSize = maxBigint(networkSizeValues);

  const addButtonRef = useRef<HTMLButtonElement | null>(null);
  const prevNetworksCount = useRef(props.group.networks.length);
  useEffect(() => {
    const current = props.group.networks.length;
    if (current > prevNetworksCount.current && addButtonRef.current) {
      addButtonRef.current.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "end" });
    }
    prevNetworksCount.current = current;
  }, [props.group.networks.length]);

  return (
    <div className="mt-3">
      <div className={networksLayoutClass}>
        {props.group.networks.map((network, networkPos) => {
          const draft = network.state.draft;
          const networkIndex = props.slotIdToIndex.get(network.id);
          const sizeValid = parseUint(draft.size) !== null;
          const widthSizeValue = networkSizeValues[networkPos] ?? 0n;
          const networkGrow = flexGrowFromSize(widthSizeValue, networksTotalSize);
          const networkWidthPct = percentWidthFromSize(widthSizeValue, networksMaxSize, 60, 100);
          const fillSizeValue = effectiveSize(network.state);
          const metrics = computeSlotMetrics({
            index: networkIndex,
            size: fillSizeValue,
            allocationsByIndex: props.allocatedByIndex,
            pendingByIndex: props.pendingByIndex,
          });
          const { allocatedValue, pendingValue, allocatedPct, pendingPct } = metrics;
          const allocatedDisplay = formatBalanceDisplay({
            canReadBalances: props.canReadBalances,
            hasRootBalance: props.hasRootBalance,
            indexDefined: networkIndex !== undefined,
            loading: props.allocationsLoading || props.pendingLoading,
            value: allocatedValue,
          });
          const pendingDisplay = formatBalanceDisplay({
            canReadBalances: props.canReadBalances,
            hasRootBalance: props.hasRootBalance,
            indexDefined: networkIndex !== undefined,
            loading: props.pendingLoading,
            value: pendingValue,
          });
          const subnetworkTrimmed = draft.subnetwork.trim();
          const subnetworkValid = subnetworkTrimmed === "" || parseBytes32(subnetworkTrimmed) !== null;
          const isFocused = focusedNetworkId === network.id;
          const isNetworkHovered = hoveredNetworkId === network.id;
          const handleNetworkClick = (event: MouseEvent<HTMLDivElement>) => {
            event.stopPropagation();
            if (isInteractiveTarget(event.target)) return;
            if (!props.onZoomNetwork) return;
            props.onZoomNetwork(network.id);
          };
          const handleNetworkHover = (event: MouseEvent<HTMLDivElement>) => {
            const target = event.target as HTMLElement | null;
            const isOverNoZoom = Boolean(target && target.closest("[data-no-zoom]"));
            if (isOverNoZoom) {
              setHoveredNetworkId((prev) => (prev === network.id ? null : prev));
              return;
            }
            setHoveredNetworkId((prev) => (prev === network.id ? prev : network.id));
          };
          const handleNetworkLeave = () => {
            setHoveredNetworkId((prev) => (prev === network.id ? null : prev));
          };
          return (
            <NetworkCard
              key={network.id}
              network={network}
              networkIndex={networkIndex}
              allocatedPct={allocatedPct}
              pendingPct={pendingPct}
              allocatedDisplay={allocatedDisplay}
              pendingDisplay={pendingDisplay}
              isShared={isShared}
              isFocused={isFocused}
              isHovered={isNetworkHovered}
              zoomable={Boolean(props.onZoomNetwork)}
              networkGrow={networkGrow}
              networkWidthPct={networkWidthPct}
              sizeInvalid={draft.size.trim() !== "" && !sizeValid}
              subnetworkInvalid={subnetworkTrimmed !== "" && !subnetworkValid}
              onCopyIndex={props.onCopyIndex}
              onSubnetworkChange={(value) => props.onUpdateNetworkDraft(network.id, { subnetwork: value })}
              onSizeChange={(value) => props.onUpdateNetworkDraft(network.id, { size: value })}
              onCardClick={handleNetworkClick}
              onCardHover={handleNetworkHover}
              onCardLeave={handleNetworkLeave}
            >
              <OperatorsRow
                network={network}
                slotIdToIndex={props.slotIdToIndex}
                allocatedByIndex={props.allocatedByIndex}
                allocationsLoading={props.allocationsLoading}
                pendingByIndex={props.pendingByIndex}
                pendingLoading={props.pendingLoading}
                canReadBalances={props.canReadBalances}
                hasRootBalance={props.hasRootBalance}
                onCopyIndex={props.onCopyIndex}
                onAddOperator={() => props.onAddOperator(network.id)}
                onUpdateOperatorDraft={(operatorId, patch) =>
                  props.onUpdateOperatorDraft(network.id, operatorId, patch)
                }
              />
            </NetworkCard>
          );
        })}

        {showAddNetwork ? (
          <AddSlotButton
            key="add-network"
            ref={addButtonRef}
            label="Add network"
            className={[
              isShared || !hasNetworks
                ? "flex w-full min-w-0 cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-200 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
                : "flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-200 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100",
            ].join(" ")}
            onClick={props.onAddNetwork}
            dataNoZoom
          />
        ) : null}
      </div>
    </div>
  );
}

function OperatorsRow(props: {
  network: NetworkSlot;
  slotIdToIndex: Map<string, bigint>;
  allocatedByIndex: Map<string, bigint>;
  allocationsLoading: boolean;
  pendingByIndex: Map<string, bigint>;
  pendingLoading: boolean;
  canReadBalances: boolean;
  hasRootBalance: boolean;
  onCopyIndex: (index: bigint) => void;
  onAddOperator: () => void;
  onUpdateOperatorDraft: (operatorId: string, patch: Partial<OperatorDraft>) => void;
}) {
  const hasOperators = props.network.operators.length > 0;
  const addButtonRef = useRef<HTMLButtonElement | null>(null);
  const prevOperatorsCount = useRef(props.network.operators.length);
  useEffect(() => {
    const current = props.network.operators.length;
    if (current > prevOperatorsCount.current && addButtonRef.current) {
      addButtonRef.current.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "end" });
    }
    prevOperatorsCount.current = current;
  }, [props.network.operators.length]);

  const operatorSizeValues = props.network.operators.map((operator) => effectiveSize(operator.state));
  const operatorsTotalSize = sumBigints(operatorSizeValues);

  return (
    <div className="mt-3 cursor-default" data-no-zoom>
      <div className="flex flex-row flex-nowrap gap-2 overflow-x-auto pb-2">
        {props.network.operators.map((operator, operatorPos) => {
          const draft = operator.state.draft;
          const operatorIndex = props.slotIdToIndex.get(operator.id);
          const sizeValid = parseUint(draft.size) !== null;
          const widthSizeValue = operatorSizeValues[operatorPos] ?? 0n;
          const operatorGrow = flexGrowFromSize(widthSizeValue, operatorsTotalSize);
          const fillSizeValue = effectiveSize(operator.state);
          const metrics = computeSlotMetrics({
            index: operatorIndex,
            size: fillSizeValue,
            allocationsByIndex: props.allocatedByIndex,
            pendingByIndex: props.pendingByIndex,
          });
          const { allocatedValue, pendingValue, allocatedPct, pendingPct } = metrics;
          const allocatedDisplay = formatBalanceDisplay({
            canReadBalances: props.canReadBalances,
            hasRootBalance: props.hasRootBalance,
            indexDefined: operatorIndex !== undefined,
            loading: props.allocationsLoading || props.pendingLoading,
            value: allocatedValue,
          });
          const pendingDisplay = formatBalanceDisplay({
            canReadBalances: props.canReadBalances,
            hasRootBalance: props.hasRootBalance,
            indexDefined: operatorIndex !== undefined,
            loading: props.pendingLoading,
            value: pendingValue,
          });
          const operatorTrimmed = draft.operator.trim();
          const operatorValid = operatorTrimmed === "" || isAddress(operatorTrimmed);
          return (
            <OperatorCard
              key={operator.id}
              operator={operator}
              operatorIndex={operatorIndex}
              allocatedPct={allocatedPct}
              pendingPct={pendingPct}
              allocatedDisplay={allocatedDisplay}
              pendingDisplay={pendingDisplay}
              operatorGrow={operatorGrow}
              sizeInvalid={draft.size.trim() !== "" && !sizeValid}
              operatorInvalid={operatorTrimmed !== "" && !operatorValid}
              onCopyIndex={props.onCopyIndex}
              onOperatorChange={(value) => props.onUpdateOperatorDraft(operator.id, { operator: value })}
              onSizeChange={(value) => props.onUpdateOperatorDraft(operator.id, { size: value })}
            />
          );
        })}

        <AddSlotButton
          key="add-operator"
          ref={addButtonRef}
          label="Add operator"
          className={[
            hasOperators
              ? "flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
              : "flex w-full min-w-0 cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100",
          ].join(" ")}
          onClick={props.onAddOperator}
          dataNoZoom
        />
      </div>
    </div>
  );
}
