// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMorphoVaultV2} from "../../src/interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";

import {Token} from "../mocks/Token.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MorphoVaultV2AdapterTest is Test {
    MorphoAdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    MorphoCuratorRegistryMock internal curatorRegistry;
    MorphoVaultFactoryMock internal morphoVaultFactory;
    Token internal collateral;
    MorphoAdapterVaultMock internal vault;
    MorphoVaultMock internal morphoVault;
    IMorphoVaultV2Adapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");
    address internal morphoAdapterRegistry = makeAddr("morphoAdapterRegistry");

    function setUp() public {
        vaultFactory = new MorphoAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        curatorRegistry = new MorphoCuratorRegistryMock();
        morphoVaultFactory = new MorphoVaultFactoryMock();
        collateral = new Token("Collateral");
        vault = new MorphoAdapterVaultMock(address(collateral), delegator);
        morphoVault = new MorphoVaultMock(address(collateral), morphoAdapterRegistry);
        vaultFactory.add(address(vault));
        curatorRegistry.setCurator(address(vault), curator);
        morphoVaultFactory.setVault(address(morphoVault), true);

        MorphoVaultV2Adapter implementation = new MorphoVaultV2Adapter(
            address(vaultFactory),
            address(factory),
            address(curatorRegistry),
            address(morphoVaultFactory),
            morphoAdapterRegistry
        );
        factory.whitelist(address(implementation));

        adapter = IMorphoVaultV2Adapter(factory.create(1, curator, abi.encode(address(vault), "")));
    }

    function test_ViewsReturnZeroBeforeMorphoVaultIsSet() public {
        assertEq(adapter.morphoVault(), address(0));
        assertEq(adapter.allocatable(), 0);
        assertEq(adapter.deallocatable(), 0);
        assertEq(adapter.totalAssets(), 0);
    }

    function test_SetMorphoVaultValidatesCuratorAndVaultShape() public {
        vm.expectRevert(IAdapter.NotCurator.selector);
        adapter.setMorphoVault(address(morphoVault));

        vm.startPrank(curator);

        morphoVaultFactory.setVault(address(morphoVault), false);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        adapter.setMorphoVault(address(morphoVault));

        morphoVaultFactory.setVault(address(morphoVault), true);
        morphoVault.setAdapterRegistry(address(0xBEEF));
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        adapter.setMorphoVault(address(morphoVault));

        morphoVault.setAdapterRegistry(morphoAdapterRegistry);
        morphoVault.setAbdicated(false);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        adapter.setMorphoVault(address(morphoVault));

        morphoVault.setAbdicated(true);
        MorphoVaultMock wrongAssetVault = new MorphoVaultMock(address(new Token("Wrong")), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(wrongAssetVault), true);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        adapter.setMorphoVault(address(wrongAssetVault));

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IMorphoVaultV2Adapter.SetMorphoVault(address(morphoVault));
        adapter.setMorphoVault(address(morphoVault));

        assertEq(adapter.morphoVault(), address(morphoVault));
        assertEq(adapter.allocatable(), type(uint256).max);
        vm.stopPrank();
    }

    function test_AllocateAndDeallocateThroughMorphoVault() public {
        _setMorphoVault();
        MorphoLiquidityAdapterMock liquidityAdapter = new MorphoLiquidityAdapterMock();
        liquidityAdapter.setRealAssets(25);
        morphoVault.setLiquidityAdapter(address(liquidityAdapter));
        collateral.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(morphoVault.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.deallocatable(), 100);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(40);

        assertEq(deallocated, 40);
        assertEq(collateral.balanceOf(address(adapter)), 40);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_AllocateReturnsZeroWhenDepositFailsOrMintsNoShares() public {
        _setMorphoVault();

        collateral.transfer(address(adapter), 100);
        morphoVault.setRevertOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        morphoVault.setRevertOnDeposit(false);
        morphoVault.setZeroSharesOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        assertEq(morphoVault.balanceOf(address(adapter)), 0);
        assertEq(collateral.balanceOf(address(adapter)), 100);
    }

    function test_DeallocateReturnsZeroForZeroAmountNoLiquidityAndWithdrawFailure() public {
        _setMorphoVault();

        vm.prank(delegator);
        assertEq(adapter.deallocate(0), 0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        collateral.transfer(address(adapter), 100);
        vm.prank(delegator);
        adapter.allocate(100);

        morphoVault.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_SetMorphoVaultRevertsWhenExistingPositionIsActiveAndCanResetAfterExit() public {
        _setMorphoVault();
        collateral.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        vm.prank(curator);
        vm.expectRevert(IMorphoVaultV2Adapter.ActivePosition.selector);
        adapter.setMorphoVault(address(0));

        vm.prank(delegator);
        adapter.deallocate(100);

        vm.prank(curator);
        adapter.setMorphoVault(address(0));

        assertEq(adapter.morphoVault(), address(0));
    }

    function test_DepositHelperAndOnlyDelegatorGuards() public {
        _setMorphoVault();

        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        MorphoVaultV2Adapter(address(adapter)).deposit(address(morphoVault), 1, address(adapter));

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }

    function test_MulticallCanSetMorphoVaultAndBubbleReverts() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IMorphoVaultV2Adapter.setMorphoVault, (address(morphoVault)));

        vm.prank(curator);
        adapter.multicall(calls);

        assertEq(adapter.morphoVault(), address(morphoVault));

        calls[0] = abi.encodeCall(MorphoVaultV2Adapter.deposit, (address(morphoVault), 1, address(adapter)));

        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        adapter.multicall(calls);
    }

    function _setMorphoVault() internal {
        vm.prank(curator);
        adapter.setMorphoVault(address(morphoVault));
    }
}

