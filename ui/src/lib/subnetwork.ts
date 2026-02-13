import { getAddress, toHex, type Address, type Hex } from "viem";

const IDENTIFIER_MASK = (1n << 96n) - 1n;
const ADDRESS_MASK = (1n << 160n) - 1n;

export type SubnetworkRef = {
  network: Address;
  identifier: bigint;
  bytes32: Hex;
};

export function encodeSubnetwork(network: Address, identifier: bigint | number): Hex {
  const networkValue = BigInt(network);
  const idValue = BigInt(identifier) & IDENTIFIER_MASK;
  return toHex((networkValue << 96n) | idValue, { size: 32 });
}

export function decodeSubnetwork(value: Hex): SubnetworkRef {
  const raw = BigInt(value);
  const network = getAddress(toHex(raw >> 96n, { size: 20 }));
  const identifier = raw & IDENTIFIER_MASK;
  return { network, identifier, bytes32: value };
}

export function encodeOperator(operator: Address): Hex {
  const raw = BigInt(operator) & ADDRESS_MASK;
  return toHex(raw, { size: 32 });
}

export function decodeOperator(value: Hex): Address {
  const raw = BigInt(value) & ADDRESS_MASK;
  return getAddress(toHex(raw, { size: 20 }));
}
