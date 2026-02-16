// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Token} from "./Token.sol";
import {MockMorphoVault} from "./MockMorphoVault.sol";
import {MockMorphoAllocatePlugin} from "./MockMorphoAllocatePlugin.sol";

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
    mapping(address plugin => uint256 allocated) public pluginAllocated;
    uint256 public donated;

    constructor(address collateral_) {
        collateral = collateral_;
    }

    function setPluginAllocated(address plugin, uint256 amount) external {
        pluginAllocated[plugin] = amount;
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

contract MockRewardsPull {
    function donate(address vault, uint256 amount) external {
        address collateral = IVaultDonateHarness(vault).collateral();
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
        IERC20(collateral).approve(vault, amount);
        IVaultDonateHarness(vault).donate(amount);
    }
}

contract MockMorphoVaultWithPreview is MockMorphoVault {
    constructor(address asset_) MockMorphoVault(asset_) {}

    function balanceOf(address account) external view returns (uint256) {
        return sharesOf[account];
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        uint256 supply = totalShares;
        if (supply == 0) {
            return 0;
        }
        return shares * asset.balanceOf(address(this)) / supply;
    }
}

contract MockMorphoAllocatePluginTest is Test {
    Token internal collateral;
    MockMorphoVaultWithPreview internal morphoVault;
    MockRewardsPull internal rewards;
    MockCuratorRegistryHarness internal curatorRegistry;
    MockVaultHarness internal vault;
    MockMorphoAllocatePlugin internal plugin;

    address internal curator = makeAddr("curator");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        collateral = new Token("Collateral");
        morphoVault = new MockMorphoVaultWithPreview(address(collateral));
        rewards = new MockRewardsPull();
        curatorRegistry = new MockCuratorRegistryHarness();
        vault = new MockVaultHarness(address(collateral));
        plugin = new MockMorphoAllocatePlugin(address(rewards), address(curatorRegistry));

        curatorRegistry.setCurator(address(vault), curator);
        vm.prank(curator);
        plugin.setMorhpoVault(address(vault), address(morphoVault));
        plugin.setGlobalLimit(address(collateral), type(uint256).max);
    }

    function test_SetMorphoVault_RevertWhenNotCurator() public {
        vm.prank(attacker);
        vm.expectRevert(MockMorphoAllocatePlugin.NotCurator.selector);
        plugin.setMorhpoVault(address(vault), address(morphoVault));
    }

    function test_SetMorphoVault_RevertWhenAssetMismatch() public {
        Token otherCollateral = new Token("Other");
        MockMorphoVaultWithPreview otherMorphoVault = new MockMorphoVaultWithPreview(address(otherCollateral));

        vm.prank(curator);
        vm.expectRevert(MockMorphoAllocatePlugin.InvalidMorphoVault.selector);
        plugin.setMorhpoVault(address(vault), address(otherMorphoVault));
    }

    function test_Allocatable_UsesGlobalLimitAndPluginBalance() public {
        plugin.setGlobalLimit(address(collateral), 100);
        collateral.transfer(address(plugin), 30);

        assertEq(plugin.allocatable(address(vault)), 70);
    }

    function test_Allocate_DepositsIntoMorphoAndDoesNotCreateSkimmableWithoutYield() public {
        _allocateFromVault(80, 80);

        assertEq(collateral.balanceOf(address(plugin)), 0);
        assertEq(collateral.balanceOf(address(morphoVault)), 80);
        assertEq(plugin.skimmable(address(vault)), 0);
        assertEq(plugin.deallocatable(address(vault)), 80);
    }

    function test_Skim_DonatesAccruedYieldToVault() public {
        _allocateFromVault(80, 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        uint256 expectedSkimmable = plugin.skimmable(address(vault));
        assertGt(expectedSkimmable, 0);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 skimmed = plugin.skim(address(vault));

        assertEq(skimmed, expectedSkimmable);
        assertEq(collateral.balanceOf(address(vault)) - vaultBalanceBefore, skimmed);
        assertEq(vault.donated(), skimmed);
        assertEq(plugin.skimmable(address(vault)), 0);
    }

    function test_Deallocate_CapsToVaultReportedPluginAllocation() public {
        _allocateFromVault(80, 50);

        vm.prank(address(vault));
        uint256 deallocated = plugin.deallocate(70);

        assertEq(deallocated, 50);
        assertEq(collateral.balanceOf(address(plugin)), 50);
        assertEq(collateral.balanceOf(address(morphoVault)), 30);
    }

    function test_Allocate_SkimsYieldBeforeDepositingMore() public {
        _allocateFromVault(80, 80);

        collateral.approve(address(morphoVault), 20);
        morphoVault.donateYield(20);

        collateral.transfer(address(plugin), 10);
        vault.setPluginAllocated(address(plugin), 90);

        vm.prank(address(vault));
        plugin.allocate(10);

        assertGt(vault.donated(), 0);
        assertEq(collateral.balanceOf(address(vault)), vault.donated());
        assertEq(collateral.balanceOf(address(plugin)), 0);
        assertGt(collateral.balanceOf(address(morphoVault)), 80);
        assertEq(plugin.skimmable(address(vault)), 0);
    }

    function _allocateFromVault(uint256 amount, uint256 allocatedToPlugin) internal {
        collateral.transfer(address(plugin), amount);
        vault.setPluginAllocated(address(plugin), allocatedToPlugin);

        vm.prank(address(vault));
        plugin.allocate(amount);
    }
}
