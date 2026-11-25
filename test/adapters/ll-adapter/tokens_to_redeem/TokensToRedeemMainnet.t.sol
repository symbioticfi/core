// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mainnet-fork suite: requires `ETH_RPC_URL` (skipped otherwise). Last updated for the
///      infiniFi locked iUSD change (liUSD-4w/liUSD-13w on InfiniFiAccount): their redemption
///      notice is a gateway `startUnwinding` call keyed by the block timestamp. Previously
///      updated for the cutoff-based redemptions change (ACRED/USCC/bEQTY on SettlementAccount +
///      CutoffAccount, mGLOBAL on CutoffMidasAccount): oracles passed to those accounts must
///      expose `getPriceData()`, and ACRED's notice is an ERC-20 transfer to the Securitize
///      redemption wallet. Re-run on fork after any change to those accounts.
import {MGlobalDataFeedHelper} from "../../../helpers/MGlobalDataFeedHelper.sol";

import {
    AA_FalconX_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AA_FalconX_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {JAAA_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {PRIME_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {FigureSubAccount} from "../../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {deJAAA_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {mFONE_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {mGLOBAL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {mHYPER_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {mM1USD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {mROX_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {AsyncRedeemOracle} from "../../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {CentrifugeAccount} from "../../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {FigureOracle} from "../../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {ParetoOracle} from "../../../../src/contracts/adapters/ll-adapter/oracles/ParetoOracle.sol";
import {AdapterFactory} from "../../../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {MigratablesFactory} from "../../../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../../../src/contracts/common/Registry.sol";
import {ILiquidLaneAdapter} from "../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAdapter} from "../../../../src/interfaces/adapters/IAdapter.sol";
import {IAsyncRedeemAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../../../src/interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {IAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {ICutoffAccount} from "../../../../src/interfaces/adapters/ll-adapter/ICutoffAccount.sol";
import {IERC7575Share} from "../../../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";
import {IFigureAccount} from "../../../../src/interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IFigureYieldVault} from "../../../../src/interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";
import {ILidoAccount} from "../../../../src/interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {ILidoWithdrawalQueue} from "../../../../src/interfaces/adapters/ll-adapter/lido/ILidoWithdrawalQueue.sol";
import {
    IMidasAccount,
    REQUEST_STATUS_PENDING
} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IParetoAccount} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {IParetoCreditVault} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCreditVault.sol";
import {IParetoWithdrawalQueue} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoWithdrawalQueue.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract TokensToRedeemMainnetTest is MGlobalDataFeedHelper {
    struct TokenSpec {
        string symbol;
        address token;
    }

    struct CentrifugeCycle {
        address token;
        address account;
        address llAdapter;
        address vault;
        address delegator;
        address asyncRedeemVault;
    }

    address internal constant AA_FALCONX = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address internal constant CARRY_TRADE_USD_TRY_LEVERAGE = 0x2bf11d2E04Bc40daa95c24B8b90EC4F5c57Dd326;
    address internal constant CENTRIFUGE_ASYNC_MANAGER = 0xF48256AbDDf96EcDDc4B3DbD23E8C1921f9761Ae;
    address internal constant CENTRIFUGE_HOOK_WARD_1 = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_HOOK_WARD_2 = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant CENTRIFUGE_MANAGER_WARD = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_SPOKE = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address internal constant DEJAAA = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant JAAA = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant MFONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;
    address internal constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant MHYPER = 0x9b5528528656DBC094765E2abB79F293c21191B9;
    address internal constant MM1USD = 0xCc5C22C7A6BCC25e66726AeF011dDE74289ED203;
    address internal constant MROX = 0x67E1F506B148d0Fc95a4E3fFb49068ceB6855c05;
    address internal constant PARETO_FALCONX_CDO = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;
    address internal constant PRIME = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address internal constant STOCK_MARKET_TR_BASIS_TRADE = 0x827Ce7E8e35861D9Ac7fE002755767b695A5594a;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal adapter = makeAddr("adapter");
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testFigureMainnetOraclesUseTwoLegConversion() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Figure oracle checks");
        _createFork();

        _assertFigureMainnetOracle(3, _tokenSpecs()[3]);
    }

    function _assertFigureMainnetOracle(uint256 index, TokenSpec memory spec) internal {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = _deployImplementation(index, address(factory));
        FigureOracle figureOracle = FigureOracle(implementation.ORACLE());
        uint256 tokenUnit = 10 ** IERC20Metadata(spec.token).decimals();
        address asyncRedeemVault = IERC4626(spec.token).asset();
        address redemptionToken = IFigureYieldVault(asyncRedeemVault).asset();
        uint256 nestedShares = IERC4626(spec.token).convertToAssets(tokenUnit);
        uint256 redemptionAssets = IFigureYieldVault(asyncRedeemVault).convertToAssets(nestedShares);
        uint256 expectedOraclePrice = redemptionAssets * 1e18 / 10 ** IERC20Metadata(redemptionToken).decimals();

        factory.whitelist(address(implementation));
        IAccount account = IAccount(
            factory.create(1, address(this), abi.encode(address(new MainnetAssetVault(redemptionToken)), adapter))
        );

        assertEq(implementation.ORACLE(), address(figureOracle), spec.symbol);
        assertEq(account.ORACLE(), address(figureOracle), spec.symbol);
        assertEq(figureOracle.TOKEN_TO_REDEEM(), spec.token, spec.symbol);
        assertEq(figureOracle.ASYNC_REDEEM_VAULT(), asyncRedeemVault, spec.symbol);
        assertEq(figureOracle.getPrice(), expectedOraclePrice, spec.symbol);
    }

    function testAllTokenAccountsUseRealMainnetTokens() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet token account checks");
        _createFork();

        TokenSpec[] memory specs = _tokenSpecs();
        assertEq(specs.length, 13);

        uint256 length = specs.length;
        for (uint256 i; i < length; ++i) {
            _assertTokenAccount(i, specs[i]);
        }
    }

    function testAllTokenAccountsRunMainnetRedemptionSequence() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet token redemption checks");
        _createFork();

        TokenSpec[] memory specs = _tokenSpecs();
        assertEq(specs.length, 13);

        uint256 length = specs.length;
        for (uint256 i; i < length; ++i) {
            uint256 snapshot = vm.snapshotState();
            _assertRedemptionSequence(i, specs[i]);
            assertTrue(vm.revertToState(snapshot), specs[i].symbol);
        }
    }

    function testAllTokenAccountsRunMainnetCloseRedemptionSequences() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet close redemption checks");
        _createFork();

        TokenSpec[] memory specs = _tokenSpecs();
        assertEq(specs.length, 13);

        uint256 length = specs.length;
        for (uint256 i; i < length; ++i) {
            uint256 snapshot = vm.snapshotState();
            _assertCloseRedemptionSequence(i, specs[i]);
            assertTrue(vm.revertToState(snapshot), specs[i].symbol);
        }
    }

    function testCentrifugeMainnetFullSwapRedemptionCycles() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Centrifuge cycle");
        _createFork();

        uint256[4] memory indexes = [uint256(1), 2, 5, 6];
        TokenSpec[] memory specs = _tokenSpecs();

        uint256 length = indexes.length;
        for (uint256 i; i < length; ++i) {
            emit log_named_string("centrifuge cycle", specs[indexes[i]].symbol);

            CentrifugeCycle memory cycle = _setUpCentrifugeCycle(indexes[i], specs[indexes[i]].token);
            (uint256 amountIn, uint256 amountOut, uint256 expectedAssets) = _swapAndAssertPendingCentrifuge(cycle);
            _fulfillCentrifugeRedeem(cycle.account, cycle.asyncRedeemVault, amountIn, expectedAssets);
            _assertFinalizedAndDeallocateCentrifuge(cycle, amountOut, expectedAssets);
        }
    }

    function testCentrifugeMainnetZeroCooldownSequentialRequests() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Centrifuge cycle");
        _createFork();

        uint256[4] memory indexes = [uint256(1), 2, 5, 6];
        TokenSpec[] memory specs = _tokenSpecs();

        uint256 length = indexes.length;
        for (uint256 i; i < length; ++i) {
            TokenSpec memory spec = specs[indexes[i]];
            emit log_named_string("centrifuge sequential cycle", spec.symbol);

            CentrifugeCycle memory cycle = _setUpCentrifugeCycle(indexes[i], spec.token);
            address marketMaker = makeAddr(string.concat("centrifugeMarketMaker", spec.symbol));
            address recipient = makeAddr(string.concat("centrifugeRecipient", spec.symbol));
            LiquidLaneAdapter(cycle.llAdapter).setMarketMaker(marketMaker, false);

            uint256 amountIn = 10 ** IERC20Metadata(cycle.token).decimals();
            uint256 amountOut = LiquidLaneAdapter(cycle.llAdapter).getAmountOut(cycle.token, amountIn);
            uint256 fulfilledAssets = IAsyncRedeemVault(cycle.asyncRedeemVault).convertToAssets(amountIn);

            _swapCentrifuge(cycle, marketMaker, recipient, amountIn, amountOut);
            _swapCentrifuge(cycle, marketMaker, recipient, amountIn, amountOut);

            IAsyncRedeemAccount account = IAsyncRedeemAccount(cycle.account);
            IAsyncRedeemVault asyncRedeemVault = IAsyncRedeemVault(cycle.asyncRedeemVault);
            assertEq(account.requestIds(0), 0, spec.symbol);
            vm.expectRevert();
            account.requestIds(1);
            assertEq(asyncRedeemVault.pendingRedeemRequest(0, cycle.account), amountIn * 2, spec.symbol);
            assertEq(asyncRedeemVault.pendingRedeemRequest(type(uint256).max, cycle.account), amountIn * 2, spec.symbol);

            _fulfillCentrifugeRedeemPart(cycle.account, cycle.asyncRedeemVault, amountIn, fulfilledAssets);

            assertEq(asyncRedeemVault.pendingRedeemRequest(0, cycle.account), amountIn, spec.symbol);
            uint256 claimableShares = asyncRedeemVault.claimableRedeemRequest(0, cycle.account);
            assertGt(claimableShares, 0, spec.symbol);
            assertEq(
                asyncRedeemVault.claimableRedeemRequest(type(uint256).max, cycle.account), claimableShares, spec.symbol
            );
            assertEq(asyncRedeemVault.maxWithdraw(cycle.account), fulfilledAssets, spec.symbol);

            IAccount(cycle.account).sync();

            assertEq(IERC20(USDC).balanceOf(cycle.account), fulfilledAssets, spec.symbol);
            assertEq(asyncRedeemVault.pendingRedeemRequest(0, cycle.account), amountIn, spec.symbol);
            assertEq(account.requestIds(0), 0, spec.symbol);
            vm.expectRevert();
            account.requestIds(1);

            _fulfillCentrifugeRedeemPart(cycle.account, cycle.asyncRedeemVault, amountIn, fulfilledAssets);
            IAccount(cycle.account).sync();

            assertEq(asyncRedeemVault.pendingRedeemRequest(0, cycle.account), 0, spec.symbol);
            assertEq(IERC20(USDC).balanceOf(cycle.account), fulfilledAssets * 2, spec.symbol);
            vm.expectRevert();
            account.requestIds(0);

            _swapCentrifuge(cycle, marketMaker, recipient, amountIn, amountOut);

            assertEq(account.requestIds(0), 0, spec.symbol);
            vm.expectRevert();
            account.requestIds(1);
            assertEq(asyncRedeemVault.pendingRedeemRequest(0, cycle.account), amountIn, spec.symbol);
        }
    }

    function testCentrifugeMainnetTokenConfigurations() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Centrifuge config");
        _createFork();

        uint256[4] memory indexes = [uint256(1), 2, 5, 6];
        TokenSpec[] memory specs = _tokenSpecs();

        uint256 length = indexes.length;
        for (uint256 i; i < length; ++i) {
            uint256 index = indexes[i];
            TokenSpec memory spec = specs[index];
            emit log_named_string("centrifuge config", spec.symbol);

            MigratablesFactory factory = new MigratablesFactory(address(this));
            IAccount implementation = _deployImplementation(index, address(factory));
            address asyncRedeemVault = _asyncRedeemVault(spec.token, USDC);

            assertEq(_assetFor(index, spec.token), USDC, spec.symbol);
            assertEq(implementation.TOKEN_TO_REDEEM(), spec.token, spec.symbol);
            assertEq(IAsyncRedeemAccount(address(implementation)).COOLDOWN(), 0, spec.symbol);
            assertEq(CentrifugeAccount(address(implementation)).ASYNC_REDEEM_VAULT(), asyncRedeemVault, spec.symbol);
            assertGt(spec.token.code.length, 0, spec.symbol);
            assertGt(asyncRedeemVault.code.length, 0, spec.symbol);
            assertEq(IAsyncRedeemVault(asyncRedeemVault).asset(), USDC, spec.symbol);
            assertGt(
                IAsyncRedeemVault(asyncRedeemVault).convertToAssets(10 ** IERC20Metadata(spec.token).decimals()), 0
            );
            AsyncRedeemOracle oracle = new AsyncRedeemOracle(1, type(uint256).max, spec.token, asyncRedeemVault);
            assertGt(oracle.getPrice(), 0, spec.symbol);
            assertNotEq(IMainnetCentrifugeShareToken(spec.token).hook(), address(0), spec.symbol);
        }
    }

    function _assertTokenAccount(uint256 index, TokenSpec memory spec) internal {
        emit log_named_string("token", spec.symbol);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = _deployImplementation(index, address(factory));

        assertEq(implementation.TOKEN_TO_REDEEM(), spec.token, spec.symbol);
        assertGt(spec.token.code.length, 0, spec.symbol);
        assertEq(IERC20Metadata(spec.token).symbol(), spec.symbol);
        assertGt(IERC20Metadata(spec.token).decimals(), 0, spec.symbol);
        assertEq(implementation.COW_SWAP_SETTLEMENT(), COW_SWAP_SETTLEMENT);
        assertEq(implementation.COW_SWAP_VAULT_RELAYER(), COW_SWAP_VAULT_RELAYER);

        address asset = _assetFor(index, spec.token);
        assertGt(asset.code.length, 0, spec.symbol);

        factory.whitelist(address(implementation));
        IAccount account =
            IAccount(factory.create(1, address(this), abi.encode(address(new MainnetAssetVault(asset)), adapter)));

        if (index == 12) {
            _permissionParetoAccount(address(account));
        }

        assertEq(account.TOKEN_TO_REDEEM(), spec.token, spec.symbol);
        assertEq(account.adapter(), adapter, spec.symbol);
        assertEq(account.converters(0), address(this), spec.symbol);
        assertEq(account.totalAssets(), 0, spec.symbol);
        if (_isMidas(index)) {
            _assertMidasRedemptionTokenConfigured(account, spec.symbol);
        }
    }

    function _assertRedemptionSequence(uint256 index, TokenSpec memory spec) internal {
        emit log_named_string("redeem token", spec.symbol);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = _deployImplementation(index, address(factory));
        address asset = _assetFor(index, spec.token);

        factory.whitelist(address(implementation));
        IAccount account =
            IAccount(factory.create(1, address(this), abi.encode(address(new MainnetAssetVault(asset)), adapter)));

        if (index == 12) {
            _permissionParetoAccount(address(account));
        }

        _warpToRedemptionWindow(index, account);

        uint256 amount = _redemptionAmount(spec.token);
        _dealTokenToAccount(index, spec.token, address(account), amount);
        assertEq(IERC20(spec.token).balanceOf(address(account)), amount, spec.symbol);

        _expectRedemptionSequenceCall(index, account, spec.token, asset, amount);
        try account.sync() {
            _assertRedemptionPostState(index, account, spec.token, asset, amount, spec.symbol);
        } catch (bytes memory reason) {
            _assertKnownMainnetSyncRestriction(index, account, spec.token, amount, reason, spec.symbol);
        }
    }

    function _assertCloseRedemptionSequence(uint256 index, TokenSpec memory spec) internal {
        emit log_named_string("close redeem token", spec.symbol);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = _deployImplementation(index, address(factory));
        address asset = _assetFor(index, spec.token);

        factory.whitelist(address(implementation));
        IAccount account =
            IAccount(factory.create(1, address(this), abi.encode(address(new MainnetAssetVault(asset)), adapter)));

        if (index == 12) {
            _permissionParetoAccount(address(account));
        }

        _warpToRedemptionWindow(index, account);
        if (_isCentrifuge(index)) {
            _permissionCentrifugeMember(spec.token, address(account));
        }

        uint256 amount = _redemptionAmount(spec.token);
        _dealTokenToAccount(index, spec.token, address(account), amount);

        try account.sync() {}
        catch (bytes memory reason) {
            _assertKnownMainnetSyncRestriction(index, account, spec.token, amount, reason, spec.symbol);
            return;
        }

        vm.warp(vm.getBlockTimestamp() + 1);
        _dealTokenToAccount(index, spec.token, address(account), amount);

        try account.sync() {
            _assertCloseRedemptionPostState(index, account, spec.token, amount, spec.symbol);
        } catch (bytes memory reason) {
            emit log_named_bytes("second close sync revert", reason);
            fail(spec.symbol);
        }
    }

    function _setUpCentrifugeCycle(uint256 index, address token) internal returns (CentrifugeCycle memory cycle) {
        cycle.token = token;

        address vaultFactory = address(new TokensMainnetVaultRegistry());
        cycle.vault = address(new TokensMainnetLiquidLaneVault(USDC));
        cycle.delegator = address(new TokensMainnetDelegator(cycle.vault));
        address adapterFactory = address(new AdapterFactory(address(this)));
        address accountFactory = address(new MigratablesFactory(address(this)));
        address accountRegistry = address(new AccountRegistry(address(this)));

        TokensMainnetVaultRegistry(vaultFactory).add(cycle.vault);
        TokensMainnetLiquidLaneVault(cycle.vault).setDelegator(cycle.delegator);

        address adapterImplementation = address(new LiquidLaneAdapter(vaultFactory, adapterFactory, accountRegistry));
        address accountImplementation = address(_deployImplementation(index, accountFactory));

        AdapterFactory(adapterFactory).whitelist(adapterImplementation);
        MigratablesFactory(accountFactory).whitelist(accountImplementation);
        AccountRegistry(accountRegistry).setAccountFactory(USDC, token, accountFactory);

        ILiquidLaneAdapter.InitParams memory params =
            ILiquidLaneAdapter.InitParams({pauser: address(this), unpauser: address(this)});
        cycle.llAdapter =
            AdapterFactory(adapterFactory).create(1, address(this), abi.encode(cycle.vault, abi.encode(params)));

        LiquidLaneAdapter(cycle.llAdapter).addTokenToRedeem(token);
        LiquidLaneAdapter(cycle.llAdapter).setLimit(token, type(uint256).max);

        cycle.account = LiquidLaneAdapter(cycle.llAdapter).accounts(token);
        cycle.asyncRedeemVault = CentrifugeAccount(cycle.account).ASYNC_REDEEM_VAULT();

        _permissionCentrifugeMember(token, cycle.llAdapter);
        _permissionCentrifugeMember(token, cycle.account);
    }

    function _swapAndAssertPendingCentrifuge(CentrifugeCycle memory cycle)
        internal
        returns (uint256 amountIn, uint256 amountOut, uint256 expectedAssets)
    {
        amountIn = 10 ** IERC20Metadata(cycle.token).decimals();
        amountOut = LiquidLaneAdapter(cycle.llAdapter).getAmountOut(cycle.token, amountIn);
        expectedAssets = IAsyncRedeemVault(cycle.asyncRedeemVault).convertToAssets(amountIn);
        address recipient = makeAddr("centrifugeRecipient");
        uint256 recipientBalance = IERC20(USDC).balanceOf(recipient);

        _dealCentrifugeShare(cycle.token, cycle.llAdapter, amountIn);
        deal(USDC, cycle.vault, amountOut);

        LiquidLaneAdapter(cycle.llAdapter).swap(ILiquidLaneAdapter.Swap(recipient, cycle.token, amountIn, amountOut));

        uint256 requestId = IAsyncRedeemAccount(cycle.account).requestIds(0);

        assertEq(requestId, 0);
        assertEq(IERC20(cycle.token).balanceOf(cycle.account), 0);
        assertEq(IERC20(cycle.token).balanceOf(cycle.llAdapter), 0);
        assertEq(IERC20(USDC).balanceOf(recipient), recipientBalance + amountOut);
        assertEq(IAccount(cycle.account).totalAssets(), amountOut);
        assertEq(IAsyncRedeemVault(cycle.asyncRedeemVault).pendingRedeemRequest(requestId, cycle.account), amountIn);
        assertEq(IAsyncRedeemVault(cycle.asyncRedeemVault).claimableRedeemRequest(requestId, cycle.account), 0);
    }

    function _swapCentrifuge(
        CentrifugeCycle memory cycle,
        address caller,
        address recipient,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        _dealCentrifugeShare(cycle.token, cycle.llAdapter, amountIn);
        deal(USDC, cycle.vault, amountOut);

        vm.prank(caller);
        LiquidLaneAdapter(cycle.llAdapter).swap(ILiquidLaneAdapter.Swap(recipient, cycle.token, amountIn, amountOut));
    }

    function _fulfillCentrifugeRedeemPart(address account, address asyncRedeemVault, uint256 shares, uint256 assets)
        internal
    {
        uint64 poolId = IMainnetCentrifugeVault(asyncRedeemVault).poolId();
        bytes16 scId = IMainnetCentrifugeVault(asyncRedeemVault).scId();
        uint128 assetId = IMainnetCentrifugeSpoke(CENTRIFUGE_SPOKE).assetToId(USDC, 0);

        _fundCentrifugeEscrow(poolId, scId, assets);
        _callbackCentrifugeRevoked(poolId, scId, assetId, shares, assets);
        _callbackCentrifugeFulfilled(poolId, scId, assetId, account, shares, assets);
    }

    function _fulfillCentrifugeRedeem(address account, address asyncRedeemVault, uint256 shares, uint256 assets)
        internal
    {
        uint64 poolId = IMainnetCentrifugeVault(asyncRedeemVault).poolId();
        bytes16 scId = IMainnetCentrifugeVault(asyncRedeemVault).scId();
        uint128 assetId = IMainnetCentrifugeSpoke(CENTRIFUGE_SPOKE).assetToId(USDC, 0);

        _fundCentrifugeEscrow(poolId, scId, assets);
        _callbackCentrifugeRevoked(poolId, scId, assetId, shares, assets);
        _callbackCentrifugeFulfilled(poolId, scId, assetId, account, shares, assets);

        assertEq(IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(0, account), 0);
        assertEq(IAsyncRedeemVault(asyncRedeemVault).maxWithdraw(account), assets);
        assertGt(IAsyncRedeemVault(asyncRedeemVault).claimableRedeemRequest(0, account), 0);
    }

    function _callbackCentrifugeRevoked(uint64 poolId, bytes16 scId, uint128 assetId, uint256 shares, uint256 assets)
        internal
    {
        uint128 pricePoolPerShare = IMainnetCentrifugeSpoke(CENTRIFUGE_SPOKE).pricePoolPerShare(poolId, scId, false);
        vm.prank(CENTRIFUGE_MANAGER_WARD);
        IMainnetCentrifugeAsyncManager(CENTRIFUGE_ASYNC_MANAGER)
            .callback(
                poolId, scId, assetId, abi.encodePacked(uint8(3), uint128(assets), uint128(shares), pricePoolPerShare)
            );
    }

    function _callbackCentrifugeFulfilled(
        uint64 poolId,
        bytes16 scId,
        uint128 assetId,
        address account,
        uint256 shares,
        uint256 assets
    ) internal {
        vm.prank(CENTRIFUGE_MANAGER_WARD);
        IMainnetCentrifugeAsyncManager(CENTRIFUGE_ASYNC_MANAGER)
            .callback(
                poolId,
                scId,
                assetId,
                abi.encodePacked(uint8(5), bytes32(bytes20(account)), uint128(assets), uint128(shares), uint128(0))
            );
    }

    function _fundCentrifugeEscrow(uint64 poolId, bytes16 scId, uint256 assets) internal {
        address balanceSheet = IMainnetCentrifugeAsyncManager(CENTRIFUGE_ASYNC_MANAGER).balanceSheet();
        address poolEscrow = IMainnetCentrifugeBalanceSheet(balanceSheet).escrow(poolId);
        (uint128 total, uint128 reserved) = IMainnetCentrifugePoolEscrow(poolEscrow).holding(scId, USDC, 0);
        uint256 requiredTotal = uint256(reserved) + assets;

        if (total < requiredTotal) {
            vm.prank(balanceSheet);
            IMainnetCentrifugePoolEscrow(poolEscrow).deposit(scId, USDC, 0, uint128(requiredTotal - total));
        }
        if (IERC20(USDC).balanceOf(poolEscrow) < requiredTotal) {
            deal(USDC, poolEscrow, requiredTotal);
        }
    }

    function _assertFinalizedAndDeallocateCentrifuge(
        CentrifugeCycle memory cycle,
        uint256 amountOut,
        uint256 expectedAssets
    ) internal {
        IAccount(cycle.account).sync();

        vm.expectRevert();
        IAsyncRedeemAccount(cycle.account).requestIds(0);

        assertEq(IERC20(USDC).balanceOf(cycle.account), expectedAssets);
        assertEq(IAccount(cycle.account).totalAssets(), expectedAssets);
        assertEq(LiquidLaneAdapter(cycle.llAdapter).totalAssets(), expectedAssets);
        assertEq(LiquidLaneAdapter(cycle.llAdapter).freeAssets(), expectedAssets);

        uint256 deallocated = TokensMainnetDelegator(cycle.delegator).deallocate(cycle.llAdapter, amountOut);

        assertEq(deallocated, expectedAssets);
        assertEq(IERC20(USDC).balanceOf(cycle.vault), expectedAssets);
        assertEq(LiquidLaneAdapter(cycle.llAdapter).totalAssets(), 0);
        assertEq(LiquidLaneAdapter(cycle.llAdapter).freeAssets(), 0);
    }

    function _dealTokenToAccount(uint256 index, address token, address account, uint256 amount) internal {
        if (_isCentrifuge(index)) {
            _dealCentrifugeShare(token, account, IERC20(token).balanceOf(account) + amount);
            return;
        }
        deal(token, account, IERC20(token).balanceOf(account) + amount);
    }

    function _tokenSpecs() internal pure returns (TokenSpec[] memory specs) {
        specs = new TokenSpec[](13);
        specs[0] = TokenSpec("CarryTradeUSDTRYLeverage", CARRY_TRADE_USD_TRY_LEVERAGE);
        specs[1] = TokenSpec("JAAA", JAAA);
        specs[2] = TokenSpec("JTRSY", JTRSY);
        specs[3] = TokenSpec("PRIME", PRIME);
        specs[4] = TokenSpec("StockMarketTRBasisTrade", STOCK_MARKET_TR_BASIS_TRADE);
        specs[5] = TokenSpec("deJAAA", DEJAAA);
        specs[6] = TokenSpec("deJTRSY", DEJTRSY);
        specs[7] = TokenSpec("mF-ONE", MFONE);
        specs[8] = TokenSpec("mGLOBAL", MGLOBAL);
        specs[9] = TokenSpec("mHYPER", MHYPER);
        specs[10] = TokenSpec("mM1-USD", MM1USD);
        specs[11] = TokenSpec("mROX", MROX);
        specs[12] = TokenSpec("AA_FalconXUSDC", AA_FALCONX);
        // Reserved index: USCC requires issuer-managed enrollment and offchain payout routing.
    }

    function _deployImplementation(uint256 index, address factory) internal returns (IAccount implementation) {
        if (index == 0) return new CarryTradeUSDTRYLeverage_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 1) {
            return new JAAA_Account(
                address(new MainnetConstantOracle()), factory, USDC, _asyncRedeemVault(JAAA, USDC), COW_SWAP_SETTLEMENT
            );
        }
        if (index == 2) {
            return new JTRSY_Account(
                address(new MainnetConstantOracle()), factory, USDC, _asyncRedeemVault(JTRSY, USDC), COW_SWAP_SETTLEMENT
            );
        }
        if (_isFigure(index)) {
            address token = PRIME;
            address subAccountImplementation = address(new FigureSubAccount(token));
            address oracle = address(new FigureOracle(1, type(uint256).max, token));
            return new PRIME_Account(oracle, factory, token, subAccountImplementation, COW_SWAP_SETTLEMENT);
        }
        if (index == 4) return new StockMarketTRBasisTrade_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 5) {
            return new deJAAA_Account(
                address(new MainnetConstantOracle()),
                factory,
                USDC,
                _asyncRedeemVault(DEJAAA, USDC),
                COW_SWAP_SETTLEMENT
            );
        }
        if (index == 6) {
            return new deJTRSY_Account(
                address(new MainnetConstantOracle()),
                factory,
                USDC,
                _asyncRedeemVault(DEJTRSY, USDC),
                COW_SWAP_SETTLEMENT
            );
        }
        if (index == 7) return new mFONE_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 8) return new mGLOBAL_Account(factory, COW_SWAP_SETTLEMENT, MGLOBAL_DATA_FEED);
        if (index == 9) return new mHYPER_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 10) return new mM1USD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 11) return new mROX_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 12) {
            return new AA_FalconX_Account(
                address(new ParetoOracle(0.9e18, 1.5e18, AA_FALCONX, PARETO_FALCONX_CDO)), factory, COW_SWAP_SETTLEMENT
            );
        }
        revert();
    }

    function _warpToRedemptionWindow(uint256 index, IAccount account) internal {
        if (index == 8) {
            uint48 cutoffTimestamp =
                ICutoffAccount(address(account)).bucketToTimestamp(ICutoffAccount(address(account)).currentBucket());
            if (cutoffTimestamp > 1 days) {
                vm.warp(uint256(cutoffTimestamp) - 1 days);
            }
        }
    }

    function _assetFor(uint256 index, address token) internal view returns (address) {
        if (_isFigure(index)) {
            return IERC4626(IERC4626(token).asset()).asset();
        }
        return USDC;
    }

    function _assertMidasRedemptionTokenConfigured(IAccount account, string memory symbol) internal view {
        address redemptionVault = IMidasAccount(address(account)).REDEMPTION_VAULT();
        address redemptionToken = IMidasAccount(address(account)).REDEMPTION_TOKEN();
        address[] memory paymentTokens = IMidasRedemptionVaultWithPaymentTokens(redemptionVault).getPaymentTokens();
        if (paymentTokens.length == 0) {
            return;
        }

        bool isConfigured;
        uint256 length = paymentTokens.length;
        for (uint256 i; i < length; ++i) {
            if (paymentTokens[i] == redemptionToken) {
                isConfigured = true;
                break;
            }
        }

        assertTrue(isConfigured, symbol);
        (address dataFeed,,,) = IMidasRedemptionVault(redemptionVault).tokensConfig(redemptionToken);
        assertNotEq(dataFeed, address(0), symbol);
    }

    function _isMidas(uint256 index) internal pure returns (bool) {
        return index == 0 || index == 4 || (index >= 7 && index <= 11);
    }

    function _isCentrifuge(uint256 index) internal pure returns (bool) {
        return index == 1 || index == 2 || index == 5 || index == 6;
    }

    function _isFigure(uint256 index) internal pure returns (bool) {
        return index == 3;
    }

    function _isKnownMainnetSyncRestricted(uint256 index) internal pure returns (bool) {
        return _isCentrifuge(index) || _isMidas(index) || _isFigure(index);
    }

    function _assertKnownMainnetSyncRestriction(
        uint256 index,
        IAccount account,
        address token,
        uint256 amount,
        bytes memory reason,
        string memory symbol
    ) internal {
        if (!_isKnownMainnetSyncRestricted(index)) {
            emit log_named_bytes("unexpected sync revert", reason);
            fail(symbol);
        }
        assertEq(IERC20(token).balanceOf(address(account)), amount, symbol);
    }

    function _redemptionAmount(address token) internal view returns (uint256) {
        return 10 ** IERC20Metadata(token).decimals();
    }

    function _expectRedemptionSequenceCall(
        uint256 index,
        IAccount account,
        address token,
        address asset,
        uint256 amount
    ) internal {
        if (_isMidas(index)) {
            address redemptionVault = IMidasAccount(address(account)).REDEMPTION_VAULT();
            address redemptionToken = IMidasAccount(address(account)).REDEMPTION_TOKEN();
            (address dataFeed,,,) = IMidasRedemptionVault(redemptionVault).tokensConfig(asset);
            vm.expectCall(
                redemptionVault,
                abi.encodeCall(
                    IMidasRedemptionVault.redeemRequest, (dataFeed == address(0) ? redemptionToken : asset, amount)
                )
            );
            return;
        }
        if (_isCentrifuge(index)) {
            vm.expectCall(
                CentrifugeAccount(address(account)).ASYNC_REDEEM_VAULT(),
                abi.encodeCall(IAsyncRedeemVault.requestRedeem, (amount, address(account), address(account)))
            );
            return;
        }
        if (_isFigure(index)) {
            vm.expectCall(token, abi.encodeCall(IERC4626.redeem, (amount, address(account), address(account))));
            return;
        }
        if (index == 12) {
            vm.expectCall(
                IParetoAccount(address(account)).WITHDRAWAL_QUEUE(),
                abi.encodeCall(IParetoWithdrawalQueue.requestWithdraw, (amount))
            );
            return;
        }
        vm.expectCall(
            ILidoAccount(payable(address(account))).WITHDRAWAL_QUEUE(),
            bytes.concat(ILidoWithdrawalQueue.requestWithdrawalsWstETH.selector)
        );
    }

    function _assertRedemptionPostState(
        uint256 index,
        IAccount account,
        address token,
        address asset,
        uint256 amount,
        string memory symbol
    ) internal {
        assertEq(IERC20(token).balanceOf(address(account)), 0, symbol);

        if (_isMidas(index)) {
            _assertMidasRedemption(account, amount, symbol);
            return;
        }
        if (_isCentrifuge(index)) {
            _assertAsyncRedemption(account, amount, symbol);
            return;
        }
        if (_isFigure(index)) {
            _assertFigureRedemption(account, token, symbol);
            return;
        }
        if (index == 12) {
            _assertParetoRedemption(account, symbol);
            return;
        }
        _assertLidoRedemption(account, symbol);
    }

    function _assertCloseRedemptionPostState(
        uint256 index,
        IAccount account,
        address token,
        uint256 amount,
        string memory symbol
    ) internal view {
        if (_isMidas(index)) {
            IMidasAccount(address(account)).requestIds(1);
            assertGt(account.totalAssets(), 0, symbol);
            return;
        }
        if (_isCentrifuge(index)) {
            uint256 requestId = IAsyncRedeemAccount(address(account)).requestIds(0);
            assertEq(
                IAsyncRedeemVault(CentrifugeAccount(address(account)).ASYNC_REDEEM_VAULT())
                    .pendingRedeemRequest(requestId, address(account)),
                2 * amount,
                symbol
            );
            assertGt(account.totalAssets(), 0, symbol);
            return;
        }
        if (_isFigure(index)) {
            address firstSubAccount = IFigureAccount(address(account)).subAccounts(0);
            address secondSubAccount = IFigureAccount(address(account)).subAccounts(1);
            assertNotEq(secondSubAccount, firstSubAccount, symbol);
            assertGt(firstSubAccount.code.length, 0, symbol);
            assertGt(secondSubAccount.code.length, 0, symbol);
            assertGt(account.totalAssets(), 0, symbol);
            return;
        }
        if (index == 12) {
            _assertParetoQueued(account, 2 * amount, symbol);
            assertGt(account.totalAssets(), 0, symbol);
            return;
        }

        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertMidasRedemption(IAccount account, uint256 amount, string memory symbol) internal view {
        uint256 requestId = IMidasAccount(address(account)).requestIds(0);
        (address sender,, uint8 status, uint256 amountMToken,,) =
            IMidasRedemptionVault(IMidasAccount(address(account)).REDEMPTION_VAULT()).redeemRequests(requestId);

        assertEq(sender, address(account), symbol);
        assertEq(status, REQUEST_STATUS_PENDING, symbol);
        assertGt(amountMToken, 0, symbol);
        assertLe(amountMToken, amount, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertAsyncRedemption(IAccount account, uint256 amount, string memory symbol) internal view {
        address asyncRedeemVault = CentrifugeAccount(address(account)).ASYNC_REDEEM_VAULT();
        uint256 requestId = IAsyncRedeemAccount(address(account)).requestIds(0);
        assertGt(IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestId, address(account)), 0, symbol);
        assertLe(IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestId, address(account)), amount, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _asyncRedeemVault(address token, address asset) internal view returns (address) {
        return IERC7575Share(token).vault(asset);
    }

    function _dealCentrifugeShare(address token, address account, uint256 amount) internal {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);

        bytes32 balanceSlot = reads[0];
        bytes32 packedBalance = vm.load(token, balanceSlot);
        vm.store(token, balanceSlot, bytes32((uint256(packedBalance) & ~uint256(type(uint128).max)) | amount));
    }

    function _permissionCentrifugeMember(address token, address account) internal {
        address hook = IMainnetCentrifugeShareToken(token).hook();
        bytes memory callData =
            abi.encodeCall(IMainnetCentrifugeTransferHook.updateMember, (token, account, type(uint64).max));

        vm.prank(CENTRIFUGE_HOOK_WARD_1);
        (bool success, bytes memory reason) = hook.call(callData);
        if (success) {
            return;
        }

        vm.prank(CENTRIFUGE_HOOK_WARD_2);
        (success, reason) = hook.call(callData);
        if (!success) {
            emit log_named_bytes("centrifuge permission revert", reason);
            fail("centrifuge permission");
        }
    }

    function _assertFigureRedemption(IAccount account, address token, string memory symbol) internal view {
        address subAccount = IFigureAccount(address(account)).subAccounts(0);
        (uint256 shares,,) = IFigureYieldVault(IERC4626(token).asset()).pendingRedemptions(subAccount);
        assertGt(shares, 0, symbol);
        assertGt(subAccount.code.length, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertParetoRedemption(IAccount account, string memory symbol) internal view {
        _assertParetoQueued(account, 10 ** IERC20Metadata(account.TOKEN_TO_REDEEM()).decimals(), symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertParetoQueued(IAccount account, uint256 amount, string memory symbol) internal view {
        address queue = IParetoAccount(address(account)).WITHDRAWAL_QUEUE();
        uint256 epoch = IParetoCreditVault(IParetoWithdrawalQueue(queue).strategy()).epochNumber() + 1;
        assertEq(IParetoWithdrawalQueue(queue).userWithdrawalsEpochs(address(account), epoch), amount, symbol);
        assertEq(IParetoAccount(address(account)).queueEpochs(0), epoch, symbol);
    }

    function _permissionParetoAccount(address account) internal {
        vm.mockCall(PARETO_FALCONX_CDO, abi.encodeCall(IParetoCDO.isEpochRunning, ()), abi.encode(true));
        vm.mockCall(PARETO_FALCONX_CDO, abi.encodeCall(IParetoCDO.isWalletAllowed, (account)), abi.encode(true));
    }

    function _assertLidoRedemption(IAccount account, string memory symbol) internal view {
        uint256 requestId = ILidoAccount(payable(address(account))).requestIds(0);
        uint256[] memory ids = new uint256[](1);
        ids[0] = requestId;

        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            ILidoWithdrawalQueue(ILidoAccount(payable(address(account))).WITHDRAWAL_QUEUE()).getWithdrawalStatus(ids);

        assertEq(statuses[0].owner, address(account), symbol);
        assertFalse(statuses[0].isClaimed, symbol);
        assertGt(statuses[0].amountOfStETH, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _skipWithoutRpc(string memory rpcUrl, string memory reason) internal {
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, reason);
        }
    }

    function _createFork() internal {
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
        _mockMGlobalDataFeed();
    }
}

contract TokensMainnetVaultRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract TokensMainnetLiquidLaneVault {
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

contract TokensMainnetDelegator {
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
        TokensMainnetLiquidLaneVault(vault).pull(assets, adapter);
        allocated = IAdapter(adapter).allocate(assets);
        if (allocated < assets) {
            TokensMainnetLiquidLaneVault(vault).push(assets - allocated, adapter);
        }
    }

    function deallocate(address adapter, uint256 assets) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(assets);
        if (deallocated > 0) {
            TokensMainnetLiquidLaneVault(vault).push(deallocated, adapter);
        }
    }
}

contract MainnetAssetVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

interface IMainnetCentrifugeAsyncManager {
    function balanceSheet() external view returns (address);

    function callback(uint64 poolId, bytes16 scId, uint128 assetId, bytes calldata payload) external;
}

interface IMainnetCentrifugeBalanceSheet {
    function escrow(uint64 poolId) external view returns (address);
}

interface IMainnetCentrifugePoolEscrow {
    function availableBalanceOf(bytes16 scId, address asset, uint256 tokenId) external view returns (uint128);

    function deposit(bytes16 scId, address asset, uint256 tokenId, uint128 value) external;

    function holding(bytes16 scId, address asset, uint256 tokenId)
        external
        view
        returns (uint128 total, uint128 reserved);
}

interface IMainnetCentrifugeShareToken {
    function hook() external view returns (address);
}

interface IMainnetCentrifugeSpoke {
    function assetToId(address asset, uint256 tokenId) external view returns (uint128 assetId);

    function pricePoolPerShare(uint64 poolId, bytes16 scId, bool checkValidity) external view returns (uint128 price);
}

interface IMainnetCentrifugeTransferHook {
    function updateMember(address token, address user, uint64 validUntil) external;
}

interface IMainnetCentrifugeVault {
    function poolId() external view returns (uint64);

    function scId() external view returns (bytes16);
}

interface IMidasRedemptionVaultWithPaymentTokens is IMidasRedemptionVault {
    function getPaymentTokens() external view returns (address[] memory);
}

interface IOwnable {
    function owner() external view returns (address);
}

interface IDSServiceConsumer {
    function getDSService(uint256 serviceId) external view returns (address);
}

interface IDSRegistryService {
    function addWallet(address wallet, string calldata investorId) external returns (bool);

    function getCountry(string calldata investorId) external view returns (string memory);

    function isInvestor(string calldata investorId) external view returns (bool);

    function isWallet(address wallet) external view returns (bool);

    function registerInvestor(string calldata investorId, string calldata collisionHash) external returns (bool);

    function setCountry(string calldata investorId, string calldata country) external returns (bool);

    function setAttribute(
        string calldata investorId,
        uint8 attributeId,
        uint256 value,
        uint256 expiry,
        string calldata proofHash
    ) external returns (bool);
}

interface IDSecuritizeToken {
    function issueTokens(address account, uint256 amount) external returns (bool);
}

interface IDSComplianceConfigurationService {
    function getUSLockPeriod() external view returns (uint256);
}

interface IDSTrustService {
    function setRole(address account, uint8 role) external returns (bool);
}

contract MainnetConstantOracle {
    function getPrice() external pure returns (uint256) {
        return 1e18;
    }

    /// @dev Settlement accounts (ACRED/USCC/bEQTY) and other CutoffAccount hosts read
    ///      `getPriceData()` on sync/totalAssets; a fresh `updatedAt` keeps cohort freezing live.
    function getPriceData() external view returns (uint256 price, uint48 updatedAt) {
        return (1e18, uint48(block.timestamp));
    }
}
