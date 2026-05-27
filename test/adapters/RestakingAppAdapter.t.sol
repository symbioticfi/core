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

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        RestakingAppAdapter implementation = new RestakingAppAdapter(
            address(vaultFactory), address(factory), address(0), address(networkMiddlewareService)
        );
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_InitializeStoresBaseAsset() public view {
        assertEq(adapter.baseAsset(), address(baseAsset));
    }

    function test_StakeSlashableAndStakeAtUseBaseAssetValue() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        uint256 expectedStake = restakingToken.previewRedeem(100);

        assertEq(adapter.stake(), expectedStake);
        assertEq(adapter.stakeAt(uint48(block.timestamp)), expectedStake);
        assertEq(adapter.slashable(), expectedStake);
    }

    function test_RewardDepositsBaseAssetIntoVaultAssetForVault() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        address rewarder = makeAddr("rewarder");
        baseAsset.transfer(rewarder, 40);
        uint256 expectedShares = restakingToken.previewDeposit(40);

        vm.startPrank(rewarder);
        baseAsset.approve(address(adapter), 40);
        adapter.reward(40);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(rewarder), 0);
        assertEq(restakingToken.balanceOf(address(vault)), expectedShares);
    }

    function test_SlashBurnsBaseAssetAndAccountsInVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);
        uint256 expectedSlashedShares = restakingToken.previewWithdraw(40);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(40);

        vm.prank(networkMiddleware);
        uint256 slashedAmount = adapter.slash(40);

        assertEq(slashedAmount, 40);
        assertEq(baseAsset.balanceOf(burner), 40);
        assertEq(restakingToken.balanceOf(address(adapter)), 100 - expectedSlashedShares);
        assertEq(adapter.stake(), restakingToken.previewRedeem(100 - expectedSlashedShares));
        assertEq(adapter.slashable(), restakingToken.previewRedeem(100 - expectedSlashedShares));
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedSlashedShares);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function _allocateRestakingShares(uint256 assets) internal {
        baseAsset.approve(address(restakingToken), assets);
        uint256 shares = restakingToken.deposit(assets, address(this));
        restakingToken.transfer(address(adapter), shares);

        delegator.allocate(address(adapter), shares);
    }

    function _createAdapter() internal returns (IRestakingAppAdapter) {
        return IRestakingAppAdapter(factory.create(1, curator, _initData()));
    }

    function _initData() internal view returns (bytes memory) {
        return abi.encode(
            address(vault),
            abi.encode(
                IRestakingAppAdapter.RestakingInitParams({
                    baseAsset: address(baseAsset),
                    subnetwork: subnetwork,
                    operator: operator,
                    duration: duration,
                    burner: burner
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
    address public immutable collateral;
    address public delegator;

    constructor(address collateral_, address delegator_) {
        collateral = collateral_;
        delegator = delegator_;
    }

    function asset() external view returns (address) {
        return collateral;
    }
}
