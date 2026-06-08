// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {
    DISCOUNT_SWAP_TYPEHASH,
    DISCOUNT_TYPEHASH,
    ILiquidLaneAdapter,
    SIGNED_SWAP_TYPEHASH
} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidLaneAdapterTest is Test {
    MockERC20 internal asset;
    MockERC20 internal tokenToRedeem;
    MockLiquidLaneDelegator internal delegator;
    MockVaultRegistry internal vaultFactory;
    AdapterFactory internal adapterFactory;
    AccountRegistry internal accountRegistry;
    MigratablesFactory internal accountFactory;
    MockLiquidLaneVault internal vault;
    LiquidLaneAdapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal curatorReceiver = makeAddr("curatorReceiver");
    address internal filler = makeAddr("filler");
    address internal marketMaker = makeAddr("marketMaker");
    address internal marketMakerReceiver = makeAddr("marketMakerReceiver");
    address internal pauser = makeAddr("pauser");
    address internal recipient = makeAddr("recipient");
    address internal unpauser = makeAddr("unpauser");

    function setUp() public {
        asset = new MockERC20("Asset", "ASSET");
        tokenToRedeem = new MockERC20("Token To Redeem", "TTR");
        vaultFactory = new MockVaultRegistry();
        vault = new MockLiquidLaneVault(address(asset));
        delegator = new MockLiquidLaneDelegator(address(vault));
        vault.setDelegator(address(delegator));
        vaultFactory.add(address(vault));
        adapterFactory = new AdapterFactory(curator);
        accountRegistry = new AccountRegistry(curator);
        accountFactory = new MigratablesFactory(curator);

        LiquidLaneAdapter implementation =
            new LiquidLaneAdapter(address(vaultFactory), address(adapterFactory), address(accountRegistry));
        MockLiquidLaneAccount accountImplementation = new MockLiquidLaneAccount(
            address(accountFactory), address(asset), address(new MockLiquidLaneOracle(1e18)), address(tokenToRedeem)
        );

        vm.startPrank(curator);
        adapterFactory.whitelist(address(implementation));
        accountFactory.whitelist(address(accountImplementation));
        accountRegistry.setAccountFactory(address(asset), address(tokenToRedeem), address(accountFactory));
        ILiquidLaneAdapter.InitParams memory params =
            ILiquidLaneAdapter.InitParams({pauser: pauser, unpauser: unpauser});
        vm.expectEmit(false, false, false, true);
        emit ILiquidLaneAdapter.Initialize(params);
        adapter = LiquidLaneAdapter(adapterFactory.create(1, curator, abi.encode(address(vault), abi.encode(params))));
        adapter.addTokenToRedeem(address(tokenToRedeem));
        adapter.setLimit(address(tokenToRedeem), type(uint256).max);
        adapter.setMarketMaker(marketMaker, true);
        vm.stopPrank();
    }

    function testAddTokenToRedeemCreatesAccount() public {
        address account = adapter.accounts(address(tokenToRedeem));

        assertEq(adapter.getTokensToRedeemLength(), 1);
        assertEq(adapter.tokensToRedeem(0), address(tokenToRedeem));
        assertEq(adapter.accounts(address(tokenToRedeem)), account);
        assertGt(account.code.length, 0);
        assertEq(MockLiquidLaneAccount(account).adapter(), address(adapter));
        assertEq(MockLiquidLaneAccount(account).vault(), address(vault));
        assertEq(MockLiquidLaneAccount(account).TOKEN_TO_REDEEM(), address(tokenToRedeem));
        assertEq(MockLiquidLaneAccount(account).owner(), curator);
    }

    function testAddTokenToRedeemRevertsWithoutAccountFactory() public {
        MockERC20 otherTokenToRedeem = new MockERC20("Other Token To Redeem", "OTTR");

        vm.startPrank(curator);
        vm.expectRevert();
        adapter.addTokenToRedeem(address(otherTokenToRedeem));
        vm.stopPrank();
    }

    function testAddTokenToRedeemRevertsForDuplicateToken() public {
        address account = adapter.accounts(address(tokenToRedeem));

        vm.prank(curator);
        vm.expectRevert(ILiquidLaneAdapter.InvalidTokenToRedeem.selector);
        adapter.addTokenToRedeem(address(tokenToRedeem));

        assertEq(adapter.getTokensToRedeemLength(), 1);
        assertEq(adapter.accounts(address(tokenToRedeem)), account);
    }

    function testRemoveTokenToRedeemClearsConfiguration() public {
        address account = adapter.accounts(address(tokenToRedeem));

        vm.prank(curator);
        adapter.removeTokenToRedeem(address(tokenToRedeem));

        assertEq(adapter.getTokensToRedeemLength(), 0);
        assertEq(adapter.accounts(address(tokenToRedeem)), account);
        assertEq(adapter.limit(address(tokenToRedeem)), 0);

        vm.prank(curator);
        vm.expectRevert(ILiquidLaneAdapter.InvalidTokenToRedeem.selector);
        adapter.setLimit(address(tokenToRedeem), type(uint256).max);
    }

    function testRemoveTokenToRedeemRevertsForUnknownToken() public {
        MockERC20 otherTokenToRedeem = new MockERC20("Other Token To Redeem", "OTTR");

        vm.prank(curator);
        vm.expectRevert(ILiquidLaneAdapter.InvalidTokenToRedeem.selector);
        adapter.removeTokenToRedeem(address(otherTokenToRedeem));
    }

    function testInitializeSetsPauserAndUnpauserFromParams() public view {
        assertEq(adapter.owner(), curator);
        assertEq(adapter.FACTORY(), address(adapterFactory));
        assertEq(adapter.pauser(), pauser);
        assertEq(adapter.unpauser(), unpauser);
    }

    function testSetPairMaxDiscountSelectorIsUnavailable() public {
        vm.prank(curator);
        (bool success,) = address(adapter)
            .call(
                abi.encodeWithSignature(
                    "setPairMaxDiscount(address,address,uint256)", address(tokenToRedeem), address(asset), 0
                )
            );

        assertFalse(success);
    }

    function testPauseAndUnpauseUsePauserUnpauserAndPauseSwaps() public {
        address newPauser = makeAddr("newPauser");

        vm.expectRevert(ILiquidLaneAdapter.InvalidCaller.selector);
        vm.prank(newPauser);
        adapter.pause();

        vm.prank(curator);
        adapter.setPauser(newPauser);

        vm.prank(newPauser);
        adapter.pause();

        assertTrue(adapter.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(marketMaker);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 90 ether
            })
        );

        vm.expectRevert(ILiquidLaneAdapter.InvalidCaller.selector);
        vm.prank(newPauser);
        adapter.unpause();

        vm.prank(curator);
        adapter.setUnpauser(newPauser);

        vm.prank(newPauser);
        adapter.unpause();

        assertFalse(adapter.paused());
    }

    function testSwapAllocatesThroughDelegatorAndSyncsRedemption() public {
        address account = adapter.accounts(address(tokenToRedeem));

        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.startPrank(marketMaker);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 90 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertEq(tokenToRedeem.balanceOf(account), 100 ether);
        assertEq(asset.balanceOf(address(vault)), 10 ether);

        // Account realizes 95 asset (90 principal + 5 rewards); totalAssets reflects the live
        // per-account value via IAccount.totalAssets().
        asset.mint(account, 95 ether);
        assertEq(adapter.totalAssets(), 95 ether);
        assertEq(adapter.freeAssets(), 95 ether);

        uint256 deallocated = delegator.deallocate(address(adapter), 90 ether);

        assertEq(deallocated, 95 ether);
        assertEq(asset.balanceOf(address(vault)), 105 ether);
        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.freeAssets(), 0);
    }

    function testSwapUsesDelegatorAllocateExactForShortfall() public {
        asset.mint(address(vault), 40 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);
        delegator.setRevertDeallocateExact(true);

        vm.startPrank(marketMaker);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 90 ether
            })
        );
        vm.stopPrank();

        assertEq(delegator.allocateExactCalls(), 1);
        assertEq(asset.balanceOf(recipient), 90 ether);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testGetMaxAssetsReturnsOnlyAcquireBalanceWhenPendingAssetsRemain() public {
        asset.mint(curator, 25 ether);
        vm.startPrank(curator);
        adapter.setReceiver(curatorReceiver);
        asset.approve(address(adapter), 25 ether);
        adapter.depositToAcquire(address(tokenToRedeem), 25 ether);
        vm.stopPrank();

        asset.mint(address(vault), 100 ether);
        delegator.setPendingAssets(30 ether);

        assertEq(adapter.getMaxAssets(address(tokenToRedeem)), 25 ether);
        assertEq(delegator.sweepPendingCalls(), 1);
    }

    function testPrefundedAcquisitionDoesNotAllocateVaultAssetsAndPaysReceiver() public {
        address account = adapter.accounts(address(tokenToRedeem));

        asset.mint(curator, 40 ether);
        asset.mint(marketMaker, 60 ether);

        vm.startPrank(curator);
        adapter.setReceiver(curatorReceiver);
        asset.approve(address(adapter), 40 ether);
        adapter.depositToAcquire(address(tokenToRedeem), 40 ether);
        adapter.setLimit(address(tokenToRedeem), 0);
        adapter.setFiller(filler, true);
        vm.stopPrank();

        vm.startPrank(marketMaker);
        adapter.setReceiver(marketMakerReceiver);
        asset.approve(address(adapter), 60 ether);
        adapter.depositToAcquire(address(tokenToRedeem), 60 ether);
        vm.stopPrank();

        tokenToRedeem.mint(filler, 100 ether);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 100 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 100 ether);
        assertEq(tokenToRedeem.balanceOf(curatorReceiver), 40 ether);
        assertEq(tokenToRedeem.balanceOf(marketMakerReceiver), 60 ether);
        assertEq(tokenToRedeem.balanceOf(filler), 0);
        assertEq(tokenToRedeem.balanceOf(account), 0);
        assertEq(adapter.acquireBalance(address(tokenToRedeem), curator), 0);
        assertEq(adapter.acquireBalance(address(tokenToRedeem), marketMaker), 0);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testSetReceiverRevertsForZeroReceiver() public {
        vm.expectRevert(ILiquidLaneAdapter.InvalidReceiver.selector);
        adapter.setReceiver(address(0));
    }

    function testDepositToAcquireRequiresReceiver() public {
        asset.mint(marketMaker, 60 ether);

        vm.startPrank(marketMaker);
        asset.approve(address(adapter), 60 ether);
        vm.expectRevert(ILiquidLaneAdapter.InvalidReceiver.selector);
        adapter.depositToAcquire(address(tokenToRedeem), 60 ether);
        vm.stopPrank();
    }

    function testSignedSwapUsesSignerAuthorizationAndNonce() public {
        uint256 signerKey = 0xA11CE;
        address signer = vm.addr(signerKey);

        vm.prank(curator);
        adapter.setMarketMaker(signer, false);

        asset.mint(address(vault), 90 ether);
        tokenToRedeem.mint(filler, 100 ether);

        ILiquidLaneAdapter.SignedSwap memory signedSwap = ILiquidLaneAdapter.SignedSwap({
            recipient: recipient,
            tokenIn: address(tokenToRedeem),
            amountIn: 100 ether,
            amountOut: 90 ether,
            caller: filler,
            signer: signer,
            nonce: 7,
            deadline: uint48(vm.getBlockTimestamp() + 1 days)
        });
        bytes memory signature = _signSignedSwap(signerKey, signedSwap);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(signedSwap, signature);
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertTrue(adapter.isUsedNonce(address(tokenToRedeem), 7));

        vm.prank(filler);
        vm.expectRevert(ILiquidLaneAdapter.AlreadyUsedNonce.selector);
        adapter.swap(signedSwap, signature);
    }

    function testDiscountSwapUsesReusableSignerDiscountAndProtocolCosign() public {
        uint256 signerKey = 0xB0B;
        uint256 protocolKey = 0xC0DE;
        address signer = vm.addr(signerKey);
        address protocol = vm.addr(protocolKey);

        vm.prank(curator);
        adapter.setMarketMaker(signer, false);

        ILiquidLaneAdapter.Discount memory discount = ILiquidLaneAdapter.Discount({
            tokenToRedeem: address(tokenToRedeem),
            discount: 100_000,
            signer: signer,
            protocol: protocol,
            nonce: 9,
            deadline: uint48(vm.getBlockTimestamp() + 1 days)
        });
        bytes memory signerSignature = _signDiscount(signerKey, discount);
        ILiquidLaneAdapter.DiscountSwap memory discountSwap = ILiquidLaneAdapter.DiscountSwap({
            discount: discount,
            signerSignature: signerSignature,
            protocolDeadline: uint48(vm.getBlockTimestamp() + 5 minutes)
        });
        bytes memory protocolSignature = _signDiscountSwap(protocolKey, discountSwap);

        asset.mint(address(vault), 90 ether);
        tokenToRedeem.mint(filler, 100 ether);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        uint256 amountOut = adapter.swap(discountSwap, protocolSignature, recipient, 100 ether);
        vm.stopPrank();

        assertEq(amountOut, 90 ether);
        assertEq(asset.balanceOf(recipient), 90 ether);
        assertTrue(adapter.isUsedNonce(address(tokenToRedeem), 9));
    }

    function testSwapRevertsWhenRateViolatesMinDiscount() public {
        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.prank(curator);
        adapter.setMinDiscount(address(tokenToRedeem), 100_000);

        vm.startPrank(marketMaker);
        tokenToRedeem.approve(address(adapter), 100 ether);
        vm.expectRevert(ILiquidLaneAdapter.InvalidSwapRate.selector);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 100 ether
            })
        );
        vm.stopPrank();
    }

    function testSwapRevertsForUnknownTokenToRedeem() public {
        MockERC20 unknownTokenToRedeem = new MockERC20("Unknown Token To Redeem", "UTTR");

        vm.expectRevert(ILiquidLaneAdapter.InvalidTokenToRedeem.selector);
        vm.prank(marketMaker);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(unknownTokenToRedeem), amountIn: 100 ether, amountOut: 90 ether
            })
        );
    }

    function _signSignedSwap(uint256 signerKey, ILiquidLaneAdapter.SignedSwap memory signedSwap)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                SIGNED_SWAP_TYPEHASH,
                signedSwap.recipient,
                signedSwap.tokenIn,
                signedSwap.amountIn,
                signedSwap.amountOut,
                signedSwap.caller,
                signedSwap.signer,
                signedSwap.nonce,
                signedSwap.deadline
            )
        );
        return _signDigest(signerKey, structHash);
    }

    function _signDiscount(uint256 signerKey, ILiquidLaneAdapter.Discount memory discount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                DISCOUNT_TYPEHASH,
                discount.tokenToRedeem,
                discount.discount,
                discount.signer,
                discount.protocol,
                discount.nonce,
                discount.deadline
            )
        );
        return _signDigest(signerKey, structHash);
    }

    function _signDiscountSwap(uint256 signerKey, ILiquidLaneAdapter.DiscountSwap memory discountSwap)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                DISCOUNT_SWAP_TYPEHASH,
                keccak256(
                    abi.encode(
                        DISCOUNT_TYPEHASH,
                        discountSwap.discount.tokenToRedeem,
                        discountSwap.discount.discount,
                        discountSwap.discount.signer,
                        discountSwap.discount.protocol,
                        discountSwap.discount.nonce,
                        discountSwap.discount.deadline
                    )
                ),
                keccak256(discountSwap.signerSignature),
                discountSwap.protocolDeadline
            )
        );
        return _signDigest(signerKey, structHash);
    }

    function _signDigest(uint256 signerKey, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("LiquidLaneAdapter")),
                keccak256(bytes("1")),
                block.chainid,
                address(adapter)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signerKey, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));
        return abi.encodePacked(r, s, v);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockVaultRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MockLiquidLaneVault {
    address public immutable asset;
    address public delegator;

    constructor(address asset_) {
        asset = asset_;
    }

    function setDelegator(address newDelegator) external {
        delegator = newDelegator;
    }

    function freeAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function withdrawable() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function pull(uint256 assets, address receiver) external {
        if (msg.sender != delegator) {
            revert();
        }
        IERC20(asset).transfer(receiver, assets);
    }

    function push(uint256 assets, address owner) external {
        if (msg.sender != delegator) {
            revert();
        }
        IERC20(asset).transferFrom(owner, address(this), assets);
    }
}

