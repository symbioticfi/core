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
import {ICoWSwapConverter, MAX_VALID_TO_DURATION} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
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
    RestakingCoWSwapSettlementMock internal settlement;
    Token internal baseAsset;
    RestakingTokenMock internal restakingToken;
    IRestakingAppAdapter internal adapter;

    bytes32 internal subnetwork;
    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal curator = makeAddr("curator");
    address internal burner = makeAddr("burner");
    address internal relayer = makeAddr("relayer");
    uint48 internal duration = 10;

    function setUp() public {
        vm.warp(100);

        vaultFactory = new RestakingAppAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        delegator = new RestakingAppAdapterDelegatorMock();
        networkMiddlewareService = new RestakingAppAdapterNetworkMiddlewareServiceMock();
        settlement = new RestakingCoWSwapSettlementMock(relayer);
        baseAsset = new Token("Base Asset");
        restakingToken = new RestakingTokenMock(IERC20(address(baseAsset)));
        vault = new RestakingAppAdapterVaultMock(address(restakingToken), address(delegator));
        vaultFactory.add(address(vault));
        vaultFactory.add(address(restakingToken));

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        RestakingAppAdapter implementation = new RestakingAppAdapter(
            address(vaultFactory), address(factory), address(settlement), address(networkMiddlewareService)
        );
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_InitializeStoresBaseAsset() public view {
        assertEq(adapter.asset(), address(baseAsset));
    }

    function test_InitializeRejectsVaultAssetMatchingBaseAsset() public {
        RestakingAppAdapterVaultMock directVault =
            new RestakingAppAdapterVaultMock(address(baseAsset), address(delegator));
        vaultFactory.add(address(directVault));

        vm.expectRevert(IRestakingAppAdapter.NotRestaking.selector);
        factory.create(1, curator, _initData(address(directVault), address(baseAsset)));
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

    function test_FreeAndTotalAssetsUseCurrentVaultAssetShares() public {
        _allocateRestakingShares(100);

        baseAsset.approve(address(restakingToken), 50);
        uint256 freeShares = restakingToken.deposit(50, address(this));
        restakingToken.transfer(address(adapter), freeShares);

        assertEq(adapter.totalAssets(), 150);
        assertEq(adapter.freeAssets(), freeShares);
    }

    function test_InterfaceExposesSyncReward() public {
        baseAsset.transfer(address(adapter), 10);

        adapter.syncReward();

        assertEq(baseAsset.balanceOf(address(adapter)), 0);
        assertEq(restakingToken.balanceOf(address(adapter)), 10);
    }

    function test_StakeAtRevertsBecauseUnsupported() public {
        _allocateRestakingShares(100);

        vm.expectRevert(IRestakingAppAdapter.Unsupported.selector);
        adapter.stakeAt(uint48(vm.getBlockTimestamp()));
    }

    function test_ConvertRejectsVaultAssetInput() public {
        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        adapter.convert(address(restakingToken), 1, address(baseAsset), "");
    }

    function test_ConvertPresignsOrderForNonBaseAssetInput() public {
        Token tokenIn = new Token("Token In");
        tokenIn.transfer(address(adapter), 100);

        vm.prank(curator);
        adapter.convert(address(tokenIn), 100, address(baseAsset), _orderData(90, 1));

        assertEq(settlement.lastOrderUid().length, 56);
        assertTrue(settlement.lastSigned());
        assertEq(tokenIn.allowance(address(adapter), relayer), type(uint256).max);
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

        vm.expectRevert(IRestakingAppAdapter.InvalidAsset.selector);

        factory.create(1, curator, _initData(address(nestedVault), address(baseAsset)));
    }

    function test_StakeSlashableAndStakeAtUseBaseAssetValue() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        uint256 expectedStake = restakingToken.previewRedeem(100);

        assertEq(adapter.stake(), expectedStake);
        vm.expectRevert(IRestakingAppAdapter.Unsupported.selector);
        adapter.stakeAt(uint48(vm.getBlockTimestamp()));
        assertEq(adapter.slashable(), expectedStake);
    }

    function test_StakeAtRejectsWhenCurrentVaultAssetChanges() public {
        _allocateRestakingShares(100);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        RestakingTokenMock newRestakingToken = new RestakingTokenMock(IERC20(address(baseAsset)));
        vaultFactory.add(address(newRestakingToken));
        vault.setAsset(address(newRestakingToken));

        vm.expectRevert(IRestakingAppAdapter.Unsupported.selector);
        adapter.stakeAt(timestamp);
    }

    function test_StakeSlashableAndStakeAtUseNestedBaseAssetValue() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();

        _allocateNestedShares(nestedAdapter, outerVault, middleVault, 100);
        baseAsset.transfer(address(middleVault), 100);

        uint256 expectedStake = middleVault.previewRedeem(outerVault.previewRedeem(100));

        assertEq(nestedAdapter.stake(), expectedStake);
        vm.expectRevert(IRestakingAppAdapter.Unsupported.selector);
        nestedAdapter.stakeAt(uint48(vm.getBlockTimestamp()));
        assertEq(nestedAdapter.slashable(), expectedStake);
    }

    function test_RewardDepositsBaseAssetIntoVaultAssetForVault() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        address rewarder = makeAddr("rewarder");
        baseAsset.transfer(rewarder, 40);
        uint256 adapterSharesBefore = restakingToken.balanceOf(address(adapter));
        uint256 expectedShares = restakingToken.previewDeposit(40);

        vm.startPrank(rewarder);
        baseAsset.approve(address(adapter), 40);
        adapter.reward(address(baseAsset), 40);
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(rewarder), 0);
        assertEq(restakingToken.balanceOf(address(adapter)), adapterSharesBefore + expectedShares);
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
        assertEq(outerVault.balanceOf(address(nestedAdapter)), outerShares);
    }

    function test_SlashBurnsBaseAssetAndAccountsInVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);
        uint256 adapterSharesBefore = restakingToken.balanceOf(address(adapter));
        uint256 expectedSlashedShares = restakingToken.previewWithdraw(40);
        uint256 expectedBurnedAssets = restakingToken.previewRedeem(expectedSlashedShares);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(expectedSlashedShares);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(baseAsset.balanceOf(burner), expectedBurnedAssets);
        assertEq(restakingToken.balanceOf(burner), 0);
        assertEq(restakingToken.balanceOf(address(adapter)), adapterSharesBefore - expectedSlashedShares);
        assertEq(adapter.stake(), restakingToken.previewRedeem(adapterSharesBefore - expectedSlashedShares));
        assertEq(adapter.slashable(), restakingToken.previewRedeem(adapterSharesBefore - expectedSlashedShares));
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedSlashedShares);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_SlashRoundsUpToAvoidUnderSlashingBaseAmount() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 200);
        uint256 expectedSlashedShares = restakingToken.previewWithdraw(10);
        uint256 expectedBurnedAssets = restakingToken.previewRedeem(expectedSlashedShares);

        assertGt(expectedSlashedShares, restakingToken.previewDeposit(10));

        vm.prank(networkMiddleware);
        adapter.slash(10);

        assertGe(baseAsset.balanceOf(burner), 10);
        assertEq(baseAsset.balanceOf(burner), expectedBurnedAssets);
    }

    function test_SlashSaturatesUsingVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(100);

        vm.prank(networkMiddleware);
        adapter.slash(250);

        assertEq(baseAsset.balanceOf(burner), 200);
        assertEq(restakingToken.balanceOf(address(adapter)), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.freeAssets(), 0);
        assertEq(delegator.lastDecreaseAssets(), 100);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseUsesBaseAssetAmountAndAccountsInVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        uint256 expectedReleasedShares = restakingToken.previewDeposit(40);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Release(expectedReleasedShares);

        vm.prank(network);
        adapter.release(40);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), restakingToken.previewRedeem(100 - expectedReleasedShares));
        assertEq(adapter.stake(), restakingToken.previewRedeem(100 - expectedReleasedShares));
        assertEq(adapter.freeAssets(), expectedReleasedShares);
        assertEq(baseAsset.balanceOf(burner), 0);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedReleasedShares);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseClearsSlashableInVaultAssetShares() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Release(100);

        vm.prank(network);
        adapter.release(200);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.freeAssets(), 100);
        assertEq(baseAsset.balanceOf(burner), 0);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 100);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_SlashWithdrawsThroughNestedVaultsAndBurnsBaseAsset() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();
        _allocateNestedShares(nestedAdapter, outerVault, middleVault, 100);
        baseAsset.transfer(address(middleVault), 100);

        uint256 adapterSharesBefore = outerVault.balanceOf(address(nestedAdapter));
        uint256 expectedMiddleShares = middleVault.previewWithdraw(40);
        uint256 expectedOuterShares = outerVault.previewWithdraw(expectedMiddleShares);
        uint256 expectedBurnedAssets = middleVault.previewRedeem(expectedMiddleShares);

        vm.expectEmit(true, true, true, true, address(nestedAdapter));
        emit IAppAdapter.Slash(expectedOuterShares);

        vm.prank(networkMiddleware);
        nestedAdapter.slash(40);

        assertEq(baseAsset.balanceOf(burner), expectedBurnedAssets);
        assertEq(outerVault.balanceOf(burner), 0);
        assertEq(middleVault.balanceOf(burner), 0);
        assertEq(outerVault.balanceOf(address(nestedAdapter)), adapterSharesBefore - expectedOuterShares);
        assertEq(
            nestedAdapter.stake(),
            middleVault.previewRedeem(outerVault.previewRedeem(adapterSharesBefore - expectedOuterShares))
        );
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), expectedOuterShares);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_SyncSlashClaimsDelayedSlashRequest() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);
        restakingToken.withdrawalQueue().setClaimReverts(true);
        uint256 slashedShares = restakingToken.previewWithdraw(40);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(baseAsset.balanceOf(burner), 0);
        assertEq(restakingToken.balanceOf(address(restakingToken.withdrawalQueue())), slashedShares);

        restakingToken.withdrawalQueue().setClaimReverts(false);
        adapter.syncSlash();

        assertEq(baseAsset.balanceOf(burner), 40);
        assertEq(restakingToken.balanceOf(address(restakingToken.withdrawalQueue())), 0);
    }

    function test_SyncSlashKeepsAndCompletesPartiallyClaimedRequest() public {
        _allocateRestakingShares(100);
        baseAsset.transfer(address(restakingToken), 100);
        restakingToken.withdrawalQueue().setMaxClaimShares(10);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(baseAsset.balanceOf(burner), 20);
        assertEq(restakingToken.balanceOf(address(restakingToken.withdrawalQueue())), 10);

        restakingToken.withdrawalQueue().setMaxClaimShares(0);
        adapter.syncSlash();

        assertEq(baseAsset.balanceOf(burner), 20);
        assertEq(restakingToken.balanceOf(address(restakingToken.withdrawalQueue())), 10);

        restakingToken.withdrawalQueue().setMaxClaimShares(type(uint256).max);
        adapter.syncSlash();

        assertEq(baseAsset.balanceOf(burner), 40);
        assertEq(restakingToken.balanceOf(address(restakingToken.withdrawalQueue())), 0);
    }

    function test_SyncSlashMovesDelayedNestedSharesThroughRemainingVaults() public {
        (IRestakingAppAdapter nestedAdapter, RestakingTokenMock outerVault, RestakingTokenMock middleVault) =
            _createNestedAdapter();
        _allocateNestedShares(nestedAdapter, outerVault, middleVault, 100);
        baseAsset.transfer(address(middleVault), 100);
        outerVault.withdrawalQueue().setClaimReverts(true);

        vm.prank(networkMiddleware);
        nestedAdapter.slash(40);

        assertEq(baseAsset.balanceOf(burner), 0);

        outerVault.withdrawalQueue().setClaimReverts(false);
        nestedAdapter.syncSlash();

        assertEq(baseAsset.balanceOf(burner), 40);
        assertEq(outerVault.balanceOf(address(outerVault.withdrawalQueue())), 0);
        assertEq(middleVault.balanceOf(address(middleVault.withdrawalQueue())), 0);
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
        address[] memory converters = new address[](1);
        converters[0] = curator;
        return abi.encode(
            initVault,
            abi.encode(
                IRestakingAppAdapter.RestakingInitParams({
                    asset: initBaseAsset,
                    initParams: IAppAdapter.InitParams({
                        subnetwork: subnetwork,
                        operator: operator,
                        duration: duration,
                        burner: burner,
                        converters: converters
                    })
                })
            )
        );
    }

    function _orderData(uint256 buyAmount, uint256 salt) internal view returns (bytes memory) {
        return abi.encode(
            ICoWSwapConverter.OrderParams({
                buyAmount: buyAmount,
                validTo: uint32(vm.getBlockTimestamp() + MAX_VALID_TO_DURATION),
                appData: bytes32(salt)
            })
        );
    }
}

