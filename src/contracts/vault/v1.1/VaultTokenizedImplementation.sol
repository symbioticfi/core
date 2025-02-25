// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {VaultStorage} from "./VaultStorage.sol";

import {IVault} from "../../../interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../../interfaces/vault/v1.1/IVaultTokenized.sol";

import {Checkpoints} from "../../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultTokenizedImplementation is
    VaultStorage,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    Proxy,
    IVaultTokenized
{
    using Checkpoints for Checkpoints.Trace256;
    using Address for address;

    address private immutable BASE_IMPLEMENTATION;

    constructor(
        address baseImplementation
    ) {
        BASE_IMPLEMENTATION = baseImplementation;
    }

    /**
     * @inheritdoc IERC20Metadata
     */
    function decimals() public view override(ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(collateral).decimals();
    }

    /**
     * @inheritdoc IERC20
     */
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IERC20
     */
    function balanceOf(
        address account
    ) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    function deposit(
        address onBehalfOf,
        uint256 amount
    ) public virtual returns (uint256 depositedAmount, uint256 mintedShares) {
        (depositedAmount, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(abi.encodeCall(IVault.deposit, (onBehalfOf, amount))),
            (uint256, uint256)
        );

        emit Transfer(address(0), onBehalfOf, mintedShares);
    }

    function withdraw(
        address claimer,
        uint256 amount
    ) public virtual returns (uint256 burnedShares, uint256 mintedShares) {
        (burnedShares, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(abi.encodeCall(IVault.withdraw, (claimer, amount))),
            (uint256, uint256)
        );

        emit Transfer(msg.sender, address(0), burnedShares);
    }

    function redeem(
        address claimer,
        uint256 shares
    ) public virtual returns (uint256 withdrawnAssets, uint256 mintedShares) {
        (withdrawnAssets, mintedShares) = abi.decode(
            BASE_IMPLEMENTATION.functionDelegateCall(abi.encodeCall(IVault.redeem, (claimer, shares))),
            (uint256, uint256)
        );

        emit Transfer(msg.sender, address(0), shares);
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _activeShares.push(Time.timestamp(), totalSupply() + value);
        } else {
            uint256 fromBalance = balanceOf(from);
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _activeSharesOf[from].push(Time.timestamp(), fromBalance - value);
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _activeShares.push(Time.timestamp(), totalSupply() - value);
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _activeSharesOf[to].push(Time.timestamp(), balanceOf(to) + value);
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @inheritdoc Proxy
     */
    function _implementation() internal view override returns (address) {
        return BASE_IMPLEMENTATION;
    }

    function _VaultTokenized_init(
        bytes calldata data
    ) external {
        (string memory name, string memory symbol) = abi.decode(data, (string, string));

        __ERC20_init(name, symbol);
    }
}
