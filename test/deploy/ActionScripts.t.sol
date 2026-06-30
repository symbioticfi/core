// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AddAdapterBaseScript} from "../../script/actions/v2/base/AddAdapterBase.s.sol";
import {ClaimWithdrawalBaseScript} from "../../script/actions/v2/base/ClaimWithdrawalBase.s.sol";
import {RequestRedeemBaseScript} from "../../script/actions/v2/base/RequestRedeemBase.s.sol";
import {SweepPendingBaseScript} from "../../script/actions/v2/base/SweepPendingBase.s.sol";
import {ReleaseBaseScript} from "../../script/adapters/actions/app-adapter/base/ReleaseBase.s.sol";
import {PrepareConvertBaseScript} from "../../script/adapters/actions/common/base/PrepareConvertBase.s.sol";
import {SetLiquidLaneLimitBaseScript} from "../../script/adapters/actions/ll-adapter/base/SetLiquidLaneLimitBase.s.sol";
import {SyncRewardBaseScript} from "../../script/adapters/actions/restaking-app-adapter/base/SyncRewardBase.s.sol";

import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {ILiquidLaneAdapter} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IRestakingAppAdapter} from "../../src/interfaces/adapters/IRestakingAppAdapter.sol";
import {ICoWSwapConverter} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../src/interfaces/vault/IWithdrawalQueue.sol";

contract AddAdapterHarness is AddAdapterBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract ClaimWithdrawalHarness is ClaimWithdrawalBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract RequestRedeemHarness is RequestRedeemBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract SweepPendingHarness is SweepPendingBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract PrepareConvertHarness is PrepareConvertBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract ReleaseHarness is ReleaseBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract SetLiquidLaneLimitHarness is SetLiquidLaneLimitBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract SyncRewardHarness is SyncRewardBaseScript {
    function sendTransaction(address, bytes memory) public override {}
}

