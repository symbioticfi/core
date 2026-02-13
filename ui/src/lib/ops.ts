import { encodeFunctionData, type Address, type Hex } from "viem";
import { universalDelegatorAbi } from "../abi/universalDelegator";
import { createIndex } from "./indexing";
import { decodeOperator, decodeSubnetwork, type SubnetworkRef } from "./subnetwork";

export type Metrics = {
  allocated: bigint;
  pending: bigint;
  available: bigint;
  balance: bigint;
  childrenPending: bigint;
};

export type SlotNode = {
  index: bigint;
  depth: number;
  size: bigint;
  isShared: boolean;
  noPlugins: boolean;
  totalChildren: number;
  existChildren: number;
  firstChild: number;
  lastChild: number;
  nextSlot: number;
  prevSlot: number;
  subnetwork?: SubnetworkRef;
  operator?: Address;
  children: SlotNode[];
  metrics: Metrics;
};

export type Op =
  | {
      id: string;
      kind: "createSlot";
      parentIndex: bigint;
      subnetworkOrOperator: Hex;
      isShared: boolean;
      noPlugins: boolean;
      size: bigint;
    }
  | {
      id: string;
      kind: "setSize";
      index: bigint;
      size: bigint;
    }
  | {
      id: string;
      kind: "swapSlots";
      index1: bigint;
      index2: bigint;
    }
  | {
      id: string;
      kind: "removeSlot";
      index: bigint;
    }
  | {
      id: string;
      kind: "setWithdrawalBufferSize";
      size: bigint;
    }
  ;

export function encodeOp(op: Op): Hex {
  switch (op.kind) {
    case "createSlot":
      return encodeFunctionData({
        abi: universalDelegatorAbi,
        functionName: "createSlot",
        args: [op.subnetworkOrOperator, op.parentIndex, op.isShared, op.noPlugins, op.size],
      });
    case "setSize":
      return encodeFunctionData({
        abi: universalDelegatorAbi,
        functionName: "setSize",
        args: [op.index, op.size],
      });
    case "swapSlots":
      return encodeFunctionData({
        abi: universalDelegatorAbi,
        functionName: "swapSlots",
        args: [op.index1, op.index2],
      });
    case "removeSlot":
      return encodeFunctionData({
        abi: universalDelegatorAbi,
        functionName: "removeSlot",
        args: [op.index],
      });
    case "setWithdrawalBufferSize":
      return encodeFunctionData({
        abi: universalDelegatorAbi,
        functionName: "setWithdrawalBufferSize",
        args: [op.size],
      });
    default:
      return "0x";
  }
}

export function encodeMulticall(ops: Op[]): Hex {
  return encodeFunctionData({
    abi: universalDelegatorAbi,
    functionName: "multicall",
    args: [ops.map(encodeOp)],
  });
}

export function summarizeOp(op: Op, formatAmount: (value: bigint) => string = (value) => value.toString()): string {
  switch (op.kind) {
    case "createSlot":
      return `Create slot under ${op.parentIndex.toString()} size=${formatAmount(op.size)}`;
    case "setSize":
      return `Set size ${op.index.toString()} -> ${formatAmount(op.size)}`;
    case "swapSlots":
      return `Swap ${op.index1.toString()} <-> ${op.index2.toString()}`;
    case "removeSlot":
      return `Remove slot ${op.index.toString()}`;
    case "setWithdrawalBufferSize":
      return `Set withdrawal buffer ${formatAmount(op.size)}`;
    default:
      return "Unknown";
  }
}

export function cloneTree(root: SlotNode): SlotNode {
  return {
    ...root,
    children: root.children.map(cloneTree),
  };
}

export function applyOps(root: SlotNode | null, ops: Op[]): SlotNode | null {
  if (!root) {
    return null;
  }
  const clone = cloneTree(root);
  const indexMap = new Map<bigint, SlotNode>();
  const parentMap = new Map<bigint, SlotNode | null>();

  const indexNodes = (node: SlotNode, parent: SlotNode | null) => {
    indexMap.set(node.index, node);
    parentMap.set(node.index, parent);
    node.children.forEach((child) => indexNodes(child, node));
  };

  indexNodes(clone, null);

  for (const op of ops) {
    if (op.kind === "setSize") {
      const node = indexMap.get(op.index);
      if (node) {
        node.size = op.size;
      }
      continue;
    }

    if (op.kind === "createSlot") {
      const parent = indexMap.get(op.parentIndex);
      if (!parent) {
        continue;
      }
      if (parent.depth >= 3) {
        continue;
      }
      const nextLocalIndex = parent.totalChildren + 1;
      parent.totalChildren += 1;
      parent.existChildren += 1;
      const newIndex = createIndex(parent.index, nextLocalIndex);
      const depth = parent.depth + 1;
      const node: SlotNode = {
        index: newIndex,
        depth,
        size: op.size,
        isShared: op.isShared,
        noPlugins: op.noPlugins,
        totalChildren: 0,
        existChildren: 0,
        firstChild: 0,
        lastChild: 0,
        nextSlot: 0,
        prevSlot: 0,
        children: [],
        metrics: {
          allocated: 0n,
          pending: 0n,
          available: 0n,
          balance: 0n,
          childrenPending: 0n,
        },
      };
      if (depth === 2) {
        node.subnetwork = decodeSubnetwork(op.subnetworkOrOperator);
      }
      if (depth === 3) {
        node.operator = decodeOperator(op.subnetworkOrOperator);
      }
      parent.children = [...parent.children, node];
      indexMap.set(newIndex, node);
      parentMap.set(newIndex, parent);
      continue;
    }

    if (op.kind === "swapSlots") {
      const parent = parentMap.get(op.index1);
      if (!parent || parent !== parentMap.get(op.index2)) {
        continue;
      }
      const idxA = parent.children.findIndex((child) => child.index === op.index1);
      const idxB = parent.children.findIndex((child) => child.index === op.index2);
      if (idxA >= 0 && idxB >= 0) {
        const temp = parent.children[idxA];
        parent.children[idxA] = parent.children[idxB];
        parent.children[idxB] = temp;
      }
      continue;
    }

    if (op.kind === "removeSlot") {
      const parent = parentMap.get(op.index);
      if (!parent) {
        continue;
      }
      parent.children = parent.children.filter((child) => child.index !== op.index);
      parent.existChildren = Math.max(0, parent.existChildren - 1);
      indexMap.delete(op.index);
      parentMap.delete(op.index);
      continue;
    }
  }

  return clone;
}
