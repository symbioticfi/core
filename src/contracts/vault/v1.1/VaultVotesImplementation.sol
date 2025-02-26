// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VaultTokenizedImplementation} from "src/contracts/vault/v1.1/VaultTokenizedImplementation.sol";

import {IVaultVotes} from "../../../interfaces/vault/v1.1/IVaultVotes.sol";

import {Checkpoints} from "../../libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";

contract VaultVotesImplementation is VaultTokenizedImplementation, VotesUpgradeable, IVaultVotes {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Address for address;

    constructor(
        address baseImplementation
    ) VaultTokenizedImplementation(baseImplementation) {}

    /**
     * @inheritdoc IERC6372
     */
    function clock() public view override(VotesUpgradeable, IERC6372) returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @inheritdoc IERC6372
     */
    function CLOCK_MODE() public view override(VotesUpgradeable, IERC6372) returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @inheritdoc IVotes
     */
    function getPastTotalSupply(
        uint256 timepoint
    ) public view override(VotesUpgradeable, IVotes) returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _activeShares.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    function deposit(
        address onBehalfOf,
        uint256 amount
    ) public override returns (uint256 depositedAmount, uint256 mintedShares) {
        (depositedAmount, mintedShares) = super.deposit(onBehalfOf, amount);

        if (_activeShares.latest() > type(uint208).max) {
            revert SafeSupplyExceeded();
        }

        _transferVotingUnits(address(0), onBehalfOf, mintedShares);
    }

    function withdraw(
        address claimer,
        uint256 amount
    ) public override returns (uint256 burnedShares, uint256 mintedShares) {
        (burnedShares, mintedShares) = super.withdraw(claimer, amount);

        _transferVotingUnits(msg.sender, address(0), burnedShares);
    }

    function redeem(
        address claimer,
        uint256 shares
    ) public override returns (uint256 withdrawnAssets, uint256 mintedShares) {
        (withdrawnAssets, mintedShares) = super.redeem(claimer, shares);

        _transferVotingUnits(msg.sender, address(0), shares);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        _transferVotingUnits(from, to, value);
    }

    /**
     * @inheritdoc VotesUpgradeable
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal override {
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    /**
     * @inheritdoc VotesUpgradeable
     */
    function _getVotingUnits(
        address account
    ) internal view override returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    function _VaultVotes_init(
        bytes calldata /* data */
    ) external {
        __EIP712_init("VaultVotes", "1");
    }
}