contract MockLiquidLaneDelegator {
    address public immutable vault;
    bool public revertDeallocateExact;
    uint256 public allocateExactCalls;
    uint256 public pendingAssets;
    uint256 public sweepPendingCalls;

    constructor(address vault_) {
        vault = vault_;
    }

    function setRevertDeallocateExact(bool newRevertDeallocateExact) external {
        revertDeallocateExact = newRevertDeallocateExact;
    }

    function setPendingAssets(uint256 newPendingAssets) external {
        pendingAssets = newPendingAssets;
    }

    function allocatable(address) external view returns (uint256) {
        return IERC20(MockLiquidLaneVault(vault).asset()).balanceOf(vault);
    }

    function limitOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function sweepPending() external returns (uint256) {
        ++sweepPendingCalls;
        return pendingAssets;
    }

    function allocate(address adapter, uint256 assets) external returns (uint256 allocated) {
        MockLiquidLaneVault(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            MockLiquidLaneVault(vault).push(assets - allocated, adapter);
        }
    }

    function allocateExact(address adapter, uint256 assets) external returns (uint256 allocated) {
        ++allocateExactCalls;
        MockERC20 asset = MockERC20(MockLiquidLaneVault(vault).asset());
        uint256 freeAssets = asset.balanceOf(vault);
        if (freeAssets < assets) {
            asset.mint(vault, assets - freeAssets);
        }
        MockLiquidLaneVault(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            MockLiquidLaneVault(vault).push(assets - allocated, adapter);
        }
    }

    function deallocateExact(uint256 assets) external view returns (uint256 deallocated) {
        if (revertDeallocateExact) {
            revert();
        }
        return assets;
    }

    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            MockLiquidLaneVault(vault).push(deallocated, adapter);
        }
    }
}

