// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VaultTokenized} from "./VaultTokenized.sol";
import {VaultVotesImplementation} from "./VaultVotesImplementation.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultVotes is VaultTokenized {
    using Address for address;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory,
        address implementation
    ) VaultTokenized(delegatorFactory, slasherFactory, vaultFactory, implementation) {}

    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);

        _implementation().functionDelegateCall(abi.encodeWithSelector(VaultVotesImplementation._initialize.selector));
    }

    function _migrate(uint64 oldVersion, uint64, /* newVersion */ bytes calldata data) internal virtual override {
        if (oldVersion != 3) {
            revert();
        }

        _implementation().functionDelegateCall(
            abi.encodeWithSelector(VaultVotesImplementation._initialize.selector, data)
        );
    }
}
