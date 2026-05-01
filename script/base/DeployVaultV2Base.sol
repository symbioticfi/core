// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {
    CREATE_SLOT_ROLE,
    IUniversalDelegator,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE,
    DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    IVaultV2,
    SET_ADAPTER_LIMIT_ROLE,
    SWAP_ADAPTERS_ROLE,
    VAULT_V2_VERSION
} from "../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";

contract DeployVaultV2Base is Script {
    struct DeployVaultV2Params {
        address owner;
        IVaultV2.InitParams vaultParams;
        IUniversalDelegator.InitParams delegatorParams;
        bool withSlasher;
        IUniversalSlasher.InitParams slasherParams;
    }

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function runBase(DeployVaultV2Params memory params) public returns (address, address, address) {
        _startBroadcast();

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(_core().vaultConfigurator)
            .create(
                IVaultConfigurator.InitParams({
                    version: VAULT_V2_VERSION,
                    owner: params.owner,
                    vaultParams: _getVaultParamsEncoded(params),
                    delegatorIndex: UNIVERSAL_DELEGATOR_TYPE,
                    delegatorParams: abi.encode(params.delegatorParams),
                    withSlasher: params.withSlasher,
                    slasherIndex: UNIVERSAL_SLASHER_TYPE,
                    slasherParams: abi.encode(params.slasherParams)
                })
            );

        Logs.log(
            string.concat(
                "Deployed VaultV2",
                "\n    vault:",
                vm.toString(vault_),
                "\n    delegator:",
                vm.toString(delegator_),
                "\n    slasher:",
                vm.toString(slasher_)
            )
        );

        _validateDeployment(vault_, delegator_, slasher_, params);

        _stopBroadcast();
        return (vault_, delegator_, slasher_);
    }

    function _getVaultParamsEncoded(DeployVaultV2Params memory params) internal pure returns (bytes memory) {
        return abi.encode(params.vaultParams);
    }

    function _validateDeployment(address vault, address delegator, address slasher, DeployVaultV2Params memory params)
        internal
        view
    {
        (,, address deployer) = vm.readCallers();

        assert(IVaultV2(vault).version() == VAULT_V2_VERSION);
        assert(VaultV2(vault).owner() == params.owner);
        assert(VaultV2(vault).delegator() == delegator);
        assert(VaultV2(vault).slasher() == slasher);

        _validateVaultParams(vault, params.vaultParams);
        _validateVaultRoles(vault, deployer, params.vaultParams);
        _validateDelegator(delegator, vault, deployer, params.delegatorParams);
        _validateSlasher(slasher, vault, params.withSlasher, params.slasherParams);
    }

    function _validateVaultParams(address vault, IVaultV2.InitParams memory params) internal view {
        assert(VaultV2(vault).collateral() == params.collateral);
        assert(VaultV2(vault).burner() == params.burner);
        assert(VaultV2(vault).epochDuration() == params.epochDuration);
        assert(VaultV2(vault).depositWhitelist() == params.depositWhitelist);
        assert(VaultV2(vault).isDepositLimit() == params.isDepositLimit);
        assert(VaultV2(vault).depositLimit() == params.depositLimit);
        assert(VaultV2(vault).isDepositorWhitelisted(params.depositorToWhitelist) == true);
    }

    function _validateVaultRoles(address vault, address deployer, IVaultV2.InitParams memory params) internal view {
        _assertVaultRole(vault, DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _assertVaultRole(vault, DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        _assertVaultRole(vault, DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        _assertVaultRole(vault, IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        _assertVaultRole(vault, DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        _assertVaultRole(vault, SET_ADAPTER_LIMIT_ROLE, params.setAdapterLimitRoleHolder);
        _assertVaultRole(vault, SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _assertVaultRole(vault, ALLOCATE_ADAPTER_ROLE, params.allocateAdapterRoleHolder);
        _assertVaultRole(vault, DEALLOCATE_ADAPTER_ROLE, params.deallocateAdapterRoleHolder);

        if (deployer != params.defaultAdminRoleHolder) {
            assert(VaultV2(vault).hasRole(DEFAULT_ADMIN_ROLE, deployer) == false);
        }
        if (deployer != params.depositWhitelistSetRoleHolder) {
            assert(VaultV2(vault).hasRole(DEPOSIT_WHITELIST_SET_ROLE, deployer) == false);
        }
        if (deployer != params.depositorWhitelistRoleHolder) {
            assert(VaultV2(vault).hasRole(DEPOSITOR_WHITELIST_ROLE, deployer) == false);
        }
        if (deployer != params.isDepositLimitSetRoleHolder) {
            assert(VaultV2(vault).hasRole(IS_DEPOSIT_LIMIT_SET_ROLE, deployer) == false);
        }
        if (deployer != params.depositLimitSetRoleHolder) {
            assert(VaultV2(vault).hasRole(DEPOSIT_LIMIT_SET_ROLE, deployer) == false);
        }
        if (deployer != params.setAdapterLimitRoleHolder) {
            assert(VaultV2(vault).hasRole(SET_ADAPTER_LIMIT_ROLE, deployer) == false);
        }
        if (deployer != params.swapAdaptersRoleHolder) {
            assert(VaultV2(vault).hasRole(SWAP_ADAPTERS_ROLE, deployer) == false);
        }
        if (deployer != params.allocateAdapterRoleHolder) {
            assert(VaultV2(vault).hasRole(ALLOCATE_ADAPTER_ROLE, deployer) == false);
        }
        if (deployer != params.deallocateAdapterRoleHolder) {
            assert(VaultV2(vault).hasRole(DEALLOCATE_ADAPTER_ROLE, deployer) == false);
        }
    }

    function _validateDelegator(
        address delegator,
        address vault,
        address deployer,
        IUniversalDelegator.InitParams memory params
    ) internal view {
        assert(UniversalDelegator(delegator).TYPE() == UNIVERSAL_DELEGATOR_TYPE);
        assert(UniversalDelegator(delegator).vault() == vault);

        _assertDelegatorRole(delegator, DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _assertDelegatorRole(delegator, CREATE_SLOT_ROLE, params.createSlotRoleHolder);
        _assertDelegatorRole(delegator, SET_SIZE_ROLE, params.setSizeRoleHolder);
        _assertDelegatorRole(delegator, SWAP_SLOTS_ROLE, params.swapSlotsRoleHolder);
        _assertDelegatorRole(delegator, REMOVE_SLOT_ROLE, params.removeSlotRoleHolder);

        if (deployer != params.defaultAdminRoleHolder) {
            assert(UniversalDelegator(delegator).hasRole(DEFAULT_ADMIN_ROLE, deployer) == false);
        }
        if (deployer != params.createSlotRoleHolder) {
            assert(UniversalDelegator(delegator).hasRole(CREATE_SLOT_ROLE, deployer) == false);
        }
        if (deployer != params.setSizeRoleHolder) {
            assert(UniversalDelegator(delegator).hasRole(SET_SIZE_ROLE, deployer) == false);
        }
        if (deployer != params.swapSlotsRoleHolder) {
            assert(UniversalDelegator(delegator).hasRole(SWAP_SLOTS_ROLE, deployer) == false);
        }
        if (deployer != params.removeSlotRoleHolder) {
            assert(UniversalDelegator(delegator).hasRole(REMOVE_SLOT_ROLE, deployer) == false);
        }
    }

    function _validateSlasher(
        address slasher,
        address vault,
        bool withSlasher,
        IUniversalSlasher.InitParams memory params
    ) internal view {
        if (!withSlasher) {
            assert(slasher == address(0));
            return;
        }

        assert(slasher != address(0));
        assert(UniversalSlasher(slasher).TYPE() == UNIVERSAL_SLASHER_TYPE);
        assert(UniversalSlasher(slasher).vault() == vault);
        assert(UniversalSlasher(slasher).isBurnerHook() == params.isBurnerHook);
        assert(UniversalSlasher(slasher).vetoDuration() == params.vetoDuration);
        assert(UniversalSlasher(slasher).resolverSetDelay() == params.resolverSetDelay);
    }

    function _assertVaultRole(address vault, bytes32 role, address holder) internal view {
        if (holder != address(0)) {
            assert(VaultV2(vault).hasRole(role, holder) == true);
        }
    }

    function _assertDelegatorRole(address delegator, bytes32 role, address holder) internal view {
        if (holder != address(0)) {
            assert(UniversalDelegator(delegator).hasRole(role, holder) == true);
        }
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }

    function _core() internal view virtual returns (SymbioticCoreConstants.Core memory) {
        return SymbioticCoreConstants.core();
    }
}
