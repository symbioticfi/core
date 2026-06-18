// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mainnet-fork suite: requires `ETH_RPC_URL` (skipped otherwise). Last updated for the
///      infiniFi locked iUSD change (liUSD-4w/liUSD-13w on InfiniFiAccount): their redemption
///      notice is a gateway `startUnwinding` call keyed by the block timestamp. Previously
///      updated for the cutoff-based redemptions change (ACRED/USCC/bEQTY on SettlementAccount +
///      CutoffAccount, mGLOBAL on CutoffMidasAccount): oracles passed to those accounts must
///      expose `getPriceData()`, and ACRED's notice is an ERC-20 transfer to the Securitize
///      redemption wallet. Re-run on fork after any change to those accounts.
import {Test} from "forge-std/Test.sol";

import {ACRDX_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {ACRED_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRED_Account.sol";
import {
    AA_FalconX_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AA_FalconX_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {DUSD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/DUSD_Account.sol";
import {JAAA_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {PRIME_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {bEQTY_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/bEQTY_Account.sol";
import {deCRDX_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deCRDX_Account.sol";
import {deJAAA_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {liUSD13w_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD13w_Account.sol";
import {liUSD4w_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD4w_Account.sol";
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
import {mROX_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {mRe7BTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7BTC_Account.sol";
import {mRe7YIELD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7YIELD_Account.sol";
import {mSL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mSL_Account.sol";
import {mTBILL_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mTBILL_Account.sol";
import {mevBTC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mevBTC_Account.sol";
import {msyrupUSD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSD_Account.sol";
import {
    msyrupUSDp_Account
} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSDp_Account.sol";
import {sAID_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sAID_Account.sol";
import {sUSN_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSN_Account.sol";
import {sUSD3_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSD3_Account.sol";
import {sthUSD_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {USCC_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/USCC_Account.sol";
import {weETH_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {AsyncRedeemOracle} from "../../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
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
import {IDigiFTAccount} from "../../../../src/interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";
import {IEtherFiAccount} from "../../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiAccount.sol";
import {IEtherFiLiquidityPool} from "../../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiLiquidityPool.sol";
import {
    IEtherFiRedemptionManager
} from "../../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiRedemptionManager.sol";
import {
    IEtherFiWithdrawRequestNFT
} from "../../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiWithdrawRequestNFT.sol";
import {IWeETH} from "../../../../src/interfaces/adapters/ll-adapter/etherfi/IWeETH.sol";
import {IFigureAccount} from "../../../../src/interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IFigureYieldVault} from "../../../../src/interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";
import {IGaibAccount} from "../../../../src/interfaces/adapters/ll-adapter/gaib/IGaibAccount.sol";
import {ISaid} from "../../../../src/interfaces/adapters/ll-adapter/gaib/ISaid.sol";
import {IInfiniFiAccount} from "../../../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiAccount.sol";
import {IInfiniFiGateway} from "../../../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiGateway.sol";
import {
    IInfiniFiUnwindingModule
} from "../../../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiUnwindingModule.sol";
import {ILidoAccount} from "../../../../src/interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {ILidoWithdrawalQueue} from "../../../../src/interfaces/adapters/ll-adapter/lido/ILidoWithdrawalQueue.sol";
import {IMakinaAccount} from "../../../../src/interfaces/adapters/ll-adapter/makina/IMakinaAccount.sol";
import {IMakinaRedeemer} from "../../../../src/interfaces/adapters/ll-adapter/makina/IMakinaRedeemer.sol";
import {
    IMidasAccount,
    REQUEST_STATUS_PENDING
} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {INoonAccount} from "../../../../src/interfaces/adapters/ll-adapter/noon/INoonAccount.sol";
import {INoonWithdrawalHandler} from "../../../../src/interfaces/adapters/ll-adapter/noon/INoonWithdrawalHandler.sol";
import {IParetoAccount} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {ISecuritizeAccount} from "../../../../src/interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol";
import {ISuperstateAccount} from "../../../../src/interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol";
import {ISthUSD} from "../../../../src/interfaces/adapters/ll-adapter/theo/ISthUSD.sol";
import {IThreeJaneSUSD3} from "../../../../src/interfaces/adapters/ll-adapter/threejane/IThreeJaneSUSD3.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract TokensToRedeemMainnetTest is Test {
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

    address internal constant ACRDX = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    address internal constant ACRED = 0x17418038ecF73BA4026c4f428547BF099706F27B;
    address internal constant AA_FALCONX = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address internal constant BEQTY = 0xEaFD6D38f41f882BCFd5fEaABccCc714B983b701;
    address internal constant CARRY_TRADE_USD_TRY_LEVERAGE = 0x2bf11d2E04Bc40daa95c24B8b90EC4F5c57Dd326;
    address internal constant CENTRIFUGE_ASYNC_MANAGER = 0xF48256AbDDf96EcDDc4B3DbD23E8C1921f9761Ae;
    address internal constant CENTRIFUGE_HOOK_WARD_1 = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_HOOK_WARD_2 = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant CENTRIFUGE_MANAGER_WARD = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_SPOKE = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address internal constant DECRDX = 0x9E2679eABFF131b8b1b48fF7566140794E0eEdc4;
    address internal constant DEJAAA = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant DUSD = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;
    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant ETHERFI_LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant ETHERFI_REDEMPTION_MANAGER = 0xE3F384Dc7002547Dd240AC1Ad69a430CCE1e292d;
    address internal constant ETHERFI_WITHDRAW_REQUEST_NFT = 0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;
    address internal constant INFINIFI_GATEWAY = 0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5;
    address internal constant INFINIFI_UNWINDING_MODULE = 0x7092A43aE5407666C78dBEA657a1891f42b3dFcc;
    address internal constant JAAA = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant LIUSD4W = 0x66bCF6151D5558AfB47c38B20663589843156078;
    address internal constant LIUSD13W = 0xbd3f9814eB946E617f1d774A6762cDbec0bf087A;
    address internal constant MAPOLLO = 0x7CF9DEC92ca9FD46f8d86e7798B72624Bc116C05;
    address internal constant MBASIS = 0x2a8c22E3b10036f3AEF5875d04f8441d4188b656;
    address internal constant MBTC = 0x007115416AB6c266329a03B09a8aa39aC2eF7d9d;
    address internal constant MEDGE = 0xbB51E2a15A9158EBE2b0Ceb8678511e063AB7a55;
    address internal constant MEVBTC = 0xb64C014307622eB15046C66fF71D04258F5963DC;
    address internal constant MEVUSD = 0x548857309BEfb6Fb6F20a9C5A56c9023D892785B;
    address internal constant MFARM = 0xA19f6e0dF08a7917F2F8A33Db66D0AF31fF5ECA6;
    address internal constant MFONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;
    address internal constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant MHYPER = 0x9b5528528656DBC094765E2abB79F293c21191B9;
    address internal constant MHYPERBTC = 0xC8495EAFf71D3A563b906295fCF2f685b1783085;
    address internal constant MHYPERETH = 0x5a42864b14C0C8241EF5ab62Dae975b163a2E0C1;
    address internal constant MM1USD = 0xCc5C22C7A6BCC25e66726AeF011dDE74289ED203;
    address internal constant MMEV = 0x030b69280892c888670EDCDCD8B69Fd8026A0BF3;
    address internal constant MROX = 0x67E1F506B148d0Fc95a4E3fFb49068ceB6855c05;
    address internal constant MRE7BTC = 0x9FB442d6B612a6dcD2acC67bb53771eF1D9F661A;
    address internal constant MRE7YIELD = 0x87C9053C819bB28e0D73d33059E1b3DA80AFb0cf;
    address internal constant MSL = 0x76CC16608aA7Cd32631bb151801bb095313F7bbd;
    address internal constant MTBILL = 0xDD629E5241CbC5919847783e6C96B2De4754e438;
    address internal constant MSYRUPUSD = 0x20226607b4fa64228ABf3072Ce561d6257683464;
    address internal constant MSYRUPUSDP = 0x2fE058CcF29f123f9dd2aEC0418AA66a877d8E50;
    address internal constant NOON_WITHDRAWAL_HANDLER = 0x0DaBc0D9B270c9B0C4C77AaCeAa712b56D0F9178;
    address internal constant PARETO_FALCONX_CDO = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;
    address internal constant PRIME = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address internal constant SAID = 0xB3B3c527BA57cd61648e2EC2F5e006A0B390A9F8;
    address internal constant STOCK_MARKET_TR_BASIS_TRADE = 0x827Ce7E8e35861D9Ac7fE002755767b695A5594a;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant STHUSD = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;
    address internal constant S_USN = 0xE24a3DC889621612422A64E6388927901608B91D;
    address internal constant SUSD3 = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USCC = 0x14d60E7FDC0D71d8611742720E4C50E7a974020c;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address internal adapter = makeAddr("adapter");
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testAllTokenAccountsUseRealMainnetTokens() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet token account checks");
        vm.createSelectFork(mainnetRpcUrl);

        TokenSpec[] memory specs = _tokenSpecs();
        assertEq(specs.length, 43);

        for (uint256 i; i < specs.length; ++i) {
            _assertTokenAccount(i, specs[i]);
        }
    }

    function testAllTokenAccountsRunMainnetRedemptionSequence() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet token redemption checks");
        vm.createSelectFork(mainnetRpcUrl);

        TokenSpec[] memory specs = _tokenSpecs();
        assertEq(specs.length, 43);

        for (uint256 i; i < specs.length; ++i) {
            _assertRedemptionSequence(i, specs[i]);
        }
    }

    function testCentrifugeMainnetFullSwapRedemptionCycles() public {
        _skipWithoutRpc(mainnetRpcUrl, "ETH_RPC_URL is required for Ethereum mainnet Centrifuge cycle");
        vm.createSelectFork(mainnetRpcUrl);

        uint256[6] memory indexes = [uint256(0), 3, 4, 8, 9, 10];
        TokenSpec[] memory specs = _tokenSpecs();

        for (uint256 i; i < indexes.length; ++i) {
            emit log_named_string("centrifuge cycle", specs[indexes[i]].symbol);

            CentrifugeCycle memory cycle = _setUpCentrifugeCycle(indexes[i], specs[indexes[i]].token);
            (uint256 amountIn, uint256 amountOut, uint256 expectedAssets) = _swapAndAssertPendingCentrifuge(cycle);
            _fulfillCentrifugeRedeem(cycle.account, cycle.asyncRedeemVault, amountIn, expectedAssets);
            _assertFinalizedAndDeallocateCentrifuge(cycle, amountOut, expectedAssets);
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

        assertEq(account.TOKEN_TO_REDEEM(), spec.token, spec.symbol);
        assertEq(account.adapter(), adapter, spec.symbol);
        assertEq(account.converters(0), address(this), spec.symbol);
        assertEq(account.totalAssets(), 0, spec.symbol);
    }

    function _assertRedemptionSequence(uint256 index, TokenSpec memory spec) internal {
        emit log_named_string("redeem token", spec.symbol);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = _deployImplementation(index, address(factory));
        address asset = _assetFor(index, spec.token);

        factory.whitelist(address(implementation));
        IAccount account =
            IAccount(factory.create(1, address(this), abi.encode(address(new MainnetAssetVault(asset)), adapter)));

        _warpToRedemptionWindow(index, account);

        uint256 amount = _redemptionAmount(index, spec.token);
        deal(spec.token, address(account), amount);
        assertEq(IERC20(spec.token).balanceOf(address(account)), amount, spec.symbol);

        _expectRedemptionSequenceCall(index, account, spec.token, asset, amount);
        try account.sync() {
            _assertRedemptionPostState(index, account, spec.token, asset, amount, spec.symbol);
        } catch (bytes memory reason) {
            _assertKnownMainnetSyncRestriction(index, account, spec.token, amount, reason, spec.symbol);
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
        cycle.asyncRedeemVault = _asyncRedeemVault(token, USDC);

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
        assertEq(IAccount(cycle.account).totalAssets(), expectedAssets);
        assertEq(IAsyncRedeemVault(cycle.asyncRedeemVault).pendingRedeemRequest(requestId, cycle.account), amountIn);
        assertEq(IAsyncRedeemVault(cycle.asyncRedeemVault).claimableRedeemRequest(requestId, cycle.account), 0);
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
        uint256 availableAssets = IMainnetCentrifugePoolEscrow(poolEscrow).availableBalanceOf(scId, USDC, 0);

        if (availableAssets < assets) {
            vm.prank(balanceSheet);
            IMainnetCentrifugePoolEscrow(poolEscrow).deposit(scId, USDC, 0, uint128(assets - availableAssets));
        }
        if (IERC20(USDC).balanceOf(poolEscrow) < assets) {
            deal(USDC, poolEscrow, assets);
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

    function _tokenSpecs() internal pure returns (TokenSpec[] memory specs) {
        specs = new TokenSpec[](43);
        specs[0] = TokenSpec("ACRDX", ACRDX);
        specs[1] = TokenSpec("CarryTradeUSDTRYLeverage", CARRY_TRADE_USD_TRY_LEVERAGE);
        specs[2] = TokenSpec("DUSD", DUSD);
        specs[3] = TokenSpec("JAAA", JAAA);
        specs[4] = TokenSpec("JTRSY", JTRSY);
        specs[5] = TokenSpec("PRIME", PRIME);
        specs[6] = TokenSpec("StockMarketTRBasisTrade", STOCK_MARKET_TR_BASIS_TRADE);
        specs[7] = TokenSpec("bEQTY", BEQTY);
        specs[8] = TokenSpec("deCRDX", DECRDX);
        specs[9] = TokenSpec("deJAAA", DEJAAA);
        specs[10] = TokenSpec("deJTRSY", DEJTRSY);
        specs[11] = TokenSpec("mAPOLLO", MAPOLLO);
        specs[12] = TokenSpec("mBASIS", MBASIS);
        specs[13] = TokenSpec("mBTC", MBTC);
        specs[14] = TokenSpec("mEDGE", MEDGE);
        specs[15] = TokenSpec("mEVUSD", MEVUSD);
        specs[16] = TokenSpec("mFARM", MFARM);
        specs[17] = TokenSpec("mF-ONE", MFONE);
        specs[18] = TokenSpec("mGLOBAL", MGLOBAL);
        specs[19] = TokenSpec("mHYPER", MHYPER);
        specs[20] = TokenSpec("mHyperBTC", MHYPERBTC);
        specs[21] = TokenSpec("mHyperETH", MHYPERETH);
        specs[22] = TokenSpec("mM1-USD", MM1USD);
        specs[23] = TokenSpec("mMEV", MMEV);
        specs[24] = TokenSpec("mROX", MROX);
        specs[25] = TokenSpec("mRe7BTC", MRE7BTC);
        specs[26] = TokenSpec("mRe7YIELD", MRE7YIELD);
        specs[27] = TokenSpec("mSL", MSL);
        specs[28] = TokenSpec("mTBILL", MTBILL);
        specs[29] = TokenSpec("mevBTC", MEVBTC);
        specs[30] = TokenSpec("msyrupUSD", MSYRUPUSD);
        specs[31] = TokenSpec("msyrupUSDp", MSYRUPUSDP);
        specs[32] = TokenSpec("sAID", SAID);
        specs[33] = TokenSpec("sUSD3", SUSD3);
        specs[34] = TokenSpec("sthUSD", STHUSD);
        specs[35] = TokenSpec("weETH", WEETH);
        specs[36] = TokenSpec("wstETH", WSTETH);
        specs[37] = TokenSpec("AA_FalconXUSDC", AA_FALCONX);
        specs[38] = TokenSpec("ACRED", ACRED);
        specs[39] = TokenSpec("sUSN", S_USN);
        specs[40] = TokenSpec("USCC", USCC);
        specs[41] = TokenSpec("liUSD-4w", LIUSD4W);
        specs[42] = TokenSpec("liUSD-13w", LIUSD13W);
    }

    function _deployImplementation(uint256 index, address factory) internal returns (IAccount implementation) {
        if (index == 0) return new ACRDX_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 1) return new CarryTradeUSDTRYLeverage_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 2) return new DUSD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 3) return new JAAA_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 4) return new JTRSY_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 5) {
            return new PRIME_Account(
                address(new AsyncRedeemOracle(IERC4626(PRIME).asset())), factory, PRIME, COW_SWAP_SETTLEMENT
            );
        }
        if (index == 6) return new StockMarketTRBasisTrade_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 7) return new bEQTY_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 8) {
            return new deCRDX_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        }
        if (index == 9) {
            return new deJAAA_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        }
        if (index == 10) {
            return new deJTRSY_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        }
        if (index == 11) return new mAPOLLO_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 12) return new mBASIS_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 13) return new mBTC_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 14) return new mEDGE_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 15) return new mEVUSD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 16) return new mFARM_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 17) return new mFONE_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 18) return new mGLOBAL_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 19) return new mHYPER_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 20) return new mHyperBTC_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 21) return new mHyperETH_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 22) return new mM1USD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 23) return new mMEV_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 24) return new mROX_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 25) return new mRe7BTC_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 26) return new mRe7YIELD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 27) return new mSL_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 28) return new mTBILL_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 29) return new mevBTC_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 30) return new msyrupUSD_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 31) return new msyrupUSDp_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 32) return new sAID_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 33) return new sUSD3_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 34) return new sthUSD_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 35) {
            return new weETH_Account(
                EETH,
                WETH,
                WEETH,
                address(new MainnetConstantOracle()),
                factory,
                ETHERFI_LIQUIDITY_POOL,
                ETHERFI_REDEMPTION_MANAGER,
                COW_SWAP_SETTLEMENT,
                ETHERFI_WITHDRAW_REQUEST_NFT
            );
        }
        if (index == 36) {
            return new wstETH_Account(
                STETH,
                WETH,
                address(new MainnetConstantOracle()),
                WSTETH,
                factory,
                LIDO_WITHDRAWAL_QUEUE,
                COW_SWAP_SETTLEMENT
            );
        }
        if (index == 37) {
            return new AA_FalconX_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        }
        if (index == 38) return new ACRED_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 39) return new sUSN_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 40) return new USCC_Account(address(new MainnetConstantOracle()), factory, COW_SWAP_SETTLEMENT);
        if (index == 41) return new liUSD4w_Account(factory, COW_SWAP_SETTLEMENT);
        if (index == 42) return new liUSD13w_Account(factory, COW_SWAP_SETTLEMENT);
        revert();
    }

    function _warpToRedemptionWindow(uint256 index, IAccount account) internal {
        if (index == 18) {
            uint48 cutoffTimestamp =
                ICutoffAccount(address(account)).bucketToTimestamp(ICutoffAccount(address(account)).currentBucket());
            vm.warp(uint256(cutoffTimestamp) - 1 days);
        }
    }

    function _assetFor(uint256 index, address token) internal view returns (address) {
        if (
            _isMidas(index) || _isCentrifuge(index) || index == 2 || index == 7 || index == 37 || _isSecuritize(index)
                || index == 40 || _isInfiniFi(index)
        ) {
            return USDC;
        }
        if (index == 5) {
            return IERC4626(IERC4626(token).asset()).asset();
        }
        if (index == 39) {
            return INoonWithdrawalHandler(NOON_WITHDRAWAL_HANDLER).usn();
        }
        if (index == 35 || index == 36) {
            return WETH;
        }
        return IERC4626(token).asset();
    }

    function _isMidas(uint256 index) internal pure returns (bool) {
        return index == 1 || index == 6 || (index >= 11 && index <= 31);
    }

    function _isCentrifuge(uint256 index) internal pure returns (bool) {
        return index == 0 || index == 3 || index == 4 || (index >= 8 && index <= 10);
    }

    function _isInfiniFi(uint256 index) internal pure returns (bool) {
        return index == 41 || index == 42;
    }

    function _isSecuritize(uint256 index) internal pure returns (bool) {
        return index == 38;
    }

    function _isKnownMainnetSyncRestricted(uint256 index) internal pure returns (bool) {
        return _isCentrifuge(index) || _isMidas(index) || index == 2 || index == 5 || index == 7 || index == 37
            || _isSecuritize(index) || index == 39 || index == 40;
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

    function _redemptionAmount(uint256 index, address token) internal view returns (uint256) {
        if (index == 35 || index == 36) {
            return 1 ether;
        }
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
                abi.encodeWithSelector(
                    IMidasRedemptionVault.redeemRequest.selector,
                    dataFeed == address(0) ? redemptionToken : asset,
                    amount
                )
            );
            return;
        }
        if (_isCentrifuge(index)) {
            vm.expectCall(
                _asyncRedeemVault(token, asset),
                abi.encodeWithSelector(
                    IAsyncRedeemVault.requestRedeem.selector, amount, address(account), address(account)
                )
            );
            return;
        }
        if (index == 2) {
            vm.expectCall(
                IMakinaAccount(address(account)).REDEEMER(),
                abi.encodeWithSelector(IMakinaRedeemer.requestRedeem.selector, amount, address(account), uint256(0))
            );
            return;
        }
        if (index == 5) {
            vm.expectCall(
                token, abi.encodeWithSelector(IERC4626.redeem.selector, amount, address(account), address(account))
            );
            return;
        }
        if (index == 7) {
            vm.expectCall(token, abi.encodeWithSelector(IERC20.transfer.selector));
            return;
        }
        if (index == 32) {
            vm.expectCall(token, abi.encodeWithSelector(ISaid.unstake.selector, amount));
            return;
        }
        if (index == 33) {
            vm.expectCall(token, abi.encodeWithSelector(IThreeJaneSUSD3.startCooldown.selector, amount));
            return;
        }
        if (index == 34) {
            vm.expectCall(token, abi.encodeWithSelector(ISthUSD.initiateRedeem.selector, amount, address(account)));
            return;
        }
        if (index == 35) {
            _expectEtherFiRedemptionSequenceCall(account, amount);
            return;
        }
        if (index == 37) {
            vm.expectCall(
                IParetoAccount(address(account)).IDLE_CDO(),
                abi.encodeWithSelector(IParetoCDO.requestWithdraw.selector, amount, token)
            );
            return;
        }
        if (_isSecuritize(index)) {
            // redemption notice is an ERC-20 transfer to the Securitize redemption wallet
            vm.expectCall(
                token, abi.encodeWithSelector(IERC20.transfer.selector, 0xbb543C77436645C8b95B64eEc39E3C0d48D4842b)
            );
            return;
        }
        if (index == 39) {
            vm.expectCall(
                token,
                abi.encodeWithSelector(IERC4626.redeem.selector, amount, NOON_WITHDRAWAL_HANDLER, address(account))
            );
            return;
        }
        if (index == 40) {
            return;
        }
        if (_isInfiniFi(index)) {
            vm.expectCall(
                INFINIFI_GATEWAY,
                abi.encodeWithSelector(
                    IInfiniFiGateway.startUnwinding.selector,
                    amount,
                    IInfiniFiAccount(address(account)).UNWINDING_EPOCHS()
                )
            );
            return;
        }
        vm.expectCall(
            ILidoAccount(payable(address(account))).WITHDRAWAL_QUEUE(),
            abi.encodeWithSelector(ILidoWithdrawalQueue.requestWithdrawalsWstETH.selector)
        );
    }

    function _expectEtherFiRedemptionSequenceCall(IAccount account, uint256 amount) internal {
        IEtherFiAccount etherFiAccount = IEtherFiAccount(payable(address(account)));
        IEtherFiRedemptionManager redemptionManager = IEtherFiRedemptionManager(etherFiAccount.REDEMPTION_MANAGER());
        address outputToken = redemptionManager.ETH_ADDRESS();
        (,, uint16 exitFeeInBps,) = redemptionManager.tokenToRedemptionInfo(outputToken);
        if (
            exitFeeInBps == 0
                && redemptionManager.canRedeem(IWeETH(account.TOKEN_TO_REDEEM()).getEETHByWeETH(amount), outputToken)
        ) {
            vm.expectCall(
                etherFiAccount.REDEMPTION_MANAGER(),
                abi.encodeWithSelector(
                    IEtherFiRedemptionManager.redeemWeEth.selector, amount, address(account), outputToken
                )
            );
            return;
        }

        vm.expectCall(account.TOKEN_TO_REDEEM(), abi.encodeWithSelector(IWeETH.unwrap.selector, amount));
        vm.expectCall(
            etherFiAccount.LIQUIDITY_POOL(),
            abi.encodeWithSelector(IEtherFiLiquidityPool.requestWithdraw.selector, address(account))
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
        if (index != 33) {
            assertEq(IERC20(token).balanceOf(address(account)), 0, symbol);
        }

        if (_isMidas(index)) {
            _assertMidasRedemption(account, amount, symbol);
            return;
        }
        if (_isCentrifuge(index)) {
            _assertAsyncRedemption(account, token, amount, symbol);
            return;
        }
        if (index == 2) {
            _assertMakinaRedemption(account, amount, symbol);
            return;
        }
        if (index == 5) {
            _assertFigureRedemption(account, token, symbol);
            return;
        }
        if (index == 7) {
            _assertDigiFTRedemption(account, symbol);
            return;
        }
        if (index == 32) {
            _assertGaibRedemption(account, symbol);
            return;
        }
        if (index == 33) {
            _assertThreeJaneRedemption(account, token, amount, symbol);
            return;
        }
        if (index == 34) {
            _assertTheoRedemption(account, token, amount, symbol);
            return;
        }
        if (index == 35) {
            _assertEtherFiRedemption(account, asset, symbol);
            return;
        }
        if (index == 37) {
            _assertParetoRedemption(account, symbol);
            return;
        }
        if (_isSecuritize(index)) {
            _assertSecuritizeRedemption(account, symbol);
            return;
        }
        if (index == 39) {
            _assertNoonRedemption(account, symbol);
            return;
        }
        if (index == 40) {
            _assertSuperstateRedemption(account, symbol);
            return;
        }
        if (_isInfiniFi(index)) {
            _assertInfiniFiRedemption(account, symbol);
            return;
        }
        _assertLidoRedemption(account, symbol);
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

    function _assertAsyncRedemption(IAccount account, address token, uint256 amount, string memory symbol)
        internal
        view
    {
        address asyncRedeemVault = _asyncRedeemVault(token, USDC);
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
        bytes memory callData = abi.encodeWithSelector(
            IMainnetCentrifugeTransferHook.updateMember.selector, token, account, type(uint64).max
        );

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

    function _assertMakinaRedemption(IAccount account, uint256 amount, string memory symbol) internal view {
        uint256 requestId = IMakinaAccount(address(account)).requestIds(0);
        assertGt(IMakinaRedeemer(IMakinaAccount(address(account)).REDEEMER()).getShares(requestId), 0, symbol);
        assertLe(IMakinaRedeemer(IMakinaAccount(address(account)).REDEEMER()).getShares(requestId), amount, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertFigureRedemption(IAccount account, address token, string memory symbol) internal view {
        (uint256 shares,,) = IFigureYieldVault(IERC4626(token).asset()).pendingRedemptions(address(account));
        assertGt(shares, 0, symbol);
        assertGt(IFigureAccount(address(account)).pendingAssets(), 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertDigiFTRedemption(IAccount account, string memory symbol) internal view {
        address subAccount = IDigiFTAccount(address(account)).subAccounts(0);
        assertGt(subAccount.code.length, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertGaibRedemption(IAccount account, string memory symbol) internal view {
        address subAccount = IGaibAccount(address(account)).subAccounts(0);
        (, uint256 pendingAssets) = ISaid(account.TOKEN_TO_REDEEM()).getUnstakeRequest(subAccount);
        assertGt(subAccount.code.length, 0, symbol);
        assertGt(pendingAssets, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertThreeJaneRedemption(IAccount account, address token, uint256 amount, string memory symbol)
        internal
        view
    {
        (,, uint256 shares) = IThreeJaneSUSD3(token).getCooldownStatus(address(account));
        assertEq(shares, amount, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertTheoRedemption(IAccount account, address token, uint256 amount, string memory symbol)
        internal
        view
    {
        (uint256 assets, uint256 shares,) = ISthUSD(token).currentRedeemRequest(address(account));
        assertEq(shares, amount, symbol);
        assertGt(assets, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertEtherFiRedemption(IAccount account, address asset, string memory symbol) internal view {
        if (IERC20(asset).balanceOf(address(account)) > 0) {
            assertGt(account.totalAssets(), 0, symbol);
            return;
        }

        uint256 requestId = IEtherFiAccount(payable(address(account))).requestIds(0);
        IEtherFiWithdrawRequestNFT.WithdrawRequest memory request = IEtherFiWithdrawRequestNFT(
                IEtherFiAccount(payable(address(account))).WITHDRAW_REQUEST_NFT()
            ).getRequest(requestId);

        assertTrue(request.isValid, symbol);
        assertGt(IEtherFiAccount(payable(address(account))).pendingAssets(), 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertParetoRedemption(IAccount account, string memory symbol) internal view {
        assertGt(IERC20(IParetoAccount(address(account)).RECEIPT_TOKEN()).balanceOf(address(account)), 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertSecuritizeRedemption(IAccount account, string memory symbol) internal view {
        (uint256 amount,) = ISecuritizeAccount(address(account)).pendingCutoffs(0);
        assertGt(amount, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertNoonRedemption(IAccount account, string memory symbol) internal view {
        uint256 requestId = INoonAccount(address(account)).requestIds(0);
        INoonWithdrawalHandler.WithdrawalRequest memory request = INoonWithdrawalHandler(
                INoonAccount(address(account)).WITHDRAWAL_HANDLER()
            ).getWithdrawalRequest(address(account), requestId);

        assertFalse(request.claimed, symbol);
        assertGt(request.amount, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertSuperstateRedemption(IAccount account, string memory symbol) internal view {
        address subAccount = ISuperstateAccount(address(account)).subAccounts(0);
        assertGt(subAccount.code.length, 0, symbol);
        assertGt(account.totalAssets(), 0, symbol);
    }

    function _assertInfiniFiRedemption(IAccount account, string memory symbol) internal view {
        uint48 unwindingTimestamp = IInfiniFiAccount(address(account)).unwindingTimestamps(0);

        assertEq(unwindingTimestamp, uint48(block.timestamp), symbol);
        assertGt(
            IInfiniFiUnwindingModule(INFINIFI_UNWINDING_MODULE).balanceOf(address(account), unwindingTimestamp),
            0,
            symbol
        );
        assertGt(account.totalAssets(), 0, symbol);
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