contract ActionScriptsTest is Test {
    address internal constant VAULT = address(0x1001);
    address internal constant DELEGATOR = address(0x1002);
    address internal constant WITHDRAWAL_QUEUE = address(0x1003);
    address internal constant ADAPTER = address(0x1004);
    address internal constant RECEIVER = address(0x1005);
    address internal constant TOKEN = address(0x1006);

    function setUp() public {
        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.delegator, ()), abi.encode(DELEGATOR));
        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.withdrawalQueue, ()), abi.encode(WITHDRAWAL_QUEUE));
    }

    function test_CoreV2ActionScriptsEncodeTargetsAndCalldata() public {
        (bytes memory data, address target) = new AddAdapterHarness().runBase(VAULT, ADAPTER);
        assertEq(target, DELEGATOR);
        assertEq(data, abi.encodeCall(IUniversalDelegator.addAdapter, (ADAPTER)));

        (data, target) = new SweepPendingHarness().runBase(VAULT);
        assertEq(target, DELEGATOR);
        assertEq(data, abi.encodeCall(IUniversalDelegator.sweepPending, ()));

        (data, target) = new RequestRedeemHarness().runBase(VAULT, 123, RECEIVER);
        assertEq(target, WITHDRAWAL_QUEUE);
        assertEq(data, abi.encodeCall(IWithdrawalQueue.requestRedeem, (123, RECEIVER)));

        (data, target) = new ClaimWithdrawalHarness().runBase(VAULT, 7, RECEIVER);
        assertEq(target, WITHDRAWAL_QUEUE);
        assertEq(data, abi.encodeCall(IWithdrawalQueue.claim, (7, RECEIVER)));
    }

    function test_NoProtocolActionScripts() public view {
        assertFalse(vm.exists("script/actions/AccrueInterest.s.sol"));
        assertFalse(vm.exists("script/actions/base/AccrueInterestBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/AccrueInterest.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/AccrueInterestBase.s.sol"));
        assertFalse(vm.exists("script/actions/BlacklistVersion.s.sol"));
        assertFalse(vm.exists("script/actions/base/BlacklistVersionBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/BlacklistVersion.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/BlacklistVersionBase.s.sol"));
        assertFalse(vm.exists("script/actions/FillWithdrawalQueue.s.sol"));
        assertFalse(vm.exists("script/actions/base/FillWithdrawalQueueBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/FillWithdrawalQueue.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/FillWithdrawalQueueBase.s.sol"));
        assertFalse(vm.exists("script/actions/MigrateEntity.s.sol"));
        assertFalse(vm.exists("script/actions/base/MigrateEntityBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/MigrateEntity.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/MigrateEntityBase.s.sol"));
        assertFalse(vm.exists("script/actions/SetAdapterWhitelistedStatus.s.sol"));
        assertFalse(vm.exists("script/actions/base/SetAdapterWhitelistedStatusBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/SetAdapterWhitelistedStatus.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/SetAdapterWhitelistedStatusBase.s.sol"));
        assertFalse(vm.exists("script/actions/SetGlobalProtocolFee.s.sol"));
        assertFalse(vm.exists("script/actions/base/SetGlobalProtocolFeeBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/SetGlobalProtocolFee.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/SetGlobalProtocolFeeBase.s.sol"));
        assertFalse(vm.exists("script/actions/SetGlobalProtocolFeeReceiver.s.sol"));
        assertFalse(vm.exists("script/actions/base/SetGlobalProtocolFeeReceiverBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/SetGlobalProtocolFeeReceiver.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/SetGlobalProtocolFeeReceiverBase.s.sol"));
        assertFalse(vm.exists("script/actions/SetVaultProtocolFee.s.sol"));
        assertFalse(vm.exists("script/actions/base/SetVaultProtocolFeeBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/SetVaultProtocolFee.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/SetVaultProtocolFeeBase.s.sol"));
        assertFalse(vm.exists("script/actions/WhitelistImplementation.s.sol"));
        assertFalse(vm.exists("script/actions/base/WhitelistImplementationBase.s.sol"));
        assertFalse(vm.exists("script/actions/v2/WhitelistImplementation.s.sol"));
        assertFalse(vm.exists("script/actions/v2/base/WhitelistImplementationBase.s.sol"));
    }

    function test_ActionScriptsUseVersionFolders() public view {
        assertTrue(vm.exists("script/actions/v2/AddAdapter.s.sol"));
        assertTrue(vm.exists("script/actions/v2/base/AddAdapterBase.s.sol"));
        assertTrue(vm.exists("script/actions/v2/ClaimWithdrawal.s.sol"));
        assertTrue(vm.exists("script/actions/v2/base/ClaimWithdrawalBase.s.sol"));
        assertTrue(vm.exists("script/actions/v1/RegisterOperator.s.sol"));
        assertTrue(vm.exists("script/actions/v1/base/RegisterOperatorBase.s.sol"));
        assertTrue(vm.exists("script/actions/v1/SetNetworkLimit.s.sol"));
        assertTrue(vm.exists("script/actions/v1/base/SetNetworkLimitBase.s.sol"));

        assertFalse(vm.exists("script/actions/AddAdapter.s.sol"));
        assertFalse(vm.exists("script/actions/base/AddAdapterBase.s.sol"));
        assertFalse(vm.exists("script/actions/ClaimWithdrawal.s.sol"));
        assertFalse(vm.exists("script/actions/base/ClaimWithdrawalBase.s.sol"));
        assertFalse(vm.exists("script/actions/RegisterOperator.s.sol"));
        assertFalse(vm.exists("script/actions/base/RegisterOperatorBase.s.sol"));
        assertFalse(vm.exists("script/actions/SetNetworkLimit.s.sol"));
        assertFalse(vm.exists("script/actions/base/SetNetworkLimitBase.s.sol"));
    }

    function test_NoLiquidLaneSwapActionScripts() public view {
        assertFalse(vm.exists("script/adapters/actions/LiquidLaneSwap.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/LiquidLaneSwapBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/LiquidLaneSignedSwap.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/LiquidLaneSignedSwapBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/LiquidLaneDiscountSwap.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/LiquidLaneDiscountSwapBase.s.sol"));
    }

    function test_AdapterActionScriptsUseCategoryFolders() public view {
        assertTrue(vm.exists("script/adapters/actions/common/PrepareConvert.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/common/base/PrepareConvertBase.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/app-adapter/Release.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/app-adapter/base/ReleaseBase.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/restaking-app-adapter/SyncReward.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/restaking-app-adapter/base/SyncRewardBase.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/ll-adapter/SetLiquidLaneLimit.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/ll-adapter/base/SetLiquidLaneLimitBase.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/3f-adapter/SetOfferSigner.s.sol"));
        assertTrue(vm.exists("script/adapters/actions/3f-adapter/base/SetOfferSignerBase.s.sol"));

        assertFalse(vm.exists("script/adapters/actions/PrepareConvert.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/PrepareConvertBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/Release.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/ReleaseBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/SyncReward.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/SyncRewardBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/SetLiquidLaneLimit.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/SetLiquidLaneLimitBase.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/SetOfferSigner.s.sol"));
        assertFalse(vm.exists("script/adapters/actions/base/SetOfferSignerBase.s.sol"));
    }

    function test_AdapterActionScriptsEncodeTargetsAndCalldata() public {
        (bytes memory data, address target) = new ReleaseHarness().runBase(ADAPTER, 123);
        assertEq(target, ADAPTER);
        assertEq(data, abi.encodeCall(IAppAdapter.release, (123)));

        (data, target) = new SyncRewardHarness().runBase(ADAPTER);
        assertEq(target, ADAPTER);
        assertEq(data, abi.encodeCall(IRestakingAppAdapter.syncReward, ()));

        bytes memory convertData = abi.encode(uint256(1));
        (data, target) = new PrepareConvertHarness().runBase(ADAPTER, TOKEN, 2, RECEIVER, convertData);
        assertEq(target, ADAPTER);
        assertEq(data, abi.encodeCall(ICoWSwapConverter.prepareConvert, (TOKEN, 2, RECEIVER, convertData)));

        (data, target) = new SetLiquidLaneLimitHarness().runBase(ADAPTER, TOKEN, 5);
        assertEq(target, ADAPTER);
        assertEq(data, abi.encodeCall(ILiquidLaneAdapter.setLimit, (TOKEN, 5)));
    }
}
