// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMorphoVaultV2} from "../../src/interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {ICoWSwapConverter} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";

import {Token} from "../mocks/Token.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MorphoVaultV2AdapterTest is Test {
    MorphoAdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    MorphoVaultFactoryMock internal morphoVaultFactory;
    Token internal assetToken;
    MorphoAdapterVaultMock internal vault;
    MorphoVaultMock internal morphoVault;
    IMorphoVaultV2Adapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");
    address internal morphoAdapterRegistry = makeAddr("morphoAdapterRegistry");
    address internal rewards = makeAddr("rewards");
    address internal settlement = makeAddr("settlement");
    address internal relayer = makeAddr("relayer");

    function setUp() public {
        vaultFactory = new MorphoAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        morphoVaultFactory = new MorphoVaultFactoryMock();
        assetToken = new Token("Asset");
        vault = new MorphoAdapterVaultMock(address(assetToken), delegator);
        morphoVault = new MorphoVaultMock(address(assetToken), morphoAdapterRegistry);
        vaultFactory.add(address(vault));
        morphoVaultFactory.setVault(address(morphoVault), true);

        MorphoVaultV2Adapter implementation = new MorphoVaultV2Adapter(
            address(vaultFactory),
            address(factory),
            rewards,
            settlement,
            address(morphoVaultFactory),
            relayer,
            morphoAdapterRegistry
        );
        factory.whitelist(address(implementation));

        adapter = _createAdapter(address(morphoVault));
    }

    function test_InitializeSetsMorphoVault() public {
        assertEq(adapter.morphoVault(), address(morphoVault));
        assertEq(adapter.allocatable(), type(uint256).max);
        assertEq(adapter.totalAssets(), 0);
    }

    function test_ModulesExposeConverterAndMerklConfiguration() public view {
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_SETTLEMENT(), settlement);
        assertEq(ICoWSwapConverter(address(adapter)).COW_SWAP_VAULT_RELAYER(), relayer);
        assertEq(IMerklClaimer(address(adapter)).MERKL_DISTRIBUTOR(), rewards);
        assertEq(MorphoVaultV2Adapter(address(adapter)).owner(), curator);
        assertTrue(MorphoVaultV2Adapter(address(adapter)).isConverter(curator));
    }

    function test_ConvertRejectsMorphoVaultInput() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        ICoWSwapConverter(address(adapter)).convert(address(morphoVault), 1, address(assetToken), "");
    }

    function test_InitializeValidatesMorphoVaultShape() public {
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        _createAdapter(address(0));

        morphoVaultFactory.setVault(address(morphoVault), false);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        _createAdapter(address(morphoVault));

        morphoVaultFactory.setVault(address(morphoVault), true);
        morphoVault.setAdapterRegistry(address(0xBEEF));
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        _createAdapter(address(morphoVault));

        morphoVault.setAdapterRegistry(morphoAdapterRegistry);
        morphoVault.setAbdicated(false);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        _createAdapter(address(morphoVault));

        morphoVault.setAbdicated(true);
        MorphoVaultMock wrongAssetVault = new MorphoVaultMock(address(new Token("Wrong")), morphoAdapterRegistry);
        morphoVaultFactory.setVault(address(wrongAssetVault), true);
        vm.expectRevert(IMorphoVaultV2Adapter.InvalidMorphoVault.selector);
        _createAdapter(address(wrongAssetVault));
    }

    function test_AllocateAndDeallocateThroughMorphoVault() public {
        MorphoLiquidityAdapterMock liquidityAdapter = new MorphoLiquidityAdapterMock();
        liquidityAdapter.setRealAssets(25);
        morphoVault.setLiquidityAdapter(address(liquidityAdapter));
        assetToken.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(morphoVault.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalAssets(), 100);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(40);

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
        morphoVault.setRevertOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        morphoVault.setRevertOnDeposit(false);
        morphoVault.setZeroSharesOnDeposit(true);

        vm.prank(delegator);
        assertEq(adapter.allocate(50), 0);

        assertEq(morphoVault.balanceOf(address(adapter)), 0);
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

        morphoVault.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_DepositHelperAndOnlyDelegatorGuards() public {
        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        MorphoVaultV2Adapter(address(adapter)).deposit(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }

    function test_MulticallBubblesDepositReverts() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(MorphoVaultV2Adapter.deposit, (1));

        vm.expectRevert(IMorphoVaultV2Adapter.NotSelf.selector);
        adapter.multicall(calls);
    }

    function _createAdapter(address targetMorphoVault) internal returns (IMorphoVaultV2Adapter) {
        address[] memory converters = new address[](1);
        converters[0] = curator;
        return IMorphoVaultV2Adapter(
            factory.create(
                1,
                curator,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IMorphoVaultV2Adapter.InitParams({morphoVault: targetMorphoVault, converters: converters})
                    )
                )
            )
        );
    }
}

contract MorphoAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
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
