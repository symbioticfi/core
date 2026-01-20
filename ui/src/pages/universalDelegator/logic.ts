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

import { universalDelegatorAbi } from "../../contracts/universalDelegator";
import { createIndex, formatIndex, getChildIndex, getDepth, getParentIndex } from "../../utils/universalDelegatorIndex";

const UNIVERSAL_DELEGATOR_EVENT_ABI = universalDelegatorAbi.filter((item) => item.type === "event") as unknown as Array<
  (typeof universalDelegatorAbi)[number]
>;

const UNIVERSAL_DELEGATOR_EVENT_TOPICS = new Set<string>(
  UNIVERSAL_DELEGATOR_EVENT_ABI.map((event) => getEventSelector(event as never)),
);

export type SlotSizeInput = string;

export type DraftState<T> = {
  draft: T;
  synced: T | null;
};

export type GroupDraft = { size: SlotSizeInput; isShared: boolean };
export type NetworkDraft = { size: SlotSizeInput; subnetwork: string };
export type OperatorDraft = { size: SlotSizeInput; operator: string };

export type OperatorSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<OperatorDraft>;
};

export type NetworkSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<NetworkDraft>;
  operators: OperatorSlot[];
};

export type GroupSlot = {
  id: string;
  index: bigint | null;
  state: DraftState<GroupDraft>;
  networks: NetworkSlot[];
};

export type UniversalDelegatorModel = {
  groups: GroupSlot[];
};

export type ZoomState =
  | { kind: "all" }
  | { kind: "group"; groupId: string }
  | { kind: "network"; groupId: string; networkId: string };

export type GroupConstructor = "shared-multi" | "shared-single" | "single-multi" | "single-single";

export type UdOperation =
  | { kind: "createSlot"; parentIndex: bigint; isShared: boolean; size: bigint; slotId?: string }
  | { kind: "setIsShared"; index: bigint; isShared: boolean }
  | { kind: "setSize"; index: bigint; size: bigint }
  | { kind: "swapSlots"; index1: bigint; index2: bigint }
  | { kind: "assignNetwork"; index: bigint; subnetwork: Hex }
  | { kind: "unassignNetwork"; subnetwork: Hex }
  | { kind: "assignOperator"; index: bigint; operator: Address }
  | { kind: "unassignOperator"; parentIndex: bigint; operator: Address };

export function parseUint(value: string): bigint | null {
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

export function parseBytes32(value: string): Hex | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (!trimmed.startsWith("0x")) return null;
  if (!isHex(trimmed)) return null;
  if (trimmed.length > 66) return null;
  return padHex(trimmed, { size: 32, dir: "right" });
}

export type HasSize = { size: SlotSizeInput };

export function effectiveSize(state: DraftState<HasSize>): bigint {
  const draft = parseUint(state.draft.size);
  if (draft !== null) return draft;
  const synced = state.synced ? parseUint(state.synced.size) : null;
  return synced ?? 0n;
}

export function sumBigints(values: bigint[]): bigint {
  let total = 0n;
  for (const v of values) total += v;
  return total;
}

export function maxBigint(values: bigint[]): bigint {
  let m = 0n;
  for (const v of values) if (v > m) m = v;
  return m;
}

