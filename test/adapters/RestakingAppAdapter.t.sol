// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {RestakingAppAdapter} from "../../src/contracts/adapters/RestakingAppAdapter.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {IRestakingAppAdapter} from "../../src/interfaces/adapters/IRestakingAppAdapter.sol";
import {MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {Token} from "../mocks/Token.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RestakingAppAdapterTest is Test {
    using Subnetwork for address;

    RestakingAppAdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    RestakingAppAdapterVaultMock internal vault;
    RestakingAppAdapterDelegatorMock internal delegator;
    RestakingAppAdapterNetworkMiddlewareServiceMock internal networkMiddlewareService;
    Token internal baseAsset;
    RestakingTokenMock internal restakingToken;
    IRestakingAppAdapter internal adapter;

    bytes32 internal subnetwork;
    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal curator = makeAddr("curator");
    address internal burner = makeAddr("burner");
    uint48 internal duration = 10;

    function setUp() public {
        vm.warp(100);

        vaultFactory = new RestakingAppAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        delegator = new RestakingAppAdapterDelegatorMock();
        networkMiddlewareService = new RestakingAppAdapterNetworkMiddlewareServiceMock();
        baseAsset = new Token("Base Asset");
        restakingToken = new RestakingTokenMock(IERC20(address(baseAsset)));
        vault = new RestakingAppAdapterVaultMock(address(restakingToken), address(delegator));
        vaultFactory.add(address(vault));
        vaultFactory.add(address(restakingToken));

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        RestakingAppAdapter implementation = new RestakingAppAdapter(
            address(vaultFactory), address(factory), address(0), address(networkMiddlewareService)
        );
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_InitializeStoresBaseAsset() public view {
        assertEq(adapter.asset(), address(baseAsset));
    }

    function test_InitializeAcceptsVaultAssetMatchingBaseAsset() public {
        RestakingAppAdapterVaultMock directVault =
            new RestakingAppAdapterVaultMock(address(baseAsset), address(delegator));
        vaultFactory.add(address(directVault));

        IRestakingAppAdapter directAdapter =
            IRestakingAppAdapter(factory.create(1, curator, _initData(address(directVault), address(baseAsset))));

        assertEq(directAdapter.asset(), address(baseAsset));
    }

    function test_InitializeAcceptsNestedVaultAssetChain() public {
        RestakingTokenMock middleVault = new RestakingTokenMock(IERC20(address(baseAsset)));
        RestakingTokenMock outerVault = new RestakingTokenMock(IERC20(address(middleVault)));
        RestakingAppAdapterVaultMock nestedVault =
            new RestakingAppAdapterVaultMock(address(outerVault), address(delegator));
        vaultFactory.add(address(nestedVault));
        vaultFactory.add(address(middleVault));
        vaultFactory.add(address(outerVault));

        IRestakingAppAdapter nestedAdapter =
            IRestakingAppAdapter(factory.create(1, curator, _initData(address(nestedVault), address(baseAsset))));

        assertEq(nestedAdapter.asset(), address(baseAsset));
    }

    function test_InitializeRejectsUnregisteredNestedVaultAsset() public {
        RestakingTokenMock unregisteredVault = new RestakingTokenMock(IERC20(address(baseAsset)));
        RestakingAppAdapterVaultMock nestedVault =
            new RestakingAppAdapterVaultMock(address(unregisteredVault), address(delegator));
        vaultFactory.add(address(nestedVault));

        vm.expectRevert(IRestakingAppAdapter.InvalidBaseAsset.selector);

        factory.create(1, curator, _initData(address(nestedVault), address(baseAsset)));
    }

    function test_InitializeRejectsAssetFoundAfterMoreThanFiveVaults() public {
        IERC20 curAsset = IERC20(address(baseAsset));
        for (uint256 i; i < 6; ++i) {
            RestakingTokenMock nextVault = new RestakingTokenMock(curAsset);
            vaultFactory.add(address(nextVault));
            curAsset = IERC20(address(nextVault));
        }
        RestakingAppAdapterVaultMock nestedVault =
            new RestakingAppAdapterVaultMock(address(curAsset), address(delegator));
        vaultFactory.add(address(nestedVault));

        vm.expectRevert(IRestakingAppAdapter.InvalidBaseAsset.selector);

        factory.create(1, curator, _initData(address(nestedVault), address(baseAsset)));
    }

    function test_StakeSlashableAndStakeAtUseBaseAssetValue() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        uint256 expectedStake = restakingToken.previewRedeem(100);

        assertEq(adapter.stake(), expectedStake);
        assertEq(adapter.stakeAt(uint48(block.timestamp)), expectedStake);
        assertEq(adapter.slashable(), expectedStake);
    }

    function test_StakeAtUsesCurrentVaultAssetWhenVaultAssetChanges() public {
        _allocateRestakingShares(100);
        uint48 timestamp = uint48(block.timestamp);

        RestakingTokenMock newRestakingToken = new RestakingTokenMock(IERC20(address(baseAsset)));
        vaultFactory.add(address(newRestakingToken));
        vault.setAsset(address(newRestakingToken));

        assertEq(adapter.stakeAt(timestamp), newRestakingToken.previewRedeem(100));
    }

    function test_StakeSlashableAndStakeAtUseNestedBaseAssetValue() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();

        _allocateNestedShares(nestedAdapter, outerVault, middleVault, 100);
        baseAsset.transfer(address(middleVault), 100);

        uint256 expectedStake = middleVault.previewRedeem(outerVault.previewRedeem(100));

        assertEq(nestedAdapter.stake(), expectedStake);
        assertEq(nestedAdapter.stakeAt(uint48(block.timestamp)), expectedStake);
        assertEq(nestedAdapter.slashable(), expectedStake);
    }

    function test_RewardDepositsBaseAssetIntoVaultAssetForVault() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        address rewarder = makeAddr("rewarder");
        baseAsset.transfer(rewarder, 40);
        uint256 expectedShares = restakingToken.previewDeposit(40);

        vm.startPrank(rewarder);
        baseAsset.approve(address(adapter), 40);
        adapter.reward(address(baseAsset), 40);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(rewarder), 0);
        assertEq(restakingToken.balanceOf(address(vault)), expectedShares);
    }

    function test_RewardDepositsBaseAssetThroughNestedVaultsForVault() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();

        address rewarder = makeAddr("rewarder");
        baseAsset.transfer(rewarder, 40);
        uint256 middleShares = middleVault.previewDeposit(40);
        uint256 outerShares = outerVault.previewDeposit(middleShares);

        vm.startPrank(rewarder);
        baseAsset.approve(address(nestedAdapter), 40);
        nestedAdapter.reward(address(baseAsset), 40);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(rewarder), 0);
        assertEq(middleVault.balanceOf(address(outerVault)), middleShares);
        assertEq(outerVault.balanceOf(address(nestedAdapter.vault())), outerShares);
    }

    function test_SlashBurnsVaultAssetAndAccountsInVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);
        uint256 expectedSlashedShares = restakingToken.previewWithdraw(40);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(40);

        vm.prank(networkMiddleware);
        uint256 slashedAmount = adapter.slash(40);

        assertEq(slashedAmount, 40);
        assertEq(baseAsset.balanceOf(burner), 0);
        assertEq(restakingToken.balanceOf(burner), 40);
        assertEq(restakingToken.balanceOf(address(adapter)), 100 - expectedSlashedShares - 40);
        assertEq(adapter.stake(), restakingToken.previewRedeem(100 - expectedSlashedShares));
        assertEq(adapter.slashable(), restakingToken.previewRedeem(100 - expectedSlashedShares));
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedSlashedShares);
        assertEq(delegator.lastDecreaseShare(), MAX_SHARE);
    }

    function test_SlashWithdrawsThroughNestedVaultsAndBurnsVaultAsset() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();
        _allocateNestedShares(nestedAdapter, outerVault, middleVault, 100);
        baseAsset.transfer(address(middleVault), 100);

        uint256 expectedMiddleShares = middleVault.previewWithdraw(40);
        uint256 expectedOuterShares = outerVault.previewWithdraw(expectedMiddleShares);

        vm.expectEmit(true, true, true, true, address(nestedAdapter));
        emit IAppAdapter.Slash(40);

        vm.prank(networkMiddleware);
        uint256 slashedAmount = nestedAdapter.slash(40);

        assertEq(slashedAmount, 40);
        assertEq(baseAsset.balanceOf(burner), 0);
        assertEq(outerVault.balanceOf(burner), 40);
        assertEq(middleVault.balanceOf(burner), 0);
        assertEq(outerVault.balanceOf(address(nestedAdapter)), 100 - expectedOuterShares - 40);
        assertEq(nestedAdapter.stake(), middleVault.previewRedeem(outerVault.previewRedeem(100 - expectedOuterShares)));
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedOuterShares);
        assertEq(delegator.lastDecreaseShare(), MAX_SHARE);
    }

    function _allocateRestakingShares(uint256 amount) internal {
        baseAsset.approve(address(restakingToken), amount);
        uint256 shares = restakingToken.deposit(amount, address(this));
        restakingToken.transfer(address(adapter), shares);

        delegator.allocate(address(adapter), shares);
    }

    function _allocateNestedShares(
        IRestakingAppAdapter targetAdapter,
        RestakingTokenMock outerVault,
        RestakingTokenMock middleVault,
        uint256 amount
    ) internal {
        baseAsset.approve(address(middleVault), amount);
        uint256 middleShares = middleVault.deposit(amount, address(this));
        middleVault.approve(address(outerVault), middleShares);
        uint256 outerShares = outerVault.deposit(middleShares, address(this));
        outerVault.transfer(address(targetAdapter), outerShares);

        delegator.allocate(address(targetAdapter), outerShares);
    }

    function _createNestedAdapter()
        internal
        returns (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault)
    {
        middleVault = new RestakingTokenMock(IERC20(address(baseAsset)));
        outerVault = new RestakingTokenMock(IERC20(address(middleVault)));
        RestakingAppAdapterVaultMock nestedVault =
            new RestakingAppAdapterVaultMock(address(outerVault), address(delegator));
        vaultFactory.add(address(nestedVault));
        vaultFactory.add(address(middleVault));
        vaultFactory.add(address(outerVault));

        nestedAdapter =
            IRestakingAppAdapter(factory.create(1, curator, _initData(address(nestedVault), address(baseAsset))));
    }

    function _createAdapter() internal returns (IRestakingAppAdapter) {
        return IRestakingAppAdapter(factory.create(1, curator, _initData()));
    }

    function _initData() internal view returns (bytes memory) {
        return _initData(address(vault), address(baseAsset));
    }

    function _initData(address initVault, address initBaseAsset) internal view returns (bytes memory) {
        return abi.encode(
            initVault,
            abi.encode(
                IRestakingAppAdapter.RestakingInitParams({
                    asset: initBaseAsset,
                    initParams: IAppAdapter.InitParams({
                        subnetwork: subnetwork, operator: operator, duration: duration, burner: burner
                    })
                })
            )
        );
    }
}

