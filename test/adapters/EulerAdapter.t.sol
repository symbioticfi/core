// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {EulerAdapter} from "../../src/contracts/adapters/EulerAdapter.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IEulerAdapter} from "../../src/interfaces/adapters/IEulerAdapter.sol";
import {ICoWSwapConverter} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";

import {Token} from "../mocks/Token.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EulerAdapterTest is Test {
    EulerAdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    EulerLendVaultFactoryMock internal lendVaultFactory;
    Token internal assetToken;
    EulerAdapterVaultMock internal vault;
    EulerLendVaultMock internal lendVault;
    IEulerAdapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");
    address internal rewards = makeAddr("rewards");
    address internal settlement = makeAddr("settlement");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vaultFactory = new EulerAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        lendVaultFactory = new EulerLendVaultFactoryMock();
        assetToken = new Token("Asset");
        vault = new EulerAdapterVaultMock(address(assetToken), delegator);
        lendVault = new EulerLendVaultMock(address(assetToken));
        vaultFactory.add(address(vault));
        lendVaultFactory.setProxy(address(lendVault), true);

        vm.mockCall(settlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(relayer));
        EulerAdapter implementation =
            new EulerAdapter(address(vaultFactory), address(factory), rewards, settlement, address(lendVaultFactory));
        factory.whitelist(address(implementation));

        adapter = _createAdapter(address(lendVault));
    }

    function test_InitializeSetsEulerLendVault() public view {
        assertEq(adapter.lendVault(), address(lendVault));
        assertEq(adapter.allocatable(), type(uint256).max);
        assertEq(adapter.totalShares(), 0);
        assertEq(adapter.totalAssets(), 0);
    }

    function test_ModulesExposeConverterAndMerklConfiguration() public view {
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_SETTLEMENT(), settlement);
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_VAULT_RELAYER(), relayer);
        assertEq(IMerklClaimer(address(adapter)).MERKL_DISTRIBUTOR(), rewards);
        assertEq(EulerAdapter(address(adapter)).owner(), curator);
        assertEq(ICoWSwapConverter(address(adapter)).converters(0), curator);
    }

    function test_ConvertRejectsEulerLendVaultInput() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        ICoWSwapConverter(address(adapter)).convert(address(lendVault), 1, address(assetToken), "");
    }

    function test_InitializeValidatesEulerLendVaultShape() public {
        vm.expectRevert(IEulerAdapter.InvalidEulerLendVault.selector);
        _createAdapter(address(0));

        EulerLendVaultMock unregisteredVault = new EulerLendVaultMock(address(assetToken));
        vm.expectRevert(IEulerAdapter.InvalidEulerLendVault.selector);
        _createAdapter(address(unregisteredVault));

        EulerLendVaultMock wrongAssetVault = new EulerLendVaultMock(address(new Token("Wrong")));
        lendVaultFactory.setProxy(address(wrongAssetVault), true);

        vm.expectRevert(IEulerAdapter.InvalidEulerLendVault.selector);
        _createAdapter(address(wrongAssetVault));
    }

    function test_AllocateAndDeallocateThroughEulerLendVault() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(lendVault.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalShares(), 100);
        assertEq(adapter.totalAssets(), 100);

        lendVault.setMaxWithdrawAmount(40);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(70);

        assertEq(deallocated, 40);
        assertEq(assetToken.balanceOf(address(adapter)), 40);
        assertEq(lendVault.balanceOf(address(adapter)), 60);
        assertEq(adapter.totalShares(), 60);
        assertEq(adapter.freeAssets(), 40);
        assertEq(adapter.totalAssets(), 100);

        vm.prank(address(vault));
        assetToken.transferFrom(address(adapter), address(vault), deallocated);

        assertEq(adapter.freeAssets(), 0);
        assertEq(adapter.totalShares(), 60);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_DirectEulerLendShareDonationDoesNotChangeManagedSharesOrAssets() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        assetToken.approve(address(lendVault), 50);
        lendVault.deposit(50, address(this));
        lendVault.transfer(address(adapter), 50);

        assertEq(lendVault.balanceOf(address(adapter)), 150);
        assertEq(adapter.totalShares(), 100);
        assertEq(adapter.totalAssets(), 100);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(150);

        assertEq(deallocated, 100);
        assertEq(adapter.totalShares(), 0);
        assertEq(lendVault.balanceOf(address(adapter)), 50);
        assertEq(adapter.totalAssets(), 100);
    }

    function test_TotalAssetsTracksManagedSharePriceIncrease() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        assetToken.transfer(address(lendVault), 25);

        assertEq(adapter.totalShares(), 100);
        assertEq(adapter.totalAssets(), 125);
    }

    function test_AllocateReturnsZeroWhenDepositFailsOrMintsNoShares() public {
        assetToken.transfer(address(adapter), 100);
        lendVault.setRevertOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        lendVault.setRevertOnDeposit(false);
        lendVault.setZeroSharesOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        assertEq(lendVault.balanceOf(address(adapter)), 0);
        assertEq(assetToken.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalShares(), 0);
    }

    function test_DeallocateReturnsZeroForZeroAmountNoLiquidityAndWithdrawFailure() public {
        vm.prank(delegator);
        assertEq(adapter.deallocate(0), 0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        lendVault.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        lendVault.setRevertOnWithdraw(false);
        lendVault.setMaxWithdrawAmount(0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_LendHelperAndOnlyDelegatorGuards() public {
        vm.expectRevert(IEulerAdapter.NotSelf.selector);
        EulerAdapter(address(adapter)).deposit(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }

    function test_MulticallBubblesLendReverts() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(EulerAdapter.deposit, (1));

        vm.expectRevert(IEulerAdapter.NotSelf.selector);
        adapter.multicall(calls);
    }

    function _createAdapter(address targetLendVault) internal returns (IEulerAdapter) {
        address[] memory converters = new address[](1);
        converters[0] = curator;
        return IEulerAdapter(
            factory.create(
                1,
                curator,
                abi.encode(
                    address(vault),
                    abi.encode(IEulerAdapter.InitParams({lendVault: targetLendVault, converters: converters}))
                )
            )
        );
    }
}

contract EulerAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract EulerAdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}

contract EulerLendVaultFactoryMock {
    mapping(address proxy => bool status) public isProxy;

    function setProxy(address proxy, bool status) external {
        isProxy[proxy] = status;
    }
}

contract EulerLendVaultMock is ERC20 {
    address public immutable asset;
    bool public revertOnDeposit;
    bool public revertOnWithdraw;
    bool public zeroSharesOnDeposit;
    uint256 public maxWithdrawAmount = type(uint256).max;

    constructor(address asset_) ERC20("Euler Lend Vault", "eTKN") {
        asset = asset_;
    }

    function setMaxWithdrawAmount(uint256 maxWithdrawAmount_) external {
        maxWithdrawAmount = maxWithdrawAmount_;
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
        if (assets > maxWithdraw(owner)) {
            revert("Too much");
        }

        uint256 totalAssets_ = IERC20(asset).balanceOf(address(this));
        shares = totalAssets_ == 0 || totalSupply() == 0 ? 0 : assets * totalSupply() / totalAssets_;

        _burn(owner, shares);
        IERC20(asset).transfer(receiver, assets);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return shares * IERC20(asset).balanceOf(address(this)) / totalSupply();
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        uint256 assets = previewRedeem(balanceOf(owner));
        return assets < maxWithdrawAmount ? assets : maxWithdrawAmount;
    }
}
