// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IMerklDistributor, IMerklClaimer} from "../../../interfaces/adapters/common/IMerklClaimer.sol";

/// @title MerklClaimer
/// @notice Minimal Merkl distributor claim forwarder.
contract MerklClaimer is IMerklClaimer {
    /* IMMUTABLES */

    /// @inheritdoc IMerklClaimer
    address public immutable MERKL_DISTRIBUTOR;

    /* CONSTRUCTOR */

    constructor(address merklDistributor) {
        MERKL_DISTRIBUTOR = merklDistributor;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IMerklClaimer
    function claim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) public {
        address[] memory users = new address[](tokens.length);
        for (uint256 i; i < users.length; ++i) {
            users[i] = address(this);
        }
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }
}
