// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

contract VaultV2FeeRegistryApiTest is Test {
    function test_feeRegistryAndVaultExposeSnapshotFeeApi() public pure {
        assertEq(IFeeRegistry.getManagementFee.selector, bytes4(keccak256("getManagementFee(address)")));
        assertEq(
            IFeeRegistry.getManagementFeeRecipient.selector, bytes4(keccak256("getManagementFeeRecipient(address)"))
        );
        assertEq(IFeeRegistry.getPerformanceFee.selector, bytes4(keccak256("getPerformanceFee(address)")));
        assertEq(
            IFeeRegistry.getPerformanceFeeRecipient.selector, bytes4(keccak256("getPerformanceFeeRecipient(address)"))
        );
        assertEq(IVaultV2.lastManagementFee.selector, bytes4(keccak256("lastManagementFee()")));
        assertEq(IVaultV2.lastPerformanceFee.selector, bytes4(keccak256("lastPerformanceFee()")));
        assertEq(IVaultV2.getAccrueInterest.selector, bytes4(keccak256("getAccrueInterest()")));
    }
}
