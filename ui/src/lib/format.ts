import { formatUnits, getAddress, parseUnits, toHex, type Address } from "viem";

export function formatBigInt(value: bigint): string {
  const raw = value.toString();
  return raw.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

export function formatToken(value: bigint, decimals?: number): string {
  if (decimals === undefined) {
    return formatBigInt(value);
  }
  const formatted = formatUnits(value, decimals);
  return formatted.replace(/(?:\.0+|(\.\d+?)0+)$/, "$1");
}

export function parseToken(value: string, decimals?: number): bigint | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  try {
    return decimals === undefined ? BigInt(trimmed) : parseUnits(trimmed, decimals);
  } catch {
    return null;
  }
}

export function formatAddress(value?: Address, chars = 4): string {
  if (!value) {
    return "-";
  }
  const addr = getAddress(value);
  return `${addr.slice(0, 2 + chars)}...${addr.slice(-chars)}`;
}

export function formatIndex(value: bigint): string {
  return toHex(value, { size: 12 });
}

export function formatRatio(ratio: number): string {
  if (!Number.isFinite(ratio)) {
    return "0%";
  }
  return `${Math.round(ratio * 100)}%`;
}
