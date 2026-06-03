// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {ERC4626Adapter} from "../../src/contracts/adapters/ERC4626Adapter.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IERC4626Adapter} from "../../src/interfaces/adapters/IERC4626Adapter.sol";
import {ICoWSwapConverter} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";

import {Token} from "../mocks/Token.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC4626AdapterTest is Test {
    ERC4626AdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    Token internal assetToken;
    ERC4626AdapterVaultMock internal vault;
    ERC4626VaultMock internal erc4626Vault;
    IERC4626Adapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");
    address internal rewards = makeAddr("rewards");
    address internal settlement = makeAddr("settlement");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vaultFactory = new ERC4626AdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        assetToken = new Token("Asset");
        vault = new ERC4626AdapterVaultMock(address(assetToken), delegator);
        erc4626Vault = new ERC4626VaultMock(address(assetToken));
        vaultFactory.add(address(vault));

        ERC4626Adapter implementation =
            new ERC4626Adapter(address(vaultFactory), address(factory), rewards, settlement, relayer);
        factory.whitelist(address(implementation));

        adapter = _createAdapter(address(erc4626Vault));
    }

    function test_InitializeSetsERC4626Vault() public {
        assertEq(adapter.erc4626Vault(), address(erc4626Vault));
        assertEq(adapter.allocatable(), type(uint256).max);
        assertEq(adapter.totalAssets(), 0);
    }

    function test_ModulesExposeConverterAndMerklConfiguration() public view {
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_SETTLEMENT(), settlement);
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_VAULT_RELAYER(), relayer);
        assertEq(IMerklClaimer(address(adapter)).MERKL_DISTRIBUTOR(), rewards);
        assertEq(ERC4626Adapter(address(adapter)).owner(), curator);
        assertTrue(ERC4626Adapter(address(adapter)).isConverter(curator));
    }

    function test_ConvertRejectsERC4626VaultInput() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        ICoWSwapConverter(address(adapter)).convert(address(erc4626Vault), 1, address(assetToken), "");
    }

    function test_InitializeValidatesERC4626VaultShape() public {
        vm.expectRevert(IERC4626Adapter.InvalidERC4626Vault.selector);
        _createAdapter(address(0));

        ERC4626VaultMock wrongAssetVault = new ERC4626VaultMock(address(new Token("Wrong")));

        vm.expectRevert(IERC4626Adapter.InvalidERC4626Vault.selector);
        _createAdapter(address(wrongAssetVault));
    }

    function test_AllocateAndDeallocateThroughERC4626Vault() public {
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(erc4626Vault.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalAssets(), 100);

        erc4626Vault.setMaxWithdrawAmount(40);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(70);

        assertEq(deallocated, 40);
        assertEq(assetToken.balanceOf(address(adapter)), 40);
        assertEq(adapter.freeAssets(), 40);
        assertEq(adapter.totalAssets(), 100);

        vm.prank(address(vault));
        assetToken.transferFrom(address(adapter), address(vault), deallocated);

        assertEq(adapter.freeAssets(), 0);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_AllocateReturnsZeroWhenDepositFailsOrMintsNoShares() public {
        assetToken.transfer(address(adapter), 100);
        erc4626Vault.setRevertOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        erc4626Vault.setRevertOnDeposit(false);
        erc4626Vault.setZeroSharesOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        assertEq(erc4626Vault.balanceOf(address(adapter)), 0);
        assertEq(assetToken.balanceOf(address(adapter)), 100);
    }

    function test_DeallocateReturnsZeroForZeroAmountNoLiquidityAndWithdrawFailure() public {
        vm.prank(delegator);
        assertEq(adapter.deallocate(0), 0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        erc4626Vault.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_DepositHelperAndOnlyDelegatorGuards() public {
        vm.expectRevert(IERC4626Adapter.NotSelf.selector);
        ERC4626Adapter(address(adapter)).deposit(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }

    function _createAdapter(address targetERC4626Vault) internal returns (IERC4626Adapter) {
        address[] memory converters = new address[](1);
        converters[0] = curator;
        return IERC4626Adapter(
            factory.create(
                1,
                curator,
                abi.encode(
                    address(vault),
                    abi.encode(IERC4626Adapter.InitParams({converters: converters, erc4626Vault: targetERC4626Vault}))
                )
            )
        );
    }
}

contract ERC4626AdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract ERC4626AdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}

contract ERC4626VaultMock is ERC20 {
    address public immutable asset;
    bool public revertOnDeposit;
    bool public revertOnWithdraw;
    bool public zeroSharesOnDeposit;
    uint256 public maxWithdrawAmount = type(uint256).max;

    constructor(address asset_) ERC20("ERC4626 Vault", "evTKN") {
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
