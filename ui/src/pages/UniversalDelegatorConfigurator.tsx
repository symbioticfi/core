import { usePrivy } from "@privy-io/react-auth";
import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type MouseEvent } from "react";
import { useAccount, usePublicClient, useReadContracts, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import {
  type Address,
  BaseError,
  ContractFunctionRevertedError,
  type Hex,
  type PublicClient,
  decodeEventLog,
  encodeFunctionData,
  getEventSelector,
  isAddress,
  isHex,
  padHex,
} from "viem";

import { universalDelegatorAbi } from "../contracts/universalDelegator";
import { createIndex, formatIndex, getChildIndex, getDepth, getParentIndex } from "../utils/universalDelegatorIndex";

const UNIVERSAL_DELEGATOR_EVENT_ABI = universalDelegatorAbi.filter((item) => item.type === "event") as unknown as Array<
  (typeof universalDelegatorAbi)[number]
>;

const UNIVERSAL_DELEGATOR_EVENT_TOPICS = new Set<string>(
  UNIVERSAL_DELEGATOR_EVENT_ABI.map((event) => getEventSelector(event as never)),
);

type SlotSizeInput = string;

type DraftState<T> = {
  draft: T;
  synced: T | null;
};

type GroupDraft = { size: SlotSizeInput; isShared: boolean };
type NetworkDraft = { size: SlotSizeInput; subnetwork: string };
type OperatorDraft = { size: SlotSizeInput; operator: string };

type OperatorSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<OperatorDraft>;
};

type NetworkSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<NetworkDraft>;
  operators: OperatorSlot[];
};

type GroupSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<GroupDraft>;
  networks: NetworkSlot[];
};

type UniversalDelegatorModel = {
  groups: GroupSlot[];
};

type ZoomState =
  | { kind: "all" }
  | { kind: "group"; groupId: string }
  | { kind: "network"; groupId: string; networkId: string };

type GroupConstructor = "shared-multi" | "shared-single" | "single-multi" | "single-single";

type UdOperation =
  | { kind: "createSlot"; parentIndex: bigint; isShared: boolean; size: bigint; slotId?: string }
  | { kind: "setIsShared"; index: bigint; isShared: boolean }
  | { kind: "setSize"; index: bigint; size: bigint }
  | { kind: "swapSlots"; index1: bigint; index2: bigint }
  | { kind: "assignNetwork"; index: bigint; subnetwork: Hex }
  | { kind: "unassignNetwork"; subnetwork: Hex }
  | { kind: "assignOperator"; index: bigint; operator: Address }
  | { kind: "unassignOperator"; parentIndex: bigint; operator: Address };

function parseUint(value: string): bigint | null {
  const normalized = value.trim();
  if (!normalized) return 0n;
  try {
    const parsed = BigInt(normalized);
    if (parsed < 0n) return null;
    return parsed;
  } catch {
    return null;
  }
}

function parseBytes32(value: string): Hex | null {
  const v = value.trim();
  if (!v) return null;

  if (!v.startsWith("0x")) return null;
  if (!isHex(v)) return null;
  if (v.length > 66) return null;
  return padHex(v, { size: 32, dir: "right" });
}

type HasSize = { size: SlotSizeInput };

function effectiveSize(state: DraftState<HasSize>): bigint {
  const draft = parseUint(state.draft.size);
  if (draft !== null) return draft;
  const synced = state.synced ? parseUint(state.synced.size) : null;
  return synced ?? 0n;
}

function sumBigints(values: bigint[]): bigint {
  let total = 0n;
  for (const v of values) total += v;
  return total;
}

function maxBigint(values: bigint[]): bigint {
  let m = 0n;
  for (const v of values) if (v > m) m = v;
  return m;
}

const FILL_OPACITY = 0.2;

function pendingPatternStyle(colorVar: string): CSSProperties {
  const lineColor = `var(${colorVar})`;
  return {
    backgroundImage: `linear-gradient(${lineColor} 0 2px, transparent 2px 10px), linear-gradient(90deg, ${lineColor} 0 2px, transparent 2px 10px)`,
    backgroundSize: "10px 10px",
    backgroundPosition: "-1px -1px",
    backgroundRepeat: "repeat",
    opacity: FILL_OPACITY,
  };
}

function allocatedFillStyle(colorVar: string): CSSProperties {
  return { backgroundColor: `var(${colorVar})`, opacity: FILL_OPACITY };
}

function isInteractiveTarget(target: EventTarget | null): boolean {
  const element = target as HTMLElement | null;
  if (!element || typeof element.closest !== "function") return false;
  return Boolean(element.closest("button, input, textarea, select, label, a, [data-no-zoom]"));
}

function formatShortAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function parsePositiveInt(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

function cloneOps(values: UdOperation[]): UdOperation[] {
  return values.map((op) => ({ ...op }));
}

function cloneModel(values: UniversalDelegatorModel): UniversalDelegatorModel {
  return {
    groups: values.groups.map((group) => ({
      id: group.id,
      index: group.index,
      state: {
        draft: { ...group.state.draft },
        synced: group.state.synced ? { ...group.state.synced } : null,
      },
      networks: group.networks.map((network) => ({
        id: network.id,
        index: network.index,
        state: {
          draft: { ...network.state.draft },
          synced: network.state.synced ? { ...network.state.synced } : null,
        },
        operators: network.operators.map((operator) => ({
          id: operator.id,
          index: operator.index,
          state: {
            draft: { ...operator.state.draft },
            synced: operator.state.synced ? { ...operator.state.synced } : null,
          },
        })),
      })),
    })),
  };
}

type OnchainSlotSnapshot = { size: bigint; isShared: boolean };

function latestTrace208Value(trace: unknown): bigint {
  const checkpoints = (trace as { _trace?: { _checkpoints?: Array<{ _value: bigint }> } })?._trace?._checkpoints;
  if (!checkpoints || checkpoints.length === 0) return 0n;
  return checkpoints[checkpoints.length - 1]?._value ?? 0n;
}

function ensureChildren(map: Map<bigint, bigint[]>, parentIndex: bigint): bigint[] {
  const existing = map.get(parentIndex);
  if (existing) return existing;
  const created: bigint[] = [];
  map.set(parentIndex, created);
  return created;
}

function bigintMin(a: bigint, b: bigint): bigint {
  return a < b ? a : b;
}

function bigintMax(a: bigint, b: bigint): bigint {
  return a > b ? a : b;
}

function saturatingSub(a: bigint, b: bigint): bigint {
  return a > b ? a - b : 0n;
}

function computeSlotIdToIndex(model: UniversalDelegatorModel): Map<string, bigint> {
  const idToIndex = new Map<string, bigint>();

  let maxGroupChild = 0n;
  for (const group of model.groups) {
    if (group.index === null) continue;
    maxGroupChild = bigintMax(maxGroupChild, getChildIndex(group.index));
  }
  let nextGroupChild = maxGroupChild + 1n;

  for (const group of model.groups) {
    const groupIndex = group.index ?? createIndex(0n, nextGroupChild++);
    idToIndex.set(group.id, groupIndex);

    let maxNetworkChild = 0n;
    for (const network of group.networks) {
      if (network.index === null) continue;
      maxNetworkChild = bigintMax(maxNetworkChild, getChildIndex(network.index));
    }
    let nextNetworkChild = maxNetworkChild + 1n;

    for (const network of group.networks) {
      const networkIndex = network.index ?? createIndex(groupIndex, nextNetworkChild++);
      idToIndex.set(network.id, networkIndex);

      let maxOperatorChild = 0n;
      for (const operator of network.operators) {
        if (operator.index === null) continue;
        maxOperatorChild = bigintMax(maxOperatorChild, getChildIndex(operator.index));
      }
      let nextOperatorChild = maxOperatorChild + 1n;

      for (const operator of network.operators) {
        const operatorIndex = operator.index ?? createIndex(networkIndex, nextOperatorChild++);
        idToIndex.set(operator.id, operatorIndex);
      }
    }
  }

  return idToIndex;
}

function computeSimulatedAllocations(
  model: UniversalDelegatorModel,
  slotIdToIndex: Map<string, bigint>,
  rootActiveStake: bigint | null,
): Map<string, bigint> {
  const allocatedByIndex = new Map<string, bigint>();
  const rootBalance = rootActiveStake ?? 0n;
  allocatedByIndex.set("0", rootBalance);

  let groupPrevSum = 0n;
  for (const group of model.groups) {
    const groupSize = effectiveSize(group.state);
    const groupAllocated = bigintMin(saturatingSub(rootBalance, groupPrevSum), groupSize);
    const groupIndex = slotIdToIndex.get(group.id);
    if (groupIndex !== undefined) allocatedByIndex.set(groupIndex.toString(), groupAllocated);
    groupPrevSum += groupSize;

    const groupIsShared = group.state.draft.isShared;
    let networkPrevSum = 0n;
    for (const network of group.networks) {
      const networkSize = effectiveSize(network.state);
      const networkAllocated = groupIsShared
        ? bigintMin(groupAllocated, networkSize)
        : bigintMin(saturatingSub(groupAllocated, networkPrevSum), networkSize);
      const networkIndex = slotIdToIndex.get(network.id);
      if (networkIndex !== undefined) allocatedByIndex.set(networkIndex.toString(), networkAllocated);
      networkPrevSum += networkSize;

      let operatorPrevSum = 0n;
      for (const operator of network.operators) {
        const operatorSize = effectiveSize(operator.state);
        const operatorAllocated = bigintMin(saturatingSub(networkAllocated, operatorPrevSum), operatorSize);
        const operatorIndex = slotIdToIndex.get(operator.id);
        if (operatorIndex !== undefined) allocatedByIndex.set(operatorIndex.toString(), operatorAllocated);
        operatorPrevSum += operatorSize;
      }
    }
  }

  return allocatedByIndex;
}

function computePendingByIndex(params: {
  model: UniversalDelegatorModel;
  slotIdToIndex: Map<string, bigint>;
  baselineSlotIdToIndex: Map<string, bigint>;
  baselineAllocationsByIndex: Map<string, bigint>;
}): Map<string, bigint> {
  const pendingByIndex = new Map<string, bigint>();
  const baselineAllocations = params.baselineAllocationsByIndex;
  const baselineIndices = params.baselineSlotIdToIndex;

  const baselineAllocatedFor = (slotId: string): bigint => {
    const baselineIndex = baselineIndices.get(slotId);
    if (baselineIndex === undefined) return 0n;
    return baselineAllocations.get(baselineIndex.toString()) ?? 0n;
  };

  let rootPending = 0n;
  for (const group of params.model.groups) {
    let groupPending = 0n;
    for (const network of group.networks) {
      let networkPending = 0n;
      for (const operator of network.operators) {
        const operatorIndex = params.slotIdToIndex.get(operator.id);
        if (operatorIndex !== undefined) pendingByIndex.set(operatorIndex.toString(), 0n);

        const baselineAllocated = baselineAllocatedFor(operator.id);
        const nextSize = effectiveSize(operator.state);
        if (baselineAllocated > nextSize) {
          networkPending += baselineAllocated - nextSize;
        }
      }

      const networkIndex = params.slotIdToIndex.get(network.id);
      if (networkIndex !== undefined) pendingByIndex.set(networkIndex.toString(), networkPending);

      const baselineAllocated = baselineAllocatedFor(network.id);
      const nextSize = effectiveSize(network.state);
      if (baselineAllocated > nextSize) {
        groupPending += baselineAllocated - nextSize;
      }
    }

    const groupIndex = params.slotIdToIndex.get(group.id);
    if (groupIndex !== undefined) pendingByIndex.set(groupIndex.toString(), groupPending);

    const baselineAllocated = baselineAllocatedFor(group.id);
    const nextSize = effectiveSize(group.state);
    if (baselineAllocated > nextSize) {
      rootPending += baselineAllocated - nextSize;
    }
  }

  pendingByIndex.set("0", rootPending);
  return pendingByIndex;
}

function computeSimulatedAllocationsFromStateWithPending(
  state: SimState,
  rootBalance: bigint,
  pendingByIndex: Map<bigint, bigint>,
): Map<bigint, bigint> {
  const allocated = new Map<bigint, bigint>();
  allocated.set(0n, rootBalance);

  const walk = (parentIndex: bigint) => {
    const children = state.children.get(parentIndex) ?? [];
    const parentAllocated = allocated.get(parentIndex) ?? 0n;
    const parentPending = pendingByIndex.get(parentIndex) ?? 0n;
    const parentAvailable = saturatingSub(parentAllocated, parentPending);
    const parentSlot = state.slots.get(parentIndex);
    const parentIsShared = parentIndex === 0n ? false : (parentSlot?.isShared ?? false);

    let prevSum = 0n;
    for (const child of children) {
      const childSlot = state.slots.get(child) ?? { size: 0n, isShared: false };
      const childAllocated = parentIsShared
        ? bigintMin(parentAvailable, childSlot.size)
        : bigintMin(saturatingSub(parentAvailable, prevSum), childSlot.size);
      allocated.set(child, childAllocated);
      prevSum += childSlot.size;
      walk(child);
    }
  };

  walk(0n);
  return allocated;
}

function computePendingByIndexFromOps(params: {
  baselineModel: UniversalDelegatorModel;
  ops: UdOperation[];
  rootActiveStake: bigint | null;
  baselinePendingByIndex?: Map<string, bigint> | null;
}): Map<string, bigint> {
  if (params.ops.length === 0) return new Map();

  const state = buildSimStateFromModel(params.baselineModel);
  const pendingByIndex = new Map<bigint, bigint>();
  if (params.baselinePendingByIndex) {
    for (const [key, value] of params.baselinePendingByIndex.entries()) {
      if (value <= 0n) continue;
      try {
        pendingByIndex.set(BigInt(key), value);
      } catch {
        // ignore invalid pending keys
      }
    }
  }
  const rootBalance = params.rootActiveStake ?? 0n;

  const addPending = (index: bigint, delta: bigint) => {
    if (delta <= 0n) return;
    pendingByIndex.set(index, (pendingByIndex.get(index) ?? 0n) + delta);
  };

  for (const op of params.ops) {
    if (op.kind === "createSlot") {
      const local = state.nextChildLocalIndex.get(op.parentIndex) ?? 1n;
      let index: bigint;
      try {
        index = createIndex(op.parentIndex, local);
      } catch {
        return new Map();
      }

      state.nextChildLocalIndex.set(op.parentIndex, local + 1n);
      state.created.add(index);
      state.slots.set(index, { size: op.size, isShared: op.isShared });

      if (!state.children.has(op.parentIndex)) state.children.set(op.parentIndex, []);
      state.children.get(op.parentIndex)!.push(index);
      if (!state.children.has(index)) state.children.set(index, []);
      continue;
    }

    if (op.kind === "setIsShared") {
      const prev = state.slots.get(op.index) ?? { size: 0n, isShared: false };
      state.slots.set(op.index, { ...prev, isShared: op.isShared });
      continue;
    }

    if (op.kind === "setSize") {
      const prev = state.slots.get(op.index) ?? { size: 0n, isShared: false };
      if (op.size < prev.size) {
        const allocated = computeSimulatedAllocationsFromStateWithPending(state, rootBalance, pendingByIndex);
        const allocatedNow = allocated.get(op.index) ?? 0n;
        if (allocatedNow > op.size) {
          addPending(getParentIndex(op.index), allocatedNow - op.size);
        }
      }
      state.slots.set(op.index, { ...prev, size: op.size });
      continue;
    }

    if (op.kind === "swapSlots") {
      const parent = getParentIndex(op.index1);
      const list = state.children.get(parent);
      if (!list) return new Map();
      const i1 = list.indexOf(op.index1);
      const i2 = list.indexOf(op.index2);
      if (i1 === -1 || i2 === -1) return new Map();
      [list[i1], list[i2]] = [list[i2]!, list[i1]!];
      continue;
    }

    if (op.kind === "assignNetwork") {
      state.networkToSlot.set(op.subnetwork.toLowerCase(), op.index);
      continue;
    }

    if (op.kind === "unassignNetwork") {
      state.networkToSlot.set(op.subnetwork.toLowerCase(), 0n);
      continue;
    }

    if (op.kind === "assignOperator") {
      const parentIndex = getParentIndex(op.index);
      const key = `${parentIndex.toString()}:${op.operator.toLowerCase()}`;
      state.operatorToSlot.set(key, op.index);
      state.operatorBySlot.set(op.index, op.operator);
      continue;
    }

    const key = `${op.parentIndex.toString()}:${op.operator.toLowerCase()}`;
    const currentIndex = state.operatorToSlot.get(key) ?? 0n;
    if (currentIndex !== 0n) state.operatorBySlot.delete(currentIndex);
    state.operatorToSlot.set(key, 0n);
  }

  const result = new Map<string, bigint>();
  for (const [index, value] of pendingByIndex.entries()) {
    result.set(index.toString(), value);
  }
  return result;
}

function computeSimulatedAllocationsWithPending(params: {
  model: UniversalDelegatorModel;
  slotIdToIndex: Map<string, bigint>;
  baselineSlotIdToIndex: Map<string, bigint>;
  baselineAllocationsByIndex: Map<string, bigint>;
  rootActiveStake: bigint | null;
  pendingByIndexOverride?: Map<string, bigint> | null;
}): { allocatedByIndex: Map<string, bigint>; pendingByIndex: Map<string, bigint> } {
  const allocatedByIndex = new Map<string, bigint>();
  const rootBalance = params.rootActiveStake ?? 0n;
  const pendingByIndex =
    params.pendingByIndexOverride ??
    computePendingByIndex({
      model: params.model,
      slotIdToIndex: params.slotIdToIndex,
      baselineSlotIdToIndex: params.baselineSlotIdToIndex,
      baselineAllocationsByIndex: params.baselineAllocationsByIndex,
    });
  const rootPending = pendingByIndex.get("0") ?? 0n;
  const rootAvailable = saturatingSub(rootBalance, rootPending);

  allocatedByIndex.set("0", rootBalance);

  let groupPrevSum = 0n;
  for (const group of params.model.groups) {
    const groupSize = effectiveSize(group.state);
    const groupAllocated = bigintMin(saturatingSub(rootAvailable, groupPrevSum), groupSize);
    const groupIndex = params.slotIdToIndex.get(group.id);
    if (groupIndex !== undefined) allocatedByIndex.set(groupIndex.toString(), groupAllocated);
    groupPrevSum += groupSize;

    const groupIsShared = group.state.draft.isShared;
    const groupPending = groupIndex !== undefined ? (pendingByIndex.get(groupIndex.toString()) ?? 0n) : 0n;
    const groupAvailable = saturatingSub(groupAllocated, groupPending);
    let networkPrevSum = 0n;
    for (const network of group.networks) {
      const networkSize = effectiveSize(network.state);
      const networkAllocated = groupIsShared
        ? bigintMin(groupAvailable, networkSize)
        : bigintMin(saturatingSub(groupAvailable, networkPrevSum), networkSize);
      const networkIndex = params.slotIdToIndex.get(network.id);
      if (networkIndex !== undefined) allocatedByIndex.set(networkIndex.toString(), networkAllocated);
      networkPrevSum += networkSize;

      const networkPending = networkIndex !== undefined ? (pendingByIndex.get(networkIndex.toString()) ?? 0n) : 0n;
      const networkAvailable = saturatingSub(networkAllocated, networkPending);
      let operatorPrevSum = 0n;
      for (const operator of network.operators) {
        const operatorSize = effectiveSize(operator.state);
        const operatorAllocated = bigintMin(saturatingSub(networkAvailable, operatorPrevSum), operatorSize);
        const operatorIndex = params.slotIdToIndex.get(operator.id);
        if (operatorIndex !== undefined) allocatedByIndex.set(operatorIndex.toString(), operatorAllocated);
        operatorPrevSum += operatorSize;
      }
    }
  }

  return { allocatedByIndex, pendingByIndex };
}

async function reconstructModelFromChain(params: {
  delegatorAddress: Address;
  publicClient: PublicClient;
}): Promise<UniversalDelegatorModel> {
  const latestBlock = await params.publicClient.getBlockNumber();

  const slots = new Map<bigint, OnchainSlotSnapshot>();
  const childrenByParent = new Map<bigint, bigint[]>();
  const networkBySlot = new Map<bigint, Hex>();
  const subnetworkToSlot = new Map<string, bigint>();
  const operatorBySlot = new Map<bigint, Address>();

  const chunkSize = 50_000n;
  for (let fromBlock = 0n; fromBlock <= latestBlock; fromBlock += chunkSize) {
    const toBlock = (() => {
      const candidate = fromBlock + chunkSize - 1n;
      return candidate > latestBlock ? latestBlock : candidate;
    })();

    const rawLogs = await params.publicClient.getLogs({
      address: params.delegatorAddress,
      fromBlock,
      toBlock,
    });

    for (const log of rawLogs) {
      const topic0 = log.topics?.[0] as string | undefined;
      if (!topic0 || !UNIVERSAL_DELEGATOR_EVENT_TOPICS.has(topic0)) continue;

      const decoded = decodeEventLog({
        abi: UNIVERSAL_DELEGATOR_EVENT_ABI as never,
        data: log.data,
        topics: log.topics,
      });

      if (decoded.eventName === "CreateSlot") {
        const args = decoded.args as unknown as { index: bigint; size: bigint };
        const index = args.index;
        const size = args.size;
        slots.set(index, { size, isShared: false });
        const parentIndex = getParentIndex(index);
        ensureChildren(childrenByParent, parentIndex).push(index);
        continue;
      }

      if (decoded.eventName === "SetSize") {
        const args = decoded.args as unknown as { index: bigint; size: bigint };
        const index = args.index;
        const size = args.size;
        const existing = slots.get(index);
        if (existing) slots.set(index, { ...existing, size });
        continue;
      }

      if (decoded.eventName === "SetIsShared") {
        const args = decoded.args as unknown as { index: bigint; isShared: boolean };
        const index = args.index;
        const isShared = args.isShared;
        const existing = slots.get(index);
        if (existing) slots.set(index, { ...existing, isShared });
        continue;
      }

      if (decoded.eventName === "SwapSlots") {
        const args = decoded.args as unknown as { index1: bigint; index2: bigint };
        const index1 = args.index1;
        const index2 = args.index2;
        const parentIndex = getParentIndex(index1);
        if (parentIndex !== getParentIndex(index2)) continue;
        const siblings = childrenByParent.get(parentIndex);
        if (!siblings) continue;
        const i1 = siblings.indexOf(index1);
        const i2 = siblings.indexOf(index2);
        if (i1 === -1 || i2 === -1) continue;
        [siblings[i1], siblings[i2]] = [siblings[i2]!, siblings[i1]!];
        continue;
      }

      if (decoded.eventName === "AssignNetwork") {
        const args = decoded.args as unknown as { index: bigint; subnetwork: Hex };
        const index = args.index;
        const subnetwork = args.subnetwork;
        const key = subnetwork.toLowerCase();
        subnetworkToSlot.set(key, index);
        networkBySlot.set(index, subnetwork);
        continue;
      }

      if (decoded.eventName === "UnassignNetwork") {
        const args = decoded.args as unknown as { subnetwork: Hex };
        const subnetwork = args.subnetwork;
        const key = subnetwork.toLowerCase();
        const prevIndex = subnetworkToSlot.get(key);
        if (prevIndex !== undefined) networkBySlot.delete(prevIndex);
        subnetworkToSlot.delete(key);
        continue;
      }

      if (decoded.eventName === "AssignOperator") {
        const args = decoded.args as unknown as { index: bigint; operator: Address };
        const index = args.index;
        const operator = args.operator;
        operatorBySlot.set(index, operator);
        continue;
      }

      if (decoded.eventName === "UnassignOperator") {
        const args = decoded.args as unknown as { index: bigint };
        const index = args.index;
        operatorBySlot.delete(index);
        continue;
      }
    }
  }

  const groupIndices = childrenByParent.get(0n) ?? [];
  const applyIsShared = (groupIndex: bigint, slotData: unknown) => {
    const slot = slots.get(groupIndex);
    if (!slot) return;
    const isSharedTrace =
      (slotData as { isShared?: unknown })?.isShared ?? (Array.isArray(slotData) ? slotData[2] : undefined);
    const isSharedValue = latestTrace208Value(isSharedTrace);
    slots.set(groupIndex, { ...slot, isShared: isSharedValue > 0n });
  };

  if (groupIndices.length > 0) {
    const batchSize = 100;
    let canUseMulticall = true;
    for (let i = 0; i < groupIndices.length; i += batchSize) {
      const batch = groupIndices.slice(i, i + batchSize);
      if (canUseMulticall) {
        try {
          const results = await params.publicClient.multicall({
            allowFailure: true,
            contracts: batch.map((groupIndex) => ({
              address: params.delegatorAddress,
              abi: universalDelegatorAbi,
              functionName: "slots",
              args: [groupIndex],
            })),
          });
          results.forEach((result, idx) => {
            if (result.status !== "success") return;
            const groupIndex = batch[idx];
            if (groupIndex === undefined) return;
            applyIsShared(groupIndex, result.result);
          });
          continue;
        } catch {
          canUseMulticall = false;
        }
      }

      for (const groupIndex of batch) {
        const slot = slots.get(groupIndex);
        if (!slot) continue;
        try {
          const slotData = await params.publicClient.readContract({
            abi: universalDelegatorAbi,
            address: params.delegatorAddress,
            functionName: "slots",
            args: [groupIndex],
          });
          applyIsShared(groupIndex, slotData);
        } catch {
          // ignore single-slot failures during reconstruction
        }
      }
    }
  }

  const groups: GroupSlot[] = [];
  for (const groupIndex of groupIndices) {
    const groupSlot = slots.get(groupIndex);
    if (!groupSlot) continue;

    const groupDraft: GroupDraft = { size: groupSlot.size.toString(), isShared: groupSlot.isShared };
    const group: GroupSlot = {
      id: `group-${formatIndex(groupIndex)}`,
      index: groupIndex,
      state: { draft: groupDraft, synced: { ...groupDraft } },
      networks: [],
    };

    const networkIndices = childrenByParent.get(groupIndex) ?? [];
    for (const networkIndex of networkIndices) {
      const networkSlot = slots.get(networkIndex);
      if (!networkSlot) continue;

      const subnetwork = networkBySlot.get(networkIndex) ?? "";
      const networkDraft: NetworkDraft = { size: networkSlot.size.toString(), subnetwork };
      const network: NetworkSlot = {
        id: `network-${formatIndex(networkIndex)}`,
        index: networkIndex,
        state: { draft: networkDraft, synced: { ...networkDraft } },
        operators: [],
      };

      const operatorIndices = childrenByParent.get(networkIndex) ?? [];
      for (const operatorIndex of operatorIndices) {
        const operatorSlot = slots.get(operatorIndex);
        if (!operatorSlot) continue;

        const operator = operatorBySlot.get(operatorIndex) ?? "";
        const operatorDraft: OperatorDraft = { size: operatorSlot.size.toString(), operator };
        network.operators.push({
          id: `operator-${formatIndex(operatorIndex)}`,
          index: operatorIndex,
          state: { draft: operatorDraft, synced: { ...operatorDraft } },
        });
      }

      group.networks.push(network);
    }

    groups.push(group);
  }

  return { groups };
}

function flexGrowFromSize(size: bigint, total: bigint): number {
  if (total <= 0n) return 1;
  if (size <= 0n) return 0;
  const scaled = (size * 1_000_000n) / total;
  if (scaled <= 0n) return 0.000001;
  return Number(scaled) / 1_000_000;
}

function percentWidthFromSize(size: bigint, max: bigint, minPct = 40, maxPct = 100): number {
  if (max <= 0n) return maxPct;
  if (size <= 0n) return minPct;
  const scaled = Number((size * 10_000n) / max) / 10_000;
  return minPct + scaled * (maxPct - minPct);
}

function autoSyncAll(model: UniversalDelegatorModel): { model: UniversalDelegatorModel; ops: UdOperation[] } {
  const nextModel = cloneModel(model);
  const nextOps: UdOperation[] = [];

  for (const group of nextModel.groups) {
    // ---------- Group ----------
    {
      const draft = group.state.draft;
      const size = parseUint(draft.size);

      if (size !== null) {
        const synced = group.state.synced;
        const syncedSize = synced ? parseUint(synced.size) : null;
        const sizeDirty = synced === null || syncedSize === null || syncedSize !== size;
        const isDirty = synced === null || synced.isShared !== draft.isShared || sizeDirty;

        if (synced === null || isDirty) {
          if (group.index === null) {
            const localIndex = BigInt(nextModel.groups.filter((g) => g.index !== null).length + 1);
            group.index = createIndex(0n, localIndex);
            nextOps.push({ kind: "createSlot", parentIndex: 0n, isShared: draft.isShared, size, slotId: group.id });
          } else {
            if (synced && synced.isShared !== draft.isShared) {
              nextOps.push({ kind: "setIsShared", index: group.index, isShared: draft.isShared });
            }
            if (synced && sizeDirty) {
              nextOps.push({ kind: "setSize", index: group.index, size });
            }
          }
          group.state.synced = { ...draft };
        }
      }
    }

    // ---------- Networks ----------
    for (const network of group.networks) {
      const draft = network.state.draft;
      const size = parseUint(draft.size);
      if (size === null) continue;
      if (group.index === null) continue;

      const subnetworkTrimmed = draft.subnetwork.trim();
      const subnetworkParsed = subnetworkTrimmed === "" ? null : parseBytes32(subnetworkTrimmed);
      const subnetworkValid = subnetworkTrimmed === "" || subnetworkParsed !== null;

      const synced = network.state.synced;
      const syncedSize = synced ? parseUint(synced.size) : null;
      const isSizeDirty = synced === null || syncedSize === null || syncedSize !== size;
      const isSubnetworkDirty =
        subnetworkValid && (synced === null || synced.subnetwork.trim() !== subnetworkTrimmed);

      if (synced === null || isSizeDirty || isSubnetworkDirty) {
        if (network.index === null) {
          const localIndex = BigInt(group.networks.filter((n) => n.index !== null).length + 1);
          network.index = createIndex(group.index, localIndex);
          nextOps.push({
            kind: "createSlot",
            parentIndex: group.index,
            isShared: false,
            size,
            slotId: network.id,
          });
          if (subnetworkParsed) {
            nextOps.push({ kind: "assignNetwork", index: network.index, subnetwork: subnetworkParsed });
          }
        } else {
          if (synced && isSizeDirty) {
            nextOps.push({ kind: "setSize", index: network.index, size });
          }

          if (synced && isSubnetworkDirty) {
            const prevTrimmed = synced.subnetwork.trim();
            const nextTrimmed = subnetworkTrimmed;
            if (prevTrimmed !== nextTrimmed) {
              const prevParsed = prevTrimmed === "" ? null : parseBytes32(prevTrimmed);
              if (prevParsed) nextOps.push({ kind: "unassignNetwork", subnetwork: prevParsed });
              if (subnetworkParsed) {
                nextOps.push({ kind: "assignNetwork", index: network.index, subnetwork: subnetworkParsed });
              }
            }
          }
        }

        if (synced === null) {
          network.state.synced = {
            ...draft,
            subnetwork: subnetworkValid ? draft.subnetwork : "",
          };
        } else {
          network.state.synced = {
            size: draft.size,
            subnetwork: subnetworkValid ? draft.subnetwork : synced.subnetwork,
          };
        }
      }

      if (network.index === null) continue;

      // ---------- Operators ----------
      for (const operator of network.operators) {
        const draftOp = operator.state.draft;
        const sizeOp = parseUint(draftOp.size);
        if (sizeOp === null) continue;

        const operatorTrimmed = draftOp.operator.trim();
        const operatorValid = operatorTrimmed === "" || isAddress(operatorTrimmed);

        const syncedOp = operator.state.synced;
        const syncedSize = syncedOp ? parseUint(syncedOp.size) : null;
        const isSizeDirtyOp = syncedOp === null || syncedSize === null || syncedSize !== sizeOp;
        const isOperatorDirtyOp =
          operatorValid &&
          (syncedOp === null || syncedOp.operator.trim().toLowerCase() !== operatorTrimmed.toLowerCase());

        if (syncedOp !== null && !isSizeDirtyOp && !isOperatorDirtyOp) continue;

        if (operator.index === null) {
          const localIndex = BigInt(network.operators.filter((o) => o.index !== null).length + 1);
          operator.index = createIndex(network.index, localIndex);
          nextOps.push({
            kind: "createSlot",
            parentIndex: network.index,
            isShared: false,
            size: sizeOp,
            slotId: operator.id,
          });
          if (operatorValid && operatorTrimmed) {
            nextOps.push({ kind: "assignOperator", index: operator.index, operator: operatorTrimmed as Address });
          }
        } else {
          if (syncedOp && isSizeDirtyOp) {
            nextOps.push({ kind: "setSize", index: operator.index, size: sizeOp });
          }

          if (syncedOp && isOperatorDirtyOp) {
            const prevTrimmed = syncedOp.operator.trim();
            const nextTrimmed = operatorTrimmed;
            if (prevTrimmed.toLowerCase() !== nextTrimmed.toLowerCase()) {
              if (prevTrimmed && isAddress(prevTrimmed)) {
                nextOps.push({
                  kind: "unassignOperator",
                  parentIndex: network.index,
                  operator: prevTrimmed as Address,
                });
              }
              if (nextTrimmed) {
                nextOps.push({ kind: "assignOperator", index: operator.index, operator: nextTrimmed as Address });
              }
            }
          }
        }

        if (syncedOp === null) {
          operator.state.synced = { ...draftOp, operator: operatorValid ? draftOp.operator : "" };
        } else {
          operator.state.synced = {
            size: draftOp.size,
            operator: operatorValid ? draftOp.operator : syncedOp.operator,
          };
        }
      }
    }
  }

  return { model: nextModel, ops: nextOps };
}

type SimSlot = { size: bigint; isShared: boolean };

type SimState = {
  children: Map<bigint, bigint[]>;
  slots: Map<bigint, SimSlot>;
  created: Set<bigint>;
  networkToSlot: Map<string, bigint>;
  operatorBySlot: Map<bigint, Address>;
  operatorToSlot: Map<string, bigint>;
  nextChildLocalIndex: Map<bigint, bigint>;
};

function bigintCompare(a: bigint, b: bigint): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function shallowOptimizeOps(ops: UdOperation[]): UdOperation[] {
  const out: UdOperation[] = [];
  for (const op of ops) {
    const last = out[out.length - 1];
    if (!last) {
      out.push(op);
      continue;
    }

    if (last.kind === "setSize" && op.kind === "setSize" && last.index === op.index) {
      out[out.length - 1] = op;
      continue;
    }

    if (last.kind === "setIsShared" && op.kind === "setIsShared" && last.index === op.index) {
      out[out.length - 1] = op;
      continue;
    }

    if (
      last.kind === "swapSlots" &&
      op.kind === "swapSlots" &&
      last.index1 === op.index2 &&
      last.index2 === op.index1
    ) {
      out.pop();
      continue;
    }

    out.push(op);
  }

  return out;
}

function mergeOps(prevOps: UdOperation[], nextOps: UdOperation[]): UdOperation[] {
  if (nextOps.length === 0) return prevOps;
  const merged = prevOps.slice();
  for (const op of nextOps) {
    if (op.kind === "createSlot" && op.slotId) {
      const existingIndex = merged.findIndex((item) => item.kind === "createSlot" && item.slotId === op.slotId);
      if (existingIndex !== -1) {
        merged[existingIndex] = { ...merged[existingIndex], ...op };
        continue;
      }
    }
    merged.push(op);
  }
  return merged;
}

function cloneSimState(state: SimState): SimState {
  return {
    children: new Map([...state.children.entries()].map(([k, v]) => [k, v.slice()])),
    slots: new Map([...state.slots.entries()].map(([k, v]) => [k, { ...v }])),
    created: new Set(state.created),
    networkToSlot: new Map(state.networkToSlot),
    operatorBySlot: new Map(state.operatorBySlot),
    operatorToSlot: new Map(state.operatorToSlot),
    nextChildLocalIndex: new Map(state.nextChildLocalIndex),
  };
}

function buildSimStateFromModel(model: UniversalDelegatorModel): SimState {
  const state: SimState = {
    children: new Map([[0n, []]]),
    slots: new Map(),
    created: new Set([0n]),
    networkToSlot: new Map(),
    operatorBySlot: new Map(),
    operatorToSlot: new Map(),
    nextChildLocalIndex: new Map(),
  };

  for (const group of model.groups) {
    if (group.index === null) continue;
    const groupIndex = group.index;
    const groupSynced = group.state.synced;
    const groupSize = parseUint(groupSynced?.size ?? group.state.draft.size) ?? 0n;
    const groupIsShared = groupSynced?.isShared ?? group.state.draft.isShared;

    state.created.add(groupIndex);
    state.slots.set(groupIndex, { size: groupSize, isShared: groupIsShared });
    state.children.get(0n)!.push(groupIndex);
    if (!state.children.has(groupIndex)) state.children.set(groupIndex, []);

    for (const network of group.networks) {
      if (network.index === null) continue;
      const networkIndex = network.index;
      const networkSynced = network.state.synced;
      const networkSize = parseUint(networkSynced?.size ?? network.state.draft.size) ?? 0n;

      state.created.add(networkIndex);
      state.slots.set(networkIndex, { size: networkSize, isShared: false });
      state.children.get(groupIndex)!.push(networkIndex);
      if (!state.children.has(networkIndex)) state.children.set(networkIndex, []);

      const subnetworkRaw = (networkSynced?.subnetwork ?? network.state.draft.subnetwork).trim();
      const subnetworkParsed = subnetworkRaw === "" ? null : parseBytes32(subnetworkRaw);
      if (subnetworkParsed) {
        state.networkToSlot.set(subnetworkParsed.toLowerCase(), networkIndex);
      }

      for (const operator of network.operators) {
        if (operator.index === null) continue;
        const operatorIndex = operator.index;
        const operatorSynced = operator.state.synced;
        const operatorSize = parseUint(operatorSynced?.size ?? operator.state.draft.size) ?? 0n;

        state.created.add(operatorIndex);
        state.slots.set(operatorIndex, { size: operatorSize, isShared: false });
        state.children.get(networkIndex)!.push(operatorIndex);
        if (!state.children.has(operatorIndex)) state.children.set(operatorIndex, []);

        const operatorRaw = (operatorSynced?.operator ?? operator.state.draft.operator).trim();
        if (operatorRaw !== "" && isAddress(operatorRaw)) {
          const normalized = operatorRaw.toLowerCase();
          state.operatorBySlot.set(operatorIndex, operatorRaw as Address);
          state.operatorToSlot.set(`${networkIndex.toString()}:${normalized}`, operatorIndex);
        }
      }
    }
  }

  for (const [parentIndex, children] of state.children.entries()) {
    let maxChild = 0n;
    for (const child of children) maxChild = bigintMax(maxChild, getChildIndex(child));
    state.nextChildLocalIndex.set(parentIndex, maxChild + 1n);
  }

  if (!state.nextChildLocalIndex.has(0n)) state.nextChildLocalIndex.set(0n, 1n);

  return state;
}

function simulateOpsFromState(initial: SimState, ops: UdOperation[]): SimState | null {
  const state = cloneSimState(initial);

  for (const op of ops) {
    if (op.kind === "createSlot") {
      const local = state.nextChildLocalIndex.get(op.parentIndex) ?? 1n;
      let index: bigint;
      try {
        index = createIndex(op.parentIndex, local);
      } catch {
        return null;
      }

      state.nextChildLocalIndex.set(op.parentIndex, local + 1n);
      state.created.add(index);
      state.slots.set(index, { size: op.size, isShared: op.isShared });

      if (!state.children.has(op.parentIndex)) state.children.set(op.parentIndex, []);
      state.children.get(op.parentIndex)!.push(index);
      if (!state.children.has(index)) state.children.set(index, []);
      continue;
    }

    if (op.kind === "setIsShared") {
      const prev = state.slots.get(op.index) ?? { size: 0n, isShared: false };
      state.slots.set(op.index, { ...prev, isShared: op.isShared });
      continue;
    }

    if (op.kind === "setSize") {
      const prev = state.slots.get(op.index) ?? { size: 0n, isShared: false };
      state.slots.set(op.index, { ...prev, size: op.size });
      continue;
    }

    if (op.kind === "swapSlots") {
      const parent = getParentIndex(op.index1);
      const list = state.children.get(parent);
      if (!list) return null;
      const i1 = list.indexOf(op.index1);
      const i2 = list.indexOf(op.index2);
      if (i1 === -1 || i2 === -1) return null;
      [list[i1], list[i2]] = [list[i2]!, list[i1]!];
      continue;
    }

    if (op.kind === "assignNetwork") {
      state.networkToSlot.set(op.subnetwork.toLowerCase(), op.index);
      continue;
    }

    if (op.kind === "unassignNetwork") {
      state.networkToSlot.set(op.subnetwork.toLowerCase(), 0n);
      continue;
    }

    if (op.kind === "assignOperator") {
      const parentIndex = getParentIndex(op.index);
      const key = `${parentIndex.toString()}:${op.operator.toLowerCase()}`;
      state.operatorToSlot.set(key, op.index);
      state.operatorBySlot.set(op.index, op.operator);
      continue;
    }

    const key = `${op.parentIndex.toString()}:${op.operator.toLowerCase()}`;
    const currentIndex = state.operatorToSlot.get(key) ?? 0n;
    if (currentIndex !== 0n) state.operatorBySlot.delete(currentIndex);
    state.operatorToSlot.set(key, 0n);
  }

  return state;
}

function computeMinimalSwaps(initial: bigint[], target: bigint[]): UdOperation[] | null {
  if (initial.length !== target.length) return null;
  if (initial.length < 2) return [];

  const current = initial.slice();
  const pos = new Map<bigint, number>();
  for (let i = 0; i < current.length; i += 1) pos.set(current[i], i);

  const swaps: UdOperation[] = [];
  for (let i = 0; i < target.length; i += 1) {
    const desired = target[i];
    const currentAt = current[i];
    if (currentAt === desired) continue;

    const j = pos.get(desired);
    if (j === undefined) return null;
    if (j < i) return null;

    swaps.push({ kind: "swapSlots", index1: currentAt, index2: desired });

    current[i] = desired;
    current[j] = currentAt;
    pos.set(currentAt, j);
    pos.set(desired, i);
  }

  return swaps;
}

function compileMinimalOpsFromInitialAndFinal(params: { initial: SimState; final: SimState }): UdOperation[] | null {
  const initialExisting = new Set(params.initial.slots.keys());
  const createOps: UdOperation[] = [];
  const swapOps: UdOperation[] = [];
  const setOps: UdOperation[] = [];
  const assignOps: UdOperation[] = [];

  function slotOrDefault(index: bigint): SimSlot {
    return params.final.slots.get(index) ?? { size: 0n, isShared: false };
  }

  function buildCreates(parentIndex: bigint, depth: number) {
    if (depth >= 3) return;

    const initialChildren = params.initial.children.get(parentIndex) ?? [];
    const finalChildren = params.final.children.get(parentIndex) ?? [];
    const finalSet = new Set(finalChildren);

    const existingChildrenInOrder = initialChildren.filter((child) => finalSet.has(child));
    const newChildren = finalChildren.filter((child) => !initialExisting.has(child));
    const newChildrenSorted = newChildren.slice().sort((a, b) => bigintCompare(getChildIndex(a), getChildIndex(b)));

    const creationOrder = [...existingChildrenInOrder, ...newChildrenSorted];
    for (const child of creationOrder) {
      if (!initialExisting.has(child)) {
        const slot = slotOrDefault(child);
        createOps.push({
          kind: "createSlot",
          parentIndex,
          isShared: parentIndex === 0n ? slot.isShared : false,
          size: slot.size,
        });
      }
      buildCreates(child, depth + 1);
    }
  }

  buildCreates(0n, 0);

  for (const [parentIndex, finalChildren] of params.final.children.entries()) {
    const initialChildren = params.initial.children.get(parentIndex) ?? [];
    const finalSet = new Set(finalChildren);

    const existingChildrenInOrder = initialChildren.filter((child) => finalSet.has(child));
    const newChildren = finalChildren.filter((child) => !initialExisting.has(child));
    const newChildrenSorted = newChildren.slice().sort((a, b) => bigintCompare(getChildIndex(a), getChildIndex(b)));

    const initialAfterCreate = [...existingChildrenInOrder, ...newChildrenSorted];
    const swaps = computeMinimalSwaps(initialAfterCreate, finalChildren);
    if (swaps === null) return null;
    swapOps.push(...swaps);
  }

  for (const [index, finalSlot] of params.final.slots.entries()) {
    if (!initialExisting.has(index)) continue;
    const initialSlot = params.initial.slots.get(index) ?? { size: 0n, isShared: false };
    if (initialSlot.size !== finalSlot.size) {
      setOps.push({ kind: "setSize", index, size: finalSlot.size });
    }
    if (getParentIndex(index) === 0n && initialSlot.isShared !== finalSlot.isShared) {
      setOps.push({ kind: "setIsShared", index, isShared: finalSlot.isShared });
    }
  }

  const allSubnetworks = new Set<string>();
  for (const key of params.initial.networkToSlot.keys()) allSubnetworks.add(key);
  for (const key of params.final.networkToSlot.keys()) allSubnetworks.add(key);
  const subnetworkKeys = [...allSubnetworks].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (const subnetwork of subnetworkKeys) {
    const initialIndex = params.initial.networkToSlot.get(subnetwork) ?? 0n;
    const finalIndex = params.final.networkToSlot.get(subnetwork) ?? 0n;
    if (initialIndex === finalIndex) continue;
    if (initialIndex !== 0n) assignOps.push({ kind: "unassignNetwork", subnetwork: subnetwork as Hex });
    if (finalIndex !== 0n) assignOps.push({ kind: "assignNetwork", index: finalIndex, subnetwork: subnetwork as Hex });
  }

  const allOperators = new Set<string>();
  for (const key of params.initial.operatorToSlot.keys()) allOperators.add(key);
  for (const key of params.final.operatorToSlot.keys()) allOperators.add(key);
  const operatorKeys = [...allOperators].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (const key of operatorKeys) {
    const initialIndex = params.initial.operatorToSlot.get(key) ?? 0n;
    const finalIndex = params.final.operatorToSlot.get(key) ?? 0n;
    if (initialIndex === finalIndex) continue;

    const [parentStr, operator] = key.split(":");
    if (!parentStr || !operator) continue;
    let parentIndex: bigint;
    try {
      parentIndex = BigInt(parentStr);
    } catch {
      continue;
    }
    if (initialIndex !== 0n) {
      assignOps.push({ kind: "unassignOperator", parentIndex, operator: operator as Address });
    }
    if (finalIndex !== 0n) {
      assignOps.push({ kind: "assignOperator", index: finalIndex, operator: operator as Address });
    }
  }

  return [...createOps, ...swapOps, ...setOps, ...assignOps];
}

function compileOpsFromModels(params: {
  baselineModel: UniversalDelegatorModel;
  nextModel: UniversalDelegatorModel;
}): UdOperation[] | null {
  const initial = buildSimStateFromModel(params.baselineModel);
  const final = buildSimStateFromModel(params.nextModel);
  return compileMinimalOpsFromInitialAndFinal({ initial, final });
}

type MulticallCandidate = { label: string; ops: UdOperation[] };

function opsKey(ops: UdOperation[]): string {
  return JSON.stringify(ops.map(opToJson));
}

function buildMulticallCandidates(params: {
  ops: UdOperation[];
  baselineModel: UniversalDelegatorModel;
}): MulticallCandidate[] {
  const candidates: MulticallCandidate[] = [];
  const seen = new Set<string>();

  function push(label: string, list: UdOperation[]) {
    const key = opsKey(list);
    if (seen.has(key)) return;
    seen.add(key);
    candidates.push({ label, ops: list });
  }

  if (params.ops.length === 0) return candidates;

  const initial = buildSimStateFromModel(params.baselineModel);
  const final = simulateOpsFromState(initial, params.ops);
  if (final) {
    const compiled = compileMinimalOpsFromInitialAndFinal({ initial, final });
    if (compiled) {
      push("optimized", compiled);
    }
  }

  push("shallow", shallowOptimizeOps(params.ops));
  push("raw", params.ops);

  return candidates;
}

function candidatePriority(label: string): number {
  if (label === "optimized") return 0;
  if (label === "shallow") return 1;
  return 2;
}

function orderMulticallCandidates(candidates: MulticallCandidate[]): MulticallCandidate[] {
  return candidates
    .slice()
    .sort((a, b) => a.ops.length - b.ops.length || candidatePriority(a.label) - candidatePriority(b.label));
}

function encodeOpsToCalls(ops: UdOperation[]): Hex[] {
  const calls: Hex[] = [];
  for (const op of ops) {
    if (op.kind === "createSlot") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "createSlot",
          args: [op.parentIndex, op.isShared, op.size],
        }),
      );
    } else if (op.kind === "setIsShared") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "setIsShared",
          args: [op.index, op.isShared],
        }),
      );
    } else if (op.kind === "setSize") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "setSize",
          args: [op.index, op.size],
        }),
      );
    } else if (op.kind === "swapSlots") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "swapSlots",
          args: [op.index1, op.index2],
        }),
      );
    } else if (op.kind === "assignNetwork") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "assignNetwork",
          args: [op.index, op.subnetwork],
        }),
      );
    } else if (op.kind === "unassignNetwork") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "unassignNetwork",
          args: [op.subnetwork],
        }),
      );
    } else if (op.kind === "assignOperator") {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "assignOperator",
          args: [op.index, op.operator],
        }),
      );
    } else {
      calls.push(
        encodeFunctionData({
          abi: universalDelegatorAbi,
          functionName: "unassignOperator",
          args: [op.parentIndex, op.operator],
        }),
      );
    }
  }
  return calls;
}

