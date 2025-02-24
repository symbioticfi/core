// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratableEntity} from "../../common/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {IVault} from "../../../interfaces/vault/v1.1/IVault.sol";

import {Checkpoints} from "../../libraries/Checkpoints.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, Proxy {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /**
     * @notice The minimum period of time that must be available to exit in case of epoch increase after migration.
     */
    uint256 public constant MIN_EXIT_WINDOW = 7 days;

    address private immutable IMPLEMENTATION;

    constructor(address vaultFactory, address implementation) MigratableEntity(vaultFactory) {
        IMPLEMENTATION = implementation;
    }

    /**
     * @inheritdoc Proxy
     */
    function _implementation() internal view override returns (address) {
        return IMPLEMENTATION;
    }

    function _processMigrateParams(
        IVault.MigrateParams memory params
    ) internal {
        if (params.epochDurationSetEpochsDelay < 3) {
            revert IVault.InvalidEpochDurationSetEpochsDelay();
        }

        if (params.flashFeeReceiver == address(0) && params.flashFeeRate != 0) {
            revert IVault.InvalidFlashParams();
        }

        epochDurationSetEpochsDelayInternal = params.epochDurationSetEpochsDelay;

        flashFeeRate = params.flashFeeRate;
        flashFeeReceiver = params.flashFeeReceiver;

        if (params.epochDurationSetRoleHolder != address(0)) {
            _grantRole(EPOCH_DURATION_SET_ROLE, params.epochDurationSetRoleHolder);
        }
        if (params.flashFeeRateSetRoleHolder != address(0)) {
            _grantRole(FLASH_FEE_RATE_SET_ROLE, params.flashFeeRateSetRoleHolder);
        }
        if (params.flashFeeReceiverSetRoleHolder != address(0)) {
            _grantRole(FLASH_FEE_RECEIVER_SET_ROLE, params.flashFeeReceiverSetRoleHolder);
        }
    }

    function _initialize(uint64, address, bytes memory data) internal virtual override {
        (IVault.InitParams memory params) = abi.decode(data, (IVault.InitParams));

        if (params.collateral == address(0)) {
            revert IVault.InvalidCollateral();
        }

        if (params.epochDuration == 0) {
            revert IVault.InvalidEpochDuration();
        }

        if (params.defaultAdminRoleHolder == address(0)) {
            if (params.depositWhitelistSetRoleHolder == address(0)) {
                if (params.depositWhitelist) {
                    if (params.depositorWhitelistRoleHolder == address(0)) {
                        revert IVault.MissingRoles();
                    }
                } else if (params.depositorWhitelistRoleHolder != address(0)) {
                    revert IVault.MissingRoles();
                }
            }

            if (params.isDepositLimitSetRoleHolder == address(0)) {
                if (params.isDepositLimit) {
                    if (params.depositLimit == 0 && params.depositLimitSetRoleHolder == address(0)) {
                        revert IVault.MissingRoles();
                    }
                } else if (params.depositLimit != 0 || params.depositLimitSetRoleHolder != address(0)) {
                    revert IVault.MissingRoles();
                }
            }
        }

        if (!params.depositWhitelist && params.depositorsWhitelisted.length > 0) {
            revert IVault.NoDepositWhitelist();
        }

        for (uint256 i; i < params.depositorsWhitelisted.length; ++i) {
            if (params.depositorsWhitelisted[i] == address(0)) {
                revert IVault.InvalidAccount();
            }

            if (isDepositorWhitelisted[params.depositorsWhitelisted[i]]) {
                revert IVault.AlreadySet();
            }

            isDepositorWhitelisted[params.depositorsWhitelisted[i]] = true;
        }

        if (params.defaultAdminRoleHolder == address(0)) {
            if (params.flashFeeReceiver == address(0)) {
                if (params.flashFeeRateSetRoleHolder == address(0)) {
                    if (params.flashFeeReceiverSetRoleHolder != address(0) && params.flashFeeRate == 0) {
                        revert IVault.InvalidFlashParams();
                    }
                } else if (params.flashFeeReceiverSetRoleHolder == address(0)) {
                    revert IVault.InvalidFlashParams();
                }
            } else if (params.flashFeeRateSetRoleHolder == address(0) && params.flashFeeRate == 0) {
                revert IVault.InvalidFlashParams();
            }
        }

        _processMigrateParams(
            IVault.MigrateParams({
                epochDurationSetEpochsDelay: params.epochDurationSetEpochsDelay,
                flashFeeRate: params.flashFeeRate,
                flashFeeReceiver: params.flashFeeReceiver,
                epochDurationSetRoleHolder: params.epochDurationSetRoleHolder,
                flashFeeRateSetRoleHolder: params.flashFeeRateSetRoleHolder,
                flashFeeReceiverSetRoleHolder: params.flashFeeReceiverSetRoleHolder
            })
        );

        collateral = params.collateral;

        burner = params.burner;

        epochDurationInitInternal = Time.timestamp();
        epochDurationInternal = params.epochDuration;

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

    function _migrate(uint64, /* oldVersion */ uint64, /* newVersion */ bytes memory data) internal virtual override {
        (IVault.MigrateParams memory params) = abi.decode(data, (IVault.MigrateParams));

        _processMigrateParams(params);

        if ((params.epochDurationSetEpochsDelay - 2) * epochDurationInternal < MIN_EXIT_WINDOW) {
            revert IVault.InsufficientExitWindow();
        }
    }
}
