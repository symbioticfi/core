// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ProtocolFeeRegistry} from "../src/contracts/ProtocolFeeRegistry.sol";
import {IProtocolFeeRegistry} from "../src/interfaces/IProtocolFeeRegistry.sol";
import {MAX_FEE, MAX_MANAGEMENT_FEE, MAX_PERFORMANCE_FEE} from "../src/interfaces/vault/IVaultV2.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFeeRegistryTest is Test {
    address internal owner = address(this);
    address internal globalReceiver = address(0xFEE);
    address internal vaultReceiver = address(0xBEEF);
    address internal vault = address(0xA11CE);
    address internal bob = address(0xB0B);

    function test_GetFeeFallsBackToGlobalAndUsesVaultOverride() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setGlobalReceiver(globalReceiver);
        protocolFeeRegistry.setGlobalFee(7, 1e16);

        (address receiver, uint96 managementFee, uint96 performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 7);
        assertEq(performanceFee, 1e16);

        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, 11, 2e16);

        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, vaultReceiver);
        assertEq(managementFee, 11);
        assertEq(performanceFee, 2e16);
        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(address(0xCAFE));
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 7);
        assertEq(performanceFee, 1e16);

        protocolFeeRegistry.setVaultFee(vault, false, vaultReceiver, 11, 2e16);

        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 7);
        assertEq(performanceFee, 1e16);
    }

    function test_VaultFeeCanOverrideGlobalFeesToZero() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setGlobalReceiver(globalReceiver);
        protocolFeeRegistry.setGlobalFee(7, 1e16);
        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, 0, 0);

        (bool isEnabled, address receiver, uint96 managementFee, uint96 performanceFee) =
            protocolFeeRegistry.vaultFee(vault);
        assertTrue(isEnabled);
        assertEq(receiver, vaultReceiver);
        assertEq(managementFee, 0);
        assertEq(performanceFee, 0);
        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, vaultReceiver);
        assertEq(managementFee, 0);
        assertEq(performanceFee, 0);
        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(address(0xCAFE));
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 7);
        assertEq(performanceFee, 1e16);

        protocolFeeRegistry.setVaultFee(vault, false, vaultReceiver, 0, 0);

        (isEnabled, receiver, managementFee, performanceFee) = protocolFeeRegistry.vaultFee(vault);
        assertFalse(isEnabled);
        assertEq(receiver, vaultReceiver);
        assertEq(managementFee, 0);
        assertEq(performanceFee, 0);
        (receiver, managementFee, performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 7);
        assertEq(performanceFee, 1e16);
    }

    function test_OnlyOwnerSetsFeeConfig() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setGlobalFee(1, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setGlobalReceiver(address(0x123));
        vm.stopPrank();
    }

    function test_SettersValidateFeeAndReceiver() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setGlobalFee(MAX_MANAGEMENT_FEE + 1, 0);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setGlobalFee(0, MAX_PERFORMANCE_FEE + 1);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, MAX_MANAGEMENT_FEE + 1, 0);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, 0, MAX_PERFORMANCE_FEE + 1);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setGlobalReceiver(address(0));
    }

    function test_SetGlobalFeeRequiresReceiverForNonZeroFees() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setGlobalFee(0, 0);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setGlobalFee(1, 0);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setGlobalFee(0, 1);

        protocolFeeRegistry.setGlobalReceiver(globalReceiver);
        protocolFeeRegistry.setGlobalFee(1, 1);

        (address receiver, uint96 managementFee, uint96 performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, globalReceiver);
        assertEq(managementFee, 1);
        assertEq(performanceFee, 1);
    }

    function test_SetVaultFeeRequiresReceiverForEnabledNonZeroFees() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setVaultFee(vault, true, address(0), 0, 0);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setVaultFee(vault, true, address(0), 1, 0);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setVaultFee(vault, true, address(0), 0, 1);

        protocolFeeRegistry.setVaultFee(vault, true, vaultReceiver, 1, 1);

        (address receiver, uint96 managementFee, uint96 performanceFee) = protocolFeeRegistry.getFee(vault);
        assertEq(receiver, vaultReceiver);
        assertEq(managementFee, 1);
        assertEq(performanceFee, 1);
    }

    function test_ProtocolFeeLimitConstantsUseUint96VaultValues() public pure {
        uint96 maxFee = MAX_FEE;
        uint96 maxManagementFee = MAX_MANAGEMENT_FEE;
        uint96 maxPerformanceFee = MAX_PERFORMANCE_FEE;

        assertEq(maxFee, 1e18);
        assertEq(maxManagementFee, 5e16 / uint256(365 days));
        assertEq(maxPerformanceFee, 2e17);
    }

    function test_ProtocolFeeRegistryApiSelectors() public pure {
        assertEq(IProtocolFeeRegistry.globalManagementFee.selector, bytes4(keccak256("globalManagementFee()")));
        assertEq(IProtocolFeeRegistry.globalPerformanceFee.selector, bytes4(keccak256("globalPerformanceFee()")));
        assertEq(IProtocolFeeRegistry.vaultFee.selector, bytes4(keccak256("vaultFee(address)")));
        assertEq(IProtocolFeeRegistry.globalReceiver.selector, bytes4(keccak256("globalReceiver()")));
        assertEq(IProtocolFeeRegistry.setGlobalFee.selector, bytes4(keccak256("setGlobalFee(uint96,uint96)")));
        assertEq(
            IProtocolFeeRegistry.setVaultFee.selector,
            bytes4(keccak256("setVaultFee(address,bool,address,uint96,uint96)"))
        );
        assertEq(IProtocolFeeRegistry.setGlobalReceiver.selector, bytes4(keccak256("setGlobalReceiver(address)")));
        assertEq(IProtocolFeeRegistry.getFee.selector, bytes4(keccak256("getFee(address)")));
    }
}