function formatViemError(error: unknown): string {
  if (error instanceof ContractFunctionRevertedError) {
    const data = error.data;
    if (data?.errorName) {
      if (data.args && data.args.length > 0) {
        const args = data.args.map((arg) => String(arg)).join(", ");
        return `${data.errorName}(${args})`;
      }
      return data.errorName;
    }
    if (error.reason) return error.reason;
  }
  if (error instanceof BaseError) return error.shortMessage ?? error.message;
  if (error instanceof Error) return error.message;
  return "Unknown error";
}

function extractRevertName(error: unknown): string | null {
  if (error instanceof ContractFunctionRevertedError) return error.data?.errorName ?? null;
  if (error instanceof BaseError) {
    const nested = error.walk((err) => err instanceof ContractFunctionRevertedError);
    if (nested instanceof ContractFunctionRevertedError) return nested.data?.errorName ?? null;
  }
  return null;
}

type CandidateSimulationResult = {
  candidate: MulticallCandidate;
  status: "success" | "failure";
  error?: unknown;
};

function computeSimulatedAllocationsFromState(state: SimState, rootBalance: bigint): Map<bigint, bigint> {
  const allocated = new Map<bigint, bigint>();
  allocated.set(0n, rootBalance);

  const walk = (parentIndex: bigint) => {
    const children = state.children.get(parentIndex) ?? [];
    const parentAllocated = allocated.get(parentIndex) ?? 0n;
    const parentSlot = state.slots.get(parentIndex);
    const parentIsShared = parentIndex === 0n ? false : (parentSlot?.isShared ?? false);

    let prevSum = 0n;
    for (const child of children) {
      const childSlot = state.slots.get(child) ?? { size: 0n, isShared: false };
      const childAllocated = parentIsShared
        ? bigintMin(parentAllocated, childSlot.size)
        : bigintMin(saturatingSub(parentAllocated, prevSum), childSlot.size);
      allocated.set(child, childAllocated);
      prevSum += childSlot.size;
      walk(child);
    }
  };

  walk(0n);
  return allocated;
}

