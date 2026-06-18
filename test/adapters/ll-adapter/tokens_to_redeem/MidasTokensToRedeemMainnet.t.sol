// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mainnet-fork suite: requires `ETH_RPC_URL` (skipped otherwise). Last updated for the
///      cutoff-based redemptions change: mGLOBAL is now a `CutoffMidasAccount` with a
///      26th-of-month cutoff, 3-day pre-cutoff window and 36-hour cooldown. Re-run on fork
///      after any change to the Midas accounts.
import {Test} from "forge-std/Test.sol";

import {CutoffMidasAccount, MidasAccount} from "../../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {mAPOLLO_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mAPOLLO_Account.sol";
import {mBASIS_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBASIS_Account.sol";
import {mBTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBTC_Account.sol";
import {mEDGE_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEDGE_Account.sol";
import {mEVUSD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEVUSD_Account.sol";
import {mFARM_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFARM_Account.sol";
import {mFONE_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {mGLOBAL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {mHYPER_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {mHyperBTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperBTC_Account.sol";
import {mHyperETH_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperETH_Account.sol";
import {mM1USD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {mMEV_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mMEV_Account.sol";
import {mevBTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mevBTC_Account.sol";
import {mRe7BTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7BTC_Account.sol";
import {mRe7YIELD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7YIELD_Account.sol";
import {mROX_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {mSL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mSL_Account.sol";
import {
    msyrupUSDp_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSDp_Account.sol";
import {msyrupUSD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSD_Account.sol";
import {mTBILL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mTBILL_Account.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {AdapterFactory} from "../../../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {MigratablesFactory} from "../../../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../../../src/contracts/common/Registry.sol";
import {ILiquidLaneAdapter} from "../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAdapter} from "../../../../src/interfaces/adapters/IAdapter.sol";
import {IAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IMidasDataFeed} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {REQUEST_STATUS_PENDING} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MidasTokensToRedeemMainnetTest is Test {
    struct TokenSpec {
        string symbol;
        uint48 maxWithdrawalDelay;
    }

    struct MGlobalCycle {
        address account;
        address llAdapter;
        address vault;
        address delegator;
    }

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address internal constant MIDAS_ACCESS_CONTROL_ADMIN = 0xd4195CF4df289a4748C1A7B6dDBE770e27bA1227;
    address internal constant MIDAS_GREENLIST_ADMIN = 0xb5CcD8dC8082467849eE008d4242f7b3b569EF05;
    address internal constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;

    address internal adapter = makeAddr("adapter");
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testOnboardsEthereumMainnetMidasTokensToRedeem() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Midas onboarding");
        vm.createSelectFork(mainnetRpcUrl);

        MidasTokensToRedeemAssetVault vault = new MidasTokensToRedeemAssetVault(MAINNET_USDC);
        TokenSpec[] memory specs = _ethereumMainnetSpecs();
        assertEq(specs.length, 23);

        for (uint256 i; i < specs.length; ++i) {
            _assertOnboarded(i, specs[i], vault);
        }
    }

    function testOnboardsRequestedPikuMidasTokensToRedeem() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Midas onboarding");
        vm.createSelectFork(mainnetRpcUrl);

        MidasTokensToRedeemAssetVault vault = new MidasTokensToRedeemAssetVault(MAINNET_USDC);
        TokenSpec[] memory specs = _ethereumMainnetSpecs();

        for (uint256 i = 21; i < specs.length; ++i) {
            _assertOnboarded(i, specs[i], vault);
        }
    }

    function testMGlobalMainnetFullSwapRedemptionCycle() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet mGLOBAL cycle");
        vm.createSelectFork(mainnetRpcUrl);

        MGlobalCycle memory cycle = _setUpMGlobalCycle();
        (uint256 requestId, uint256 amountOut, uint256 expectedRedeemedAssets) = _swapAndAssertPendingMGlobal(cycle);
        _approveMGlobalRequest(cycle.account, requestId, expectedRedeemedAssets);
        _assertFinalizedAndDeallocateMGlobal(
            cycle.account, cycle.llAdapter, cycle.vault, cycle.delegator, amountOut, expectedRedeemedAssets
        );
    }

    function _setUpMGlobalCycle() internal returns (MGlobalCycle memory cycle) {
        address vaultFactory = address(new MidasMainnetVaultRegistry());
        cycle.vault = address(new MidasMainnetLiquidLaneVault(MAINNET_USDC));
        cycle.delegator = address(new MidasMainnetDelegator(cycle.vault));
        address adapterFactory = address(new AdapterFactory(address(this)));
        address accountRegistry = address(new AccountRegistry(address(this)));
        address accountFactory = address(new MigratablesFactory(address(this)));

        MidasMainnetVaultRegistry(vaultFactory).add(cycle.vault);
        MidasMainnetLiquidLaneVault(cycle.vault).setDelegator(cycle.delegator);

        address adapterImplementation = address(new LiquidLaneAdapter(vaultFactory, adapterFactory, accountRegistry));
        address accountImplementation = address(new mGLOBAL_Account(accountFactory, COW_SWAP_SETTLEMENT));

        AdapterFactory(adapterFactory).whitelist(adapterImplementation);
        MigratablesFactory(accountFactory).whitelist(accountImplementation);
        AccountRegistry(accountRegistry).setAccountFactory(MAINNET_USDC, MGLOBAL, accountFactory);

        ILiquidLaneAdapter.InitParams memory params =
            ILiquidLaneAdapter.InitParams({pauser: address(this), unpauser: address(this)});
        cycle.llAdapter =
            AdapterFactory(adapterFactory).create(1, address(this), abi.encode(cycle.vault, abi.encode(params)));

        LiquidLaneAdapter(cycle.llAdapter).addTokenToRedeem(MGLOBAL);
        LiquidLaneAdapter(cycle.llAdapter).setLimit(MGLOBAL, type(uint256).max);

        cycle.account = LiquidLaneAdapter(cycle.llAdapter).accounts(MGLOBAL);
        _configureMidasRequestPath(cycle.account, cycle.llAdapter);
    }

    function _swapAndAssertPendingMGlobal(MGlobalCycle memory cycle)
        internal
        returns (uint256 requestId, uint256 amountOut, uint256 expectedRedeemedAssets)
    {
        uint256 amountIn = 10 ** IERC20Metadata(MGLOBAL).decimals();
        amountOut = LiquidLaneAdapter(cycle.llAdapter).getAmountOut(MGLOBAL, amountIn);
        address recipient = makeAddr("recipient");

        _mockHealthyMGlobalDataFeed(cycle.account);
        vm.warp(uint256(CutoffMidasAccount(cycle.account).nextCutoff()) - 1 days);
        deal(MGLOBAL, cycle.llAdapter, amountIn);
        deal(MAINNET_USDC, cycle.vault, amountOut);

        LiquidLaneAdapter(cycle.llAdapter)
            .swap(
                ILiquidLaneAdapter.Swap({
                recipient: recipient, tokenIn: MGLOBAL, amountIn: amountIn, amountOut: amountOut
            })
            );

        (requestId, expectedRedeemedAssets) =
            _assertPendingMGlobalRequest(cycle.account, cycle.llAdapter, recipient, amountOut);
    }

    function _mockHealthyMGlobalDataFeed(address account) internal {
        address dataFeed = address(IMidasRedemptionVault(MidasAccount(account).REDEMPTION_VAULT()).mTokenDataFeed());
        uint256 price = IMidasDataFeed(dataFeed).getDataInBase18();
        vm.mockCall(dataFeed, abi.encodeWithSelector(IMidasDataFeed.getDataInBase18.selector), abi.encode(price));
    }

    function _assertFinalizedAndDeallocateMGlobal(
        address account,
        address llAdapter,
        address vault,
        address delegator,
        uint256 amountOut,
        uint256 expectedRedeemedAssets
    ) internal {
        assertEq(IERC20(MAINNET_USDC).balanceOf(account), expectedRedeemedAssets);
        assertEq(MidasAccount(account).totalAssets(), expectedRedeemedAssets);

        MidasAccount(account).sync();

        vm.expectRevert();
        MidasAccount(account).requestIds(0);
        assertEq(LiquidLaneAdapter(llAdapter).totalAssets(), expectedRedeemedAssets);
        assertEq(LiquidLaneAdapter(llAdapter).freeAssets(), expectedRedeemedAssets);

        uint256 deallocated = MidasMainnetDelegator(delegator).deallocate(llAdapter, amountOut);

        assertEq(deallocated, expectedRedeemedAssets);
        assertEq(IERC20(MAINNET_USDC).balanceOf(vault), expectedRedeemedAssets);
        assertEq(LiquidLaneAdapter(llAdapter).totalAssets(), 0);
        assertEq(LiquidLaneAdapter(llAdapter).freeAssets(), 0);
    }

    function _assertPendingMGlobalRequest(address account, address llAdapter, address recipient, uint256 amountOut)
        internal
        view
        returns (uint256 requestId, uint256 expectedRedeemedAssets)
    {
        requestId = MidasAccount(account).requestIds(0);
        (
            address sender,
            address tokenOut,
            uint8 status,
            uint256 amountMToken,
            uint256 mTokenRate,
            uint256 tokenOutRate
        ) = IMidasRedemptionVault(MidasAccount(account).REDEMPTION_VAULT()).redeemRequests(requestId);

        assertEq(sender, account);
        assertEq(tokenOut, MAINNET_USDC);
        assertEq(status, REQUEST_STATUS_PENDING);
        assertGt(amountMToken, 0);
        assertGt(MidasAccount(account).totalAssets(), 0);
        assertEq(IERC20(MGLOBAL).balanceOf(llAdapter), 0);
        assertEq(IERC20(MGLOBAL).balanceOf(account), 0);
        assertEq(IERC20(MAINNET_USDC).balanceOf(recipient), amountOut);

        expectedRedeemedAssets = amountMToken * mTokenRate / tokenOutRate / 1e12;
    }

    function _approveMGlobalRequest(address account, uint256 requestId, uint256 expectedRedeemedAssets) internal {
        address redemptionVault = MidasAccount(account).REDEMPTION_VAULT();
        (,,,, uint256 mTokenRate,) = IMidasRedemptionVault(redemptionVault).redeemRequests(requestId);
        address requestRedeemer = IMidasLiveRedemptionVault(redemptionVault).requestRedeemer();

        deal(MAINNET_USDC, requestRedeemer, expectedRedeemedAssets);
        vm.prank(requestRedeemer);
        IERC20(MAINNET_USDC).approve(redemptionVault, type(uint256).max);

        _grantMidasRole(
            IMidasVaultAdmin(redemptionVault).accessControl(),
            IMidasVaultAdmin(redemptionVault).vaultRole(),
            address(this)
        );
        IMidasLiveRedemptionVault(redemptionVault).approveRequest(requestId, mTokenRate);
    }

    function _assertOnboarded(uint256 index, TokenSpec memory spec, MidasTokensToRedeemAssetVault vault) internal {
        emit log_named_string("token", spec.symbol);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MidasAccount implementation = _deployImplementation(index, factory);
        address token = implementation.TOKEN_TO_REDEEM();
        address redemptionToken = implementation.REDEMPTION_TOKEN();
        address redemptionVault = implementation.REDEMPTION_VAULT();

        assertEq(IMidasTokenRedeemConfig(address(implementation)).MAX_WITHDRAWAL_DELAY(), spec.maxWithdrawalDelay);

        factory.whitelist(address(implementation));
        MidasAccount account = MidasAccount(factory.create(1, address(this), _initData(token, vault)));

        assertEq(IERC20Metadata(token).symbol(), spec.symbol);
        assertEq(IMidasRedemptionVaultWithMToken(redemptionVault).mToken(), token);
        assertEq(account.TOKEN_TO_REDEEM(), token);
        assertEq(account.REDEMPTION_TOKEN(), redemptionToken);
        assertEq(account.REDEMPTION_VAULT(), redemptionVault);
        assertEq(account.ORACLE(), implementation.ORACLE());
        assertEq(account.COOLDOWN(), _cooldown(index, spec.maxWithdrawalDelay));
        assertEq(account.converters(0), address(this));
        assertEq(account.adapter(), adapter);
        assertEq(account.vault(), address(vault));
        assertEq(
            MidasOracle(account.ORACLE()).DATA_FEED(), address(IMidasRedemptionVault(redemptionVault).mTokenDataFeed())
        );
        _stabilizeMidasDataFeed(MidasOracle(account.ORACLE()).DATA_FEED());
        assertGt(MidasOracle(account.ORACLE()).getPrice(), 0);
        assertEq(IERC20(token).allowance(address(account), redemptionVault), type(uint256).max);
        assertEq(IAccount(address(account)).totalAssets(), 0);

        if (keccak256(bytes(spec.symbol)) == keccak256("mGLOBAL")) {
            // mGLOBAL is a CutoffMidasAccount: bucket conversion is fixed to the 26th of each month.
            assertEq(
                CutoffMidasAccount(address(account))
                    .bucketToTimestamp(CutoffMidasAccount(address(account)).timestampToBucket(1_784_505_600)),
                0
            );
        }
    }

    function _initData(address, MidasTokensToRedeemAssetVault vault) internal view returns (bytes memory) {
        return abi.encode(address(vault), adapter);
    }

    function _ethereumMainnetSpecs() internal pure returns (TokenSpec[] memory specs) {
        specs = new TokenSpec[](23);
        specs[0] = TokenSpec("mF-ONE", 35 days);
        specs[1] = _ethereumCompSpec("mTBILL", 3 days);
        specs[2] = _ethereumCompSpec("mGLOBAL", 65 days);
        specs[3] = _ethereumCompSpec("mHYPER", 3 days);
        specs[4] = _ethereumCompSpec("mM1-USD", 17 days);
        specs[5] = _ethereumCompSpec("mHyperBTC", 7 days);
        specs[6] = _ethereumCompSpec("mRe7YIELD", 24 days);
        specs[7] = _ethereumCompSpec("mHyperETH", 7 days);
        specs[8] = _ethereumCompSpec("mSL", 3 days);
        specs[9] = _ethereumCompSpec("mAPOLLO", 3 days);
        specs[10] = _ethereumCompSpec("mROX", 3 days);
        specs[11] = _ethereumCompSpec("msyrupUSDp", 3 days);
        specs[12] = _ethereumCompSpec("mEVUSD", 3 days);
        specs[13] = _ethereumCompSpec("mEDGE", 3 days);
        specs[14] = _ethereumCompSpec("mMEV", 3 days);
        specs[15] = _ethereumCompSpec("mBASIS", 7 days);
        specs[16] = _ethereumCompSpec("mRe7BTC", 24 days);
        specs[17] = _ethereumCompSpec("mBTC", 7 days);
        specs[18] = _ethereumCompSpec("mevBTC", 7 days);
        specs[19] = _ethereumCompSpec("msyrupUSD", 7 days);
        specs[20] = _ethereumCompSpec("mFARM", 7 days);
        specs[21] = _ethereumCompSpec("CarryTradeUSDTRYLeverage", 2 days);
        specs[22] = _ethereumCompSpec("StockMarketTRBasisTrade", 2 days);
    }

    function _deployImplementation(uint256 index, MigratablesFactory factory)
        internal
        returns (MidasAccount implementation)
    {
        if (index == 0) {
            return new mFONE_Account(address(factory), COW_SWAP_SETTLEMENT);
        }
        if (index == 1) return new mTBILL_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 2) return new mGLOBAL_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 3) return new mHYPER_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 4) return new mM1USD_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 5) return new mHyperBTC_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 6) return new mRe7YIELD_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 7) return new mHyperETH_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 8) return new mSL_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 9) return new mAPOLLO_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 10) return new mROX_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 11) return new msyrupUSDp_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 12) return new mEVUSD_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 13) return new mEDGE_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 14) return new mMEV_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 15) return new mBASIS_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 16) return new mRe7BTC_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 17) return new mBTC_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 18) return new mevBTC_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 19) return new msyrupUSD_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 20) return new mFARM_Account(address(factory), COW_SWAP_SETTLEMENT);
        if (index == 21) {
            return new CarryTradeUSDTRYLeverage_Account(address(factory), COW_SWAP_SETTLEMENT);
        }
        return new StockMarketTRBasisTrade_Account(address(factory), COW_SWAP_SETTLEMENT);
    }

    function _ethereumCompSpec(string memory symbol, uint48 maxWithdrawalDelay)
        internal
        pure
        returns (TokenSpec memory spec)
    {
        spec = TokenSpec(symbol, maxWithdrawalDelay);
    }

    function _cooldown(uint256 index, uint48 maxWithdrawalDelay) internal pure returns (uint48) {
        if (index == 2) {
            return 36 hours;
        }

        uint48 cooldownDays = maxWithdrawalDelay / 10 / 1 days;
        if (cooldownDays == 0) {
            return 1 days;
        }
        return cooldownDays * 1 days;
    }

    function _configureMidasRequestPath(address account, address llAdapter) internal {
        address redemptionVault = MidasAccount(account).REDEMPTION_VAULT();
        address accessControl = IMidasVaultAdmin(redemptionVault).accessControl();

        if (IMidasVaultAdmin(redemptionVault).greenlistEnabled()) {
            bytes32 greenlistedRole = IMidasVaultAdmin(redemptionVault).greenlistedRole();
            _grantMidasRole(accessControl, greenlistedRole, account);
            _grantMidasRole(accessControl, greenlistedRole, llAdapter);
        }

        bytes32 pauseAdminRole = IMidasVaultAdmin(redemptionVault).pauseAdminRole();
        if (IMidasVaultAdmin(redemptionVault).paused()) {
            _grantMidasRole(accessControl, pauseAdminRole, address(this));
            IMidasVaultAdmin(redemptionVault).unpause();
        }

        bytes4 redeemRequestSelector = IMidasRedemptionVault.redeemRequest.selector;
        if (IMidasVaultAdmin(redemptionVault).fnPaused(redeemRequestSelector)) {
            _grantMidasRole(accessControl, pauseAdminRole, address(this));
            IMidasVaultAdmin(redemptionVault).unpauseFn(redeemRequestSelector);
        }

        address mTokenDataFeed = address(IMidasRedemptionVault(redemptionVault).mTokenDataFeed());
        _stabilizeMidasDataFeed(mTokenDataFeed);

        (address dataFeed, uint256 fee, uint256 allowance, bool stable) =
            IMidasRedemptionVault(redemptionVault).tokensConfig(MAINNET_USDC);
        if (dataFeed == address(0)) {
            _grantMidasRole(accessControl, IMidasVaultAdmin(redemptionVault).vaultRole(), address(this));
            IMidasVaultAdmin(redemptionVault).addPaymentToken(MAINNET_USDC, mTokenDataFeed, 0, type(uint256).max, true);
            return;
        }
        if (stable && dataFeed != mTokenDataFeed) {
            _grantMidasRole(accessControl, IMidasVaultAdmin(redemptionVault).vaultRole(), address(this));
            IMidasVaultAdmin(redemptionVault).removePaymentToken(MAINNET_USDC);
            IMidasVaultAdmin(redemptionVault).addPaymentToken(MAINNET_USDC, mTokenDataFeed, fee, allowance, stable);
            dataFeed = mTokenDataFeed;
        }

        _stabilizeMidasDataFeed(dataFeed);
    }

    function _stabilizeMidasDataFeed(address dataFeed) internal {
        (bool success,) = dataFeed.staticcall(abi.encodeWithSelector(IMidasDataFeed.getDataInBase18.selector));
        if (success) {
            return;
        }

        (,,, uint256 updatedAt,) = IChainlinkAggregatorV3(IMidasDataFeed(dataFeed).aggregator()).latestRoundData();
        vm.warp(updatedAt + IMidasLiveDataFeed(dataFeed).healthyDiff() / 2);
    }

    function _grantMidasRole(address accessControl, bytes32 role, address account) internal {
        if (IMidasAccessControl(accessControl).hasRole(role, account)) {
            return;
        }

        bytes32 adminRole = IMidasAccessControl(accessControl).getRoleAdmin(role);
        address admin = MIDAS_ACCESS_CONTROL_ADMIN;
        if (!IMidasAccessControl(accessControl).hasRole(adminRole, admin)) {
            admin = MIDAS_GREENLIST_ADMIN;
        }
        assertTrue(IMidasAccessControl(accessControl).hasRole(adminRole, admin));

        vm.prank(admin);
        IMidasAccessControl(accessControl).grantRole(role, account);
    }

    function _skipWithoutRpc(string memory rpcUrl, string memory reason) internal {
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, reason);
        }
    }
}

