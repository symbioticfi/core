import { type Address, type Hex, type PublicClient } from "viem";

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
