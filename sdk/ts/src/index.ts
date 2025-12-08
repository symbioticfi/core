import {
    type Address,
    type Hex,
    type PublicClient,
    decodeAbiParameters,
    decodeFunctionResult,
    encodeAbiParameters,
    encodeFunctionData
} from "viem";

const ZERO_BYTES32: Hex = `0x${"00".repeat(32)}`;
const ZERO_HINT = encodeAbiParameters([{ type: "bytes32" }], [ZERO_BYTES32]) as Hex;

export type HintCandidate = {
    label: string;
    value: Hex;
};

export type SimulationRequest = Parameters<PublicClient["simulateContract"]>[0];

export type HintEvaluation<Result> = {
    candidate: HintCandidate;
    success: boolean;
    gas?: bigint;
    result?: Result;
    request?: SimulationRequest;
    error?: unknown;
};

export type HintSelection<Result> = {
    best?: HintEvaluation<Result>;
    evaluations: HintEvaluation<Result>[];
};

export type HintContracts = {
    vaultHints?: Address;
    baseDelegatorHints?: Address;
    slasherHints?: Address;
    vetoSlasherHints?: Address;
    optInServiceHints?: Address;
    defaultStakerRewards?: Address;
};

const vaultHintsAbi = [
    {
        type: "function",
        name: "activeBalanceOfHints",
        stateMutability: "view",
        inputs: [
            { name: "vault", type: "address" },
            { name: "account", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "activeStakeHint",
        stateMutability: "view",
        inputs: [
            { name: "vault", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hint", type: "bytes" }]
    },
    {
        type: "function",
        name: "activeSharesHint",
        stateMutability: "view",
        inputs: [
            { name: "vault", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hint", type: "bytes" }]
    },
    {
        type: "function",
        name: "activeSharesOfHint",
        stateMutability: "view",
        inputs: [
            { name: "vault", type: "address" },
            { name: "account", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hint", type: "bytes" }]
    }
] as const;

const baseDelegatorHintsAbi = [
    {
        type: "function",
        name: "stakeHints",
        stateMutability: "view",
        inputs: [
            { name: "delegator", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "operator", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "TYPE",
        stateMutability: "view",
        inputs: [],
        outputs: [{ name: "t", type: "uint8" }]
    }
] as const;

const slasherHintsAbi = [
    {
        type: "function",
        name: "slashHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "operator", type: "address" },
            { name: "captureTimestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "cumulativeSlashHint",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "operator", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hint", type: "bytes" }]
    },
    {
        type: "function",
        name: "slashableStakeHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "operator", type: "address" },
            { name: "captureTimestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    }
] as const;

const vetoSlasherHintsAbi = [
    {
        type: "function",
        name: "requestSlashHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "operator", type: "address" },
            { name: "captureTimestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "executeSlashHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "slashIndex", type: "uint256" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "vetoSlashHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "slashIndex", type: "uint256" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    },
    {
        type: "function",
        name: "setResolverHints",
        stateMutability: "view",
        inputs: [
            { name: "slasher", type: "address" },
            { name: "subnetwork", type: "bytes32" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hints", type: "bytes" }]
    }
] as const;

const optInServiceHintsAbi = [
    {
        type: "function",
        name: "optInHint",
        stateMutability: "view",
        inputs: [
            { name: "optInService", type: "address" },
            { name: "who", type: "address" },
            { name: "where", type: "address" },
            { name: "timestamp", type: "uint48" }
        ],
        outputs: [{ name: "hint", type: "bytes" }]
    }
] as const;

const defaultStakerRewardsAbi = [
    {
        type: "function",
        name: "VAULT",
        stateMutability: "view",
        inputs: [],
        outputs: [{ name: "vault", type: "address" }]
    },
    {
        type: "function",
        name: "rewardsLength",
        stateMutability: "view",
        inputs: [
            { name: "token", type: "address" },
            { name: "network", type: "address" }
        ],
        outputs: [{ name: "length", type: "uint256" }]
    },
    {
        type: "function",
        name: "rewards",
        stateMutability: "view",
        inputs: [
            { name: "token", type: "address" },
            { name: "network", type: "address" },
            { name: "index", type: "uint256" }
        ],
        outputs: [
            { name: "amount", type: "uint256" },
            { name: "timestamp", type: "uint48" }
        ]
    },
    {
        type: "function",
        name: "lastUnclaimedReward",
        stateMutability: "view",
        inputs: [
            { name: "account", type: "address" },
            { name: "token", type: "address" },
            { name: "network", type: "address" }
        ],
        outputs: [{ name: "index", type: "uint256" }]
    }
] as const;

const stakeHintsComponents: Record<number, { name: string; label: string; type: "tuple"; components: { name: string; type: string }[] }> = {
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

const stakeBaseHintsComponents = [
    { name: "operatorVaultOptInHint", type: "bytes" },
    { name: "operatorNetworkOptInHint", type: "bytes" }
] as const;

function baseHintCandidates(): HintCandidate[] {
    return [{ label: "empty-bytes", value: "0x" }];
}

function dedupeCandidates(candidates: HintCandidate[]): HintCandidate[] {
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

function toUint48(value: bigint | number): number {
    return Number(value);
}

type StructHintPart = {
    name: string;
    label: string;
    value: Hex;
};

function buildStructHintCandidates(
    parts: StructHintPart[],
    encode: (values: Record<string, Hex | "0x">) => Hex,
    baseLabel: string
): HintCandidate[] {
    // Consider only non-empty hints for combinations; always include all fields in the struct.
    const available = parts.filter((part) => part.value !== "0x");
    if (available.length === 0) {
        return [];
    }

    const allNames = parts.map((p) => p.name);
    const candidates: HintCandidate[] = [];
    const totalMasks = 1 << available.length;

    for (let mask = 1; mask < totalMasks; mask++) {
        const values: Record<string, Hex | "0x"> = {};
        for (const name of allNames) {
            values[name] = "0x";
        }

        const labels: string[] = [];
        for (let idx = 0; idx < available.length; idx++) {
            if ((mask >> idx) & 1) {
                const part = available[idx];
                values[part.name] = part.value;
                labels.push(part.label);
            }
        }

        candidates.push({
            label: `${baseLabel}-${labels.join("-")}`,
            value: encode(values)
        });
    }

    return candidates;
}

type ByteLeaf = { path: string[]; value: Hex | "0x" };
type Components = readonly { name: string; type: string; components?: Components }[];

function collectByteLeaves(
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

function hasIncludedDescendant(includeSet: Set<string>, key: string): boolean {
    if (includeSet.has(key)) return true;
    for (const p of includeSet) {
        if (p.startsWith(`${key}.`)) return true;
    }
    return false;
}

function rebuildTupleWithMask(
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

function buildByteHintCandidates(
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

export class HintSDK {
    private readonly baseCandidates: HintCandidate[];

    constructor(
        private readonly client: PublicClient,
        private readonly contracts: HintContracts = {},
        private readonly defaultAccount?: Address
    ) {
        this.baseCandidates = baseHintCandidates();
    }

    async vaultActiveBalanceOfCandidates(params: {
        vault: Address;
        account: Address;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.vaultHints;

        if (address) {
            const components: Components = [
                { name: "activeSharesOfHint", type: "bytes" },
                { name: "activeStakeHint", type: "bytes" },
                { name: "activeSharesHint", type: "bytes" }
            ];

            const hints = await this.client.readContract({
                address,
                abi: vaultHintsAbi,
                functionName: "activeBalanceOfHints",
                args: [params.vault, params.account, toUint48(params.timestamp)]
            });

            if (hints !== "0x") {
                candidates.push({ label: "vault-hints", value: hints as Hex });

                try {
                    const [decoded] = decodeAbiParameters([{ type: "tuple", components }], hints);
                    const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                    const structCandidates =
                        buildByteHintCandidates(components, decodedArray, {}, "vault-activeBalance");
                    candidates.push(...structCandidates);
                } catch {
                    // ignore decoding errors; fall back to raw + empty
                }
            }
        }

        return dedupeCandidates(candidates);
    }

    async stakeCandidates(params: {
        delegator: Address;
        subnetwork: Hex;
        operator: Address;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.baseDelegatorHints;

        if (!address) {
            return dedupeCandidates(candidates);
        }

        let delegatorType: number | undefined;
        try {
            delegatorType = Number(
                await this.client.readContract({ address: params.delegator, abi: baseDelegatorHintsAbi, functionName: "TYPE" })
            );
        } catch {
            delegatorType = undefined;
        }

        const hints = await this.client.readContract({
            address,
            abi: baseDelegatorHintsAbi,
            functionName: "stakeHints",
            args: [params.delegator, params.subnetwork, params.operator, toUint48(params.timestamp)]
        });

        if (hints !== "0x") {
            candidates.push({ label: "delegator-hints", value: hints as Hex });
        }

        const shape = delegatorType !== undefined ? stakeHintsComponents[delegatorType] : undefined;
        if (shape && hints !== "0x") {
            try {
                const [decodedTuple] = decodeAbiParameters([{ type: "tuple", components: shape.components }], hints);
                const decodedArray = Array.isArray(decodedTuple) ? decodedTuple : [decodedTuple];

                const nestedMap: Record<string, Components> = {
                    "baseHints": stakeBaseHintsComponents
                };

                const structCandidates = buildByteHintCandidates(
                    shape.components,
                    decodedArray,
                    nestedMap,
                    `stake-${shape.label}`
                );
                candidates.push(...structCandidates);
            } catch {
                // ignore decode errors; fallback to raw hints + empty
            }
        }

        return dedupeCandidates(candidates);
    }

    async slashCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.slasherHints;

        if (!address) {
            return dedupeCandidates(candidates);
        }

        const slashHints = await this.client.readContract({
            address,
            abi: slasherHintsAbi,
            functionName: "slashHints",
            args: [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)]
        });

        if (slashHints !== "0x") {
            candidates.push({ label: "slasher-hints", value: slashHints as Hex });
            try {
                const [decoded] = decodeAbiParameters(
                    [{ type: "tuple", components: [{ name: "slashableStakeHints", type: "bytes" }] }],
                    slashHints
                );
                const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                const nestedMap: Record<string, Components> = {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                };
                const structCandidates = buildByteHintCandidates(
                    [{ name: "slashableStakeHints", type: "bytes" }],
                    decodedArray,
                    nestedMap,
                    "slasher"
                );
                candidates.push(...structCandidates);
            } catch {
                // ignore decode errors
            }
        }

        return dedupeCandidates(candidates);
    }

    async slashableStakeCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.slasherHints;

        if (!address) {
            return dedupeCandidates(candidates);
        }

        // Use slasher hints contract to fetch nested hints for slashableStake
        const slashableHints = await this.client.readContract({
            address,
            abi: slasherHintsAbi,
            functionName: "slashableStakeHints",
            args: [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)]
        });

        if (slashableHints !== "0x") {
            candidates.push({ label: "slashable-hints", value: slashableHints as Hex });

            try {
                const [decoded] = decodeAbiParameters(
                    [
                        {
                            type: "tuple",
                            components: [
                                { name: "stakeHints", type: "bytes" },
                                { name: "cumulativeSlashFromHint", type: "bytes" }
                            ]
                        }
                    ],
                    slashableHints
                );
                const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                const structCandidates = buildByteHintCandidates(
                    [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ],
                    decodedArray,
                    {},
                    "slashable"
                );
                candidates.push(...structCandidates);
            } catch {
                // ignore decode errors
            }
        }

        return dedupeCandidates(candidates);
    }

    async vetoSlashRequestCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.vetoSlasherHints;

        if (!address) {
            return candidates;
        }

        const hints = await this.client.readContract({
            address,
            abi: vetoSlasherHintsAbi,
            functionName: "requestSlashHints",
            args: [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)]
        });

        if (hints !== "0x") {
            candidates.unshift({ label: "veto-requestSlashHints", value: hints as Hex });

            try {
                const components: Components = [{ name: "slashableStakeHints", type: "bytes" }];
                const [decoded] = decodeAbiParameters(
                    [
                        {
                            type: "tuple",
                            components
                        }
                    ],
                    hints
                );
                const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                const nestedMap: Record<string, Components> = {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                };
                const structCandidates = buildByteHintCandidates(
                    components,
                    decodedArray,
                    nestedMap,
                    "veto-request"
                );
                candidates.push(...structCandidates);
            } catch {
                // ignore decode errors
            }
        }

        return dedupeCandidates(candidates);
    }

    async vetoSlashExecuteCandidates(params: { slasher: Address; slashIndex: bigint | number }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.vetoSlasherHints;

        if (!address) {
            return candidates;
        }

        const hints = await this.client.readContract({
            address,
            abi: vetoSlasherHintsAbi,
            functionName: "executeSlashHints",
            args: [params.slasher, BigInt(params.slashIndex)]
        });

        if (hints !== "0x") {
            candidates.unshift({ label: "veto-executeSlashHints", value: hints as Hex });

            try {
                const components: Components = [
                    { name: "captureResolverHint", type: "bytes" },
                    { name: "currentResolverHint", type: "bytes" },
                    { name: "slashableStakeHints", type: "bytes" }
                ];
                const [decoded] = decodeAbiParameters(
                    [
                        {
                            type: "tuple",
                            components
                        }
                    ],
                    hints
                );
                const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                const nestedMap: Record<string, Components> = {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                };
                const structCandidates = buildByteHintCandidates(
                    components,
                    decodedArray,
                    nestedMap,
                    "veto-execute"
                );
                candidates.push(...structCandidates);
            } catch {
                // ignore decode errors
            }
        }

        return dedupeCandidates(candidates);
    }

    async vetoSlashVetoCandidates(params: { slasher: Address; slashIndex: bigint | number }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.vetoSlasherHints;

        if (!address) {
            return candidates;
        }

        const hints = await this.client.readContract({
            address,
            abi: vetoSlasherHintsAbi,
            functionName: "vetoSlashHints",
            args: [params.slasher, BigInt(params.slashIndex)]
        });

        if (hints !== "0x") {
            candidates.unshift({ label: "veto-vetoSlashHints", value: hints as Hex });
        }

        return dedupeCandidates(candidates);
    }

    async vetoSlashResolverCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.vetoSlasherHints;

        if (!address) {
            return candidates;
        }

        const hints = await this.client.readContract({
            address,
            abi: vetoSlasherHintsAbi,
            functionName: "setResolverHints",
            args: [params.slasher, params.subnetwork, toUint48(params.timestamp)]
        });

        if (hints !== "0x") {
            candidates.unshift({ label: "veto-setResolverHints", value: hints as Hex });
        }

        return dedupeCandidates(candidates);
    }

    async resolverCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        return this.vetoSlashResolverCandidates(params);
    }

    async optInCandidates(params: {
        optInService: Address;
        who: Address;
        where: Address;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const candidates = [...this.baseCandidates];
        const address = this.contracts.optInServiceHints;

        if (address) {
            const hint = await this.client.readContract({
                address,
                abi: optInServiceHintsAbi,
                functionName: "optInHint",
                args: [params.optInService, params.who, params.where, toUint48(params.timestamp)]
            });

            if (hint !== "0x") {
                candidates.unshift({ label: "opt-in-hints", value: hint as Hex });
            }
        }

        return dedupeCandidates(candidates);
    }

    async defaultStakerRewardsDistributeCandidates(params: {
        rewards: Address;
        timestamp: bigint | number;
        maxAdminFee: bigint | number;
        vault?: Address;
    }): Promise<HintCandidate[]> {
        const candidates: HintCandidate[] = [];
        const vault =
            params.vault
            ?? await this.client.readContract({
                address: params.rewards,
                abi: defaultStakerRewardsAbi,
                functionName: "VAULT"
            });

        const activeSharesHint =
            this.contracts.vaultHints === undefined
                ? "0x"
                : await this.client.readContract({
                    address: this.contracts.vaultHints,
                    abi: vaultHintsAbi,
                    functionName: "activeSharesHint",
                    args: [vault, toUint48(params.timestamp)]
                });

        const activeStakeHint =
            this.contracts.vaultHints === undefined
                ? "0x"
                : await this.client.readContract({
                    address: this.contracts.vaultHints,
                    abi: vaultHintsAbi,
                    functionName: "activeStakeHint",
                    args: [vault, toUint48(params.timestamp)]
                });

        const encoded = encodeAbiParameters(
            [
                { name: "timestamp", type: "uint48" },
                { name: "maxAdminFee", type: "uint256" },
                { name: "activeSharesHint", type: "bytes" },
                { name: "activeStakeHint", type: "bytes" }
            ],
            [toUint48(params.timestamp), BigInt(params.maxAdminFee), activeSharesHint, activeStakeHint]
        );

        candidates.push({ label: "default-staker-rewards-distribute", value: encoded as Hex });
        candidates.push({ label: "default-staker-rewards-distribute-empty", value: encodeAbiParameters(
            [
                { name: "timestamp", type: "uint48" },
                { name: "maxAdminFee", type: "uint256" },
                { name: "activeSharesHint", type: "bytes" },
                { name: "activeStakeHint", type: "bytes" }
            ],
            [toUint48(params.timestamp), BigInt(params.maxAdminFee), "0x", "0x"]
        ) as Hex });

        return dedupeCandidates(candidates);
    }

    async defaultStakerRewardsClaimCandidates(params: {
        rewards: Address;
        account: Address;
        token: Address;
        network: Address;
        maxRewards: bigint | number;
        vault?: Address;
    }): Promise<HintCandidate[]> {
        const startIndex = await this.client.readContract({
            address: params.rewards,
            abi: defaultStakerRewardsAbi,
            functionName: "lastUnclaimedReward",
            args: [params.account, params.token, params.network]
        });
        const rewardsLength = await this.client.readContract({
            address: params.rewards,
            abi: defaultStakerRewardsAbi,
            functionName: "rewardsLength",
            args: [params.token, params.network]
        });

        const totalRemaining = BigInt(rewardsLength) - BigInt(startIndex);
        const rewardsToClaim = Number(totalRemaining < BigInt(params.maxRewards) ? totalRemaining : BigInt(params.maxRewards));

        const vault =
            params.vault
            ?? await this.client.readContract({
                address: params.rewards,
                abi: defaultStakerRewardsAbi,
                functionName: "VAULT"
            });

        const activeSharesOfHints: Hex[] = [];
        for (let i = 0; i < rewardsToClaim; i++) {
            const reward = await this.client.readContract({
                address: params.rewards,
                abi: defaultStakerRewardsAbi,
                functionName: "rewards",
                args: [params.token, params.network, BigInt(startIndex) + BigInt(i)]
            });
            const ts = BigInt((reward as readonly [bigint, bigint | number])[1]);

            if (this.contracts.vaultHints) {
                const hint = await this.client.readContract({
                    address: this.contracts.vaultHints,
                    abi: vaultHintsAbi,
                    functionName: "activeSharesOfHint",
                    args: [vault, params.account, toUint48(ts)]
                });
                activeSharesOfHints.push(hint as Hex);
            } else {
                activeSharesOfHints.push("0x");
            }
        }

        const fallbackHints = Array(rewardsToClaim).fill("0x");

        const encodedWithHints = encodeAbiParameters(
            [
                { name: "network", type: "address" },
                { name: "maxRewards", type: "uint256" },
                { name: "activeSharesOfHints", type: "bytes[]" }
            ],
            [params.network, BigInt(params.maxRewards), activeSharesOfHints]
        ) as Hex;

        const encodedEmpty = encodeAbiParameters(
            [
                { name: "network", type: "address" },
                { name: "maxRewards", type: "uint256" },
                { name: "activeSharesOfHints", type: "bytes[]" }
            ],
            [params.network, BigInt(params.maxRewards), fallbackHints]
        ) as Hex;

        const candidates: HintCandidate[] = [
            { label: "default-staker-rewards-claim", value: encodedWithHints },
            { label: "default-staker-rewards-claim-empty", value: encodedEmpty }
        ];

        return dedupeCandidates(candidates);
    }

    async selectBestHint<Result = unknown>(params: {
        candidates: HintCandidate[];
        buildCall: (hint: Hex) => SimulationRequest;
    }): Promise<HintSelection<Result>> {
        const candidates = dedupeCandidates(params.candidates);

        const requests = candidates.map((candidate) => {
            const request = params.buildCall(candidate.value);
            const account = (request as { account?: Address }).account ?? this.defaultAccount;

            const call = {
                to: request.address,
                abi: (request as { abi?: unknown }).abi as unknown,
                functionName: (request as { functionName?: string }).functionName,
                args: (request as { args?: unknown[] }).args ?? [],
                gas: (request as { gas?: bigint }).gas,
                value: (request as { value?: bigint }).value
            };

            return { candidate, request, account, call };
        });

        // If calls use different accounts, prefer the first one (simulateCalls only accepts a single account).
        const account = requests.find((r) => r.account)?.account ?? this.defaultAccount;

        const response = await this.client.simulateCalls({
            account,
            calls: requests.map((r) => ({
                ...r.call,
                data:
                    r.call.abi && r.call.functionName
                        ? encodeFunctionData({
                            abi: r.call.abi as any,
                            functionName: r.call.functionName as string,
                            args: r.call.args
                        })
                        : undefined
            }))
        } as any);

        const evaluations: HintEvaluation<Result>[] = response.results.map((result, idx) => {
            const { candidate, request } = requests[idx];
            const output = (result as { data?: Hex; result?: Hex }).data ?? (result as { result?: Hex }).result;
            let decoded: Result | undefined;
            if (result.status === "success" && output && (requests[idx].call.abi as any)) {
                try {
                    decoded = decodeFunctionResult({
                        abi: requests[idx].call.abi as any,
                        functionName: requests[idx].call.functionName as string,
                        data: output
                    }) as Result;
                } catch {
                    decoded = undefined;
                }
            }

            return {
                candidate,
                success: result.status === "success",
                gas: (result as { gasUsed?: bigint; gas?: bigint }).gasUsed
                    ?? (result as { gas?: bigint }).gas,
                result: decoded,
                request
            };
        });

        const successful = evaluations.filter((evaluation) => evaluation.success);
        const best = successful.reduce<HintEvaluation<Result> | undefined>((winner, evaluation) => {
            if (!winner) return evaluation;
            if (winner.gas === undefined) return evaluation;
            if (evaluation.gas === undefined) return winner;
            return evaluation.gas < winner.gas ? evaluation : winner;
        }, undefined);

        return { best, evaluations };
    }
}

export const abis = {
    vaultHintsAbi,
    baseDelegatorHintsAbi,
    slasherHintsAbi,
    vetoSlasherHintsAbi,
    optInServiceHintsAbi,
    defaultStakerRewardsAbi
};

export const defaults = {
    ZERO_HINT,
    ZERO_BYTES32
};