function describeNotEnoughAvailable(params: {
  ops: UdOperation[];
  failureIndex: number;
  baselineModel: UniversalDelegatorModel;
  rootBalance: bigint | null;
}): string | null {
  const failing = params.ops[params.failureIndex];
  if (!failing || failing.kind !== "setSize") return null;

  const initial = buildSimStateFromModel(params.baselineModel);
  const before = simulateOpsFromState(initial, params.ops.slice(0, params.failureIndex));
  if (!before) return null;

  const prevSize = before.slots.get(failing.index)?.size ?? 0n;
  if (failing.size <= prevSize) return null;
  const increase = failing.size - prevSize;

  const parentIndex = getParentIndex(failing.index);
  const parentDepth = getDepth(parentIndex);
  const childDepth = getDepth(failing.index);
  const parentLabel =
    parentDepth === 0
      ? "root"
      : parentDepth === 1
        ? `Group #${getChildIndex(parentIndex)}`
        : `Network #${getChildIndex(parentIndex)}`;
  const childLabel = childDepth === 1 ? "Group" : childDepth === 2 ? "Network" : "Operator";

  const children = before.children.get(parentIndex) ?? [];
  let childrenSize = 0n;
  for (const child of children) {
    childrenSize += before.slots.get(child)?.size ?? 0n;
  }

  let available: bigint | null = null;
  if (parentIndex === 0n) {
    available = params.rootBalance;
  } else if (params.rootBalance !== null) {
    const allocated = computeSimulatedAllocationsFromState(before, params.rootBalance);
    available = allocated.get(parentIndex) ?? null;
  }
  if (available === null) {
    available = before.slots.get(parentIndex)?.size ?? null;
  }
  if (available === null) return null;

  const unallocated = saturatingSub(available, childrenSize);
  if (increase <= unallocated) return null;
  return `${childLabel} size increase by ${increase.toString()} in ${parentLabel} exceeds available ${unallocated.toString()}.`;
}