contract RestakingTokenMock is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 internal immutable _asset;

    constructor(IERC20 asset_) ERC20("Restaking Token", "rstTKN") {
        _asset = asset_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets * supply / totalAssets();
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares * totalAssets() / supply;
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets(), Math.Rounding.Ceil);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }
}

contract RestakingAppAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract RestakingAppAdapterDelegatorMock {
    uint256 public decreaseLimitsCalls;
    uint256 public lastDecreaseAssets;
    uint256 public lastDecreaseShare;

    function allocate(address adapter, uint256 amount) external {
        IAdapter(adapter).allocate(amount);
    }

    function limitOf(address adapter) external view returns (uint256) {
        return IAdapter(adapter).totalAssets();
    }

    function decreaseLimits(uint256 assets, uint256 share) external {
        ++decreaseLimitsCalls;
        lastDecreaseAssets = assets;
        lastDecreaseShare = share;
    }
}

contract RestakingAppAdapterNetworkMiddlewareServiceMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract RestakingAppAdapterVaultMock {
    address public collateral;
    address public delegator;

    constructor(address collateral_, address delegator_) {
        collateral = collateral_;
        delegator = delegator_;
    }

    function setAsset(address collateral_) external {
        collateral = collateral_;
    }

    function asset() external view returns (address) {
        return collateral;
    }
}
