// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IMerklDistributor, IMerklRedistributor} from "../../../interfaces/adapters/common/IMerklRedistributor.sol";

/// @title MerklRedistributor
/// @notice Minimal Merkl distributor claim forwarder.
contract MerklRedistributor is IMerklRedistributor {
    /* IMMUTABLES */

    /// @inheritdoc IMerklRedistributor
    address public immutable MERKL_DISTRIBUTOR;

    /* CONSTRUCTOR */

    constructor(address merklDistributor) {
        MERKL_DISTRIBUTOR = merklDistributor;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IMerklRedistributor
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) public {
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }
}
