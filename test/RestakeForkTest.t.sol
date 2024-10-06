// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {StakeManager} from "../src/contracts/StakeManager.sol";

contract AdvancedRestakeForkTest is Test {
    StakeManager stakeManager;
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createFork(rpcUrl);

        stakeManager = new StakeManager();
        owner = address(this);
        alicePrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        bobPrivateKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);

        vm.deal(alice, 10 ether); // Fund alice with 10 ether for testing
        vm.deal(bob, 5 ether);    // Fund bob with 5 ether for testing
    }

    function testMultipleRestakeScenarios() public {
        vm.startPrank(alice);
        stakeManager.stake{value: 5 ether}();
        uint initialBalance = stakeManager.getStakedBalance(alice);
        
        stakeManager.restake(2 ether);
        uint afterRestakeBalance = stakeManager.getStakedBalance(alice);
        
        assert(afterRestakeBalance == initialBalance + 2 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        stakeManager.stake{value: 3 ether}();
        uint bobInitialBalance = stakeManager.getStakedBalance(bob);

        stakeManager.restake(1 ether);
        uint bobAfterRestakeBalance = stakeManager.getStakedBalance(bob);

        assert(bobAfterRestakeBalance == bobInitialBalance + 1 ether);
        vm.stopPrank();
    }

    function testWithdrawalAfterRestake() public {
        vm.startPrank(alice);
        stakeManager.stake{value: 5 ether}();
        stakeManager.restake(3 ether);

        uint stakedBalance = stakeManager.getStakedBalance(alice);
        uint withdrawAmount = 6 ether;
        stakeManager.withdraw(withdrawAmount);
        uint remainingBalance = stakeManager.getStakedBalance(alice);

        assert(stakedBalance - withdrawAmount == remainingBalance);
        vm.stopPrank();
    }
}
