// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccountsBase, MockERC20, MockOracle} from "./AccountsBase.t.sol";

import {ParetoAccount} from "../../../src/contracts/adapters/ll-adapter/ParetoAccount.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IParetoAccount} from "../../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ParetoAccountTest is AccountsBase {
    uint256 internal constant TRANCHE_UNIT = 1e18;
    uint256 internal constant VIRTUAL_PRICE = 1_100_000;

    MockERC20 internal tranche;
    MockERC20 internal usdc;
    ParetoTestCreditVault internal creditVault;
    ParetoTestWithdrawalQueue internal withdrawalQueue;
    MockOracle internal oracle;
    ParetoAccount internal account;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tranche = new MockERC20("Pareto AA Tranche", "AA_TEST", 18);
        creditVault = new ParetoTestCreditVault();
        withdrawalQueue = new ParetoTestWithdrawalQueue(creditVault, usdc, tranche);
        oracle = new MockOracle(VIRTUAL_PRICE * 1e12);
        account = _deployPareto();
    }

    function test_TotalAssets_UsesOracleForHeldAndUnprocessedQueueInventory() public {
        oracle.setPrice(1_050_000e12);
        tranche.mint(address(account), 2 * TRANCHE_UNIT);

        assertEq(account.totalAssets(), 2_100_000);

        account.sync();

        assertEq(withdrawalQueue.userWithdrawalsEpochs(address(account), 13), 2 * TRANCHE_UNIT);
        assertEq(account.totalAssets(), 2_100_000);
    }

    function test_Sync_ReturnsWithoutQueueCallWhenBalanceIsZero() public {
        account.sync();

        assertEq(withdrawalQueue.requestCalls(), 0);
    }

    function test_Sync_AggregatesSameQueueEpochWithoutDuplicateTracking() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();
        tranche.mint(address(account), 2 * TRANCHE_UNIT);
        account.sync();

        assertEq(withdrawalQueue.userWithdrawalsEpochs(address(account), 13), 3 * TRANCHE_UNIT);
        assertEq(account.queueEpochs(0), 13);
        vm.expectRevert();
        account.queueEpochs(1);
    }

    function test_Sync_ClaimsReadyQueueEpochAndPreservesPendingEpoch() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();

        creditVault.setEpochNumber(13);
        tranche.mint(address(account), 2 * TRANCHE_UNIT);
        account.sync();

        withdrawalQueue.processEpoch(13, 1_050_000);
        withdrawalQueue.settleEpoch(13);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 1_050_000);
        assertEq(account.queueEpochs(0), 14);
        vm.expectRevert();
        account.queueEpochs(1);

        withdrawalQueue.processEpoch(14, 1_075_000);
        withdrawalQueue.settleEpoch(14);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 3_200_000);
        vm.expectRevert();
        account.queueEpochs(0);
    }

    function test_TotalAssets_UsesRebasedFinalQueuePrice() public {
        tranche.mint(address(account), 2 * TRANCHE_UNIT);
        account.sync();

        withdrawalQueue.processEpoch(13, 1_100_000);
        assertEq(account.totalAssets(), 2_200_000);

        withdrawalQueue.settleEpochAtPrice(13, 1_050_000);
        assertEq(account.totalAssets(), 2_100_000);

        account.sync();
        assertEq(usdc.balanceOf(address(account)), 2_100_000);
    }

    function test_Sync_PropagatesUnexpectedQueueClaimFailure() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();

        withdrawalQueue.processEpoch(13, VIRTUAL_PRICE);
        withdrawalQueue.settleEpoch(13);
        withdrawalQueue.setFailClaim(true);

        vm.expectRevert(ParetoTestWithdrawalQueue.UnexpectedClaimFailure.selector);
        account.sync();

        assertEq(account.queueEpochs(0), 13);
    }

    function test_Sync_WaitsForQueueSettlementBeforeClaim() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();

        withdrawalQueue.processEpoch(13, VIRTUAL_PRICE);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 0);
        assertEq(withdrawalQueue.userWithdrawalsEpochs(address(account), 13), TRANCHE_UNIT);
        assertEq(account.queueEpochs(0), 13);

        withdrawalQueue.settleEpoch(13);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), VIRTUAL_PRICE);
    }

    function test_Sync_QueueRequestFailureRollsBackTrackedEpoch() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        withdrawalQueue.setRejectRequest(true);

        vm.expectRevert(ParetoTestWithdrawalQueue.RequestRejected.selector);
        account.sync();

        assertEq(tranche.balanceOf(address(account)), TRANCHE_UNIT);
        vm.expectRevert();
        account.queueEpochs(0);
    }

    function test_Sync_QueueRequestFailureRollsBackClaim() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();
        withdrawalQueue.processEpoch(13, VIRTUAL_PRICE);
        withdrawalQueue.settleEpoch(13);

        tranche.mint(address(account), 2 * TRANCHE_UNIT);
        withdrawalQueue.setRejectRequest(true);

        vm.expectRevert(ParetoTestWithdrawalQueue.RequestRejected.selector);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 0);
        assertEq(tranche.balanceOf(address(account)), 2 * TRANCHE_UNIT);
        assertEq(withdrawalQueue.userWithdrawalsEpochs(address(account), 13), TRANCHE_UNIT);
        assertEq(account.queueEpochs(0), 13);
    }

    function test_Sync_ClearsTrackedEpochWhoseQueueRequestNoLongerExists() public {
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();

        withdrawalQueue.clearUserRequest(address(account), 13);
        withdrawalQueue.setFailClaim(true);
        account.sync();

        vm.expectRevert();
        account.queueEpochs(0);
    }

    function test_Sync_ClaimsDuringEpochBufferButDefersQueuingWhenEpochNotRunning() public {
        // Queue an epoch while the epoch is running, then settle it during the inter-epoch buffer.
        tranche.mint(address(account), TRANCHE_UNIT);
        account.sync();
        creditVault.setEpochNumber(13);
        withdrawalQueue.processEpoch(13, 1_050_000);
        withdrawalQueue.settleEpoch(13);

        // During the buffer the real queue reverts requestWithdraw with EpochNotRunning; a sync holding
        // fresh tranche tokens must still claim the matured epoch and simply defer the new request.
        creditVault.setEpochRunning(false);
        tranche.mint(address(account), 2 * TRANCHE_UNIT);
        account.sync();

        assertEq(usdc.balanceOf(address(account)), 1_050_000, "matured epoch claimed during buffer");
        assertEq(tranche.balanceOf(address(account)), 2 * TRANCHE_UNIT, "fresh tranche held, not queued");
        assertEq(withdrawalQueue.requestCalls(), 1, "no requestWithdraw during buffer");
        vm.expectRevert();
        account.queueEpochs(0);

        // Once the epoch runs again, the held tranche is queued.
        creditVault.setEpochRunning(true);
        account.sync();
        assertEq(withdrawalQueue.requestCalls(), 2, "queued after epoch resumes");
        assertEq(account.queueEpochs(0), 14);
    }

    function test_Initialize_ApprovesOfficialQueue() public view {
        assertEq(tranche.allowance(address(account), address(withdrawalQueue)), type(uint256).max);
    }

    function test_Initialize_SupportsVaultAssetDifferentFromQueueUnderlying() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ParetoAccount implementation = _newImplementation(address(tranche), address(withdrawalQueue), address(factory));
        factory.whitelist(address(implementation));
        // A USDT vault redeeming Pareto's USDC underlying is supported; the mismatch is settled via CoWSwap.
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        ParetoAccount usdtAccount =
            ParetoAccount(factory.create(1, address(this), _initData(address(usdt), address(tranche))));

        assertEq(usdtAccount.REDEMPTION_TOKEN(), address(usdc));

        // Unprocessed tranche inventory is valued through the oracle in the vault asset.
        oracle.setPrice(1_050_000e12);
        tranche.mint(address(usdtAccount), 2 * TRANCHE_UNIT);
        assertEq(usdtAccount.totalAssets(), 2_100_000);
        usdtAccount.sync();

        // A processed, settled epoch is valued in USDC (1:1 with USDT) whether still claimable...
        creditVault.setEpochNumber(13);
        withdrawalQueue.processEpoch(13, 1_050_000);
        withdrawalQueue.settleEpoch(13);
        assertEq(usdtAccount.totalAssets(), 2_100_000);

        // ...or already claimed into the account's held USDC balance (which the base does not count as
        // the vault asset, so ParetoAccount adds it back).
        usdtAccount.sync();
        assertEq(usdc.balanceOf(address(usdtAccount)), 2_100_000);
        assertEq(usdtAccount.totalAssets(), 2_100_000);
    }

    function _deployPareto() internal returns (ParetoAccount deployedAccount) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ParetoAccount implementation = _newImplementation(address(tranche), address(withdrawalQueue), address(factory));
        factory.whitelist(address(implementation));
        deployedAccount = ParetoAccount(factory.create(1, address(this), _initData(address(usdc), address(tranche))));
    }

    function _newImplementation(address token, address queue, address factory)
        internal
        returns (ParetoAccount implementation)
    {
        implementation = new ParetoAccount(address(oracle), factory, token, queue, cowSwapSettlement);
    }
}

