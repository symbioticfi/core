import { decodeAbiParameters, encodeAbiParameters, type Address, type Hex, type PublicClient, encodeFunctionData, decodeFunctionResult } from "viem";
import { 
    baseDelegatorHintsAbi, 
    optInServiceHintsAbi, 
    slasherHintsAbi, 
    vaultHintsAbi, 
    vetoSlasherHintsAbi, 
    defaultStakerRewardsAbi
} from "./abis.js";
import { type HintCandidate, type HintContracts, type HintSelection, type SimulationRequest, type HintEvaluation } from "./types.js";
import {
    baseHintCandidates,
    buildByteHintCandidates,
    dedupeCandidates,
    stakeBaseHintsComponents,
    stakeHintsComponents,
    toUint48,
    type Components
} from "./utils.js";

const ZERO_BYTES32: Hex = `0x${"00".repeat(32)}`;
const ZERO_HINT = encodeAbiParameters([{ type: "bytes32" }], [ZERO_BYTES32]) as Hex;

export class HintSDK {
    private readonly baseCandidates: HintCandidate[];

    constructor(
        private readonly client: PublicClient,
        private readonly contracts: HintContracts = {},
        private readonly defaultAccount?: Address
    ) {
        this.baseCandidates = baseHintCandidates();
    }

    private async fetchHints(
        address: Address | undefined,
        abi: any,
        functionName: string,
        args: any[],
        config: {
            rawLabel?: string;
            structLabel?: string;
            components?: Components;
            resolveShape?: (hint: Hex) => Promise<{ components: Components; structLabelSuffix?: string; nestedMap?: Record<string, Components> } | undefined>;
            nestedMap?: Record<string, Components>;
        }
    ): Promise<HintCandidate[]> {
        const candidates: HintCandidate[] = [];
        if (!address) return candidates;

        const hint = await this.client.readContract({
            address,
            abi,
            functionName,
            args
        }) as Hex;

        if (hint !== "0x") {
            if (config.rawLabel) {
                candidates.push({ label: config.rawLabel, value: hint });
            } else if (!config.structLabel && !config.resolveShape) {
                // If no labels provided, maybe this call was just for raw hint without label? 
                // In existing code, all raw hints have labels.
            }

            if (config.components || config.resolveShape) {
                try {
                    let components = config.components;
                    let nestedMap = config.nestedMap ?? {};
                    let structLabel = config.structLabel ?? config.rawLabel ?? "hint";

                    if (config.resolveShape) {
                        const resolved = await config.resolveShape(hint);
                        if (!resolved) return candidates; 
                        components = resolved.components;
                        if (resolved.structLabelSuffix) {
                            // If explicit structLabel base was not provided, use a default, but usually for delegated hints we construct it.
                            structLabel = config.structLabel ? `${config.structLabel}-${resolved.structLabelSuffix}` : resolved.structLabelSuffix;
                        }
                        if (resolved.nestedMap) {
                            nestedMap = resolved.nestedMap;
                        }
                    }

                    if (components) {
                        const [decoded] = decodeAbiParameters([{ type: "tuple", components }], hint);
                        const decodedArray = Array.isArray(decoded) ? decoded : [decoded];
                        
                        const structCandidates = buildByteHintCandidates(
                            components, 
                            decodedArray, 
                            nestedMap, 
                            structLabel
                        );
                        candidates.push(...structCandidates);
                    }
                } catch {
                    // ignore decode errors
                }
            }
        }
        return candidates;
    }

    async vaultActiveBalanceOfCandidates(params: {
        vault: Address;
        account: Address;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.vaultHints,
            vaultHintsAbi,
            "activeBalanceOfHints",
            [params.vault, params.account, toUint48(params.timestamp)],
            {
                rawLabel: "vault-hints",
                structLabel: "vault-activeBalance",
                components: [
                    { name: "activeSharesOfHint", type: "bytes" },
                    { name: "activeStakeHint", type: "bytes" },
                    { name: "activeSharesHint", type: "bytes" }
                ]
            }
        );
        return dedupeCandidates([...this.baseCandidates, ...fetched]);
    }

    async stakeCandidates(params: {
        delegator: Address;
        subnetwork: Hex;
        operator: Address;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.baseDelegatorHints,
            baseDelegatorHintsAbi,
            "stakeHints",
            [params.delegator, params.subnetwork, params.operator, toUint48(params.timestamp)],
            {
                rawLabel: "delegator-hints",
                structLabel: "stake", // will be appended with suffix
                resolveShape: async () => {
                   let delegatorType: number | undefined;
                    try {
                        delegatorType = Number(
                            await this.client.readContract({ address: params.delegator, abi: baseDelegatorHintsAbi, functionName: "TYPE" })
                        );
                    } catch {
                        delegatorType = undefined;
                    }
                    
                    const shape = delegatorType !== undefined ? stakeHintsComponents[delegatorType] : undefined;
                    if (!shape) return undefined;

                    return {
                        components: shape.components,
                        structLabelSuffix: shape.label,
                        nestedMap: { "baseHints": stakeBaseHintsComponents }
                    };
                }
            }
        );
        return dedupeCandidates([...this.baseCandidates, ...fetched]);
    }

