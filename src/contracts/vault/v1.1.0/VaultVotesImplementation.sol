// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VaultStorage} from "../VaultStorage.sol";

import {IVault} from "../../../interfaces/vault/v1.1.0/IVault.sol";
import {IVaultVotes} from "../../../interfaces/vault/v1.1.0/IVaultVotes.sol";

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

contract VaultVotesImplementation is VaultStorage, VotesUpgradeable, Proxy, IVaultVotes {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Address for address;

    address private immutable BASE_IMPLEMENTATION;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address baseImplementation
    ) VaultStorage(delegatorFactory, slasherFactory) {
        BASE_IMPLEMENTATION = baseImplementation;
    }

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
    ) external returns (uint256 depositedAmount, uint256 mintedShares) {
        (depositedAmount, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(
                abi.encodeWithSelector(IVault.deposit.selector, onBehalfOf, amount)
            ),
            (uint256, uint256)
        );

        if (_activeShares.latest() > type(uint208).max) {
            revert SafeSupplyExceeded();
        }

        _transferVotingUnits(address(0), onBehalfOf, mintedShares);
    }

    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares) {
        (burnedShares, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(abi.encodeWithSelector(IVault.withdraw.selector, claimer, amount)),
            (uint256, uint256)
        );

        _transferVotingUnits(msg.sender, address(0), burnedShares);
    }

    function redeem(address claimer, uint256 shares) external returns (uint256 withdrawnAssets, uint256 mintedShares) {
        (withdrawnAssets, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(abi.encodeWithSelector(IVault.redeem.selector, claimer, shares)),
            (uint256, uint256)
        );

        _transferVotingUnits(msg.sender, address(0), shares);
    }

    /**
     * @dev Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
     * should be zero. Total supply of voting units will be adjusted with mints and burns.
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal override {
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(
        address account
    ) internal view override returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    function _implementation() internal view override returns (address) {
        return BASE_IMPLEMENTATION;
    }

    function _initialize(
        bytes calldata /* data */
    ) external {
        __EIP712_init("VaultVotes", "1");
    }
}
