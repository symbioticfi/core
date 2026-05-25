// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {Entity} from "../../src/contracts/common/Entity.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {ProtocolFeeRegistry} from "../../src/contracts/ProtocolFeeRegistry.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IProtocolFeeRegistry} from "../../src/interfaces/IProtocolFeeRegistry.sol";
import {
    IVaultV2,
    VAULT_V2_VERSION,
    MAX_MANAGEMENT_FEE,
    MAX_PERFORMANCE_FEE,
    PERFORMANCE_FEE_ROLE,
    MANAGEMENT_FEE_ROLE
} from "../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../mocks/Token.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract VaultV2MigratableEntityMock is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}
}

contract VaultV2EntityMock is Entity {
    constructor(address factory, uint64 type_) Entity(factory, type_) {}
}

contract VaultV2SixDecimalToken is Token {
    constructor() Token("Six Decimal Collateral") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract VaultV2FeeApiTest is Test {
    function test_vaultAndProtocolFeeExposeFeeApi() public pure {
        assertEq(IVaultV2.lastProtocolFee.selector, bytes4(keccak256("lastProtocolFee()")));
        assertEq(IVaultV2.lastProtocolFeeReceiver.selector, bytes4(keccak256("lastProtocolFeeReceiver()")));
        assertEq(IVaultV2.managementFee.selector, bytes4(keccak256("managementFee()")));
        assertEq(IVaultV2.managementFeeReceiver.selector, bytes4(keccak256("managementFeeReceiver()")));
        assertEq(IVaultV2.performanceFee.selector, bytes4(keccak256("performanceFee()")));
        assertEq(IVaultV2.performanceFeeReceiver.selector, bytes4(keccak256("performanceFeeReceiver()")));
        assertEq(IVaultV2.setManagementFee.selector, bytes4(keccak256("setManagementFee(uint96,address)")));
        assertEq(IVaultV2.setPerformanceFee.selector, bytes4(keccak256("setPerformanceFee(uint96,address)")));
        assertEq(IVaultV2.setSlasher.selector, bytes4(keccak256("setSlasher(address)")));
        assertEq(IVaultV2.getAccrueInterest.selector, bytes4(keccak256("getAccrueInterest()")));
        assertEq(IVaultV2.virtualShares.selector, bytes4(keccak256("virtualShares()")));
        assertEq(IVaultV2.freeAssets.selector, bytes4(keccak256("freeAssets()")));
        assertEq(IVaultV2.withdrawable.selector, bytes4(keccak256("withdrawable()")));
        assertEq(IProtocolFeeRegistry.getFee.selector, bytes4(keccak256("getFee(address)")));
        assertEq(IProtocolFeeRegistry.getReceiver.selector, bytes4(keccak256("getReceiver(address)")));
        assertEq(
            IERC20Permit.permit.selector,
            bytes4(keccak256("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))
        );
        assertEq(IERC20Permit.nonces.selector, bytes4(keccak256("nonces(address)")));
        assertEq(IERC20Permit.DOMAIN_SEPARATOR.selector, bytes4(keccak256("DOMAIN_SEPARATOR()")));
    }
}

contract VaultV2BehaviorTest is Test {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    Token internal collateral;
    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    AdapterRegistry internal adapterRegistry;
    ProtocolFeeRegistry internal protocolFee;

    address internal protocolFeeReceiver = address(0xFEE);
    address internal nextProtocolFeeReceiver = address(0xFEE2);
    address internal performanceFeeReceiver = address(0xF00D);
    address internal managementFeeReceiver = address(0xCAFE);

    function setUp() public {
        collateral = new Token("Collateral");
        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        adapterRegistry = new AdapterRegistry(address(this));
        protocolFee = new ProtocolFeeRegistry(address(this));
        protocolFee.setGlobalReceiver(protocolFeeReceiver);

        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(0x1),
                    address(vaultFactory),
                    address(0x2),
                    address(adapterRegistry),
                    address(delegatorFactory),
                    address(protocolFee),
                    address(new WithdrawalQueue())
                )
            )
        );

        for (uint64 i; i < UNIVERSAL_DELEGATOR_TYPE; ++i) {
            delegatorFactory.whitelist(address(new VaultV2EntityMock(address(delegatorFactory), i)));
        }
        delegatorFactory.whitelist(
            address(
                new UniversalDelegator(
                    UNIVERSAL_DELEGATOR_TYPE, address(vaultFactory), address(adapterRegistry), address(delegatorFactory)
                )
            )
        );
    }

    function test_MaxDepositAndMaxMintApplyWhitelistAndLimit() public {
        VaultV2 vault = _createVault(true, true, 100);

        assertEq(vault.maxDeposit(bob), 0);
        assertEq(vault.maxMint(bob), 0);
        assertEq(vault.maxDeposit(alice), 100);
        assertEq(vault.maxMint(alice), vault.previewDeposit(100));

        IERC20(address(collateral)).transfer(address(vault), 40);

        assertEq(vault.maxDeposit(alice), 60);
        assertEq(vault.maxMint(alice), vault.previewDeposit(60));
    }

    function test_WithdrawableIncludesFreeAssets() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);

        assertEq(vault.withdrawable(), vault.freeAssets());
    }

    function test_InitializeStartsWithDefaultFeeConfig() public {
        VaultV2 vault = _createVault(false, false, 0);

        (bool success,) = address(vault).staticcall(abi.encodeWithSignature("PROTOCOL_FEE()"));
        assertFalse(success);
        assertEq(vault.lastProtocolFee(), 0);
        assertEq(vault.lastProtocolFeeReceiver(), protocolFeeReceiver);
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 0);
        assertEq(vault.managementFeeReceiver(), address(0));
        assertEq(vault.performanceFeeReceiver(), address(0));
        assertTrue(vault.hasRole(PERFORMANCE_FEE_ROLE, address(this)));
        assertTrue(vault.hasRole(MANAGEMENT_FEE_ROLE, address(this)));
        assertEq(vault.virtualShares(), 1);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.freeAssets(), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        _assertNoLegacyShareGetters(vault);
    }

    function test_InitializeStoresAssetAdjustedVirtualShares() public {
        collateral = new VaultV2SixDecimalToken();

        VaultV2 vault = _createVault(false, false, 0);

        assertEq(vault.virtualShares(), 1e12);
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.freeAssets(), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        _assertNoLegacyShareGetters(vault);
    }

    function test_SetCuratorFeesEnforcesCapsReceiversAndRoles() public {
        VaultV2 vault = _createVault(false, false, 0);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.setPerformanceFee(1, address(0));

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.setManagementFee(1, address(0));

        vm.expectRevert(IVaultV2.FeeTooHigh.selector);
        vault.setPerformanceFee(uint96(MAX_PERFORMANCE_FEE + 1), performanceFeeReceiver);

        vm.expectRevert(IVaultV2.FeeTooHigh.selector);
        vault.setManagementFee(uint96(MAX_MANAGEMENT_FEE + 1), managementFeeReceiver);

        vm.recordLogs();
        vault.setPerformanceFee(uint96(MAX_PERFORMANCE_FEE), performanceFeeReceiver);
        Vm.Log[] memory performanceFeeLogs = vm.getRecordedLogs();

        assertEq(performanceFeeLogs.length, 2);
        assertEq(performanceFeeLogs[1].topics[0], keccak256("SetPerformanceFee(uint256,address)"));
        assertEq(performanceFeeLogs[1].topics[1], bytes32(uint256(uint160(performanceFeeReceiver))));
        assertEq(abi.decode(performanceFeeLogs[1].data, (uint256)), MAX_PERFORMANCE_FEE);

        vm.recordLogs();
        vault.setManagementFee(uint96(MAX_MANAGEMENT_FEE), managementFeeReceiver);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[1].topics[0], keccak256("SetManagementFee(uint256,address)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(managementFeeReceiver))));
        assertEq(abi.decode(logs[1].data, (uint256)), MAX_MANAGEMENT_FEE);

        assertEq(vault.performanceFee(), MAX_PERFORMANCE_FEE);
        assertEq(vault.performanceFeeReceiver(), performanceFeeReceiver);
        assertEq(vault.managementFee(), MAX_MANAGEMENT_FEE);
        assertEq(vault.managementFeeReceiver(), managementFeeReceiver);

        vm.startPrank(bob);
        vm.expectRevert();
        vault.setPerformanceFee(0, address(0));
        vm.expectRevert();
        vault.setManagementFee(0, address(0));
        vm.stopPrank();
    }

    function test_TotalSupplyIncludesAccruedCuratorAndProtocolFeeSharesBeforeMinting() public {
        VaultV2 vault = _createVault(false, false, 0);
        _setCuratorFees(vault);
        protocolFee.setGlobalFee(13);
        _deposit(vault, alice, 100 ether);
        uint256 rawSupply = vault.totalSupply();

        vm.warp(block.timestamp + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        (, uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) =
            vault.getAccrueInterest();

        assertGt(protocolFeeShares + performanceFeeShares + managementFeeShares, 0);
        assertEq(vault.totalSupply(), rawSupply + protocolFeeShares + performanceFeeShares + managementFeeShares);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_AccrueInterestMintsPreviewedFeeSharesToReceiversWithoutChangingVisibleSupply() public {
        VaultV2 vault = _createVault(false, false, 0);
        _setCuratorFees(vault);
        protocolFee.setGlobalFee(13);
        _deposit(vault, alice, 100 ether);

        vm.warp(block.timestamp + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        uint256 previewSupply = vault.totalSupply();
        (, uint256 previewPerformanceFeeShares, uint256 previewManagementFeeShares, uint256 previewProtocolFeeShares) =
            vault.getAccrueInterest();

        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares) = vault.accrueInterest();

        assertEq(protocolFeeShares, previewProtocolFeeShares);
        assertEq(performanceFeeShares, previewPerformanceFeeShares);
        assertEq(managementFeeShares, previewManagementFeeShares);
        assertEq(vault.balanceOf(protocolFeeReceiver), protocolFeeShares);
        assertEq(vault.balanceOf(performanceFeeReceiver), performanceFeeShares);
        assertEq(vault.balanceOf(managementFeeReceiver), managementFeeShares);
        assertEq(vault.totalSupply(), previewSupply);
        assertEq(vault.lastUpdate(), block.timestamp);
    }

    function test_AccrueInterestUsesCachedProtocolFeeAndReceiverThenRefreshes() public {
        VaultV2 vault = _createVault(false, false, 0);
        protocolFee.setGlobalFee(13);
        vault.accrueInterest();

        assertEq(vault.lastProtocolFee(), 13);
        assertEq(vault.lastProtocolFeeReceiver(), protocolFeeReceiver);

        _deposit(vault, alice, 100 ether);
        protocolFee.setGlobalFee(0);
        protocolFee.setGlobalReceiver(nextProtocolFeeReceiver);

        vm.warp(block.timestamp + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        (,,, uint256 previewProtocolFeeShares) = vault.getAccrueInterest();
        assertGt(previewProtocolFeeShares, 0);

        (,, uint256 protocolFeeShares) = vault.accrueInterest();

        assertEq(protocolFeeShares, previewProtocolFeeShares);
        assertEq(vault.balanceOf(protocolFeeReceiver), protocolFeeShares);
        assertEq(vault.balanceOf(nextProtocolFeeReceiver), 0);
        assertEq(vault.lastProtocolFee(), 0);
        assertEq(vault.lastProtocolFeeReceiver(), nextProtocolFeeReceiver);
    }

    function test_VaultConfiguratorCanCreateVaultV2WithoutSlasher() public {
        bytes memory vaultParams = _vaultParams(false, false, 0);
        bytes memory delegatorParams = _delegatorParams();

        VaultConfigurator configurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(0x2));

        (address vault, address delegator, address slasher) = configurator.create(
            IVaultConfigurator.InitParams({
                version: VAULT_V2_VERSION,
                owner: address(this),
                vaultParams: vaultParams,
                delegatorIndex: UNIVERSAL_DELEGATOR_TYPE,
                delegatorParams: delegatorParams,
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        assertEq(VaultV2(vault).delegator(), delegator);
        assertEq(slasher, address(0));
    }

    function _createVault(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        returns (VaultV2 vault)
    {
        bytes memory data = _vaultParams(depositWhitelist, isDepositLimit, depositLimit);

        address vaultAddress = vaultFactory.create(VAULT_V2_VERSION, address(this), data);

        address delegator =
            delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(vaultAddress, _delegatorParams()));

        vault = VaultV2(vaultAddress);
        vault.setDelegator(delegator);
    }

    function _vaultParams(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(
            IVaultV2.InitParams({
                name: "Vault",
                symbol: "vTKN",
                asset: address(collateral),
                depositWhitelist: depositWhitelist,
                depositorToWhitelist: alice,
                isDepositLimit: isDepositLimit,
                depositLimit: depositLimit,
                defaultAdminRoleHolder: address(this),
                depositWhitelistSetRoleHolder: address(this),
                depositorWhitelistRoleHolder: address(this),
                isDepositLimitSetRoleHolder: address(this),
                depositLimitSetRoleHolder: address(this),
                performanceFeeRoleHolder: address(this),
                managementFeeRoleHolder: address(this)
            })
        );
    }

    function _delegatorParams() internal view returns (bytes memory) {
        return abi.encode(
            IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: address(this),
                addAdapterRoleHolder: address(this),
                removeAdapterRoleHolder: address(this),
                setAdapterLimitsRoleHolder: address(this),
                setAutoAllocateAdaptersRoleHolder: address(this),
                swapAdaptersRoleHolder: address(this),
                allocateRoleHolder: address(this),
                deallocateRoleHolder: address(this),
                adapters: new address[](0)
            })
        );
    }

    function _assertNoLegacyShareGetters(VaultV2 vault) internal view {
        _assertMissingGetter(address(vault), abi.encodeWithSignature("activeShares()"));
        _assertMissingGetter(
            address(vault), abi.encodeWithSignature("activeSharesAt(uint48,bytes)", uint48(block.timestamp), "")
        );
        _assertMissingGetter(address(vault), abi.encodeWithSignature("activeSharesOf(address)", alice));
        _assertMissingGetter(
            address(vault),
            abi.encodeWithSignature("activeSharesOfAt(address,uint48,bytes)", alice, uint48(block.timestamp), "")
        );
    }

    function _assertMissingGetter(address target, bytes memory data) internal view {
        (bool success,) = target.staticcall(data);
        assertFalse(success);
    }

    function _setCuratorFees(VaultV2 vault) internal {
        vault.setPerformanceFee(11, performanceFeeReceiver);
        vault.setManagementFee(7, managementFeeReceiver);
    }

    function _deposit(VaultV2 vault, address account, uint256 assets) internal {
        collateral.transfer(account, assets);

        vm.startPrank(account);
        collateral.approve(address(vault), assets);
        vault.deposit(assets, account);
        vm.stopPrank();
    }
}