contract MockLiquidLaneAccount is MigratableEntity, IAccount {
    address public immutable asset;
    address public immutable ORACLE;
    address public adapter;
    address public vault;
    address public immutable TOKEN_TO_REDEEM;

    constructor(address factory, address asset_, address oracle_, address tokenToRedeem) MigratableEntity(factory) {
        asset = asset_;
        ORACLE = oracle_;
        TOKEN_TO_REDEEM = tokenToRedeem;
    }

    modifier onlyAdapter() {
        if (msg.sender != adapter) {
            revert NotAdapter();
        }
        _;
    }

    function initialize(address vault_) external onlyAdapter {
        vault = vault_;
    }

    function sync() external {}

    function freeAssets() external view returns (uint256 assets) {
        assets = IERC20(asset).balanceOf(address(this));
    }

    function totalAssets() external view returns (uint256 assets) {
        assets = IERC20(asset).balanceOf(address(this));
    }

    function COW_SWAP_SETTLEMENT() external pure returns (address) {
        return address(0);
    }

    function COW_SWAP_VAULT_RELAYER() external pure returns (address) {
        return address(0);
    }

    function convert(address, uint256, address, bytes calldata) external pure {}

    function executableAt(uint256, bytes32) external pure returns (uint48) {
        return 0;
    }

    function converters(uint256) external pure returns (address) {
        return address(0);
    }

    function prepareConvert(address, uint256, address, bytes calldata) external pure returns (bytes32) {
        return bytes32(0);
    }

    function setConverters(address[] memory) external pure {}

    function _initialize(uint64, address, bytes memory data) internal override {
        (vault, adapter) = abi.decode(data, (address, address));

        IERC20(asset).approve(adapter, type(uint256).max);
    }
}

contract MockLiquidLaneOracle {
    uint256 public price;

    constructor(uint256 price_) {
        price = price_;
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
