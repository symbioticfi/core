// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ProtocolFee} from "../../src/contracts/vault/ProtocolFee.sol";
import {IProtocolFee, MAX_PROTOCOL_FEE} from "../../src/interfaces/vault/IProtocolFee.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFeeTest is Test {
    address internal owner = address(this);
    address internal globalReceiver = address(0xFEE);
    address internal vaultReceiver = address(0xBEEF);
    address internal vault = address(0xA11CE);
    address internal bob = address(0xB0B);

    function test_GettersFallBackToGlobalAndUseVaultOverrides() public {
        ProtocolFee protocolFee = new ProtocolFee(owner, globalReceiver);

        protocolFee.setGlobalFee(1e16);
        protocolFee.setGlobalReceiver(globalReceiver);

        assertEq(protocolFee.getFee(vault), 1e16);
        assertEq(protocolFee.getReceiver(vault), globalReceiver);

        protocolFee.setVaultFee(vault, 2e16);
        protocolFee.setVaultReceiver(vault, vaultReceiver);

        assertEq(protocolFee.getFee(vault), 2e16);
        assertEq(protocolFee.getFee(address(0xCAFE)), 1e16);
        assertEq(protocolFee.getReceiver(vault), vaultReceiver);
        assertEq(protocolFee.getReceiver(address(0xCAFE)), globalReceiver);

        protocolFee.setVaultReceiver(vault, address(0));

        assertEq(protocolFee.getReceiver(vault), globalReceiver);
    }

    function test_OnlyOwnerSetsFeeConfig() public {
        ProtocolFee protocolFee = new ProtocolFee(owner, globalReceiver);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFee.setGlobalFee(1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFee.setVaultFee(vault, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFee.setGlobalReceiver(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        protocolFee.setVaultReceiver(vault, address(0x123));
        vm.stopPrank();
    }

    function test_SettersValidateFeeAndReceiver() public {
        ProtocolFee protocolFee = new ProtocolFee(owner, globalReceiver);

        vm.expectRevert(IProtocolFee.FeeTooHigh.selector);
        protocolFee.setGlobalFee(MAX_PROTOCOL_FEE + 1);

        vm.expectRevert(IProtocolFee.FeeTooHigh.selector);
        protocolFee.setVaultFee(vault, MAX_PROTOCOL_FEE + 1);

        vm.expectRevert(IProtocolFee.InvalidReceiver.selector);
        protocolFee.setGlobalReceiver(address(0));
    }

    function test_ProtocolFeeApiSelectors() public pure {
        assertEq(IProtocolFee.globalFee.selector, bytes4(keccak256("globalFee()")));
        assertEq(IProtocolFee.vaultFee.selector, bytes4(keccak256("vaultFee(address)")));
        assertEq(IProtocolFee.globalReceiver.selector, bytes4(keccak256("globalReceiver()")));
        assertEq(IProtocolFee.vaultReceiver.selector, bytes4(keccak256("vaultReceiver(address)")));
        assertEq(IProtocolFee.setGlobalReceiver.selector, bytes4(keccak256("setGlobalReceiver(address)")));
        assertEq(IProtocolFee.setVaultReceiver.selector, bytes4(keccak256("setVaultReceiver(address,address)")));
    }
}
