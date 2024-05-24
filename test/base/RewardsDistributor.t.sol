// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";

import {SimpleRewardsDistributor} from "test/mocks/SimpleRewardsDistributor.sol";
import {IRewardsDistributorBase} from "src/interfaces/base/IRewardsDistributorBase.sol";

contract RewardsDistributorTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NetworkRegistry networkRegistry;
    SimpleRewardsDistributor rewardsDistributor;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        networkRegistry = new NetworkRegistry();
        rewardsDistributor = new SimpleRewardsDistributor(address(networkRegistry));
    }

    function test_Create() public {
        assertEq(rewardsDistributor.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(rewardsDistributor.VAULT(), address(1));
        assertEq(rewardsDistributor.version(), 1);

        vm.startPrank(bob);
        networkRegistry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        rewardsDistributor.distributeReward(bob, address(0), 0, 0);
        vm.stopPrank();
    }

    function test_CreateRevertNotNetwork() public {
        vm.expectRevert(IRewardsDistributorBase.NotNetwork.selector);
        vm.startPrank(alice);
        rewardsDistributor.distributeReward(bob, address(0), 0, 0);
        vm.stopPrank();
    }
}
