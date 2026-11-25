// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle} from "./AccountsBase.t.sol";

import {AssetoOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AssetoOracle.sol";
import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {MAX_REDEEM_QUEUE_LENGTH} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProviderAccountsTest is AccountsBase {
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    function testAssetoOracleReadsLatestPriceData() public {
        MockAssetoPricer pricer = new MockAssetoPricer(975e18, uint48(vm.getBlockTimestamp()));
        AssetoOracle oracle = new AssetoOracle(1, type(uint256).max, address(pricer));

        assertEq(oracle.getPrice(), 975e18);

        pricer.setPrice(2, 976e18, uint48(vm.getBlockTimestamp() + 1));

        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 976e18);
        assertEq(updatedAt, uint48(vm.getBlockTimestamp() + 1));
    }

    function testOpenEdenRedeemQueueLimitIsThirty() public pure {
        assertEq(MAX_REDEEM_QUEUE_LENGTH, 30);
    }

    function testOpenEdenRequestsAndValuesQueuedRedeems() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        hybond.mint(address(account), 2 ether);

        (,, uint256 directPreviewAssets) = express.previewRedeem(2 ether);
        uint256 oracleScaledAssets = account.totalAssets();
        assertEq(directPreviewAssets, 2_398_799);
        assertEq(oracleScaledAssets, 2_398_800);
        assertEq(oracleScaledAssets - directPreviewAssets, 1);
        assertLe(oracleScaledAssets - directPreviewAssets, 1);

        account.sync();

        assertEq(hybond.balanceOf(address(account)), 0);
        assertEq(hybond.balanceOf(address(express)), 2 ether);
        assertEq(express.pendingRedeemInfo(address(account)), 2 ether);
        assertEq(account.totalAssets(), oracleScaledAssets);

        express.processPending(address(account), 1 ether);
        assertEq(account.totalAssets(), oracleScaledAssets);

        express.processRedeem(address(account), 1 ether);
        assertEq(usdc.balanceOf(address(account)), 1_199_400);
        assertEq(account.totalAssets(), 2_398_800);
    }

    function testOpenEdenRevertsRequestBelowExpressRedeemMinimum() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        express.setRedeemMinimum(100 ether);
        hybond.mint(address(account), 99 ether);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "RedeemLessThanMinimum"));
        account.sync();

        assertEq(hybond.balanceOf(address(account)), 99 ether);
        assertEq(express.pendingRedeemInfo(address(account)), 0);

        hybond.mint(address(account), 1 ether);
        account.sync();

        assertEq(hybond.balanceOf(address(account)), 0);
        assertEq(express.pendingRedeemInfo(address(account)), 100 ether);
    }

    function testOpenEdenSupportsDifferentStableAssetAndCountsSettledRedemptionToken() public {
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdt, address(oracle), express);

        hybond.mint(address(account), 2 ether);
        assertEq(account.totalAssets(), 2_398_800);

        account.sync();
        assertEq(account.totalAssets(), 2_398_800);

        express.processPending(address(account), 1 ether);
        express.processRedeem(address(account), 1 ether);

        assertEq(usdc.balanceOf(address(account)), 1_199_400);
        assertEq(usdt.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2_398_800);
    }

    function testOpenEdenUsesLockedFinalQueueValueBelowLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);

        previewOracle.setPrice(15e17);

        assertEq(account.totalAssets(), 2_398_799);
    }

    function testOpenEdenReadsOnlyAccountEntriesBelowQueueLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 2; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);
        previewOracle.setPrice(15e17);

        assertEq(express.getRedeemQueueLength(), MAX_REDEEM_QUEUE_LENGTH - 1);
        assertEq(account.totalAssets(), 2_398_799);
    }

    function testOpenEdenFallsBackToRedeemInfoAtQueueLimit() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 1; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 2 ether);
        previewOracle.setPrice(15e17);

        assertEq(express.getRedeemQueueLength(), MAX_REDEEM_QUEUE_LENGTH);
        assertEq(account.totalAssets(), 2_997_000);
    }

    function testOpenEdenUsesOneOracleCallForPendingAndFallbackRedeems() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);

        for (uint256 i; i < MAX_REDEEM_QUEUE_LENGTH - 1; ++i) {
            express.addRedeemQueueEntry(makeAddr(string.concat("receiver", vm.toString(i))), 1 ether, 1e6, 1e3);
        }
        hybond.mint(address(account), 2 ether);
        account.sync();
        express.processPending(address(account), 1 ether);
        previewOracle.setPrice(15e17);

        vm.expectCall(address(oracle), abi.encodeWithSignature("getPrice()"), 1);
        assertEq(account.totalAssets(), 2_997_000);
    }

    function testOpenEdenPermissionlessRequestsRespectCooldown() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 hybond = new MockERC20("HYBOND", "HYBOND", 18);
        MockOracle previewOracle = new MockOracle(12_006e14);
        MockOpenEdenExpress express = new MockOpenEdenExpress(hybond, usdc, previewOracle);
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));
        OpenEdenAccount account = _deployOpenEden(hybond, usdc, address(oracle), express);
        address caller = makeAddr("caller");

        hybond.mint(address(account), 1 ether);
        vm.prank(caller);
        account.sync();

        hybond.mint(address(account), 1 ether);
        vm.warp(vm.getBlockTimestamp() + TOKEN_COOLDOWN - 1);
        vm.prank(caller);
        account.sync();

        assertEq(express.pendingRedeemInfo(address(account)), 1 ether);
        assertEq(hybond.balanceOf(address(account)), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(caller);
        account.sync();

        assertEq(express.pendingRedeemInfo(address(account)), 2 ether);
        assertEq(hybond.balanceOf(address(account)), 0);
    }

    function _deployOpenEden(MockERC20 hybond, MockERC20 asset, address oracle, MockOpenEdenExpress express)
        internal
        returns (OpenEdenAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        OpenEdenAccount implementation = new OpenEdenAccount(
            oracle, address(factory), TOKEN_COOLDOWN, address(hybond), address(express), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        account = OpenEdenAccount(factory.create(1, address(this), _initData(address(asset), address(hybond))));
    }
}

