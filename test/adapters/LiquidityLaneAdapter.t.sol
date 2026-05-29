// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {LiquidityLaneAdapter} from "../../src/contracts/adapters/LiquidityLaneAdapter.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {
    DISCOUNT_SWAP_TYPEHASH,
    DISCOUNT_TYPEHASH,
    ILiquidityLaneAdapter,
    SIGNED_SWAP_TYPEHASH
} from "../../src/interfaces/adapters/ILiquidityLaneAdapter.sol";
import {ILiquidityLaneAccount} from "../../src/interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneAccount.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityLaneAdapterTest is Test {
    MockERC20 internal asset;
    MockERC20 internal tokenToRedeem;
    MockLiquidityLaneDelegator internal delegator;
    MockLiquidityLaneRegistry internal vaultFactory;
    MockLiquidityLaneVault internal vault;
    LiquidityLaneAdapter internal adapter;

    address internal adapterFactory = makeAddr("adapterFactory");
    address internal curator = makeAddr("curator");
    address internal curatorReceiver = makeAddr("curatorReceiver");
    address internal filler = makeAddr("filler");
    address internal marketMaker = makeAddr("marketMaker");
    address internal marketMakerReceiver = makeAddr("marketMakerReceiver");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        asset = new MockERC20("Asset", "ASSET");
        tokenToRedeem = new MockERC20("Token To Redeem", "TTR");
        vaultFactory = new MockLiquidityLaneRegistry();
        vault = new MockLiquidityLaneVault(address(asset));
        delegator = new MockLiquidityLaneDelegator(address(vault));
        vault.setDelegator(address(delegator));
        vaultFactory.add(address(vault));

        LiquidityLaneAdapter implementation = new LiquidityLaneAdapter(address(vaultFactory), adapterFactory);
        adapter = LiquidityLaneAdapter(
            address(
                new MigratableEntityProxy(
                    address(implementation),
                    abi.encodeCall(IMigratableEntity.initialize, (1, curator, abi.encode(address(vault), "")))
                )
            )
        );

        MockLiquidityLaneAccount accountImplementation = new MockLiquidityLaneAccount(address(adapter), address(asset));
        UpgradeableBeacon accountBeacon = new UpgradeableBeacon(address(accountImplementation), curator);

        vm.startPrank(curator);
        adapter.setAccountBeacon(address(tokenToRedeem), address(accountBeacon));
        adapter.setOracle(address(asset), address(new MockLiquidityLaneOracle(1e18)));
        adapter.setOracle(address(tokenToRedeem), address(new MockLiquidityLaneOracle(1e18)));
        adapter.setLimit(address(vault), address(tokenToRedeem), type(uint256).max);
        adapter.setMakerMaker(address(vault), marketMaker, true);
        vm.stopPrank();
    }

    function testSwapAllocatesThroughDelegatorAndSyncsRedemption() public {
        address account = adapter.getAccount(address(vault), address(tokenToRedeem));

        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.startPrank(marketMaker);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient,
                vault: address(vault),
                tokenIn: address(tokenToRedeem),
                amountIn: 100 ether,
                amountOut: 90 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertEq(tokenToRedeem.balanceOf(account), 100 ether);
        assertEq(adapter.allocated(address(vault), address(tokenToRedeem)), 90 ether);
        assertEq(adapter.totalAssets(), 90 ether);
        assertEq(asset.balanceOf(address(vault)), 10 ether);

        asset.mint(account, 95 ether);
        uint256 deallocated = delegator.deallocate(address(adapter), 90 ether);

        assertEq(deallocated, 95 ether);
        assertEq(adapter.allocated(address(vault), address(tokenToRedeem)), 0);
        assertEq(asset.balanceOf(address(vault)), 105 ether);
        assertEq(adapter.totalAssets(), 0);
    }

    function testPrefundedAcquisitionDoesNotAllocateVaultAssetsAndPaysReceiver() public {
        address account = adapter.getAccount(address(vault), address(tokenToRedeem));

        asset.mint(curator, 40 ether);
        asset.mint(marketMaker, 60 ether);

        vm.startPrank(curator);
        adapter.setReceiver(curatorReceiver);
        asset.approve(address(adapter), 40 ether);
        adapter.depositToAcquire(address(vault), address(tokenToRedeem), 40 ether);
        adapter.setFiller(address(vault), filler, true);
        vm.stopPrank();

        vm.startPrank(marketMaker);
        adapter.setReceiver(marketMakerReceiver);
        asset.approve(address(adapter), 60 ether);
        adapter.depositToAcquire(address(vault), address(tokenToRedeem), 60 ether);
        vm.stopPrank();

        tokenToRedeem.mint(filler, 100 ether);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient,
                vault: address(vault),
                tokenIn: address(tokenToRedeem),
                amountIn: 100 ether,
                amountOut: 100 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 100 ether);
        assertEq(tokenToRedeem.balanceOf(curatorReceiver), 40 ether);
        assertEq(tokenToRedeem.balanceOf(marketMakerReceiver), 60 ether);
        assertEq(tokenToRedeem.balanceOf(filler), 0);
        assertEq(tokenToRedeem.balanceOf(account), 0);
        assertEq(adapter.acquireTotal(address(vault)), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testSetReceiverRevertsForZeroReceiver() public {
        vm.expectRevert(ILiquidityLaneAdapter.InvalidReceiver.selector);
        adapter.setReceiver(address(0));
    }

    function testDepositToAcquireRequiresReceiver() public {
        asset.mint(marketMaker, 60 ether);

        vm.startPrank(marketMaker);
        asset.approve(address(adapter), 60 ether);
        vm.expectRevert(ILiquidityLaneAdapter.InvalidReceiver.selector);
        adapter.depositToAcquire(address(vault), address(tokenToRedeem), 60 ether);
        vm.stopPrank();
    }

    function testSignedSwapUsesSignerAuthorizationAndNonce() public {
        uint256 signerKey = 0xA11CE;
        address signer = vm.addr(signerKey);

        vm.prank(curator);
        adapter.setMakerMaker(address(vault), signer, false);

        asset.mint(address(vault), 90 ether);
        tokenToRedeem.mint(filler, 100 ether);

        ILiquidityLaneAdapter.SignedSwap memory signedSwap = ILiquidityLaneAdapter.SignedSwap({
            recipient: recipient,
            vault: address(vault),
            tokenIn: address(tokenToRedeem),
            amountIn: 100 ether,
            amountOut: 90 ether,
            caller: filler,
            signer: signer,
            nonce: 7,
            deadline: block.timestamp + 1 days
        });
        bytes memory signature = _signSignedSwap(signerKey, signedSwap);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(signedSwap, signature);
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertTrue(adapter.isUsedNonce(address(vault), address(tokenToRedeem), 7));

        vm.prank(filler);
        vm.expectRevert(ILiquidityLaneAdapter.AlreadyUsedNonce.selector);
        adapter.swap(signedSwap, signature);
    }

    function testDiscountSwapUsesReusableSignerDiscountAndProtocolCosign() public {
        uint256 signerKey = 0xB0B;
        uint256 protocolKey = 0xC0DE;
        address signer = vm.addr(signerKey);
        address protocol = vm.addr(protocolKey);

        vm.prank(curator);
        adapter.setMakerMaker(address(vault), signer, false);

        ILiquidityLaneAdapter.Discount memory discount = ILiquidityLaneAdapter.Discount({
            vault: address(vault),
            tokenToRedeem: address(tokenToRedeem),
            discount: 100_000,
            signer: signer,
            protocol: protocol,
            nonce: 9,
            deadline: uint48(block.timestamp + 1 days)
        });
        bytes memory signerSignature = _signDiscount(signerKey, discount);
        ILiquidityLaneAdapter.DiscountSwap memory discountSwap = ILiquidityLaneAdapter.DiscountSwap({
            discount: discount, signerSignature: signerSignature, protocolDeadline: uint48(block.timestamp + 5 minutes)
        });
        bytes memory protocolSignature = _signDiscountSwap(protocolKey, discountSwap);

        asset.mint(address(vault), 90 ether);
        tokenToRedeem.mint(filler, 100 ether);

        vm.startPrank(filler);
        tokenToRedeem.transfer(address(adapter), 100 ether);
        adapter.swap(discountSwap, protocolSignature, recipient, 100 ether, 90 ether);
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertTrue(adapter.isUsedNonce(address(vault), address(tokenToRedeem), 9));
    }

    function testSwapRevertsWhenRateViolatesMinDiscount() public {
        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.prank(curator);
        adapter.setMinDiscount(address(vault), address(tokenToRedeem), 100_000);

        vm.startPrank(marketMaker);
        tokenToRedeem.approve(address(adapter), 100 ether);
        vm.expectRevert(ILiquidityLaneAdapter.InvalidSwapRate.selector);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient,
                vault: address(vault),
                tokenIn: address(tokenToRedeem),
                amountIn: 100 ether,
                amountOut: 100 ether
            })
        );
        vm.stopPrank();
    }

    function _signSignedSwap(uint256 signerKey, ILiquidityLaneAdapter.SignedSwap memory signedSwap)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                SIGNED_SWAP_TYPEHASH,
                signedSwap.recipient,
                signedSwap.vault,
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

    function _signDiscount(uint256 signerKey, ILiquidityLaneAdapter.Discount memory discount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                DISCOUNT_TYPEHASH,
                discount.vault,
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

    function _signDiscountSwap(uint256 signerKey, ILiquidityLaneAdapter.DiscountSwap memory discountSwap)
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
                        discountSwap.discount.vault,
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
                keccak256(bytes("LiquidityLaneAdapter")),
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

contract MockLiquidityLaneRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MockLiquidityLaneVault {
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

contract MockLiquidityLaneDelegator {
    address public immutable vault;

    constructor(address vault_) {
        vault = vault_;
    }

    function allocatable(address) external view returns (uint256) {
        return IERC20(MockLiquidityLaneVault(vault).asset()).balanceOf(vault);
    }

    function limitOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function allocate(address adapter, uint256 assets) external returns (uint256 allocated) {
        MockLiquidityLaneVault(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            MockLiquidityLaneVault(vault).push(assets - allocated, adapter);
        }
    }

    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            MockLiquidityLaneVault(vault).push(deallocated, adapter);
        }
    }
}

contract MockLiquidityLaneAccount is ILiquidityLaneAccount {
    address public immutable adapter;
    address public immutable asset;
    address public vault;
    uint256 public owed;

    constructor(address adapter_, address asset_) {
        adapter = adapter_;
        asset = asset_;
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

    function redeem() external view {
        if (msg.sender != adapter) {
            revert NotAdapter();
        }
    }

    function redeem(uint256, uint256 amountSpent) external onlyAdapter {
        owed += amountSpent;
    }

    function convertRedemption(address, address, uint256, uint256, bytes calldata) external view onlyAdapter {}

    function deallocate() external onlyAdapter returns (uint256 principal, uint256 rewards) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        principal = balance < owed ? balance : owed;
        rewards = balance - principal;
        owed -= principal;
        IERC20(asset).approve(adapter, principal + rewards);
    }
}

contract MockLiquidityLaneOracle {
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
