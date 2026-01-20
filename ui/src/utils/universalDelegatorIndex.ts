const MASK_32 = (1n << 32n) - 1n;
const MASK_64 = (1n << 64n) - 1n;
const MASK_96 = (1n << 96n) - 1n;

export type UniversalDelegatorDepth = 0 | 1 | 2 | 3;

export function getDepth(index: bigint): UniversalDelegatorDepth {
  if (index === 0n) return 0;
  if ((index & MASK_64) === 0n) return 1;
  if ((index & MASK_32) === 0n) return 2;
  return 3;
}

export function createIndex(parentIndex: bigint, localIndex: bigint): bigint {
  if (localIndex === 0n) {
    throw new Error("ZeroIndex");
  }

  const depth = getDepth(parentIndex);
  if (depth === 0) return localIndex << 64n;
  if (depth === 1) return parentIndex | (localIndex << 32n);
  if (depth === 2) return parentIndex | localIndex;
  throw new Error("NotParentIndex");
}

export function getParentIndex(index: bigint): bigint {
  if (index === 0n) {
    throw new Error("ZeroIndex");
  }

  const depth = getDepth(index);
  if (depth === 1) return 0n;
  if (depth === 2) return index & (MASK_96 ^ MASK_64);
  return index & (MASK_96 ^ MASK_32);
}

export function getChildIndex(index: bigint): bigint {
  if (index === 0n) {
    throw new Error("ZeroIndex");
  }

  const depth = getDepth(index);
  if (depth === 1) return (index >> 64n) & MASK_32;
  if (depth === 2) return (index >> 32n) & MASK_32;
  return index & MASK_32;
}

export function formatIndex(index: bigint): string {
  return `0x${index.toString(16).padStart(24, "0")}`;
}