interface IMidasRedemptionVaultWithMToken is IMidasRedemptionVault {
    function mToken() external view returns (address);
}

interface IMidasTokenRedeemConfig {
    function MAX_WITHDRAWAL_DELAY() external view returns (uint48);
}

contract MidasTokensToRedeemAssetVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MidasMainnetVaultRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MidasMainnetLiquidLaneVault {
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

contract MidasMainnetDelegator {
    address public immutable vault;

    constructor(address vault_) {
        vault = vault_;
    }

    function limitOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function sweepPending() external pure returns (uint256) {
        return 0;
    }

    function allocateExact(address adapter, uint256 assets) external returns (uint256 allocated) {
        MidasMainnetLiquidLaneVault(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            MidasMainnetLiquidLaneVault(vault).push(assets - allocated, adapter);
        }
    }

    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            MidasMainnetLiquidLaneVault(vault).push(deallocated, adapter);
        }
    }
}

interface IMidasLiveRedemptionVault is IMidasRedemptionVault {
    function approveRequest(uint256 requestId, uint256 newMTokenRate) external;

    function requestRedeemer() external view returns (address);
}

interface IMidasLiveDataFeed is IMidasDataFeed {
    function healthyDiff() external view returns (uint256);
}

interface IMidasVaultAdmin {
    function accessControl() external view returns (address);

    function addPaymentToken(address token, address dataFeed, uint256 tokenFee, uint256 allowance, bool stable) external;

    function fnPaused(bytes4 selector) external view returns (bool);

    function greenlistEnabled() external view returns (bool);

    function greenlistedRole() external view returns (bytes32);

    function pauseAdminRole() external view returns (bytes32);

    function paused() external view returns (bool);

    function removePaymentToken(address token) external;

    function unpause() external;

    function unpauseFn(bytes4 selector) external;

    function vaultRole() external view returns (bytes32);
}

interface IMidasAccessControl {
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function grantRole(bytes32 role, address account) external;
}

interface IChainlinkAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
