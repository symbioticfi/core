// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";

import {SimpleRewardsDistributor} from "test/mocks/SimpleRewardsDistributor.sol";

contract RewardsDistributorTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NetworkRegistry networkRegistry;
    SimpleRewardsDistributor stakerRewardsDistributor;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        networkRegistry = new NetworkRegistry();
        stakerRewardsDistributor = new SimpleRewardsDistributor();
    }

    function test_Create() public {
        assertEq(stakerRewardsDistributor.version(), 1);

        vm.startPrank(bob);
        networkRegistry.registerNetwork();
        vm.stopPrank();

        vm.startPrank(alice);
        stakerRewardsDistributor.distributeReward(bob, address(0), 0, 0);
        vm.stopPrank();
    }
}