contract MorphoAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MorphoCuratorRegistryMock {
    mapping(address vault => address curator) public curatorOf;

    function setCurator(address vault, address curator) external {
        curatorOf[vault] = curator;
    }

    function getCurator(address vault) external view returns (address) {
        return curatorOf[vault];
    }
}

contract MorphoVaultFactoryMock {
    mapping(address vault => bool status) public isVaultV2;

    function setVault(address vault, bool status) external {
        isVaultV2[vault] = status;
    }
}

contract MorphoAdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}

contract MorphoLiquidityAdapterMock {
    uint256 public realAssets;

    function setRealAssets(uint256 realAssets_) external {
        realAssets = realAssets_;
    }
}

contract MorphoVaultMock is ERC20 {
    address public immutable asset;
    address public adapterRegistry;
    address public liquidityAdapter;
    bool public abdicatedStatus = true;
    bool public revertOnDeposit;
    bool public revertOnWithdraw;
    bool public zeroSharesOnDeposit;

    constructor(address asset_, address adapterRegistry_) ERC20("Morpho Vault", "mvTKN") {
        asset = asset_;
        adapterRegistry = adapterRegistry_;
    }

    function setAdapterRegistry(address adapterRegistry_) external {
        adapterRegistry = adapterRegistry_;
    }

    function setLiquidityAdapter(address liquidityAdapter_) external {
        liquidityAdapter = liquidityAdapter_;
    }

    function setAbdicated(bool status) external {
        abdicatedStatus = status;
    }

    function setRevertOnDeposit(bool status) external {
        revertOnDeposit = status;
    }

    function setRevertOnWithdraw(bool status) external {
        revertOnWithdraw = status;
    }

    function setZeroSharesOnDeposit(bool status) external {
        zeroSharesOnDeposit = status;
    }

    function abdicated(bytes4) external view returns (bool) {
        return abdicatedStatus;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (revertOnDeposit) {
            revert("Deposit failed");
        }

        uint256 totalAssetsBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transferFrom(msg.sender, address(this), assets);
        if (zeroSharesOnDeposit) {
            return 0;
        }

        shares = totalSupply() == 0 || totalAssetsBefore == 0 ? assets : assets * totalSupply() / totalAssetsBefore;
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (revertOnWithdraw) {
            revert("Withdraw failed");
        }

        uint256 totalAssets_ = IERC20(asset).balanceOf(address(this));
        shares = totalAssets_ == 0 || totalSupply() == 0 ? 0 : assets * totalSupply() / totalAssets_;
        if (shares > balanceOf(owner)) {
            shares = balanceOf(owner);
            assets = shares * totalAssets_ / totalSupply();
        }

        _burn(owner, shares);
        IERC20(asset).transfer(receiver, assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return shares * IERC20(asset).balanceOf(address(this)) / totalSupply();
    }
}
