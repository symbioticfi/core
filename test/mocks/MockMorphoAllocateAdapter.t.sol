// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Token} from "./Token.sol";
import {MockMorphoVault} from "./MockMorphoVault.sol";
import {MockMorphoAllocateAdapter} from "./MockMorphoAllocateAdapter.sol";

contract MockCuratorRegistryHarness {
    mapping(address vault => address curator) public curators;

    function setCurator(address vault, address curator) external {
        curators[vault] = curator;
    }

    function getCurator(address vault) external view returns (address) {
        return curators[vault];
    }
}

contract MockVaultHarness {
    address public immutable collateral;
    mapping(address adapter => uint256 allocated) public adapterAllocated;
    uint256 public donated;

    constructor(address collateral_) {
        collateral = collateral_;
    }

    function setAdapterAllocated(address adapter, uint256 amount) external {
        adapterAllocated[adapter] = amount;
    }

    function donate(uint256 amount) external {
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
        donated += amount;
    }
}

interface IVaultDonateHarness {
    function collateral() external view returns (address);
    function donate(uint256 amount) external;
}

contract MockRewardsPull is ReentrancyGuard {
    function donate(address vault, uint256 amount) external nonReentrant {
        address collateral = IVaultDonateHarness(vault).collateral();
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
        IERC20(collateral).approve(vault, amount);
        IVaultDonateHarness(vault).donate(amount);
    }
}

contract MockMorphoVaultWithPreview is MockMorphoVault {
    constructor(address asset_) MockMorphoVault(asset_) {}

    function balanceOf(address account) external view override returns (uint256) {
        return sharesOf[account];
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        uint256 supply = totalShares;
        if (supply == 0) {
            return 0;
        }
        return shares * asset.balanceOf(address(this)) / supply;
    }
}

contract MockMorphoAllocateAdapterTest is Test {
    Token internal collateral;
    MockMorphoVaultWithPreview internal morphoVault;
    MockRewardsPull internal rewards;
    MockCuratorRegistryHarness internal curatorRegistry;
    MockVaultHarness internal vault;
    MockMorphoAllocateAdapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        collateral = new Token("Collateral");
        morphoVault = new MockMorphoVaultWithPreview(address(collateral));
        rewards = new MockRewardsPull();
        curatorRegistry = new MockCuratorRegistryHarness();
        vault = new MockVaultHarness(address(collateral));
        adapter = new MockMorphoAllocateAdapter(address(rewards), address(curatorRegistry));

        curatorRegistry.setCurator(address(vault), curator);
        vm.prank(curator);
        adapter.setMorhpoVault(address(vault), address(morphoVault));
        adapter.setGlobalLimit(address(collateral), type(uint256).max);
    }

    function test_SetMorphoVault_RevertWhenNotCurator() public {
        vm.prank(attacker);
        vm.expectRevert(MockMorphoAllocateAdapter.NotCurator.selector);
        adapter.setMorhpoVault(address(vault), address(morphoVault));
    }

    function test_SetMorphoVault_RevertWhenAssetMismatch() public {
        Token otherCollateral = new Token("Other");
        MockMorphoVaultWithPreview otherMorphoVault = new MockMorphoVaultWithPreview(address(otherCollateral));

        vm.prank(curator);
        vm.expectRevert(MockMorphoAllocateAdapter.InvalidMorphoVault.selector);
        adapter.setMorhpoVault(address(vault), address(otherMorphoVault));
    }

    function test_Allocatable_UsesGlobalLimitAndAdapterBalance() public {
        adapter.setGlobalLimit(address(collateral), 100);
        collateral.transfer(address(adapter), 30);

        assertEq(adapter.allocatable(address(vault)), 70);
    }



    function test_Deallocate_CapsToVaultReportedAdapterAllocation() public {
        _allocateFromVault(80, 50);

        vm.prank(address(vault));
        uint256 deallocated = adapter.deallocate(70);

        assertEq(deallocated, 50);
        assertEq(collateral.balanceOf(address(adapter)), 50);
        assertEq(collateral.balanceOf(address(morphoVault)), 30);
    }


    function _allocateFromVault(uint256 amount, uint256 allocatedToAdapter) internal {
        collateral.transfer(address(adapter), amount);
        vault.setAdapterAllocated(address(adapter), allocatedToAdapter);

        vm.prank(address(vault));
        adapter.allocate(amount);
    }
}