    async slashCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.slasherHints,
            slasherHintsAbi,
            "slashHints",
            [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)],
            {
                rawLabel: "slasher-hints",
                structLabel: "slasher",
                components: [{ name: "slashableStakeHints", type: "bytes" }],
                nestedMap: {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                }
            }
        );
        return dedupeCandidates([...this.baseCandidates, ...fetched]);
    }

    async slashableStakeCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.slasherHints,
            slasherHintsAbi,
            "slashableStakeHints",
            [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)],
            {
                rawLabel: "slashable-hints",
                structLabel: "slashable",
                components: [
                    { name: "stakeHints", type: "bytes" },
                    { name: "cumulativeSlashFromHint", type: "bytes" }
                ]
            }
        );
        return dedupeCandidates([...this.baseCandidates, ...fetched]);
    }

    async vetoSlashRequestCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        operator: Address;
        captureTimestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.vetoSlasherHints,
            vetoSlasherHintsAbi,
            "requestSlashHints",
            [params.slasher, params.subnetwork, params.operator, toUint48(params.captureTimestamp)],
            {
                rawLabel: "veto-requestSlashHints",
                structLabel: "veto-request",
                components: [{ name: "slashableStakeHints", type: "bytes" }],
                nestedMap: {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                }
            }
        );
        // Special case: `veto-requestSlashHints` raw label was unshifted (at start) in original code, but here order doesn't strictly matter for dedupe, but let's be consistent.
        // `dedupeCandidates` preserves first occurrence.
        // Base hints are always first.
        
        // Wait, original: `candidates.unshift(...)`.
        // My code: `[...this.baseCandidates, ...fetched]` puts fetched after base.
        // But `unshift` puts it BEFORE base candidates?
        // Let's check original `vetoSlashRequestCandidates`:
        // `candidates = [...this.baseCandidates];`
        // `candidates.unshift(...)` -> Put BEFORE base candidates.
        
        // Actually, does it matter? `baseHintCandidates` is just "empty-bytes".
        // Usually empty bytes is a fallback.
        // If I put it at the end, it might be preferred less if the consumer logic picks first?
        // `selectBestHint` simulates ALL and picks best successfully.
        // So order only matters for default fallback if all fail/same gas?
        // `dedupeCandidates` keeps FIRST unique.
        
        // If I unshift, I put hints BEFORE "empty-bytes".
        // If I push, I put hints AFTER "empty-bytes".
        
        // Original code:
        // `candidates = [...base]`
        // `candidates.unshift(...)`
        // So `[hints..., base...]`
        
        // My new code: `[...base, ...fetched]` -> `[base..., hints...]`
        
        // I should probably conform to original order: `[...fetched, ...this.baseCandidates]`.
        // Exception: `vaultActiveBalanceOfCandidates` used `push` (AFTER base).
        // `stakeCandidates` used `push`.
        // `slashCandidates` used `push`.
        // `slashableStakeCandidates` used `push`.
        
        // `vetoSlashRequestCandidates` used `unshift` (BEFORE base).
        // `vetoSlashExecuteCandidates` used `unshift`.
        // `vetoSlashVetoCandidates` used `unshift`.
        // `vetoSlashResolverCandidates` used `unshift`.
        // `optInCandidates` used `unshift`.
        
        // OK, I will respect this difference.
        
        return dedupeCandidates([...fetched, ...this.baseCandidates]);
    }

    async vetoSlashExecuteCandidates(params: { slasher: Address; slashIndex: bigint | number }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.vetoSlasherHints,
            vetoSlasherHintsAbi,
            "executeSlashHints",
            [params.slasher, BigInt(params.slashIndex)],
            {
                rawLabel: "veto-executeSlashHints",
                structLabel: "veto-execute",
                components: [
                    { name: "captureResolverHint", type: "bytes" },
                    { name: "currentResolverHint", type: "bytes" },
                    { name: "slashableStakeHints", type: "bytes" }
                ],
                nestedMap: {
                    "slashableStakeHints": [
                        { name: "stakeHints", type: "bytes" },
                        { name: "cumulativeSlashFromHint", type: "bytes" }
                    ]
                }
            }
        );
        return dedupeCandidates([...fetched, ...this.baseCandidates]);
    }

    async vetoSlashVetoCandidates(params: { slasher: Address; slashIndex: bigint | number }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.vetoSlasherHints,
            vetoSlasherHintsAbi,
            "vetoSlashHints",
            [params.slasher, BigInt(params.slashIndex)],
            {
                rawLabel: "veto-vetoSlashHints"
            }
        );
        return dedupeCandidates([...fetched, ...this.baseCandidates]);
    }

    async vetoSlashResolverCandidates(params: {
        slasher: Address;
        subnetwork: Hex;
        timestamp: bigint | number;
    }): Promise<HintCandidate[]> {
        const fetched = await this.fetchHints(
            this.contracts.vetoSlasherHints,
            vetoSlasherHintsAbi,
            "setResolverHints",
            [params.slasher, params.subnetwork, toUint48(params.timestamp)],
            {
                rawLabel: "veto-setResolverHints"
            }
        );
        return dedupeCandidates([...fetched, ...this.baseCandidates]);
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
        const fetched = await this.fetchHints(
            this.contracts.optInServiceHints,
            optInServiceHintsAbi,
            "optInHint",
            [params.optInService, params.who, params.where, toUint48(params.timestamp)],
            {
                rawLabel: "opt-in-hints"
            }
        );
        return dedupeCandidates([...fetched, ...this.baseCandidates]);
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
