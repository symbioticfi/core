// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {ThreeFAdapter} from "../../src/contracts/adapters/ThreeFAdapter.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IThreeFAdapter, MAX_REQUESTS} from "../../src/interfaces/adapters/IThreeFAdapter.sol";
import {IThreeFRequestCallback} from "../../src/interfaces/adapters/3f-adapter/IThreeFRequestCallback.sol";
import {IThreeFWhitelist} from "../../src/interfaces/adapters/3f-adapter/IThreeFWhitelist.sol";
import {Offer} from "../../src/interfaces/adapters/3f-adapter/ThreeFTypes.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ThreeFAdapterTest is Test {
    uint256 internal constant SIGNER_PK = 0xB0B;
    uint256 internal constant PRINCIPAL = 100_000e6;
    uint256 internal constant YIELD = 2000e6;
    uint256 internal constant VAULT_LIQUIDITY = 10_000_000e6;

    address internal adapter;
    address internal adapterFactory;
    address internal assetToken;
    address internal delegator;
    address internal request;
    address internal signer;
    address internal vault;
    address internal vaultFactory;
    address internal whitelist;

    function setUp() public {
        signer = vm.addr(SIGNER_PK);

        assetToken = address(new ThreeFTokenMock());
        vaultFactory = address(new ThreeFVaultFactoryMock());
        whitelist = address(new ThreeFWhitelistMock());
        vault = address(new ThreeFVaultMock(assetToken));
        delegator = address(new ThreeFDelegatorMock(vault));
        request = _newRequest();

        ThreeFVaultMock(vault).setDelegator(delegator);
        ThreeFVaultFactoryMock(vaultFactory).setEntity(vault, true);

        adapterFactory = address(new AdapterFactory(address(this)));
        AdapterFactory(adapterFactory).whitelist(address(new ThreeFAdapter(vaultFactory, adapterFactory, whitelist)));

        adapter = AdapterFactory(adapterFactory).create(1, address(this), abi.encode(vault, bytes("")));

        IThreeFAdapter(adapter).setOfferSigner(signer);
        IThreeFAdapter(adapter).setLimitsPerRequest(0, 1, type(uint256).max);
        ThreeFDelegatorMock(delegator).setLimit(adapter, type(uint256).max);
        ThreeFTokenMock(assetToken).mint(vault, VAULT_LIQUIDITY);
    }

    function test_ConsumePullsPrincipalJustInTimeAndTracksRequest() public {
        _consume(request, PRINCIPAL, YIELD);

        assertEq(IERC20(assetToken).balanceOf(request), PRINCIPAL);
        assertEq(IERC20(assetToken).balanceOf(vault), VAULT_LIQUIDITY - PRINCIPAL);
        assertEq(IERC20(assetToken).balanceOf(adapter), 0);
        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL);
        assertEq(IThreeFAdapter(adapter).requests(0), request);
        assertEq(IThreeFAdapter(adapter).requestIndex(request), 1);
        assertEq(IThreeFAdapter(adapter).pendingAssets(request), PRINCIPAL);
    }

    function test_TotalAssetsUsesPrincipalSharesBeforeRequestIsWithdrawable() public {
        _consume(request, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).pull(makeAddr("borrower"), PRINCIPAL - 1);
        ThreeFRequestMock(request).setRevertBalancesOf(true);

        assertEq(IERC20(assetToken).balanceOf(request), 1);
        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL);
    }

    function test_TotalAssetsUsesConvertToAssetsWhenRequestIsWithdrawable() public {
        _consume(request, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).pull(makeAddr("loss"), 10_000e6);
        ThreeFRequestMock(request).setCanWithdraw(true);

        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL - 10_000e6);

        ThreeFTokenMock(assetToken).mint(request, YIELD);

        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL - 10_000e6 + YIELD);
    }

    function test_FinalizeRequestBurnsTrackedRequestAndRemovesIt() public {
        _consume(request, PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);

        IThreeFAdapter(adapter).finalizeRequest(request);

        assertEq(IThreeFAdapter(adapter).requestIndex(request), 0);
        assertEq(IThreeFAdapter(adapter).pendingAssets(request), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), PRINCIPAL + YIELD);
        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL + YIELD);
    }

    function test_FinalizeRequestKeepsRequestAccountedDuringExternalBurn() public {
        _consume(request, PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);
        ThreeFRequestMock(request).setAdapterToReadDuringBurn(adapter);

        IThreeFAdapter(adapter).finalizeRequest(request);

        assertEq(ThreeFRequestMock(request).totalAssetsDuringBurn(), PRINCIPAL + YIELD);
        assertEq(IThreeFAdapter(adapter).requestIndex(request), 0);
        assertEq(IThreeFAdapter(adapter).pendingAssets(request), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), PRINCIPAL + YIELD);
    }

    function test_FinalizeRequestKeepsMovedRequestIndex() public {
        address firstRequest = request;
        address secondRequest = _newRequest();

        _consume(firstRequest, PRINCIPAL, YIELD);
        _consume(secondRequest, PRINCIPAL / 2, YIELD / 2);
        ThreeFTokenMock(assetToken).mint(firstRequest, YIELD);
        ThreeFTokenMock(assetToken).mint(secondRequest, YIELD / 2);
        ThreeFRequestMock(firstRequest).setCanWithdraw(true);
        ThreeFRequestMock(secondRequest).setCanWithdraw(true);

        IThreeFAdapter(adapter).finalizeRequest(firstRequest);

        assertEq(IThreeFAdapter(adapter).requestIndex(firstRequest), 0);
        assertEq(IThreeFAdapter(adapter).pendingAssets(firstRequest), 0);
        assertEq(IThreeFAdapter(adapter).requestIndex(secondRequest), 1);
        assertEq(IThreeFAdapter(adapter).pendingAssets(secondRequest), PRINCIPAL / 2);
        assertEq(IThreeFAdapter(adapter).requests(0), secondRequest);

        IThreeFAdapter(adapter).finalizeRequest(secondRequest);

        assertEq(IThreeFAdapter(adapter).requestIndex(secondRequest), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), PRINCIPAL + YIELD + PRINCIPAL / 2 + YIELD / 2);
    }

    function test_FinalizeRequestRevertsForUnknownRequest() public {
        vm.expectRevert(IThreeFAdapter.NotRequest.selector);
        IThreeFAdapter(adapter).finalizeRequest(makeAddr("unknown"));
    }

    function test_RequestsLengthTracksActiveSet() public {
        assertEq(IThreeFAdapter(adapter).requestsLength(), 0);

        address firstRequest = request;
        address secondRequest = _newRequest();
        _consume(firstRequest, PRINCIPAL, YIELD);
        assertEq(IThreeFAdapter(adapter).requestsLength(), 1);
        _consume(secondRequest, PRINCIPAL / 2, YIELD / 2);
        assertEq(IThreeFAdapter(adapter).requestsLength(), 2);

        ThreeFTokenMock(assetToken).mint(firstRequest, YIELD);
        ThreeFRequestMock(firstRequest).setCanWithdraw(true);
        IThreeFAdapter(adapter).finalizeRequest(firstRequest);
        assertEq(IThreeFAdapter(adapter).requestsLength(), 1);
    }

    function test_ConsumeRevertsWhenRequestAlreadyActive() public {
        _consume(request, PRINCIPAL, YIELD);

        _expectConsumeRevert(IThreeFAdapter.AlreadyRequest.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsBeforeMaxLimitConfigured() public {
        address unconfiguredAdapter =
            AdapterFactory(adapterFactory).create(1, address(this), abi.encode(vault, bytes("")));
        ThreeFDelegatorMock(delegator).setLimit(unconfiguredAdapter, type(uint256).max);

        _expectConsumeRevert(IThreeFAdapter.TooLargeRequest.selector, request, unconfiguredAdapter, 1e6, 1);
    }

    function test_ConsumeRevertsWhenPrincipalIsBelowConfiguredMinimum() public {
        _expectConsumeRevert(IThreeFAdapter.TooSmallRequest.selector, request, 0, YIELD);
    }

    function test_ConsumeRevertsWhenMaxRequestsExceeded() public {
        for (uint256 i; i < MAX_REQUESTS; ++i) {
            _consume(_newRequest(), 1e6, 1);
        }

        address extraRequest = _newRequest();
        _expectConsumeRevert(IThreeFAdapter.TooManyRequests.selector, extraRequest, 1e6, 1);
    }

    function test_ConsumeRevertsWhenNotWhitelisted() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.NotWhitelisted);

        _expectConsumeRevert(IThreeFAdapter.NotRequest.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenPausedWhitelisted() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.PausedWhitelisted);

        _expectConsumeRevert(IThreeFAdapter.NotRequest.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsOnAssetMismatch() public {
        address wrongRequest = address(new ThreeFRequestMock(address(new ThreeFTokenMock())));
        ThreeFWhitelistMock(whitelist).set(wrongRequest, IThreeFWhitelist.WhitelistStatus.Whitelisted);

        _expectConsumeRevert(IThreeFAdapter.WrongAsset.selector, wrongRequest, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenVaultLiquidityDry() public {
        vm.prank(delegator);
        ThreeFVaultMock(vault).pull(makeAddr("drain"), VAULT_LIQUIDITY);

        _expectConsumeRevert(IThreeFAdapter.InsufficientAllocate.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenDelegatorCapExceeded() public {
        ThreeFDelegatorMock(delegator).setLimit(adapter, PRINCIPAL - 1);

        _expectConsumeRevert(IThreeFAdapter.InsufficientAllocate.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenRequestLimitsAreExceeded() public {
        IThreeFAdapter(adapter).setLimitsPerRequest(0, 10e6, PRINCIPAL - 1);

        _expectConsumeRevert(IThreeFAdapter.TooLargeRequest.selector, request, PRINCIPAL, YIELD);

        IThreeFAdapter(adapter).setLimitsPerRequest(0, PRINCIPAL + 1, type(uint256).max);

        _expectConsumeRevert(IThreeFAdapter.TooSmallRequest.selector, request, PRINCIPAL, YIELD);

        IThreeFAdapter(adapter).setLimitsPerRequest(30_000, 1, type(uint256).max);

        _expectConsumeRevert(IThreeFAdapter.TooLowYield.selector, request, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenOfferMakerIsNotAdapter() public {
        Offer memory offer = _offer(makeAddr("maker"), PRINCIPAL, YIELD, type(uint256).max);

        vm.expectRevert(IThreeFAdapter.InvalidOffer.selector);
        ThreeFRequestMock(request).consume(adapter, offer, "", PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenOfferDoesNotUseCallback() public {
        Offer memory offer = _offer(adapter, PRINCIPAL, YIELD, type(uint256).max);
        offer.useCallback = false;

        vm.expectRevert(IThreeFAdapter.InvalidOffer.selector);
        ThreeFRequestMock(request).consume(adapter, offer, "", PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenOfferExpectedReturnIsZero() public {
        Offer memory offer = _offer(adapter, PRINCIPAL, 0, type(uint256).max);

        vm.expectRevert(IThreeFAdapter.InvalidOffer.selector);
        ThreeFRequestMock(request).consume(adapter, offer, "", PRINCIPAL, 0);
    }

    function test_ConsumeRevertsWhenOfferIsExpired() public {
        Offer memory offer = _offer(adapter, PRINCIPAL, YIELD, block.timestamp - 1);

        vm.expectRevert(IThreeFAdapter.ExpiredOffer.selector);
        ThreeFRequestMock(request).consume(adapter, offer, "", PRINCIPAL, YIELD);
    }

    function test_AllocatableIsZeroOutsideConsume() public view {
        assertEq(IThreeFAdapter(adapter).allocatable(), 0);
    }

    function test_DeallocateRecallsFinalizedBalanceToVault() public {
        _consume(request, PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);
        IThreeFAdapter(adapter).finalizeRequest(request);

        uint256 vaultBefore = IERC20(assetToken).balanceOf(vault);
        uint256 deallocated = ThreeFDelegatorMock(delegator).deallocate(adapter, PRINCIPAL);

        assertEq(deallocated, PRINCIPAL + YIELD);
        assertEq(IERC20(assetToken).balanceOf(vault) - vaultBefore, PRINCIPAL + YIELD);
        assertEq(IERC20(assetToken).balanceOf(adapter), 0);
    }

    function test_DeallocateOnlyDelegator() public {
        _consume(request, PRINCIPAL, YIELD);

        vm.expectRevert(IAdapter.NotVault.selector);
        IThreeFAdapter(adapter).deallocate(PRINCIPAL);
    }

    function test_GetMaxAssetsAccountsForDelegatorLimitAndVaultWithdrawable() public {
        ThreeFDelegatorMock(delegator).setLimit(adapter, PRINCIPAL);

        assertEq(IThreeFAdapter(adapter).getMaxAssets(), PRINCIPAL);

        _consume(request, 40_000e6, YIELD);

        assertEq(IThreeFAdapter(adapter).getMaxAssets(), 60_000e6);
    }

    function test_IsValidSignatureAcceptsOfferSigner() public view {
        bytes32 digest = keccak256("some offer digest");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);

        assertEq(
            IThreeFAdapter(adapter).isValidSignature(digest, abi.encodePacked(r, s, v)),
            IERC1271.isValidSignature.selector
        );
    }

    function test_IsValidSignatureRejectsOtherSigner() public view {
        bytes32 digest = keccak256("some offer digest");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, digest);

        assertEq(IThreeFAdapter(adapter).isValidSignature(digest, abi.encodePacked(r, s, v)), bytes4(0xffffffff));
    }

    function test_IsValidSignatureRejectsUnsetSigner() public {
        IThreeFAdapter(adapter).setOfferSigner(address(0));
        bytes32 digest = keccak256("some offer digest");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);

        assertEq(IThreeFAdapter(adapter).isValidSignature(digest, abi.encodePacked(r, s, v)), bytes4(0xffffffff));
    }

    function test_OwnerGatedConfig() public {
        vm.startPrank(makeAddr("notOwner"));

        vm.expectRevert();
        IThreeFAdapter(adapter).setOfferSigner(makeAddr("x"));

        vm.expectRevert();
        IThreeFAdapter(adapter).setLimitsPerRequest(1, 2, 3);

        vm.stopPrank();
    }

    function test_SetRequestNonceForwardsAsAdapter() public {
        IThreeFAdapter(adapter).setRequestNonce(request, 7);

        assertEq(ThreeFRequestMock(request).nonce(adapter), 7);
    }

    function test_SetRequestNonceRevertsWhenNotOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        IThreeFAdapter(adapter).setRequestNonce(request, 7);
    }

    function test_SetRequestNonceRevertsWhenNotWhitelisted() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.NotWhitelisted);

        vm.expectRevert(IThreeFAdapter.NotRequest.selector);
        IThreeFAdapter(adapter).setRequestNonce(request, 7);
    }

    function test_SetRequestNonceRevertsWhenPausedWhitelisted() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.PausedWhitelisted);

        vm.expectRevert(IThreeFAdapter.NotRequest.selector);
        IThreeFAdapter(adapter).setRequestNonce(request, 7);
    }

    function test_SetRequestNonceRevertsOnAssetMismatch() public {
        address wrongRequest = address(new ThreeFRequestMock(address(new ThreeFTokenMock())));
        ThreeFWhitelistMock(whitelist).set(wrongRequest, IThreeFWhitelist.WhitelistStatus.Whitelisted);

        vm.expectRevert(IThreeFAdapter.WrongAsset.selector);
        IThreeFAdapter(adapter).setRequestNonce(wrongRequest, 7);
    }

    function _newRequest() internal returns (address newRequest) {
        newRequest = address(new ThreeFRequestMock(assetToken));
        ThreeFWhitelistMock(whitelist).set(newRequest, IThreeFWhitelist.WhitelistStatus.Whitelisted);
    }

    function _consume(address request_, uint256 principal, uint256 yieldAmount) internal {
        _consume(request_, adapter, principal, yieldAmount);
    }

    function _consume(address request_, address adapter_, uint256 principal, uint256 yieldAmount) internal {
        Offer memory offer = _offer(adapter_, principal, yieldAmount, type(uint256).max);
        ThreeFRequestMock(request_).consume(adapter_, offer, "", principal, yieldAmount);
    }

    function _expectConsumeRevert(bytes4 selector, address request_, uint256 principal, uint256 yieldAmount) internal {
        _expectConsumeRevert(selector, request_, adapter, principal, yieldAmount);
    }

    function _expectConsumeRevert(
        bytes4 selector,
        address request_,
        address adapter_,
        uint256 principal,
        uint256 yieldAmount
    ) internal {
        Offer memory offer = _offer(adapter_, principal, yieldAmount, type(uint256).max);

        vm.expectRevert(selector);
        ThreeFRequestMock(request_).consume(adapter_, offer, "", principal, yieldAmount);
    }

    function _offer(address maker, uint256 amount, uint256 expectedReturn, uint256 expiration)
        internal
        pure
        returns (Offer memory offer)
    {
        offer = Offer({
            maker: maker,
            amount: amount,
            expectedReturn: expectedReturn,
            nonce: 1,
            expiration: expiration,
            useCallback: true
        });
    }
}

contract ThreeFTokenMock is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ThreeFVaultFactoryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract ThreeFWhitelistMock is IThreeFWhitelist {
    mapping(address account => WhitelistStatus status) internal _statuses;

    function set(address account, WhitelistStatus status) external {
        _statuses[account] = status;
    }

    function isWhitelisted(address account) external view returns (WhitelistStatus) {
        return _statuses[account];
    }
}

contract ThreeFVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_) {
        asset = asset_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function pull(address receiver, uint256 amount) external {
        if (msg.sender != delegator) {
            revert();
        }

        IERC20(asset).transfer(receiver, amount);
    }

    function withdrawable() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function recall(address account, uint256 amount) external {
        if (msg.sender != delegator) {
            revert();
        }

        IERC20(asset).transferFrom(account, address(this), amount);
    }
}

contract ThreeFDelegatorMock {
    address public immutable vault;
    mapping(address adapter => uint256 limit) public limits;

    constructor(address vault_) {
        vault = vault_;
    }

    function setLimit(address adapter, uint256 limit) external {
        limits[adapter] = limit;
    }

    function limitOf(address adapter) external view returns (uint256) {
        return limits[adapter];
    }

    function sweepPending() external pure returns (uint256) {
        return 0;
    }

    function allocateExact(address adapter, uint256 assets) external returns (uint256 allocated) {
        uint256 totalAssets = IAdapter(adapter).totalAssets();
        uint256 limit = limits[adapter] > totalAssets ? limits[adapter] - totalAssets : 0;
        if (assets > limit) {
            assets = limit;
        }

        uint256 freeAssets = IERC20(ThreeFVaultMock(vault).asset()).balanceOf(vault);
        if (assets > freeAssets) {
            assets = freeAssets;
        }

        uint256 allocatable = IAdapter(adapter).allocatable();
        if (assets > allocatable) {
            assets = allocatable;
        }
        if (assets == 0) {
            return 0;
        }

        ThreeFVaultMock(vault).pull(adapter, assets);
        allocated = IAdapter(adapter).allocate(assets);
    }

    function deallocate(address adapter, uint256 amount) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(amount);
        if (deallocated > 0) {
            ThreeFVaultMock(vault).recall(adapter, deallocated);
        }
    }
}

contract ThreeFRequestMock {
    address public immutable asset;
    address public adapterToReadDuringBurn;
    bool public canWithdraw;
    bool public revertBalancesOf;
    uint256 public totalAssetsDuringBurn;

    uint256 public ptSupply;
    uint256 public ytSupply;

    mapping(address account => uint256 balance) internal _ptBalances;
    mapping(address account => uint256 balance) internal _ytBalances;
    mapping(address account => uint256 currentNonce) public nonce;

    constructor(address asset_) {
        asset = asset_;
    }

    function setNonce(uint256 newNonce) external {
        if (nonce[msg.sender] >= newNonce) {
            revert();
        }
        nonce[msg.sender] = newNonce;
    }

    function setCanWithdraw(bool status) external {
        canWithdraw = status;
    }

    function setRevertBalancesOf(bool status) external {
        revertBalancesOf = status;
    }

    function setAdapterToReadDuringBurn(address adapter) external {
        adapterToReadDuringBurn = adapter;
    }

    function balancesOf(address account) external view returns (uint256 ptShares, uint256 ytShares) {
        if (revertBalancesOf) {
            revert();
        }

        ptShares = _ptBalances[account];
        ytShares = _ytBalances[account];
    }

    function convertToAssets(uint256 ptShares, uint256 ytShares)
        public
        view
        returns (uint256 pAssets, uint256 yAssets)
    {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (ptSupply > 0) {
            pAssets = balance * ptShares / ptSupply;
        }
        if (ytSupply > 0 && balance > pAssets) {
            yAssets = (balance - pAssets) * ytShares / ytSupply;
        }
    }

    function pull(address receiver, uint256 amount) external {
        IERC20(asset).transfer(receiver, amount);
    }

    function consume(
        address adapter,
        Offer calldata offer,
        bytes calldata signature,
        uint256 principal,
        uint256 yieldAmount
    ) external {
        IThreeFRequestCallback(adapter).onRequestConsumed(offer, signature, principal, yieldAmount);

        IERC20(asset).transferFrom(adapter, address(this), principal);
        _ptBalances[adapter] += principal;
        _ytBalances[adapter] += yieldAmount;
        ptSupply += principal;
        ytSupply += yieldAmount;
    }

    function burnAll(address owner, address receiver) external returns (uint256, uint256, uint256, uint256) {
        if (adapterToReadDuringBurn != address(0)) {
            totalAssetsDuringBurn = IThreeFAdapter(adapterToReadDuringBurn).totalAssets();
        }

        uint256 ptShares = _ptBalances[owner];
        uint256 ytShares = _ytBalances[owner];
        (uint256 pAssets, uint256 yAssets) = convertToAssets(ptShares, ytShares);

        _ptBalances[owner] = 0;
        _ytBalances[owner] = 0;
        ptSupply -= ptShares;
        ytSupply -= ytShares;

        IERC20(asset).transfer(receiver, pAssets + yAssets);

        return (ptShares, ytShares, pAssets, yAssets);
    }
}