contract ParetoTestCreditVault {
    uint256 public epochNumber = 12;
    bool public isEpochRunning = true;

    function setEpochNumber(uint256 epochNumber_) external {
        epochNumber = epochNumber_;
    }

    function setEpochRunning(bool running) external {
        isEpochRunning = running;
    }
}

contract ParetoTestWithdrawalQueue {
    using SafeERC20 for IERC20;

    error RequestRejected();
    error UnexpectedClaimFailure();

    ParetoTestCreditVault public immutable strategy;
    MockERC20 public immutable underlying;
    MockERC20 public immutable tranche;

    mapping(address account => mapping(uint256 epoch => uint256 shares)) public userWithdrawalsEpochs;
    mapping(uint256 epoch => uint256 price) public epochWithdrawPrice;
    mapping(uint256 epoch => uint256 assets) public epochPendingClaims;
    mapping(uint256 epoch => uint256 shares) public epochPendingWithdrawals;
    mapping(uint256 epoch => uint256 shares) public epochProcessedWithdrawals;
    bool public failClaim;
    bool public rejectRequest;
    uint256 public requestCalls;

    constructor(ParetoTestCreditVault strategy_, MockERC20 underlying_, MockERC20 tranche_) {
        strategy = strategy_;
        underlying = underlying_;
        tranche = tranche_;
    }

    function idleCDOEpoch() external view returns (address) {
        return address(strategy);
    }

    function setFailClaim(bool failClaim_) external {
        failClaim = failClaim_;
    }

    function setRejectRequest(bool rejectRequest_) external {
        rejectRequest = rejectRequest_;
    }

    function clearUserRequest(address account, uint256 epoch) external {
        userWithdrawalsEpochs[account][epoch] = 0;
    }

    function processEpoch(uint256 epoch, uint256 price) external {
        epochWithdrawPrice[epoch] = price;
        uint256 shares = epochPendingWithdrawals[epoch];
        epochPendingWithdrawals[epoch] = 0;
        epochProcessedWithdrawals[epoch] = shares;
        epochPendingClaims[epoch] = shares * price / 1e18;
    }

    function settleEpoch(uint256 epoch) external {
        underlying.mint(address(this), epochPendingClaims[epoch]);
        epochPendingClaims[epoch] = 0;
    }

    function settleEpochAtPrice(uint256 epoch, uint256 price) external {
        epochWithdrawPrice[epoch] = price;
        underlying.mint(address(this), epochProcessedWithdrawals[epoch] * price / 1e18);
        epochPendingClaims[epoch] = 0;
    }

    function claimWithdrawRequest(uint256 epoch) external {
        if (failClaim) {
            revert UnexpectedClaimFailure();
        }
        if (epochWithdrawPrice[epoch] == 0 || epochPendingClaims[epoch] != 0) {
            revert UnexpectedClaimFailure();
        }

        uint256 amount = userWithdrawalsEpochs[msg.sender][epoch];
        userWithdrawalsEpochs[msg.sender][epoch] = 0;
        IERC20(address(underlying)).safeTransfer(msg.sender, amount * epochWithdrawPrice[epoch] / 1e18);
    }

    function requestWithdraw(uint256 amount) external {
        if (rejectRequest) {
            revert RequestRejected();
        }

        ++requestCalls;
        IERC20(address(tranche)).safeTransferFrom(msg.sender, address(this), amount);
        uint256 epoch = strategy.epochNumber() + 1;
        userWithdrawalsEpochs[msg.sender][epoch] += amount;
        epochPendingWithdrawals[epoch] += amount;
    }
}
