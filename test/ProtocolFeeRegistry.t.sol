// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ProtocolFeeRegistry} from "../src/contracts/ProtocolFeeRegistry.sol";
import {IProtocolFeeRegistry, MAX_PROTOCOL_FEE} from "../src/interfaces/IProtocolFeeRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFeeRegistryTest is Test {
    address internal owner = address(this);
    address internal globalReceiver = address(0xFEE);
    address internal vaultReceiver = address(0xBEEF);
    address internal vault = address(0xA11CE);
    address internal bob = address(0xB0B);

    function test_GettersFallBackToGlobalAndUseVaultOverrides() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setGlobalFee(1e16);
        protocolFeeRegistry.setGlobalReceiver(globalReceiver);

        assertEq(protocolFeeRegistry.getFee(vault), 1e16);
        assertEq(protocolFeeRegistry.getReceiver(vault), globalReceiver);

        protocolFeeRegistry.setVaultFee(vault, true, 2e16);
        protocolFeeRegistry.setVaultReceiver(vault, vaultReceiver);

        assertEq(protocolFeeRegistry.getFee(vault), 2e16);
        assertEq(protocolFeeRegistry.getFee(address(0xCAFE)), 1e16);
        assertEq(protocolFeeRegistry.getReceiver(vault), vaultReceiver);
        assertEq(protocolFeeRegistry.getReceiver(address(0xCAFE)), globalReceiver);

        protocolFeeRegistry.setVaultReceiver(vault, address(0));

        assertEq(protocolFeeRegistry.getReceiver(vault), globalReceiver);
    }

    function test_VaultFeeCanOverrideGlobalFeeToZero() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        protocolFeeRegistry.setGlobalFee(1e16);
        protocolFeeRegistry.setVaultFee(vault, true, 0);

        (bool isEnabled, uint256 fee) = protocolFeeRegistry.vaultFee(vault);
        assertTrue(isEnabled);
        assertEq(fee, 0);
        assertEq(protocolFeeRegistry.getFee(vault), 0);
        assertEq(protocolFeeRegistry.getFee(address(0xCAFE)), 1e16);

        protocolFeeRegistry.setVaultFee(vault, false, 0);

        (isEnabled, fee) = protocolFeeRegistry.vaultFee(vault);
        assertFalse(isEnabled);
        assertEq(fee, 0);
        assertEq(protocolFeeRegistry.getFee(vault), 1e16);
    }

    function test_OnlyOwnerSetsFeeConfig() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setGlobalFee(1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setVaultFee(vault, true, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setGlobalReceiver(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFeeRegistry.setVaultReceiver(vault, address(0x123));
        vm.stopPrank();
    }

    function test_SettersValidateFeeAndReceiver() public {
        ProtocolFeeRegistry protocolFeeRegistry = new ProtocolFeeRegistry(owner);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setGlobalFee(MAX_PROTOCOL_FEE + 1);

        vm.expectRevert(IProtocolFeeRegistry.FeeTooHigh.selector);
        protocolFeeRegistry.setVaultFee(vault, true, MAX_PROTOCOL_FEE + 1);

        vm.expectRevert(IProtocolFeeRegistry.InvalidReceiver.selector);
        protocolFeeRegistry.setGlobalReceiver(address(0));
    }

    function test_ProtocolFeeRegistryApiSelectors() public pure {
        assertEq(IProtocolFeeRegistry.globalFee.selector, bytes4(keccak256("globalFee()")));
        assertEq(IProtocolFeeRegistry.vaultFee.selector, bytes4(keccak256("vaultFee(address)")));
        assertEq(IProtocolFeeRegistry.globalReceiver.selector, bytes4(keccak256("globalReceiver()")));
        assertEq(IProtocolFeeRegistry.vaultReceiver.selector, bytes4(keccak256("vaultReceiver(address)")));
        assertEq(IProtocolFeeRegistry.setVaultFee.selector, bytes4(keccak256("setVaultFee(address,bool,uint256)")));
        assertEq(IProtocolFeeRegistry.setGlobalReceiver.selector, bytes4(keccak256("setGlobalReceiver(address)")));
        assertEq(IProtocolFeeRegistry.setVaultReceiver.selector, bytes4(keccak256("setVaultReceiver(address,address)")));
    }
}