export function formatShortAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function parsePositiveInt(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

export function cloneOps(values: UdOperation[]): UdOperation[] {
  return values.map((op) => ({ ...op }));
}

export function cloneModel(values: UniversalDelegatorModel): UniversalDelegatorModel {
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

export function bigintMin(a: bigint, b: bigint): bigint {
  return a < b ? a : b;
}

export function bigintMax(a: bigint, b: bigint): bigint {
  return a > b ? a : b;
}

export function saturatingSub(a: bigint, b: bigint): bigint {
  return a > b ? a - b : 0n;
}

export function computeSlotIdToIndex(model: UniversalDelegatorModel): Map<string, bigint> {
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

export function computeSimulatedAllocations(
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
    const parentIsShared = parentIndex === 0n ? false : parentSlot?.isShared ?? false;

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

export function computePendingByIndexFromOps(params: {
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
      state._networkToSlot.set(op.subnetwork.toLowerCase(), op.index);
      continue;
    }

    if (op.kind === "unassignNetwork") {
      state._networkToSlot.set(op.subnetwork.toLowerCase(), 0n);
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

export function computeSimulatedAllocationsWithPending(params: {
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
    const groupPending = groupIndex !== undefined ? pendingByIndex.get(groupIndex.toString()) ?? 0n : 0n;
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

      const networkPending = networkIndex !== undefined ? pendingByIndex.get(networkIndex.toString()) ?? 0n : 0n;
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

export async function reconstructModelFromChain(params: {
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

export function flexGrowFromSize(size: bigint, total: bigint): number {
  if (total <= 0n) return 1;
  if (size <= 0n) return 0;
  const scaled = (size * 1_000_000n) / total;
  if (scaled <= 0n) return 0.000001;
  return Number(scaled) / 1_000_000;
}

export function percentWidthFromSize(size: bigint, max: bigint, minPct = 40, maxPct = 100): number {
  if (max <= 0n) return maxPct;
  if (size <= 0n) return minPct;
  const scaled = Number((size * 10_000n) / max) / 10_000;
  return minPct + scaled * (maxPct - minPct);
}

export function autoSyncAll(model: UniversalDelegatorModel): { model: UniversalDelegatorModel; ops: UdOperation[] } {
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
      const isSubnetworkDirty = subnetworkValid && (synced === null || synced.subnetwork.trim() !== subnetworkTrimmed);

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
  _networkToSlot: Map<string, bigint>;
  operatorBySlot: Map<bigint, Address>;
  operatorToSlot: Map<string, bigint>;
  nextChildLocalIndex: Map<bigint, bigint>;
};

export function bigintCompare(a: bigint, b: bigint): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

export function shallowOptimizeOps(ops: UdOperation[]): UdOperation[] {
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

export function mergeOps(prevOps: UdOperation[], nextOps: UdOperation[]): UdOperation[] {
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
    _networkToSlot: new Map(state._networkToSlot),
    operatorBySlot: new Map(state.operatorBySlot),
    operatorToSlot: new Map(state.operatorToSlot),
    nextChildLocalIndex: new Map(state.nextChildLocalIndex),
  };
}

export function buildSimStateFromModel(model: UniversalDelegatorModel): SimState {
  const state: SimState = {
    children: new Map([[0n, []]]),
    slots: new Map(),
    created: new Set([0n]),
    _networkToSlot: new Map(),
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
        state._networkToSlot.set(subnetworkParsed.toLowerCase(), networkIndex);
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

export function simulateOpsFromState(initial: SimState, ops: UdOperation[]): SimState | null {
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
      state._networkToSlot.set(op.subnetwork.toLowerCase(), op.index);
      continue;
    }

    if (op.kind === "unassignNetwork") {
      state._networkToSlot.set(op.subnetwork.toLowerCase(), 0n);
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
  for (const key of params.initial._networkToSlot.keys()) allSubnetworks.add(key);
  for (const key of params.final._networkToSlot.keys()) allSubnetworks.add(key);
  const subnetworkKeys = [...allSubnetworks].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (const subnetwork of subnetworkKeys) {
    const initialIndex = params.initial._networkToSlot.get(subnetwork) ?? 0n;
    const finalIndex = params.final._networkToSlot.get(subnetwork) ?? 0n;
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

export function compileOpsFromModels(params: {
  baselineModel: UniversalDelegatorModel;
  nextModel: UniversalDelegatorModel;
}): UdOperation[] | null {
  const initial = buildSimStateFromModel(params.baselineModel);
  const final = buildSimStateFromModel(params.nextModel);
  return compileMinimalOpsFromInitialAndFinal({ initial, final });
}

export type MulticallCandidate = { label: string; ops: UdOperation[] };

export function opsKey(ops: UdOperation[]): string {
  return JSON.stringify(ops.map(opToJson));
}

export function buildMulticallCandidates(params: {
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

export function orderMulticallCandidates(candidates: MulticallCandidate[]): MulticallCandidate[] {
  return candidates
    .slice()
    .sort((a, b) => a.ops.length - b.ops.length || candidatePriority(a.label) - candidatePriority(b.label));
}

export function encodeOpsToCalls(ops: UdOperation[]): Hex[] {
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

export function formatViemError(error: unknown): string {
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

export function extractRevertName(error: unknown): string | null {
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
    const parentIsShared = parentIndex === 0n ? false : parentSlot?.isShared ?? false;

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

export function describeNotEnoughAvailable(params: {
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

export async function simulateMulticallCandidates(params: {
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

export async function simulateMulticall(params: {
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

export async function findFailingOp(params: {
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

export function opsBaselineModel(params: {
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

export function formatOp(op: UdOperation): string {
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

export function opToJson(op: UdOperation): Record<string, unknown> {
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
