// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VotesUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/governance/utils/VotesUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {VaultTokenized} from "./VaultTokenized.sol";

contract VaultVotes is VaultTokenized, VotesUpgradeable {
    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory
    ) VaultTokenized(delegatorFactory, slasherFactory, vaultFactory) {}

    function clock() public view override returns (uint48) {
        return Time.timestamp();
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _getVotingUnits(
        address account
    ) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    function _maxSupply() internal view virtual returns (uint256) {
        return type(uint208).max;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        VaultTokenized._update(from, to, value);

        // copied from ERC20Votes._update
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }
}
