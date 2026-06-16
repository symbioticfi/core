// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";

import {Token} from "../mocks/Token.sol";
import {MockAaveAToken, MockAavePool} from "../mocks/HoodiScenarioProtocolMocks.sol";

contract AaveV3AdapterTest is Test {
    AaveV3AdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    Token internal assetToken;
    MockAaveAToken internal aToken;
    MockAavePool internal pool;
    AaveV3AdapterVaultMock internal vault;
    IAaveV3Adapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");

    function setUp() public {
        vaultFactory = new AaveV3AdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        assetToken = new Token("Asset");
        aToken = new MockAaveAToken(address(assetToken));
        pool = new MockAavePool(address(assetToken), address(aToken), address(0));
        aToken.setPool(address(pool));
        vault = new AaveV3AdapterVaultMock(address(assetToken), delegator);
        vaultFactory.add(address(vault));

        AaveV3Adapter implementation = new AaveV3Adapter(address(pool), address(vaultFactory), address(factory));
        factory.whitelist(address(implementation));

        adapter = IAaveV3Adapter(factory.create(1, curator, abi.encode(address(vault), _initData())));
    }

    function test_InitializeRejectsMissingReserve() public {
        Token localAssetToken = new Token("Other");
        AaveV3AdapterVaultMock localVault = new AaveV3AdapterVaultMock(address(localAssetToken), delegator);
        vaultFactory.add(address(localVault));

        vm.expectRevert(IAaveV3Adapter.InvalidAToken.selector);
        factory.create(1, curator, abi.encode(address(localVault), _initData()));
    }

    function test_FreeAssetsUseVaultAsset() public {
        assertEq(adapter.freeAssets(), 0);

        assetToken.transfer(address(adapter), 123);

        assertEq(adapter.freeAssets(), 123);
    }

    function test_ATokenViewReturnsInitializedReserveToken() public view {
        assertEq(adapter.aToken(), address(aToken));
    }

    function test_ATokenViewDoesNotFollowReserveTokenUpdates() public {
        MockAaveAToken newAToken = new MockAaveAToken(address(assetToken));

        pool.setReserveToken(address(assetToken), address(newAToken));

        assertEq(adapter.aToken(), address(aToken));
    }

    function test_OwnerReturnsCurator() public view {
        assertEq(AaveV3Adapter(address(adapter)).owner(), curator);
    }

    function test_AllocateAndDeallocateThroughAave() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(aToken.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalATokens(), 100);
        assertEq(adapter.totalAssets(), 100);

        pool.setVirtualUnderlyingBalance(40);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(70);

        assertEq(deallocated, 40);
        assertEq(assetToken.balanceOf(address(adapter)), 40);
        assertEq(adapter.totalATokens(), 60);
        assertEq(adapter.freeAssets(), 40);
        assertEq(adapter.totalAssets(), 100);

        vm.prank(address(vault));
        assetToken.transferFrom(address(adapter), address(vault), deallocated);

        assertEq(adapter.freeAssets(), 0);
        assertEq(adapter.totalATokens(), 60);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_DirectATokenDonationDoesNotChangeTotalATokens() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        aToken.mint(address(this), 50);
        aToken.transfer(address(adapter), 50);

        assertEq(aToken.balanceOf(address(adapter)), 150);
        assertEq(adapter.totalATokens(), 100);
        assertEq(adapter.totalAssets(), 100);
    }

    function test_AllocateAndDeallocateReturnZeroForZeroAmount() public {
        vm.startPrank(delegator);
        assertEq(adapter.allocate(0), 0);
        assertEq(adapter.deallocate(0), 0);
        vm.stopPrank();
    }

    function test_AllocateReturnsZeroWhenSupplyReverts() public {
        assetToken.transfer(address(adapter), 100);
        pool.setRevertOnSupply(true);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 0);
        assertEq(aToken.balanceOf(address(adapter)), 0);
        assertEq(assetToken.balanceOf(address(adapter)), 100);
    }

    function test_DeallocateReturnsZeroWhenWithdrawRevertsOrNoLiquidity() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        pool.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        pool.setRevertOnWithdraw(false);
        pool.setVirtualUnderlyingBalance(0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_OnlyDelegatorCanMoveAssets() public {
        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }

    function _initData() internal pure returns (bytes memory) {
        return "";
    }
}

contract AaveV3AdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract AaveV3AdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}
