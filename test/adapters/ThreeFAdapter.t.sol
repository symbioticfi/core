// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {ThreeFAdapter} from "../../src/contracts/adapters/ThreeFAdapter.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {
    IThreeFAdapter,
    IThreeFRequestCallback,
    IThreeFWhitelist,
    Offer
} from "../../src/interfaces/adapters/IThreeFAdapter.sol";

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
        request = address(new ThreeFRequestMock(assetToken));

        ThreeFVaultMock(vault).setDelegator(delegator);
        ThreeFVaultFactoryMock(vaultFactory).setEntity(vault, true);

        adapterFactory = address(new AdapterFactory(address(this)));
        AdapterFactory(adapterFactory).whitelist(address(new ThreeFAdapter(whitelist, adapterFactory, vaultFactory)));

        adapter = AdapterFactory(adapterFactory).create(1, address(this), abi.encode(vault, bytes("")));

        IThreeFAdapter(adapter).setOfferSigner(signer);
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.Whitelisted);
        ThreeFDelegatorMock(delegator).setLimit(adapter, type(uint256).max);
        ThreeFTokenMock(assetToken).mint(vault, VAULT_LIQUIDITY);
    }

    function test_ConsumePullsPrincipalJustInTime() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        assertEq(IERC20(assetToken).balanceOf(request), PRINCIPAL);
        assertEq(IERC20(assetToken).balanceOf(vault), VAULT_LIQUIDITY - PRINCIPAL);
        assertEq(IERC20(assetToken).balanceOf(adapter), 0);
        assertEq(IThreeFAdapter(adapter).outstandingPrincipal(), PRINCIPAL);
        assertEq(IThreeFAdapter(adapter).totalAssets(), PRINCIPAL);

        (uint256 principal, uint256 ytExpected, uint48 openedAt, bool redeemed) =
            IThreeFAdapter(adapter).positions(request);
        assertEq(principal, PRINCIPAL);
        assertEq(ytExpected, YIELD);
        assertEq(openedAt, uint48(vm.getBlockTimestamp()));
        assertFalse(redeemed);

        assertTrue(IThreeFAdapter(adapter).isRequest(request));
        assertEq(IThreeFAdapter(adapter).activeLoans(), 1);
    }

    function test_ConsumeSpendsIdleBalanceBeforePulling() public {
        ThreeFTokenMock(assetToken).mint(adapter, 30_000e6);

        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        assertEq(IERC20(assetToken).balanceOf(request), PRINCIPAL);
        assertEq(IERC20(assetToken).balanceOf(vault), VAULT_LIQUIDITY - 70_000e6);
        assertEq(IERC20(assetToken).balanceOf(adapter), 0);
    }

    function test_ConsumeRevertsWhenRequestAlreadyActive() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        vm.expectRevert(IThreeFAdapter.RequestAlreadyActive.selector);
        ThreeFRequestMock(request).consume(adapter, 1, 1);

        assertEq(IThreeFAdapter(adapter).outstandingPrincipal(), PRINCIPAL);
        assertEq(IThreeFAdapter(adapter).activeLoans(), 1);
    }

    function test_ConsumeRevertsWhenNotAttested() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.NotWhitelisted);

        vm.expectRevert(IThreeFAdapter.NotAttested.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenPausedWhitelisted() public {
        ThreeFWhitelistMock(whitelist).set(request, IThreeFWhitelist.WhitelistStatus.PausedWhitelisted);

        vm.expectRevert(IThreeFAdapter.NotAttested.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsOnAssetMismatch() public {
        address wrongRequest = address(new ThreeFRequestMock(address(new ThreeFTokenMock())));
        ThreeFWhitelistMock(whitelist).set(wrongRequest, IThreeFWhitelist.WhitelistStatus.Whitelisted);

        vm.expectRevert(IThreeFAdapter.AssetMismatch.selector);
        ThreeFRequestMock(wrongRequest).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenVaultLiquidityDry() public {
        vm.prank(delegator);
        ThreeFVaultMock(vault).pull(makeAddr("drain"), VAULT_LIQUIDITY);

        vm.expectRevert(IThreeFAdapter.InsufficientLiquidity.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenDelegatorCapExceeded() public {
        ThreeFDelegatorMock(delegator).setLimit(adapter, PRINCIPAL - 1);

        vm.expectRevert(IThreeFAdapter.InsufficientLiquidity.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_ConsumeRevertsWhenExposureLimitsAreExceeded() public {
        IThreeFAdapter(adapter).setExposureLimits(PRINCIPAL - 1, 0);

        vm.expectRevert(IThreeFAdapter.PerRequestCapExceeded.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        IThreeFAdapter(adapter).setExposureLimits(0, 30_000);

        vm.expectRevert(IThreeFAdapter.YieldTooLow.selector);
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
    }

    function test_AllocatableIsZeroOutsideConsume() public view {
        assertEq(IThreeFAdapter(adapter).allocatable(), 0);
    }

    function test_RedeemSkipsUnknownRequest() public {
        address[] memory requests = new address[](1);
        requests[0] = makeAddr("strangerRequest");

        IThreeFAdapter(adapter).redeem(requests);

        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), 0);
    }

    function test_RedeemSkipsNotReadyRequest() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        address[] memory requests = new address[](1);
        requests[0] = request;

        IThreeFAdapter(adapter).redeem(requests);

        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), 0);
        assertTrue(IThreeFAdapter(adapter).isRequest(request));
        assertEq(IThreeFAdapter(adapter).activeLoans(), 1);
    }

    function test_RedeemRealizesReadyPosition() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).fundRedemption(PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);

        address[] memory requests = new address[](1);
        requests[0] = request;

        IThreeFAdapter(adapter).redeem(requests);

        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), PRINCIPAL);
        assertEq(IThreeFAdapter(adapter).outstandingPrincipal(), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), PRINCIPAL + YIELD);
        assertFalse(IThreeFAdapter(adapter).isRequest(request));
        assertEq(IThreeFAdapter(adapter).activeLoans(), 0);

        (,,, bool redeemed) = IThreeFAdapter(adapter).positions(request);
        assertTrue(redeemed);
    }

    function test_ActiveRequestsTracksOpenSet() public {
        assertEq(IThreeFAdapter(adapter).activeRequests().length, 0);

        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        address second = address(new ThreeFRequestMock(assetToken));
        ThreeFWhitelistMock(whitelist).set(second, IThreeFWhitelist.WhitelistStatus.Whitelisted);
        ThreeFRequestMock(second).consume(adapter, PRINCIPAL, YIELD);

        address[] memory open = IThreeFAdapter(adapter).activeRequests();
        assertEq(open.length, 2);
        assertEq(IThreeFAdapter(adapter).activeLoans(), 2);
        assertTrue(IThreeFAdapter(adapter).isRequest(request));
        assertTrue(IThreeFAdapter(adapter).isRequest(second));

        // Redeem the first; it leaves the active set while the second remains.
        ThreeFRequestMock(request).fundRedemption(PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);
        address[] memory toRedeem = new address[](1);
        toRedeem[0] = request;
        IThreeFAdapter(adapter).redeem(toRedeem);

        open = IThreeFAdapter(adapter).activeRequests();
        assertEq(open.length, 1);
        assertEq(open[0], second);
        assertEq(IThreeFAdapter(adapter).activeLoans(), 1);
        assertFalse(IThreeFAdapter(adapter).isRequest(request));
        assertTrue(IThreeFAdapter(adapter).isRequest(second));
    }

    function test_RedeemLossScenarioRealizesLessThanPrincipal() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).fundRedemption(PRINCIPAL - 10_000e6, 0);
        ThreeFRequestMock(request).setCanWithdraw(true);

        address[] memory requests = new address[](1);
        requests[0] = request;

        IThreeFAdapter(adapter).redeem(requests);

        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), PRINCIPAL - 10_000e6);
        assertEq(IThreeFAdapter(adapter).outstandingPrincipal(), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), PRINCIPAL - 10_000e6);
    }

    function test_ConsumeRecyclesRealizedPrincipalAccounting() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).fundRedemption(PRINCIPAL, 0);
        ThreeFRequestMock(request).setCanWithdraw(true);

        address[] memory requests = new address[](1);
        requests[0] = request;

        IThreeFAdapter(adapter).redeem(requests);
        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), PRINCIPAL);

        address nextRequest = address(new ThreeFRequestMock(assetToken));
        ThreeFWhitelistMock(whitelist).set(nextRequest, IThreeFWhitelist.WhitelistStatus.Whitelisted);

        ThreeFRequestMock(nextRequest).consume(adapter, 40_000e6, YIELD);

        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), PRINCIPAL - 40_000e6);
    }

    function test_DeallocateRecallsRealizedBalanceToVault() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);
        ThreeFRequestMock(request).fundRedemption(PRINCIPAL, YIELD);
        ThreeFTokenMock(assetToken).mint(request, YIELD);
        ThreeFRequestMock(request).setCanWithdraw(true);

        address[] memory requests = new address[](1);
        requests[0] = request;

        IThreeFAdapter(adapter).redeem(requests);

        uint256 vaultBefore = IERC20(assetToken).balanceOf(vault);
        uint256 deallocated = ThreeFDelegatorMock(delegator).deallocate(adapter, PRINCIPAL);

        assertEq(deallocated, PRINCIPAL + YIELD);
        assertEq(IERC20(assetToken).balanceOf(vault) - vaultBefore, PRINCIPAL + YIELD);
        assertEq(IThreeFAdapter(adapter).realizedPrincipal(), 0);
        assertEq(IERC20(assetToken).balanceOf(adapter), 0);
    }

    function test_DeallocateOnlyDelegator() public {
        ThreeFRequestMock(request).consume(adapter, PRINCIPAL, YIELD);

        vm.expectRevert(IAdapter.NotVault.selector);
        IThreeFAdapter(adapter).deallocate(PRINCIPAL);
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
        IThreeFAdapter(adapter).setExposureLimits(1, 2);

        vm.stopPrank();
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
    bool public canWithdraw;
    uint256 public pAssets;
    uint256 public yAssets;

    constructor(address asset_) {
        asset = asset_;
    }

    function setCanWithdraw(bool status) external {
        canWithdraw = status;
    }

    function consume(address adapter, uint256 principal, uint256 yieldAmount) external {
        IThreeFRequestCallback(adapter)
            .onRequestConsumed(
                Offer({
                maker: adapter,
                amount: principal,
                expectedReturn: yieldAmount,
                nonce: 1,
                expiration: type(uint256).max,
                useCallback: true
            }),
                "",
                principal,
                yieldAmount
            );

        IERC20(asset).transferFrom(adapter, address(this), principal);
    }

    function fundRedemption(uint256 pAssets_, uint256 yAssets_) external {
        pAssets = pAssets_;
        yAssets = yAssets_;
    }

    function burnAll(address, address receiver) external returns (uint256, uint256, uint256, uint256) {
        uint256 curPAssets = pAssets;
        uint256 curYAssets = yAssets;

        pAssets = 0;
        yAssets = 0;

        IERC20(asset).transfer(receiver, curPAssets + curYAssets);

        return (0, 0, curPAssets, curYAssets);
    }
}
