// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {UniversalDelegatorFactory} from "../../src/contracts/UniversalDelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {ProtocolFeeRegistry} from "../../src/contracts/ProtocolFeeRegistry.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../src/contracts/WithdrawalQueueFactory.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
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
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract VaultV2MigratableEntityMock is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}
}

contract VaultV2SixDecimalToken is Token {
    constructor() Token("Six Decimal Collateral") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract VaultV2ZeroRevertToken is Token {
    error ZeroTransfer();

    constructor() Token("Zero Revert Collateral") {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (amount == 0) {
            revert ZeroTransfer();
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (amount == 0) {
            revert ZeroTransfer();
        }
        return super.transferFrom(from, to, amount);
    }
}

interface OwnableView {
    function owner() external view returns (address);
}

contract VaultV2FeeApiTest is Test {
    function test_vaultAndProtocolFeeExposeFeeApi() public pure {
        uint96 maxManagementFee = MAX_MANAGEMENT_FEE;
        uint96 maxPerformanceFee = MAX_PERFORMANCE_FEE;

        assertEq(maxManagementFee, 5e16 / uint256(365 days));
        assertEq(maxPerformanceFee, 2e17);

        assertEq(IVaultV2.lastProtocolManagementFee.selector, bytes4(keccak256("lastProtocolManagementFee()")));
        assertEq(IVaultV2.lastProtocolPerformanceFee.selector, bytes4(keccak256("lastProtocolPerformanceFee()")));
        assertEq(IVaultV2.lastProtocolFeeReceiver.selector, bytes4(keccak256("lastProtocolFeeReceiver()")));
        assertEq(IVaultV2.managementFee.selector, bytes4(keccak256("managementFee()")));
        assertEq(IVaultV2.managementFeeReceiver.selector, bytes4(keccak256("managementFeeReceiver()")));
        assertEq(IVaultV2.performanceFee.selector, bytes4(keccak256("performanceFee()")));
        assertEq(IVaultV2.performanceFeeReceiver.selector, bytes4(keccak256("performanceFeeReceiver()")));
        assertEq(IVaultV2.setManagementFee.selector, bytes4(keccak256("setManagementFee(uint96,address)")));
        assertEq(IVaultV2.setPerformanceFee.selector, bytes4(keccak256("setPerformanceFee(uint96,address)")));
        assertEq(IVaultV2.getAccrueInterest.selector, bytes4(keccak256("getAccrueInterest()")));
        assertEq(IVaultV2.freeAssets.selector, bytes4(keccak256("freeAssets()")));
        assertEq(IVaultV2.withdrawable.selector, bytes4(keccak256("withdrawable()")));
        assertEq(IVaultV2.totalSupplyAt.selector, bytes4(keccak256("totalSupplyAt(uint48)")));
        assertEq(IVaultV2.balanceOfAt.selector, bytes4(keccak256("balanceOfAt(address,uint48)")));
        assertEq(IProtocolFeeRegistry.getFee.selector, bytes4(keccak256("getFee(address)")));
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
    WithdrawalQueueFactory internal withdrawalQueueFactory;
    UniversalDelegatorFactory internal delegatorFactory;
    AdapterRegistry internal adapterRegistry;
    ProtocolFeeRegistry internal protocolFee;

    address internal protocolFeeReceiver = address(0xFEE);
    address internal nextProtocolFeeReceiver = address(0xFEE2);
    address internal performanceFeeReceiver = address(0xF00D);
    address internal managementFeeReceiver = address(0xCAFE);

    function setUp() public {
        collateral = new Token("Collateral");
        vaultFactory = new VaultFactory(address(this));
        withdrawalQueueFactory = new WithdrawalQueueFactory(address(this));
        delegatorFactory = new UniversalDelegatorFactory(address(this));
        adapterRegistry = new AdapterRegistry(address(this));
        protocolFee = new ProtocolFeeRegistry(address(this));
        protocolFee.setGlobalReceiver(protocolFeeReceiver);

        withdrawalQueueFactory.whitelist(address(new WithdrawalQueue(address(withdrawalQueueFactory))));

        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(vaultFactory),
                    address(delegatorFactory),
                    address(protocolFee),
                    address(withdrawalQueueFactory)
                )
            )
        );

        delegatorFactory.whitelist(address(new UniversalDelegator(address(adapterRegistry), address(delegatorFactory))));
    }

    function test_MaxDepositAndMaxMintApplyWhitelistAndLimit() public {
        VaultV2 vault = _createVault(true, true, 100);

        vm.startPrank(bob);
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        vm.stopPrank();

        vm.startPrank(alice);
        assertEq(vault.maxDeposit(bob), 100);
        assertEq(vault.maxMint(bob), vault.previewDeposit(100));
        vm.stopPrank();

        IERC20(address(collateral)).transfer(address(vault), 40);

        vm.startPrank(alice);
        assertEq(vault.maxDeposit(bob), 60);
        assertEq(vault.maxMint(bob), vault.previewDeposit(60));
        vm.stopPrank();
    }

    function test_WithdrawableIncludesFreeAssets() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);

        assertEq(vault.withdrawable(), vault.freeAssets());
    }

    function test_RedeemableUsesFloorRoundedShares() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 2);
        collateral.transfer(address(vault), 1);

        assertEq(vault.withdrawable(), 3);
        assertEq(vault.previewWithdraw(vault.withdrawable()), 3);
        assertEq(vault.redeemable(), 2);
    }

    function test_InitializeStartsWithDefaultFeeConfig() public {
        VaultV2 vault = _createVault(false, false, 0);

        (bool success,) = address(vault).staticcall(abi.encodeWithSignature("PROTOCOL_FEE()"));
        assertFalse(success);
        assertEq(vault.lastProtocolManagementFee(), 0);
        assertEq(vault.lastProtocolPerformanceFee(), 0);
        assertEq(vault.lastProtocolFeeReceiver(), protocolFeeReceiver);
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 0);
        assertEq(vault.managementFeeReceiver(), address(0));
        assertEq(vault.performanceFeeReceiver(), address(0));
        assertTrue(vault.hasRole(PERFORMANCE_FEE_ROLE, address(this)));
        assertTrue(vault.hasRole(MANAGEMENT_FEE_ROLE, address(this)));
        assertEq(vault.previewDeposit(1), 1);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.freeAssets(), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        _assertEmptyShareCheckpoints(vault);
    }

    function test_InitializeCreatesWithdrawalQueueThroughFactoryOwnedByVault() public {
        address initOwner = address(0x1234);
        address vaultAddress = vaultFactory.create(VAULT_V2_VERSION, initOwner, _vaultParams(false, false, 0));
        address queue = VaultV2(vaultAddress).withdrawalQueue();

        assertTrue(withdrawalQueueFactory.isEntity(queue));
        assertEq(IMigratableEntity(queue).FACTORY(), address(withdrawalQueueFactory));
        assertEq(IMigratableEntity(queue).version(), 1);
        assertEq(WithdrawalQueue(queue).vault(), vaultAddress);
        assertEq(OwnableView(queue).owner(), vaultAddress);
    }

    function test_InitializeUsesAssetAdjustedVirtualShareOffset() public {
        collateral = new VaultV2SixDecimalToken();

        VaultV2 vault = _createVault(false, false, 0);

        assertEq(vault.previewDeposit(1), 1e12);
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.freeAssets(), 0);
        assertEq(collateral.balanceOf(address(vault)), 0);
        _assertEmptyShareCheckpoints(vault);
    }

    function test_InitializeRejectsInvalidAssetAndOwner() public {
        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vaultFactory.create(VAULT_V2_VERSION, address(this), _vaultParamsWithAsset(address(0), false, false, 0));

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vaultFactory.create(VAULT_V2_VERSION, address(0), _vaultParams(false, false, 0));
    }

    function test_BasicViewsAndDepositLimitControls() public {
        VaultV2 vault = _createVault(false, false, 0);

        assertTrue(vault.isInitialized());
        assertEq(vault.asset(), address(collateral));
        (bool hasCollateralGetter,) = address(vault).staticcall(abi.encodeWithSignature("collateral()"));
        assertFalse(hasCollateralGetter);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.nonces(alice), 0);

        vault.setDepositWhitelist(true);
        assertEq(vault.maxDeposit(bob), 0);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.setDepositorWhitelistStatus(address(0), true);

        vault.setDepositorWhitelistStatus(bob, true);
        vault.setIsDepositLimit(true);
        vault.setDepositLimit(100);

        vm.prank(bob);
        assertEq(vault.maxDeposit(bob), 100);
    }

    function test_ActiveShareCheckpointsTrackDepositsTransfersAndBurns() public {
        VaultV2 vault = _createVault(false, false, 0);

        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalSupplyAt(uint48(vm.getBlockTimestamp())), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOfAt(alice, uint48(vm.getBlockTimestamp())), 0);

        vm.warp(vm.getBlockTimestamp() + 1);
        uint48 depositTimestamp = uint48(vm.getBlockTimestamp());
        _deposit(vault, alice, 100 ether);

        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.totalSupplyAt(depositTimestamp), 100 ether);
        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(vault.balanceOfAt(alice, depositTimestamp), 100 ether);
        assertEq(vault.balanceOfAt(bob, depositTimestamp), 0);

        vm.warp(vm.getBlockTimestamp() + 1);
        uint48 transferTimestamp = uint48(vm.getBlockTimestamp());
        vm.prank(alice);
        vault.transfer(bob, 40 ether);

        assertEq(vault.totalSupplyAt(depositTimestamp), 100 ether);
        assertEq(vault.totalSupplyAt(transferTimestamp), 100 ether);
        assertEq(vault.balanceOfAt(alice, depositTimestamp), 100 ether);
        assertEq(vault.balanceOfAt(alice, transferTimestamp), 60 ether);
        assertEq(vault.balanceOfAt(bob, transferTimestamp), 40 ether);

        vm.warp(vm.getBlockTimestamp() + 1);
        uint48 withdrawTimestamp = uint48(vm.getBlockTimestamp());
        vm.prank(alice);
        vault.withdraw(20 ether, alice, alice);

        assertEq(vault.totalSupply(), 80 ether);
        assertEq(vault.totalSupplyAt(withdrawTimestamp), 80 ether);
        assertEq(vault.balanceOf(alice), 40 ether);
        assertEq(vault.balanceOfAt(alice, withdrawTimestamp), 40 ether);
        assertEq(vault.balanceOfAt(bob, withdrawTimestamp), 40 ether);
    }

    function test_TransferRevertsWhenBalanceIsInsufficient() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 100 ether, 101 ether)
        );
        vm.prank(alice);
        vault.transfer(bob, 101 ether);
    }

    function test_MulticallAppliesCallsAndBubblesReverts() public {
        VaultV2 vault = _createVault(false, false, 0);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IVaultV2.setIsDepositLimit, (true));
        calls[1] = abi.encodeCall(IVaultV2.setDepositLimit, (123));
        vault.multicall(calls);

        assertTrue(vault.isDepositLimit());
        assertEq(vault.depositLimit(), 123);

        calls = new bytes[](1);
        calls[0] = abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (address(0), true));

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.multicall(calls);
    }

    function test_DepositWithdrawRedeemPullAndPush() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);

        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 100 ether);

        vm.startPrank(alice);
        vault.withdraw(40 ether, bob, alice);
        uint256 remainingShares = vault.balanceOf(alice);
        vault.redeem(remainingShares, bob, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(collateral.balanceOf(bob), 100 ether);

        _deposit(vault, alice, 20 ether);

        vm.expectRevert(IVaultV2.NotDelegator.selector);
        vault.pull(1, bob);

        vm.expectRevert(IVaultV2.NotDelegator.selector);
        vault.push(1, bob);

        vm.prank(vault.delegator());
        vault.pull(10 ether, bob);

        vm.startPrank(bob);
        collateral.approve(address(vault), 10 ether);
        vm.stopPrank();

        vm.prank(vault.delegator());
        vault.push(10 ether, bob);
    }

    function test_ZeroAmountPullAndPushSkipTransferAndEvent() public {
        collateral = new VaultV2ZeroRevertToken();
        VaultV2 vault = _createVault(false, false, 0);

        vm.recordLogs();
        vm.prank(vault.delegator());
        vault.pull(0, bob);
        assertFalse(_hasTopic(vm.getRecordedLogs(), keccak256("Pull(uint256,address)")));

        vm.recordLogs();
        vm.prank(vault.delegator());
        vault.push(0, bob);
        assertFalse(_hasTopic(vm.getRecordedLogs(), keccak256("Push(uint256,address)")));
    }

    function test_PreviewMintAndWithdrawRoundUpWithFees() public {
        VaultV2 vault = _createVault(false, false, 0);
        _setCuratorFees(vault);
        _deposit(vault, alice, 100 ether);

        vm.warp(vm.getBlockTimestamp() + 30 days);
        collateral.transfer(address(vault), 100 ether);

        assertGt(vault.previewMint(1 ether), 0);
        assertGt(vault.previewWithdraw(1 ether), 0);
    }

    function test_SetCuratorFeesEnforcesCapsReceiversAndRoles() public {
        VaultV2 vault = _createVault(false, false, 0);

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.setManagementFee(1, address(0));

        vm.expectRevert(IVaultV2.InvalidAddress.selector);
        vault.setPerformanceFee(1, address(0));

        vm.expectRevert(IVaultV2.FeeTooHigh.selector);
        vault.setManagementFee(uint96(MAX_MANAGEMENT_FEE + 1), managementFeeReceiver);

        vm.expectRevert(IVaultV2.FeeTooHigh.selector);
        vault.setPerformanceFee(uint96(MAX_PERFORMANCE_FEE + 1), performanceFeeReceiver);

        vm.recordLogs();
        vault.setManagementFee(uint96(MAX_MANAGEMENT_FEE), managementFeeReceiver);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3);
        assertEq(logs[2].topics[0], keccak256("SetManagementFee(uint256,address)"));
        assertEq(logs[2].topics[1], bytes32(uint256(uint160(managementFeeReceiver))));
        assertEq(abi.decode(logs[2].data, (uint256)), MAX_MANAGEMENT_FEE);

        vm.recordLogs();
        vault.setPerformanceFee(uint96(MAX_PERFORMANCE_FEE), performanceFeeReceiver);
        Vm.Log[] memory performanceFeeLogs = vm.getRecordedLogs();

        assertEq(performanceFeeLogs.length, 3);
        assertEq(performanceFeeLogs[2].topics[0], keccak256("SetPerformanceFee(uint256,address)"));
        assertEq(performanceFeeLogs[2].topics[1], bytes32(uint256(uint160(performanceFeeReceiver))));
        assertEq(abi.decode(performanceFeeLogs[2].data, (uint256)), MAX_PERFORMANCE_FEE);

        assertEq(vault.managementFee(), MAX_MANAGEMENT_FEE);
        assertEq(vault.managementFeeReceiver(), managementFeeReceiver);
        assertEq(vault.performanceFee(), MAX_PERFORMANCE_FEE);
        assertEq(vault.performanceFeeReceiver(), performanceFeeReceiver);

        vm.startPrank(bob);
        vm.expectRevert();
        vault.setManagementFee(0, address(0));
        vm.expectRevert();
        vault.setPerformanceFee(0, address(0));
        vm.stopPrank();
    }

    function test_TotalSupplyIncludesAccruedCuratorAndProtocolFeeSharesBeforeMinting() public {
        VaultV2 vault = _createVault(false, false, 0);
        _setCuratorFees(vault);
        protocolFee.setGlobalFee(17, 13);
        _deposit(vault, alice, 100 ether);
        uint256 rawSupply = vault.totalSupply();

        vm.warp(vm.getBlockTimestamp() + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        (, uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares) =
            vault.getAccrueInterest();

        assertGt(managementFeeShares + performanceFeeShares + protocolFeeShares, 0);
        assertEq(vault.totalSupply(), rawSupply + managementFeeShares + performanceFeeShares + protocolFeeShares);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_AccrueInterestMintsPreviewedFeeSharesToReceiversWithoutChangingVisibleSupply() public {
        VaultV2 vault = _createVault(false, false, 0);
        _setCuratorFees(vault);
        protocolFee.setGlobalFee(17, 13);
        _deposit(vault, alice, 100 ether);

        vm.warp(vm.getBlockTimestamp() + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        uint256 previewSupply = vault.totalSupply();
        (, uint256 previewManagementFeeShares, uint256 previewPerformanceFeeShares, uint256 previewProtocolFeeShares) =
            vault.getAccrueInterest();

        (uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares) = vault.accrueInterest();

        assertEq(protocolFeeShares, previewProtocolFeeShares);
        assertEq(managementFeeShares, previewManagementFeeShares);
        assertEq(performanceFeeShares, previewPerformanceFeeShares);
        assertEq(vault.balanceOf(protocolFeeReceiver), protocolFeeShares);
        assertEq(vault.balanceOf(managementFeeReceiver), managementFeeShares);
        assertEq(vault.balanceOf(performanceFeeReceiver), performanceFeeShares);
        assertEq(vault.totalSupply(), previewSupply);
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function test_ProtocolManagementFeeAccruesWithoutInterest() public {
        VaultV2 vault = _createVault(false, false, 0);
        protocolFee.setGlobalFee(uint96(MAX_MANAGEMENT_FEE), 0);
        vault.accrueInterest();

        _deposit(vault, alice, 100 ether);

        vm.warp(vm.getBlockTimestamp() + 30 days);

        (,, uint256 protocolFeeShares) = vault.accrueInterest();

        assertGt(protocolFeeShares, 0);
        assertEq(vault.balanceOf(protocolFeeReceiver), protocolFeeShares);
    }

    function test_AccrueInterestUsesCachedProtocolFeeAndReceiverThenRefreshes() public {
        VaultV2 vault = _createVault(false, false, 0);
        protocolFee.setGlobalFee(17, 13);
        vault.accrueInterest();

        assertEq(vault.lastProtocolManagementFee(), 17);
        assertEq(vault.lastProtocolPerformanceFee(), 13);
        assertEq(vault.lastProtocolFeeReceiver(), protocolFeeReceiver);

        _deposit(vault, alice, 100 ether);
        protocolFee.setGlobalFee(0, 0);
        protocolFee.setGlobalReceiver(nextProtocolFeeReceiver);

        vm.warp(vm.getBlockTimestamp() + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        (,,, uint256 previewProtocolFeeShares) = vault.getAccrueInterest();
        assertGt(previewProtocolFeeShares, 0);

        (,, uint256 protocolFeeShares) = vault.accrueInterest();

        assertEq(protocolFeeShares, previewProtocolFeeShares);
        assertEq(vault.balanceOf(protocolFeeReceiver), protocolFeeShares);
        assertEq(vault.balanceOf(nextProtocolFeeReceiver), 0);
        assertEq(vault.lastProtocolManagementFee(), 0);
        assertEq(vault.lastProtocolPerformanceFee(), 0);
        assertEq(vault.lastProtocolFeeReceiver(), nextProtocolFeeReceiver);
    }

    function test_CreateVaultV2InitializesDelegator() public {
        VaultV2 vault = _createVault(false, false, 0);
        address delegator = vault.delegator();

        assertTrue(delegatorFactory.isEntity(delegator));
        assertEq(IUniversalDelegator(delegator).vault(), address(vault));
    }

    function test_UnsupportedMigrationsRevert() public {
        VaultV2 vault = _createVault(false, false, 0);

        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(vaultFactory),
                    address(delegatorFactory),
                    address(protocolFee),
                    address(withdrawalQueueFactory)
                )
            )
        );
        withdrawalQueueFactory.whitelist(address(new WithdrawalQueue(address(withdrawalQueueFactory))));

        uint64 vaultVersion = vaultFactory.lastVersion();
        address queue = vault.withdrawalQueue();
        uint64 queueVersion = withdrawalQueueFactory.lastVersion();

        vm.expectRevert();
        vaultFactory.migrate(address(vault), vaultVersion, "");

        vm.expectRevert();
        vm.prank(address(vault));
        withdrawalQueueFactory.migrate(queue, queueVersion, "");
    }

    function _createVault(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        returns (VaultV2 vault)
    {
        bytes memory data = _vaultParams(depositWhitelist, isDepositLimit, depositLimit);

        vault = VaultV2(vaultFactory.create(VAULT_V2_VERSION, address(this), data));
    }

    function _vaultParams(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        view
        returns (bytes memory)
    {
        return _vaultParamsWithAsset(address(collateral), depositWhitelist, isDepositLimit, depositLimit);
    }

    function _vaultParamsWithAsset(address asset, bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(
            IVaultV2.InitParams({
                name: "Vault",
                symbol: "vTKN",
                asset: asset,
                depositWhitelist: depositWhitelist,
                depositorToWhitelist: alice,
                isDepositLimit: isDepositLimit,
                depositLimit: depositLimit,
                defaultAdminRoleHolder: address(this),
                depositWhitelistSetRoleHolder: address(this),
                depositorWhitelistRoleHolder: address(this),
                isDepositLimitSetRoleHolder: address(this),
                depositLimitSetRoleHolder: address(this),
                managementFeeRoleHolder: address(this),
                performanceFeeRoleHolder: address(this),
                delegatorParams: _delegatorParams()
            })
        );
    }

    function _delegatorParams() internal view returns (bytes memory) {
        return abi.encode(
            IUniversalDelegator.InitParams({
                allocateRoleHolder: address(this),
                deallocateRoleHolder: address(this),
                addAdapterRoleHolder: address(this),
                swapAdaptersRoleHolder: address(this),
                defaultAdminRoleHolder: address(this),
                removeAdapterRoleHolder: address(this),
                forceDeallocateRoleHolder: address(this),
                setAdapterLimitsRoleHolder: address(this),
                setAutoAllocateAdaptersRoleHolder: address(this)
            })
        );
    }

    function _assertEmptyShareCheckpoints(VaultV2 vault) internal view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalSupplyAt(uint48(vm.getBlockTimestamp())), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOfAt(alice, uint48(vm.getBlockTimestamp())), 0);
    }

    function _setCuratorFees(VaultV2 vault) internal {
        vault.setManagementFee(7, managementFeeReceiver);
        vault.setPerformanceFee(11, performanceFeeReceiver);
    }

    function _deposit(VaultV2 vault, address account, uint256 assets) internal {
        collateral.transfer(account, assets);

        vm.startPrank(account);
        collateral.approve(address(vault), assets);
        vault.deposit(assets, account);
        vm.stopPrank();
    }

    function _hasTopic(Vm.Log[] memory logs, bytes32 topic) internal pure returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return true;
            }
        }
        return false;
    }
}
