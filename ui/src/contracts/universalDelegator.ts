export const universalDelegatorAbi = [
  {
    type: 'function',
    name: 'slots',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint96' }],
    outputs: [
      {
        name: 'size',
        type: 'tuple',
        components: [
          {
            name: '_trace',
            type: 'tuple',
            components: [
              {
                name: '_checkpoints',
                type: 'tuple[]',
                components: [
                  { name: '_key', type: 'uint48' },
                  { name: '_value', type: 'uint208' },
                ],
              },
            ],
          },
          { name: '_values', type: 'uint256[]' },
        ],
      },
      {
        name: 'prevSum',
        type: 'tuple',
        components: [
          {
            name: '_trace',
            type: 'tuple',
            components: [
              {
                name: '_checkpoints',
                type: 'tuple[]',
                components: [
                  { name: '_key', type: 'uint48' },
                  { name: '_value', type: 'uint208' },
                ],
              },
            ],
          },
          { name: '_values', type: 'uint256[]' },
        ],
      },
      {
        name: 'isShared',
        type: 'tuple',
        components: [
          {
            name: '_trace',
            type: 'tuple',
            components: [
              {
                name: '_checkpoints',
                type: 'tuple[]',
                components: [
                  { name: '_key', type: 'uint48' },
                  { name: '_value', type: 'uint208' },
                ],
              },
            ],
          },
        ],
      },
      {
        name: 'pendingFreeCumulative',
        type: 'tuple',
        components: [
          {
            name: '_trace',
            type: 'tuple',
            components: [
              {
                name: '_checkpoints',
                type: 'tuple[]',
                components: [
                  { name: '_key', type: 'uint48' },
                  { name: '_value', type: 'uint208' },
                ],
              },
            ],
          },
          { name: '_values', type: 'uint256[]' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'getBalance',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint96' }],
    outputs: [{ name: 'balance', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getAllocated',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint96' }],
    outputs: [{ name: 'allocated', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getAvailable',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint96' }],
    outputs: [{ name: 'available', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'multicall',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'data', type: 'bytes[]' }],
    outputs: [{ name: 'results', type: 'bytes[]' }],
  },
  {
    type: 'function',
    name: 'createSlot',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'parentIndex', type: 'uint96' },
      { name: 'isShared', type: 'bool' },
      { name: 'size', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'setIsShared',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'index', type: 'uint96' },
      { name: 'isShared', type: 'bool' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'setSize',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'index', type: 'uint96' },
      { name: 'size', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'swapSlots',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'index1', type: 'uint96' },
      { name: 'index2', type: 'uint96' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'assignNetwork',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'index', type: 'uint96' },
      { name: 'subnetwork', type: 'bytes32' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'unassignNetwork',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'subnetwork', type: 'bytes32' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'assignOperator',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'index', type: 'uint96' },
      { name: 'operator', type: 'address' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'unassignOperator',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'parentIndex', type: 'uint96' },
      { name: 'operator', type: 'address' },
    ],
    outputs: [],
  },
  { type: 'error', name: 'NotEnoughAvailable', inputs: [] },
  { type: 'error', name: 'NotSameParent', inputs: [] },
  { type: 'error', name: 'WrongOrder', inputs: [] },
  { type: 'error', name: 'NotSameAllocated', inputs: [] },
  { type: 'error', name: 'PartiallyAllocated', inputs: [] },
  { type: 'error', name: 'NetworkAlreadyAssigned', inputs: [] },
  { type: 'error', name: 'NetworkNotAssigned', inputs: [] },
  { type: 'error', name: 'OperatorAlreadyAssigned', inputs: [] },
  { type: 'error', name: 'OperatorNotAssigned', inputs: [] },
  { type: 'error', name: 'SlotAllocated', inputs: [] },
  { type: 'error', name: 'MissingRoleHolders', inputs: [] },
  { type: 'error', name: 'IsSharedNotChanged', inputs: [] },
  { type: 'error', name: 'WrongDepth', inputs: [] },
  {
    type: 'error',
    name: 'AccessControlUnauthorizedAccount',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'role', type: 'bytes32' },
    ],
  },
  {
    type: 'event',
    name: 'CreateSlot',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'size', type: 'uint256', indexed: false },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SetIsShared',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'isShared', type: 'bool', indexed: false },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SetSize',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'size', type: 'uint256', indexed: false },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SwapSlots',
    inputs: [
      { name: 'index1', type: 'uint96', indexed: true },
      { name: 'index2', type: 'uint96', indexed: true },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'AssignNetwork',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'subnetwork', type: 'bytes32', indexed: true },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UnassignNetwork',
    inputs: [{ name: 'subnetwork', type: 'bytes32', indexed: true }],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'AssignOperator',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'operator', type: 'address', indexed: true },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UnassignOperator',
    inputs: [
      { name: 'index', type: 'uint96', indexed: true },
      { name: 'operator', type: 'address', indexed: true },
    ],
    anonymous: false,
  },
] as const
