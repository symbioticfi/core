import { decodeAbiParameters, encodeAbiParameters, type Hex } from "viem";
import { type HintCandidate } from "./types.js";

export const stakeHintsComponents: Record<number, { name: string; label: string; type: "tuple"; components: { name: string; type: string }[] }> = {
    0: {
        name: "networkRestakeStakeHints",
        label: "net-restake",
        type: "tuple",
        components: [
            { name: "baseHints", type: "bytes" },
            { name: "activeStakeHint", type: "bytes" },
            { name: "networkLimitHint", type: "bytes" },
            { name: "totalOperatorNetworkSharesHint", type: "bytes" },
            { name: "operatorNetworkSharesHint", type: "bytes" }
        ]
    },
    1: {
        name: "fullRestakeStakeHints",
        label: "full-restake",
        type: "tuple",
        components: [
            { name: "baseHints", type: "bytes" },
            { name: "activeStakeHint", type: "bytes" },
            { name: "networkLimitHint", type: "bytes" },
            { name: "operatorNetworkLimitHint", type: "bytes" }
        ]
    },
    2: {
        name: "operatorSpecificStakeHints",
        label: "op-specific",
        type: "tuple",
        components: [
            { name: "baseHints", type: "bytes" },
            { name: "activeStakeHint", type: "bytes" },
            { name: "networkLimitHint", type: "bytes" }
        ]
    },
    3: {
        name: "operatorNetworkSpecificStakeHints",
        label: "op-net-specific",
        type: "tuple",
        components: [
            { name: "baseHints", type: "bytes" },
            { name: "activeStakeHint", type: "bytes" },
            { name: "maxNetworkLimitHint", type: "bytes" }
        ]
    }
};

export const stakeBaseHintsComponents = [
    { name: "operatorVaultOptInHint", type: "bytes" },
    { name: "operatorNetworkOptInHint", type: "bytes" }
] as const;

export function baseHintCandidates(): HintCandidate[] {
    return [{ label: "empty-bytes", value: "0x" }];
}

export function dedupeCandidates(candidates: HintCandidate[]): HintCandidate[] {
    const seen = new Set<string>();
    const unique: HintCandidate[] = [];

    for (const candidate of candidates) {
        const key = candidate.value.toLowerCase();
        if (seen.has(key)) {
            continue;
        }
        seen.add(key);
        unique.push(candidate);
    }

    return unique;
}

export function toUint48(value: bigint | number): number {
    return Number(value);
}



export type ByteLeaf = { path: string[]; value: Hex | "0x" };
export type Components = readonly { name: string; type: string; components?: Components }[];

export function collectByteLeaves(
    components: Components,
    values: unknown,
    nested: Record<string, Components>,
    path: string[] = []
): ByteLeaf[] {
    const arr = Array.isArray(values) ? values : [values];
    const leaves: ByteLeaf[] = [];

    components.forEach((component, idx) => {
        const nextPath = [...path, component.name];
        const key = nextPath.join(".");
        const value = arr[idx];

        if (component.type === "tuple" && component.components) {
            leaves.push(...collectByteLeaves(component.components, value ?? [], nested, nextPath));
            return;
        }

        if (component.type === "bytes") {
            const nestedComponents = nested[key];
            if (nestedComponents && typeof value === "string" && value !== "0x") {
                try {
                    const [decoded] = decodeAbiParameters([{ type: "tuple", components: nestedComponents }], value as Hex);
                    const decodedArr = Array.isArray(decoded) ? decoded : [decoded];
                    leaves.push(...collectByteLeaves(nestedComponents, decodedArr, nested, nextPath));
                    return;
                } catch {
                    // fall through to treat as a leaf
                }
            }

            leaves.push({ path: nextPath, value: (value ?? "0x") as Hex });
        }
    });

    return leaves;
}

export function hasIncludedDescendant(includeSet: Set<string>, key: string): boolean {
    if (includeSet.has(key)) return true;
    for (const p of includeSet) {
        if (p.startsWith(`${key}.`)) return true;
    }
    return false;
}

export function rebuildTupleWithMask(
    components: Components,
    values: unknown,
    includeSet: Set<string>,
    nested: Record<string, Components>,
    path: string[] = []
): unknown[] {
    const arr = Array.isArray(values) ? values : [values];
    return components.map((component, idx) => {
        const nextPath = [...path, component.name];
        const key = nextPath.join(".");
        const value = arr[idx];

        if (component.type === "tuple" && component.components) {
            return rebuildTupleWithMask(component.components, value ?? [], includeSet, nested, nextPath);
        }

        if (component.type === "bytes") {
            const nestedComponents = nested[key];
            const hasChild = nestedComponents && typeof value === "string" && value !== "0x";
            if (hasChild) {
                try {
                    const [decoded] = decodeAbiParameters([{ type: "tuple", components: nestedComponents }], value as Hex);
                    const decodedArr = Array.isArray(decoded) ? decoded : [decoded];
                    const rebuiltChild = rebuildTupleWithMask(
                        nestedComponents,
                        decodedArr,
                        includeSet,
                        nested,
                        nextPath
                    );
                    if (!hasIncludedDescendant(includeSet, key)) {
                        return "0x";
                    }
                    return (encodeAbiParameters as any)(
                        [{ type: "tuple", components: nestedComponents }],
                        [rebuiltChild]
                    ) as Hex;
                } catch {
                    // ignore decode errors and fall back
                }
            }

            return includeSet.has(key) ? ((value ?? "0x") as Hex) : ("0x" as Hex);
        }

        return value;
    });
}

export function buildByteHintCandidates(
    components: Components,
    decodedValues: unknown,
    nested: Record<string, Components>,
    baseLabel: string
): HintCandidate[] {
    const leaves = collectByteLeaves(components, decodedValues, nested);
    const available = leaves.filter((leaf) => leaf.value !== "0x");
    if (available.length === 0) return [];

    const totalMasks = 1 << available.length;
    const candidates: HintCandidate[] = [];

    for (let mask = 1; mask < totalMasks; mask++) {
        const includeSet = new Set<string>();
        const labels: string[] = [];
        available.forEach((leaf, idx) => {
            if ((mask >> idx) & 1) {
                const key = leaf.path.join(".");
                includeSet.add(key);
                labels.push(key.replace(/\./g, "-"));
            }
        });

        const rebuilt = rebuildTupleWithMask(components, decodedValues, includeSet, nested);
        const value = (encodeAbiParameters as any)([{ type: "tuple", components }], [rebuilt]) as Hex;

        candidates.push({ label: `${baseLabel}-${labels.join("-")}`, value });
    }

    return candidates;
}