contract MockAssetoPricer {
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
    }

    mapping(uint256 priceId => PriceInfo priceInfo) public prices;

    uint256 public latestPriceId;

    constructor(uint256 price, uint48 timestamp) {
        setPrice(1, price, timestamp);
    }

    function setPrice(uint256 priceId, uint256 price, uint48 timestamp) public {
        prices[priceId] = PriceInfo({price: price, timestamp: timestamp});
        latestPriceId = priceId;
    }

    function getLatestPrice() external view returns (uint256) {
        return prices[latestPriceId].price;
    }
}

contract MockOpenEdenExpress {
    struct RedeemQueueEntry {
        address sender;
        address receiver;
        uint256 tokenAmount;
        uint256 shareAmount;
        uint256 redeemAssetAmt;
        uint256 feeAssetAmt;
        uint256 requestTimestamp;
        bytes32 id;
    }

    address public immutable token;
    address public immutable redeemAsset;
    address public immutable priceOracle;
    uint256 public redeemMinimum;

    mapping(address account => uint256 amount) public pendingRedeemInfo;
    mapping(address account => uint256 amount) public redeemInfo;
    RedeemQueueEntry[] internal redeemQueue;

    constructor(MockERC20 token_, MockERC20 redeemAsset_, MockOracle priceOracle_) {
        token = address(token_);
        redeemAsset = address(redeemAsset_);
        priceOracle = address(priceOracle_);
    }

    function previewRedeem(uint256 tokenAmount)
        external
        view
        returns (uint256 feeAmt, uint256 redeemAssetAmt, uint256 netRedeemAssetAmt)
    {
        redeemAssetAmt = tokenAmount * MockOracle(priceOracle).getPrice() / 1e30;
        feeAmt = redeemAssetAmt / 1000;
        netRedeemAssetAmt = redeemAssetAmt - feeAmt;
    }

    function setRedeemMinimum(uint256 minimum) external {
        redeemMinimum = minimum;
    }

    function requestRedeem(address to, uint256 tokenAmount) external {
        require(tokenAmount >= redeemMinimum, "RedeemLessThanMinimum");
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        pendingRedeemInfo[to] += tokenAmount;
    }

    function processPending(address account, uint256 tokenAmount) external {
        pendingRedeemInfo[account] -= tokenAmount;
        redeemInfo[account] += tokenAmount;
        (uint256 feeAmt, uint256 redeemAssetAmt,) = this.previewRedeem(tokenAmount);
        redeemQueue.push(
            RedeemQueueEntry({
                sender: account,
                receiver: account,
                tokenAmount: tokenAmount,
                shareAmount: 0,
                redeemAssetAmt: redeemAssetAmt,
                feeAssetAmt: feeAmt,
                requestTimestamp: block.timestamp,
                id: bytes32(redeemQueue.length)
            })
        );
    }

    function processRedeem(address account, uint256 tokenAmount) external {
        RedeemQueueEntry memory request = redeemQueue[0];
        require(request.receiver == account && request.tokenAmount == tokenAmount);
        for (uint256 i; i + 1 < redeemQueue.length; ++i) {
            redeemQueue[i] = redeemQueue[i + 1];
        }
        redeemQueue.pop();
        redeemInfo[account] -= tokenAmount;
        MockERC20(redeemAsset).mint(account, request.redeemAssetAmt - request.feeAssetAmt);
    }

    function addRedeemQueueEntry(address receiver, uint256 tokenAmount, uint256 redeemAssetAmt, uint256 feeAssetAmt)
        external
    {
        redeemInfo[receiver] += tokenAmount;
        redeemQueue.push(
            RedeemQueueEntry({
                sender: receiver,
                receiver: receiver,
                tokenAmount: tokenAmount,
                shareAmount: 0,
                redeemAssetAmt: redeemAssetAmt,
                feeAssetAmt: feeAssetAmt,
                requestTimestamp: block.timestamp,
                id: bytes32(redeemQueue.length)
            })
        );
    }

    function getRedeemQueueLength() external view returns (uint256) {
        return redeemQueue.length;
    }

    function getRedeemQueueInfo(uint256 index)
        external
        view
        returns (
            address sender,
            address receiver,
            uint256 tokenAmount,
            uint256 shareAmount,
            uint256 redeemAssetAmt,
            uint256 feeAssetAmt,
            uint256 requestTimestamp,
            bytes32 id
        )
    {
        RedeemQueueEntry memory request = redeemQueue[index];
        return (
            request.sender,
            request.receiver,
            request.tokenAmount,
            request.shareAmount,
            request.redeemAssetAmt,
            request.feeAssetAmt,
            request.requestTimestamp,
            request.id
        );
    }
}
