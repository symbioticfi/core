// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreInit.sol";

import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SymbioticCoreMigrationTest is SymbioticCoreInit {
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";
    string internal constant LEGACY_NAME = "Legacy";
    string internal constant LEGACY_SYMBOL = "LEG";

    function test_MigrateVaultToVaultV2_Integration() public {
        address owner = address(this);
        address collateral = _getToken_SymbioticCore();
        uint48 epochDuration = 7 days;

        bytes memory vaultParams = abi.encode(
            IVault.InitParams({
                collateral: collateral,
                burner: address(0xdEaD),
                epochDuration: epochDuration,
                depositWhitelist: false,
                isDepositLimit: false,
                depositLimit: 0,
                defaultAdminRoleHolder: owner,
                depositWhitelistSetRoleHolder: owner,
                depositorWhitelistRoleHolder: owner,
                isDepositLimitSetRoleHolder: owner,
                depositLimitSetRoleHolder: owner
            })
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;

        bytes memory delegatorParams = abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: IBaseDelegator.BaseParams({
                    defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: owner
                }),
                networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
            })
        );

        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: vetoDuration,
                resolverSetEpochsDelay: 3
            })
        );

        (address vault,, address slasher) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: owner,
            version: 1,
            owner: owner,
            vaultParams: vaultParams,
            delegatorIndex: 0,
            delegatorParams: delegatorParams,
            withSlasher: true,
            slasherIndex: 1,
            slasherParams: slasherParams
        });

        uint256 expectedSlashRequestsLength = IVetoSlasher(slasher).slashRequestsLength();

        bytes memory migrateData = abi.encode(_buildMigrateParams(owner, epochDuration, VAULT_NAME, VAULT_SYMBOL));
        symbioticCore.vaultFactory.migrate(vault, symbioticCore.vaultFactory.lastVersion(), migrateData);

        _assertMigrationState(vault, expectedSlashRequestsLength);

        assertEq(IERC20Metadata(vault).name(), VAULT_NAME);
        assertEq(IERC20Metadata(vault).symbol(), VAULT_SYMBOL);
    }

    function test_MigrateTokenizedToVaultV2_Integration() public {
        address owner = address(this);
        address collateral = _getToken_SymbioticCore();
        uint48 epochDuration = 7 days;

        bytes memory vaultParams = abi.encode(
            IVaultTokenized.InitParamsTokenized({
                baseParams: IVault.InitParams({
                    collateral: collateral,
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    depositWhitelist: false,
                    isDepositLimit: false,
                    depositLimit: 0,
                    defaultAdminRoleHolder: owner,
                    depositWhitelistSetRoleHolder: owner,
                    depositorWhitelistRoleHolder: owner,
                    isDepositLimitSetRoleHolder: owner,
                    depositLimitSetRoleHolder: owner
                }),
                name: LEGACY_NAME,
                symbol: LEGACY_SYMBOL
            })
        );

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;

        bytes memory delegatorParams = abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: IBaseDelegator.BaseParams({
                    defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: owner
                }),
                networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
            })
        );

        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        bytes memory slasherParams = abi.encode(
            IVetoSlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                vetoDuration: vetoDuration,
                resolverSetEpochsDelay: 3
            })
        );

        (address vault,, address slasher) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: owner,
            version: 2,
            owner: owner,
            vaultParams: vaultParams,
            delegatorIndex: 0,
            delegatorParams: delegatorParams,
            withSlasher: true,
            slasherIndex: 1,
            slasherParams: slasherParams
        });

        uint256 expectedSlashRequestsLength = IVetoSlasher(slasher).slashRequestsLength();

        assertEq(IERC20Metadata(vault).name(), LEGACY_NAME);
        assertEq(IERC20Metadata(vault).symbol(), LEGACY_SYMBOL);

        bytes memory migrateData = abi.encode(_buildMigrateParams(owner, epochDuration, VAULT_NAME, VAULT_SYMBOL));
        symbioticCore.vaultFactory.migrate(vault, symbioticCore.vaultFactory.lastVersion(), migrateData);

        _assertMigrationState(vault, expectedSlashRequestsLength);

        assertEq(IERC20Metadata(vault).name(), LEGACY_NAME);
        assertEq(IERC20Metadata(vault).symbol(), LEGACY_SYMBOL);
    }

    function _buildMigrateParams(address admin, uint48 epochDuration, string memory name_, string memory symbol_)
        internal
        view
        returns (IVaultV2.MigrateParams memory)
    {
        uint48 vetoDuration = epochDuration > 1 ? 1 : 0;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            baseParams: IBaseDelegator.BaseParams({
                defaultAdminRoleHolder: admin, hook: address(0), hookSetRoleHolder: admin
            }),
            createSlotRoleHolder: admin,
            setIsSharedRoleHolder: admin,
            setSizeRoleHolder: admin,
            setShareRoleHolder: admin,
            swapSlotsRoleHolder: admin,
            assignNetworkRoleHolder: admin,
            unassignNetworkRoleHolder: admin,
            assignOperatorRoleHolder: admin,
            unassignOperatorRoleHolder: admin
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
            vetoDuration: vetoDuration,
            resolverSetEpochsDelay: 3
        });
        return IVaultV2.MigrateParams({
            name: name_,
            symbol: symbol_,
            delegatorParams: abi.encode(delegatorParams),
            slasherParams: abi.encode(slasherParams)
        });
    }

    function _assertMigrationState(address vault, uint256 expectedSlashRequestsLength) internal view {
        IVaultV2 vaultV2 = IVaultV2(vault);
        assertEq(IMigratableEntity(vault).version(), symbioticCore.vaultFactory.lastVersion());
        assertEq(IEntity(vaultV2.delegator()).TYPE(), symbioticCore.delegatorFactory.totalTypes() - 1);
        assertEq(IEntity(vaultV2.slasher()).TYPE(), symbioticCore.slasherFactory.totalTypes() - 1);
        assertEq(IUniversalDelegator(vaultV2.delegator()).getSlot(0).pendingFreeCumulative, type(uint256).max);
        assertEq(IUniversalSlasher(vaultV2.slasher()).slashRequestsLength(), expectedSlashRequestsLength);
    }
}
