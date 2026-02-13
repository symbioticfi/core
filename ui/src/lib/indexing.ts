export const WITHDRAWAL_BUFFER_CHILD_INDEX = 0xffffffff;
export const WITHDRAWAL_BUFFER_INDEX = 0xffffffff0000000000000000n;

const MASK_32 = (1n << 32n) - 1n;
const MASK_96 = (1n << 96n) - 1n;

const shiftLeft96 = (value: bigint, shift: bigint) => (value << shift) & MASK_96;

export function createIndex(parentIndex: bigint, localIndex: number | bigint): bigint {
  const local = BigInt(localIndex) & MASK_32;
  const parent = parentIndex & MASK_96;
  if (parent === 0n) {
    return local << 64n;
  }
  if (shiftLeft96(parent, 32n) === 0n) {
    return parent | (local << 32n);
  }
  if (shiftLeft96(parent, 64n) === 0n) {
    return parent | local;
  }
  throw new Error("Not a parent index");
}

export function getParentIndex(index: bigint): bigint {
  const value = index & MASK_96;
  if (value === 0n) {
    throw new Error("Zero index");
  }
  if (shiftLeft96(value, 32n) === 0n) {
    return 0n;
  }
  if (shiftLeft96(value, 64n) === 0n) {
    return value & 0xffffffff0000000000000000n;
  }
  return value & 0xffffffffffffffff00000000n;
}

export function getChildIndex(index: bigint): number {
  const value = index & MASK_96;
  if (value === 0n) {
    throw new Error("Zero index");
  }
  if (shiftLeft96(value, 32n) === 0n) {
    return Number(value >> 64n);
  }
  if (shiftLeft96(value, 64n) === 0n) {
    return Number((value >> 32n) & MASK_32);
  }
  return Number(value & MASK_32);
}

export function getDepth(index: bigint): number {
  const value = index & MASK_96;
  if (value === 0n) {
    return 0;
  }
  if (shiftLeft96(value, 32n) === 0n) {
    return 1;
  }
  if (shiftLeft96(value, 64n) === 0n) {
    return 2;
  }
  return 3;
}