async function simulateMulticallCandidates(params: {
  publicClient: PublicClient;
  delegatorAddress: Address;
  account: Address;
  candidates: MulticallCandidate[];
}): Promise<CandidateSimulationResult[]> {
  if (params.candidates.length === 0) return [];
  const calls = params.candidates.map((candidate) => ({
    to: params.delegatorAddress,
    abi: universalDelegatorAbi,
    functionName: "multicall",
    args: [encodeOpsToCalls(candidate.ops)],
  }));
  const { results } = await params.publicClient.simulateCalls({
    account: params.account,
    calls,
  });
  return results.map((result, index) => ({
    candidate: params.candidates[index]!,
    status: result.status,
    error: result.status === "failure" ? result.error : undefined,
  }));
}

async function simulateMulticall(params: {
  publicClient: PublicClient;
  delegatorAddress: Address;
  account: Address;
  calls: Hex[];
}): Promise<void> {
  if (params.calls.length === 0) return;
  await params.publicClient.simulateContract({
    address: params.delegatorAddress,
    abi: universalDelegatorAbi,
    functionName: "multicall",
    args: [params.calls],
    account: params.account,
  });
}

async function findFailingOp(params: {
  publicClient: PublicClient;
  delegatorAddress: Address;
  account: Address;
  ops: UdOperation[];
}): Promise<{ index: number; error: unknown } | null> {
  if (params.ops.length === 0) return null;
  const calls = encodeOpsToCalls(params.ops);
  if (calls.length === 0) return null;

  let low = 0;
  let high = calls.length - 1;
  let failure: { index: number; error: unknown } | null = null;

  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    try {
      await simulateMulticall({
        publicClient: params.publicClient,
        delegatorAddress: params.delegatorAddress,
        account: params.account,
        calls: calls.slice(0, mid + 1),
      });
      low = mid + 1;
    } catch (error) {
      failure = { index: mid, error };
      high = mid - 1;
    }
  }

  return failure;
}

