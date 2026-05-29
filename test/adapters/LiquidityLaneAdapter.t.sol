// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {LiquidityLaneAdapter} from "../../src/contracts/adapters/LiquidityLaneAdapter.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {
    ILiquidityLaneAdapter,
    LIQUIDITY_LANE_SIGNED_SWAP_TYPEHASH
} from "../../src/interfaces/adapters/ILiquidityLaneAdapter.sol";
import {ILiquidityLaneAccount} from "../../src/interfaces/adapters/liquidity_lane_adapter/ILiquidityLaneAccount.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityLaneAdapterTest is Test {
    MockERC20 internal asset;
    MockERC20 internal tokenToRedeem;
    MockLiquidityLaneAccount internal account;
    MockLiquidityLaneDelegator internal delegator;
    MockLiquidityLaneRegistry internal vaultFactory;
    MockLiquidityLaneVault internal vault;
    LiquidityLaneAdapter internal adapter;

    address internal adapterFactory = makeAddr("adapterFactory");
    address internal curator = makeAddr("curator");
    address internal filler = makeAddr("filler");
    address internal marketMaker = makeAddr("marketMaker");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        asset = new MockERC20("Asset", "ASSET");
        tokenToRedeem = new MockERC20("Token To Redeem", "TTR");
        vaultFactory = new MockLiquidityLaneRegistry();
        vault = new MockLiquidityLaneVault(address(asset));
        delegator = new MockLiquidityLaneDelegator(address(vault));
        vault.setDelegator(address(delegator));
        vaultFactory.add(address(vault));

        LiquidityLaneAdapter implementation =
            new LiquidityLaneAdapter(address(vaultFactory), adapterFactory, address(0));
        adapter = LiquidityLaneAdapter(
            address(
                new MigratableEntityProxy(
                    address(implementation),
                    abi.encodeCall(IMigratableEntity.initialize, (1, curator, abi.encode(address(vault), "")))
                )
            )
        );

        account = new MockLiquidityLaneAccount(address(adapter), address(asset));

        vm.startPrank(curator);
        adapter.setAccount(address(tokenToRedeem), address(account));
        adapter.setOracle(address(asset), address(new MockLiquidityLaneOracle(1e18)));
        adapter.setOracle(address(tokenToRedeem), address(new MockLiquidityLaneOracle(1e18)));
        adapter.setLimit(address(tokenToRedeem), type(uint256).max);
        adapter.setMarketMaker(marketMaker, true);
        vm.stopPrank();
    }

    function testSwapAllocatesThroughDelegatorAndSyncsRedemption() public {
        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.startPrank(marketMaker);
        tokenToRedeem.approve(address(adapter), 100 ether);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 90 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertEq(tokenToRedeem.balanceOf(address(account)), 100 ether);
        assertEq(adapter.allocated(address(tokenToRedeem)), 90 ether);
        assertEq(adapter.allocatedTotal(), 90 ether);
        assertEq(adapter.totalAssets(), 90 ether);
        assertEq(asset.balanceOf(address(vault)), 10 ether);

        asset.mint(address(account), 95 ether);
        (uint256 principal, uint256 rewards) = adapter.sync();

        assertEq(principal, 90 ether);
        assertEq(rewards, 5 ether);
        assertEq(adapter.allocated(address(tokenToRedeem)), 0);
        assertEq(adapter.allocatedTotal(), 0);
        assertEq(adapter.freeAssets(), 95 ether);
        assertEq(adapter.totalAssets(), 95 ether);

        delegator.deallocate(address(adapter), 90 ether);

        assertEq(asset.balanceOf(address(vault)), 105 ether);
        assertEq(adapter.totalAssets(), 0);
    }

    function testPrefundedAcquisitionDoesNotAllocateVaultAssets() public {
        asset.mint(marketMaker, 60 ether);

        vm.startPrank(marketMaker);
        asset.approve(address(adapter), 60 ether);
        adapter.depositToAcquire(address(tokenToRedeem), 60 ether);
        vm.stopPrank();

        vm.prank(curator);
        adapter.setFiller(filler, true);

        tokenToRedeem.mint(filler, 100 ether);

        vm.startPrank(filler);
        tokenToRedeem.approve(address(adapter), 100 ether);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 60 ether
            })
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 60 ether);
        assertEq(tokenToRedeem.balanceOf(marketMaker), 100 ether);
        assertEq(tokenToRedeem.balanceOf(filler), 0);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(adapter.acquireTotal(), 0);
        assertEq(adapter.allocatedTotal(), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testSignedSwapUsesSignerAuthorizationAndNonce() public {
        uint256 signerKey = 0xA11CE;
        address signer = vm.addr(signerKey);

        vm.prank(curator);
        adapter.setMarketMaker(signer, false);

        asset.mint(address(vault), 90 ether);
        tokenToRedeem.mint(filler, 100 ether);

        ILiquidityLaneAdapter.SignedSwap memory signedSwap = ILiquidityLaneAdapter.SignedSwap({
            recipient: recipient,
            tokenIn: address(tokenToRedeem),
            amountIn: 100 ether,
            amountOut: 90 ether,
            caller: filler,
            signer: signer,
            nonce: 7,
            deadline: uint48(block.timestamp + 1 days)
        });
        bytes memory signature = _sign(signerKey, signedSwap);

        vm.startPrank(filler);
        tokenToRedeem.approve(address(adapter), 100 ether);
        adapter.swap(signedSwap, signature);
        vm.stopPrank();

        assertEq(asset.balanceOf(recipient), 90 ether);
        assertTrue(adapter.isUsedNonce(address(tokenToRedeem), 7));

        vm.prank(filler);
        vm.expectRevert(ILiquidityLaneAdapter.AlreadyUsedNonce.selector);
        adapter.swap(signedSwap, signature);
    }

    function testSwapRevertsWhenRateViolatesMinDiscount() public {
        asset.mint(address(vault), 100 ether);
        tokenToRedeem.mint(marketMaker, 100 ether);

        vm.prank(curator);
        adapter.setMinDiscount(address(tokenToRedeem), 100_000);

        vm.startPrank(marketMaker);
        tokenToRedeem.approve(address(adapter), 100 ether);
        vm.expectRevert(ILiquidityLaneAdapter.InvalidRate.selector);
        adapter.swap(
            ILiquidityLaneAdapter.Swap({
                recipient: recipient, tokenIn: address(tokenToRedeem), amountIn: 100 ether, amountOut: 100 ether
            })
        );
        vm.stopPrank();
    }

    function _sign(uint256 signerKey, ILiquidityLaneAdapter.SignedSwap memory signedSwap)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("LiquidityLaneAdapter")),
                keccak256(bytes("1")),
                block.chainid,
                address(adapter)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                LIQUIDITY_LANE_SIGNED_SWAP_TYPEHASH,
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
    uint256 public owed;

    constructor(address adapter_, address asset_) {
        adapter = adapter_;
        asset = asset_;
    }

    function redeem(uint256, uint256 amountSpent) external {
        if (msg.sender != adapter) {
            revert();
        }
        owed += amountSpent;
    }

    function convertRedemption(address, address, uint256, uint256, bytes calldata) external view {
        if (msg.sender != adapter) {
            revert();
        }
    }

    function deallocate() external returns (uint256 principal, uint256 rewards) {
        if (msg.sender != adapter) {
            revert();
        }

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
