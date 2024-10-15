// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Vault} from "./Vault.sol";

import {IVaultTokenized} from "../../interfaces/vault/IVaultTokenized.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract VaultTokenized is Vault, ERC20Upgradeable, IVaultTokenized {
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory
    ) Vault(delegatorFactory, slasherFactory, vaultFactory) {}

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral).decimals();
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function totalSupply() public view override returns (uint256) {
        return activeShares();
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return activeSharesOf(account);
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(
        address onBehalfOf,
        uint256 amount
    ) public override(Vault, IVault) returns (uint256 depositedAmount, uint256 mintedShares) {
        (depositedAmount, mintedShares) = super.deposit(onBehalfOf, amount);

        emit Transfer(address(0), onBehalfOf, mintedShares);
    }

    function _withdraw(
        address claimer,
        uint256 withdrawnAssets,
        uint256 burnedShares
    ) internal override returns (uint256 mintedShares) {
        mintedShares = super._withdraw(claimer, withdrawnAssets, burnedShares);

        emit Transfer(msg.sender, address(0), burnedShares);
    }

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(address from, address to, uint256 value) internal override {
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

    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        (InitParamsTokenized memory params) = abi.decode(data, (InitParamsTokenized));

        super._initialize(initialVersion, owner_, abi.encode(params.baseParams));

        __ERC20_init(params.name, params.symbol);
    }
}