contract RestakingCoWSwapSettlementMock {
    address public vaultRelayer;
    bytes32 public domainSeparator = keccak256("DOMAIN");
    bytes public lastOrderUid;
    bool public lastSigned;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }

    function setPreSignature(bytes calldata orderUid, bool signed) external {
        lastOrderUid = orderUid;
        lastSigned = signed;
    }
}

contract RestakingTokenMock is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 internal immutable _asset;
    RestakingWithdrawalQueueMock public immutable withdrawalQueue;

    constructor(IERC20 asset_) ERC20("Restaking Token", "rstTKN") {
        _asset = asset_;
        withdrawalQueue = new RestakingWithdrawalQueueMock(address(this), true);
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

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
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

contract RestakingWithdrawalQueueMock {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Request {
        uint256 shares;
        bool claimed;
    }

    address public immutable vault;
    bool internal immutable _redeems;
    uint256 internal _nextTokenId = 1;
    bool public claimReverts;
    uint256 public maxClaimShares = type(uint256).max;
    mapping(uint256 tokenId => Request request) internal _requests;

    constructor(address vault_, bool redeems_) {
        vault = vault_;
        _redeems = redeems_;
    }

    function requestRedeem(uint256 shares, address) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _requests[tokenId].shares = shares;
        if (_redeems) {
            IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);
        }
    }

    function setClaimReverts(bool claimReverts_) external {
        claimReverts = claimReverts_;
    }

    function setMaxClaimShares(uint256 maxClaimShares_) external {
        maxClaimShares = maxClaimShares_;
    }

    function claim(uint256 tokenId, address receiver) external returns (uint256 assets, uint256 shares) {
        if (claimReverts) {
            revert("CLAIM_REVERTS");
        }

        Request storage request = _requests[tokenId];
        shares = request.shares.min(maxClaimShares);
        assets = _redeems ? RestakingTokenMock(vault).previewRedeem(shares) : shares;
        request.shares -= shares;
        request.claimed = request.shares == 0;
        if (_redeems && shares > 0) {
            RestakingTokenMock(vault).withdraw(assets, receiver, address(this));
        }
    }

    function isClaimed(uint256 tokenId) external view returns (bool) {
        return _requests[tokenId].claimed;
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

    function absoluteLimitOf(address adapter) external view returns (uint256) {
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
    address public assetToken;
    address public delegator;
    RestakingWithdrawalQueueMock public immutable withdrawalQueue;

    constructor(address assetToken_, address delegator_) {
        assetToken = assetToken_;
        delegator = delegator_;
        withdrawalQueue = new RestakingWithdrawalQueueMock(address(this), false);
    }

    function setAsset(address assetToken_) external {
        assetToken = assetToken_;
    }

    function asset() external view returns (address) {
        return assetToken;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
}
