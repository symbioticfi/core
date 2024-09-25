// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Vault} from "./Vault.sol";

import {IVaultTokenized} from "../../interfaces/vault/IVaultTokenized.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract VaultTokenized is Vault, ERC20Upgradeable, IVaultTokenized {
    using Checkpoints for Checkpoints.Trace256;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory
    ) Vault(delegatorFactory, slasherFactory, vaultFactory) {}

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

    function _initialize(uint64 initialVersion, address owner_, bytes calldata data) internal override {
        (InitParamsTokenized memory params) = abi.decode(data, (InitParamsTokenized));

        __ERC20_init(string.concat("Symbiotic_", params.name), string.concat("SYMB_", params.symbol));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.defaultAdminRoleHolder == address(0)) {
            if (params.depositWhitelistSetRoleHolder == address(0)) {
                if (params.depositWhitelist) {
                    if (params.depositorWhitelistRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositorWhitelistRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }

            if (params.isDepositLimitSetRoleHolder == address(0)) {
                if (params.isDepositLimit) {
                    if (params.depositLimit == 0 && params.depositLimitSetRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositLimit != 0 || params.depositLimitSetRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }
        }

        collateral = params.collateral;

        burner = params.burner;

        epochDurationInit = Time.timestamp();
        epochDuration = params.epochDuration;

        depositWhitelist = params.depositWhitelist;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        if (params.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        }
        if (params.depositWhitelistSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        }
        if (params.depositorWhitelistRoleHolder != address(0)) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        }
        if (params.isDepositLimitSetRoleHolder != address(0)) {
            _grantRole(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        }
        if (params.depositLimitSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        }
    }
}
