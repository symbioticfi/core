export const vaultHintsAbi = [
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

export const baseDelegatorHintsAbi = [
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

export const slasherHintsAbi = [
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

export const vetoSlasherHintsAbi = [
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

export const optInServiceHintsAbi = [
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

export const defaultStakerRewardsAbi = [
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