function opsBaselineModel(params: {
  model: UniversalDelegatorModel;
  ops: UdOperation[];
  history: Array<{ model: UniversalDelegatorModel; ops: UdOperation[] }>;
}): UniversalDelegatorModel {
  if (params.ops.length === 0) return params.model;
  for (let i = params.history.length - 1; i >= 0; i -= 1) {
    const snapshot = params.history[i];
    if (snapshot && snapshot.ops.length === 0) return snapshot.model;
  }
  return params.history[0]?.model ?? params.model;
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

        let candidateResults: CandidateSimulationResult[] | null = null;
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
        const balance = index === 0n ? (rootBalance ?? 0n) : (onchainAllocationsByIndex.get(index.toString()) ?? 0n);
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

  const encodedCalls = useMemo(() => encodeOpsToCalls(selectedOps), [selectedOps]);

  const multicallCalldata = useMemo(() => {
    if (encodedCalls.length === 0) return null;
    return encodeFunctionData({
      abi: universalDelegatorAbi,
      functionName: "multicall",
      args: [encodedCalls],
    });
  }, [encodedCalls]);

  function pushHistorySnapshot() {
    setHistory((prev) => [...prev, { model: cloneModel(model), ops: cloneOps(ops) }]);
  }

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
    pushHistorySnapshot();
    const group: GroupSlot = {
      id: newId("group"),
      index: null,
      state: { draft: { size: "", isShared: false }, synced: null },
      networks: [],
    };
    setModel((prev) => ({ ...prev, groups: [...prev.groups, group] }));
  }

  function addGroupFromTemplate() {
    if (!addGroupValid) return;
    pushHistorySnapshot();
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
    setModel((prev) => ({ ...prev, groups: [...prev.groups, group] }));
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
    pushHistorySnapshot();
    setModel((prev) => {
      const updated: UniversalDelegatorModel = {
        ...prev,
        groups: prev.groups.map((g) =>
          g.id === groupId ? { ...g, state: { ...g.state, draft: { ...g.state.draft, ...patch } } } : g,
        ),
      };
      const auto = autoSyncAll(updated);
      setOps((prevOps) => {
        const compiled = compileOpsFromModels({ baselineModel, nextModel: auto.model });
        if (compiled) return compiled;
        if (auto.ops.length === 0) return prevOps;
        return shallowOptimizeOps(mergeOps(prevOps, auto.ops));
      });
      return auto.model;
    });
  }

  function addDraftNetwork(groupId: string) {
    pushHistorySnapshot();
    const group = model.groups.find((g) => g.id === groupId);
    if (!group) return;

    const network: NetworkSlot = {
      id: newId("network"),
      index: null,
      state: { draft: { size: "", subnetwork: "" }, synced: null },
      operators: [],
    };

    setModel((prev) => ({
      ...prev,
      groups: prev.groups.map((g) => (g.id === groupId ? { ...g, networks: [...g.networks, network] } : g)),
    }));
  }

  function updateNetworkDraft(groupId: string, networkId: string, patch: Partial<NetworkDraft>) {
    pushHistorySnapshot();
    setModel((prev) => {
      const updated: UniversalDelegatorModel = {
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
      };
      const auto = autoSyncAll(updated);
      setOps((prevOps) => {
        const compiled = compileOpsFromModels({ baselineModel, nextModel: auto.model });
        if (compiled) return compiled;
        if (auto.ops.length === 0) return prevOps;
        return shallowOptimizeOps(mergeOps(prevOps, auto.ops));
      });
      return auto.model;
    });
  }

  function addDraftOperator(groupId: string, networkId: string) {
    const group = model.groups.find((g) => g.id === groupId);
    const network = group?.networks.find((n) => n.id === networkId);
    if (!network) return;

    pushHistorySnapshot();

    const slot: OperatorSlot = {
      id: newId("operator"),
      index: null,
      state: { draft: { size: "", operator: "" }, synced: null },
    };

    setModel((prev) => ({
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
    pushHistorySnapshot();
    setModel((prev) => {
      const updated: UniversalDelegatorModel = {
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
      };
      const auto = autoSyncAll(updated);
      setOps((prevOps) => {
        const compiled = compileOpsFromModels({ baselineModel, nextModel: auto.model });
        if (compiled) return compiled;
        if (auto.ops.length === 0) return prevOps;
        return shallowOptimizeOps(mergeOps(prevOps, auto.ops));
      });
      return auto.model;
    });
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
    !isValidatingMulticall &&
    !multicallError;

  const groupSizeValues = visibleGroups.map((group) => effectiveSize(group.state));
  const groupTotalSize = sumBigints(groupSizeValues);
  const walletConnected = Boolean(authenticated && isConnected && accountAddress);
  const shortAccountAddress = accountAddress ? formatShortAddress(accountAddress) : "";
  const chainLabel = chain?.name ?? "Unknown chain";
  const walletStatusLabel = walletConnected ? "Wallet connected" : "Wallet disconnected";
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
        <div className="flex-none flex items-center gap-3">
          <div className="hidden sm:flex flex-col gap-1 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-xs shadow-sm">
            <div className="flex items-center gap-2 text-[11px] uppercase tracking-wide text-base-content/60">
              <span className={`h-2 w-2 rounded-full ${walletConnected ? "bg-success" : "bg-warning"}`} />
              <span>{walletStatusLabel}</span>
            </div>
            {walletConnected ? (
              <div className="flex items-center gap-2">
                <span className="font-mono text-xs" title={accountAddress ?? undefined}>
                  {shortAccountAddress}
                </span>
                <span className="badge badge-sm border-base-300/80 bg-base-100">{chainLabel}</span>
              </div>
            ) : null}
          </div>
          {authenticated ? (
            <button className={`btn btn-outline btn-sm min-w-[92px] ${hoverActionClass}`} onClick={logout}>
              Disconnect
            </button>
          ) : (
            <button className={`btn btn-primary btn-sm min-w-[92px] ${hoverActionClass}`} onClick={login}>
              Connect
            </button>
          )}
        </div>
      </div>

      <div className="mx-auto w-full max-w-[120rem] px-2 py-4 sm:px-3 lg:px-4">
        <div className="flex flex-col gap-4">
          <div className="card bg-base-200 shadow">
            <div className="card-body gap-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold">Multicall</div>
                  <div className="text-xs opacity-70">{encodedCalls.length} call(s) queued</div>
                  <div className="text-xs opacity-70">
                    Strategy: {selectedCandidateLabel}
                    {selectedCandidateLabel !== primaryCandidateLabel ? " (fallback)" : null}
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  {isValidatingMulticall ? (
                    <div className="text-xs opacity-70 whitespace-nowrap">
                      Validating multicall against on-chain state…
                    </div>
                  ) : null}
                  <button className="btn btn-primary btn-sm" disabled={!canExecute} onClick={executeMulticall}>
                    {isPending ? "Submitting…" : "Execute"}
                  </button>
                </div>
              </div>

              {multicallWarning ? (
                <div className="alert alert-warning text-xs">
                  <span>{multicallWarning}</span>
                </div>
              ) : null}

              {(isPending || isConfirming || isConfirmed || error) && (
                <div className="rounded-lg bg-base-100 p-3 text-sm">
                  {txHash ? <div className="font-mono text-xs break-all">{txHash}</div> : null}
                  <div className="mt-2">
                    {error ? (
                      <div className="text-error">{error.message}</div>
                    ) : isConfirmed ? (
                      <div className="text-success">Confirmed</div>
                    ) : isConfirming ? (
                      <div>Waiting for confirmation…</div>
                    ) : isPending ? (
                      <div>Waiting for wallet approval…</div>
                    ) : null}
                  </div>
                </div>
              )}

              <div className="divider my-0">Ops</div>
              <div className="max-h-[28rem] overflow-auto rounded-lg bg-base-100 p-3">
                {selectedOps.length === 0 ? (
                  <div className="text-sm opacity-70">No operations yet.</div>
                ) : (
                  <ol className="list-decimal pl-4 text-xs font-mono">
                    {selectedOps.map((op, i) => (
                      <li
                        key={i}
                        className={`mb-1 ${
                          multicallErrorOp && multicallErrorOp.index === i ? "text-error font-semibold" : ""
                        }`}
                      >
                        {formatOp(op)}
                      </li>
                    ))}
                  </ol>
                )}
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  className={`btn btn-ghost btn-sm ${hoverActionClass}`}
                  disabled={!multicallCalldata}
                  onClick={() =>
                    multicallCalldata
                      ? void navigator.clipboard.writeText(multicallCalldata).then(() => flashToast("Calldata copied!"))
                      : Promise.resolve()
                  }
                >
                  Copy Calldata
                </button>
                {multicallError ? <div className="ml-auto text-right text-xs text-error">{multicallError}</div> : null}
              </div>
            </div>
          </div>

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
                          <option value="single-single">Single Operator with Single Operator</option>
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
                  Allocated: {canReadBalances ? (rootBalance?.toString() ?? (balancesLoading ? "loading…" : "—")) : "—"}
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
                    const allocatedRaw =
                      groupIndex !== undefined ? (allocationsByIndex.get(groupIndex.toString()) ?? 0n) : 0n;
                    const pendingRaw =
                      groupIndex !== undefined ? (pendingByIndex.get(groupIndex.toString()) ?? 0n) : 0n;
                    const pendingValue = pendingRaw > allocatedRaw ? allocatedRaw : pendingRaw;
                    const allocatedValue = saturatingSub(allocatedRaw, pendingValue);
                    const allocatedPct =
                      fillSizeValue > 0n ? Math.min(100, Number((allocatedValue * 10000n) / fillSizeValue) / 100) : 0;
                    const pendingPctRaw =
                      fillSizeValue > 0n ? Number((pendingValue * 10000n) / fillSizeValue) / 100 : 0;
                    const pendingPct = Math.max(0, Math.min(100 - allocatedPct, pendingPctRaw));
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
                      <div
                        key={group.id}
                        className={`card shrink-0 min-w-[18rem] bg-base-100 shadow relative overflow-hidden border transition-colors ${
                          isGroupHovered ? "border-white" : "border-transparent"
                        } ${isGroupFocused ? "cursor-zoom-out" : "cursor-zoom-in"}`}
                        style={{ flexGrow: groupGrow, flexBasis: 0 }}
                        onClick={handleGroupClick}
                        onMouseMove={handleGroupHover}
                        onMouseLeave={handleGroupLeave}
                      >
                        <div
                          className="pointer-events-none absolute inset-y-0 left-0"
                          style={{ width: `${allocatedPct}%`, ...allocatedFillStyle("--color-primary") }}
                        />
                        {pendingPct > 0 ? (
                          <div
                            className="pointer-events-none absolute inset-y-0"
                            style={{
                              left: `${allocatedPct}%`,
                              width: `${pendingPct}%`,
                              ...pendingPatternStyle("--color-primary"),
                            }}
                          />
                        ) : null}
                        <div className="card-body relative z-10 gap-3">
                          <div className="grid grid-cols-[minmax(0,1fr)_minmax(6rem,8rem)] items-start gap-3">
                            <div className="min-w-0 overflow-hidden">
                              <div className="flex items-center gap-2 min-w-0 flex-wrap">
                                {groupIndex !== undefined ? (
                                  <button
                                    type="button"
                                    className="badge badge-sm font-mono text-[10px] shrink-0 whitespace-nowrap cursor-pointer bg-base-100 text-base-content/60 border-base-300/60 transition-colors hover:bg-primary/10 hover:border-primary/30 hover:text-base-content hover:shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                                    title={formatIndex(groupIndex)}
                                    onClick={() => copyIndexToClipboard(groupIndex)}
                                  >
                                    {getChildIndex(groupIndex).toString()}
                                  </button>
                                ) : null}
                                <div className="font-semibold">Group</div>
                              </div>
                              <div className="font-mono text-xs opacity-70">
                                <div className="truncate">
                                  Allocated:{" "}
                                  {!canReadBalances || !hasRootBalance || groupIndex === undefined
                                    ? "—"
                                    : allocationsLoading || pendingLoading
                                      ? "loading…"
                                      : allocatedValue.toString()}
                                </div>
                                <div className="truncate">
                                  Pending:{" "}
                                  {!canReadBalances || !hasRootBalance || groupIndex === undefined
                                    ? "—"
                                    : pendingLoading
                                      ? "loading…"
                                      : pendingValue.toString()}
                                </div>
                              </div>
                            </div>

                            <div className="flex flex-col items-end gap-2 min-w-0">
                              <label className="label cursor-pointer gap-2 py-0">
                                <span className="label-text text-xs">Shared</span>
                                <input
                                  type="checkbox"
                                  className="toggle toggle-sm"
                                  checked={draft.isShared}
                                  onChange={(e) => updateGroupDraft(group.id, { isShared: e.target.checked })}
                                />
                              </label>

                              <label className="form-control w-full min-w-0">
                                <div className="label py-0">
                                  <span className="label-text text-xs">Size</span>
                                </div>
                                <input
                                  className={[
                                    "input input-bordered input-sm w-full min-w-0",
                                    draft.size.trim() !== "" && !sizeValid ? "input-error" : "",
                                  ].join(" ")}
                                  value={draft.size}
                                  onChange={(e) => updateGroupDraft(group.id, { size: e.target.value })}
                                />
                              </label>
                            </div>
                          </div>

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
                        </div>
                      </div>
                    );
                  })}

                  {zoom.kind === "all" ? (
                    <button
                      key="add-group"
                      type="button"
                      className="flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
                      onClick={addDraftGroup}
                    >
                      <div className="text-center">
                        <div className="text-2xl leading-none">+</div>
                        <div className="mt-1">Add group</div>
                      </div>
                    </button>
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

function formatOp(op: UdOperation): string {
  if (op.kind === "createSlot") {
    return `createSlot(${formatIndex(op.parentIndex)}, ${op.isShared}, ${op.size})`;
  }
  if (op.kind === "setIsShared") {
    return `setIsShared(${formatIndex(op.index)}, ${op.isShared})`;
  }
  if (op.kind === "setSize") {
    return `setSize(${formatIndex(op.index)}, ${op.size})`;
  }
  if (op.kind === "swapSlots") {
    return `swapSlots(${formatIndex(op.index1)}, ${formatIndex(op.index2)})`;
  }
  if (op.kind === "assignNetwork") {
    return `assignNetwork(${formatIndex(op.index)}, ${op.subnetwork})`;
  }
  if (op.kind === "unassignNetwork") {
    return `unassignNetwork(${op.subnetwork})`;
  }
  if (op.kind === "assignOperator") {
    return `assignOperator(${formatIndex(op.index)}, ${op.operator})`;
  }
  return `unassignOperator(${formatIndex(op.parentIndex)}, ${op.operator})`;
}

function opToJson(op: UdOperation): Record<string, unknown> {
  if (op.kind === "createSlot") {
    return {
      kind: op.kind,
      parentIndex: formatIndex(op.parentIndex),
      isShared: op.isShared,
      size: op.size.toString(),
    };
  }
  if (op.kind === "setIsShared") {
    return { kind: op.kind, index: formatIndex(op.index), isShared: op.isShared };
  }
  if (op.kind === "setSize") {
    return { kind: op.kind, index: formatIndex(op.index), size: op.size.toString() };
  }
  if (op.kind === "swapSlots") {
    return {
      kind: op.kind,
      index1: formatIndex(op.index1),
      index2: formatIndex(op.index2),
    };
  }
  if (op.kind === "assignNetwork") {
    return { kind: op.kind, index: formatIndex(op.index), subnetwork: op.subnetwork };
  }
  if (op.kind === "unassignNetwork") {
    return { kind: op.kind, subnetwork: op.subnetwork };
  }
  if (op.kind === "assignOperator") {
    return { kind: op.kind, index: formatIndex(op.index), operator: op.operator };
  }
  return {
    kind: op.kind,
    parentIndex: formatIndex(op.parentIndex),
    operator: op.operator,
  };
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
          const allocatedRaw =
            networkIndex !== undefined ? (props.allocatedByIndex.get(networkIndex.toString()) ?? 0n) : 0n;
          const pendingRaw =
            networkIndex !== undefined ? (props.pendingByIndex.get(networkIndex.toString()) ?? 0n) : 0n;
          const pendingValue = pendingRaw > allocatedRaw ? allocatedRaw : pendingRaw;
          const allocatedValue = saturatingSub(allocatedRaw, pendingValue);
          const allocatedPct =
            fillSizeValue > 0n ? Math.min(100, Number((allocatedValue * 10000n) / fillSizeValue) / 100) : 0;
          const pendingPctRaw = fillSizeValue > 0n ? Number((pendingValue * 10000n) / fillSizeValue) / 100 : 0;
          const pendingPct = Math.max(0, Math.min(100 - allocatedPct, pendingPctRaw));
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
            <div
              key={network.id}
              data-network-card
              className={
                isShared
                  ? `card bg-base-200 border shadow relative overflow-hidden transition-colors ${
                      props.onZoomNetwork ? (isNetworkHovered ? "border-white" : "border-base-300") : "border-base-300"
                    } ${props.onZoomNetwork ? (isFocused ? "cursor-zoom-out" : "cursor-zoom-in") : ""}`
                  : `card shrink-0 min-w-[18rem] bg-base-200 border shadow relative overflow-hidden transition-colors ${
                      props.onZoomNetwork ? (isNetworkHovered ? "border-white" : "border-base-300") : "border-base-300"
                    } ${props.onZoomNetwork ? (isFocused ? "cursor-zoom-out" : "cursor-zoom-in") : ""}`
              }
              style={isShared ? { width: `${networkWidthPct}%` } : { flexGrow: networkGrow, flexBasis: 0 }}
              onClick={handleNetworkClick}
              onMouseMove={handleNetworkHover}
              onMouseLeave={handleNetworkLeave}
            >
              <div
                className="pointer-events-none absolute inset-y-0 left-0"
                style={{ width: `${allocatedPct}%`, ...allocatedFillStyle("--color-secondary") }}
              />
              {pendingPct > 0 ? (
                <div
                  className="pointer-events-none absolute inset-y-0"
                  style={{
                    left: `${allocatedPct}%`,
                    width: `${pendingPct}%`,
                    ...pendingPatternStyle("--color-secondary"),
                  }}
                />
              ) : null}
              <div className="card-body relative z-10 gap-3">
                <div className="grid grid-cols-[minmax(0,1fr)_minmax(4.5rem,6rem)] items-start gap-3">
                  <div className="min-w-0 overflow-hidden">
                    <div className="flex items-center gap-2 min-w-0 flex-wrap">
                      {networkIndex !== undefined ? (
                        <button
                          type="button"
                          className="badge badge-sm font-mono text-[10px] shrink-0 whitespace-nowrap cursor-pointer bg-base-100 text-base-content/60 border-base-300/60 transition-colors hover:bg-primary/10 hover:border-primary/30 hover:text-base-content hover:shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                          title={formatIndex(networkIndex)}
                          onClick={() => props.onCopyIndex(networkIndex)}
                        >
                          {getChildIndex(networkIndex).toString()}
                        </button>
                      ) : null}
                      <div className="font-semibold">Network</div>
                    </div>
                    <div className="font-mono text-xs opacity-70">
                      <div className="truncate">
                        Allocated:{" "}
                        {!props.canReadBalances || !props.hasRootBalance || networkIndex === undefined
                          ? "—"
                          : props.allocationsLoading || props.pendingLoading
                            ? "loading…"
                            : allocatedValue.toString()}
                      </div>
                      <div className="truncate">
                        Pending:{" "}
                        {!props.canReadBalances || !props.hasRootBalance || networkIndex === undefined
                          ? "—"
                          : props.pendingLoading
                            ? "loading…"
                            : pendingValue.toString()}
                      </div>
                    </div>
                    <input
                      className={[
                        "input input-bordered input-sm font-mono mt-2 w-full max-w-[66ch]",
                        subnetworkTrimmed !== "" && !subnetworkValid ? "input-error" : "",
                      ].join(" ")}
                      placeholder="0x…"
                      value={draft.subnetwork}
                      onChange={(e) => props.onUpdateNetworkDraft(network.id, { subnetwork: e.target.value })}
                    />
                  </div>

                  <label className="form-control w-full min-w-0 overflow-hidden">
                    <div className="label py-0">
                      <span className="label-text text-xs">Size</span>
                    </div>
                    <input
                      className={[
                        "input input-bordered input-sm w-full min-w-0",
                        draft.size.trim() !== "" && !sizeValid ? "input-error" : "",
                      ].join(" ")}
                      value={draft.size}
                      onChange={(e) => props.onUpdateNetworkDraft(network.id, { size: e.target.value })}
                    />
                  </label>
                </div>

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
              </div>
            </div>
          );
        })}

        {showAddNetwork ? (
          <button
            key="add-network"
            ref={addButtonRef}
            type="button"
            className={[
              isShared || !hasNetworks
                ? "flex w-full min-w-0 cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-200 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
                : "flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-200 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100",
            ].join(" ")}
            onClick={props.onAddNetwork}
            data-no-zoom
          >
            <div className="text-center">
              <div className="text-2xl leading-none">+</div>
              <div className="mt-1">Add network</div>
            </div>
          </button>
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
          const allocatedRaw =
            operatorIndex !== undefined ? (props.allocatedByIndex.get(operatorIndex.toString()) ?? 0n) : 0n;
          const pendingRaw =
            operatorIndex !== undefined ? (props.pendingByIndex.get(operatorIndex.toString()) ?? 0n) : 0n;
          const pendingValue = pendingRaw > allocatedRaw ? allocatedRaw : pendingRaw;
          const allocatedValue = saturatingSub(allocatedRaw, pendingValue);
          const allocatedPct =
            fillSizeValue > 0n ? Math.min(100, Number((allocatedValue * 10000n) / fillSizeValue) / 100) : 0;
          const pendingPctRaw = fillSizeValue > 0n ? Number((pendingValue * 10000n) / fillSizeValue) / 100 : 0;
          const pendingPct = Math.max(0, Math.min(100 - allocatedPct, pendingPctRaw));
          const operatorTrimmed = draft.operator.trim();
          const operatorValid = operatorTrimmed === "" || isAddress(operatorTrimmed);
          return (
            <div
              key={operator.id}
              className="card shrink-0 min-w-[18rem] bg-base-100 border border-base-300 shadow relative overflow-hidden cursor-default"
              style={{ flexGrow: operatorGrow, flexBasis: 0 }}
              data-no-zoom
            >
              <div
                className="pointer-events-none absolute inset-y-0 left-0"
                style={{ width: `${allocatedPct}%`, ...allocatedFillStyle("--color-accent") }}
              />
              {pendingPct > 0 ? (
                <div
                  className="pointer-events-none absolute inset-y-0"
                  style={{
                    left: `${allocatedPct}%`,
                    width: `${pendingPct}%`,
                    ...pendingPatternStyle("--color-accent"),
                  }}
                />
              ) : null}
              <div className="card-body relative z-10 gap-2">
                <div className="grid grid-cols-[minmax(0,1fr)_minmax(4.5rem,6rem)] items-start gap-3">
                  <div className="min-w-0 overflow-hidden">
                    <div className="flex items-center gap-2 min-w-0 flex-wrap">
                      {operatorIndex !== undefined ? (
                        <button
                          type="button"
                          className="badge badge-sm font-mono text-[10px] shrink-0 whitespace-nowrap cursor-pointer bg-base-100 text-base-content/60 border-base-300/60 transition-colors hover:bg-primary/10 hover:border-primary/30 hover:text-base-content hover:shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                          title={formatIndex(operatorIndex)}
                          onClick={() => props.onCopyIndex(operatorIndex)}
                        >
                          {getChildIndex(operatorIndex).toString()}
                        </button>
                      ) : null}
                      <div className="font-semibold">Operator</div>
                    </div>
                    <div className="font-mono text-xs opacity-70">
                      <div className="truncate">
                        Allocated:{" "}
                        {!props.canReadBalances || !props.hasRootBalance || operatorIndex === undefined
                          ? "—"
                          : props.allocationsLoading || props.pendingLoading
                            ? "loading…"
                            : allocatedValue.toString()}
                      </div>
                      <div className="truncate">
                        Pending:{" "}
                        {!props.canReadBalances || !props.hasRootBalance || operatorIndex === undefined
                          ? "—"
                          : props.pendingLoading
                            ? "loading…"
                            : pendingValue.toString()}
                      </div>
                    </div>
                    <input
                      className={[
                        "input input-bordered input-sm font-mono mt-2 w-full max-w-[42ch]",
                        operatorTrimmed !== "" && !operatorValid ? "input-error" : "",
                      ].join(" ")}
                      placeholder="0x…"
                      value={draft.operator}
                      onChange={(e) => props.onUpdateOperatorDraft(operator.id, { operator: e.target.value })}
                    />
                  </div>

                  <label className="form-control w-full min-w-0 overflow-hidden">
                    <div className="label py-0">
                      <span className="label-text text-xs">Size</span>
                    </div>
                    <input
                      className={[
                        "input input-bordered input-sm w-full min-w-0",
                        draft.size.trim() !== "" && !sizeValid ? "input-error" : "",
                      ].join(" ")}
                      value={draft.size}
                      onChange={(e) => props.onUpdateOperatorDraft(operator.id, { size: e.target.value })}
                    />
                  </label>
                </div>
              </div>
            </div>
          );
        })}

        <button
          key="add-operator"
          ref={addButtonRef}
          type="button"
          className={[
            hasOperators
              ? "flex shrink-0 w-[18rem] cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100"
              : "flex w-full min-w-0 cursor-pointer items-center justify-center rounded-lg border border-dashed border-base-300 bg-base-100 p-6 text-sm opacity-70 hover:cursor-pointer hover:opacity-100",
          ].join(" ")}
          onClick={props.onAddOperator}
          data-no-zoom
        >
          <div className="text-center">
            <div className="text-2xl leading-none">+</div>
            <div className="mt-1">Add operator</div>
          </div>
        </button>
      </div>
    </div>
  );
}
