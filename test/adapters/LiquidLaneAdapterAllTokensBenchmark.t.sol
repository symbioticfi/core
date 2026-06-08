// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {ACRDX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {DUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/DUSD_Account.sol";
import {JAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {PRIME_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {PST_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PST_Account.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {deJAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {mAPOLLO_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mAPOLLO_Account.sol";
import {mBASIS_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBASIS_Account.sol";
import {mBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBTC_Account.sol";
import {mEDGE_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEDGE_Account.sol";
import {mEVUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEVUSD_Account.sol";
import {mFARM_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFARM_Account.sol";
import {mFONE_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {mGLOBAL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {mHYPER_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {mHyperBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperBTC_Account.sol";
import {mHyperETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperETH_Account.sol";
import {mM1USD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {mMEV_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mMEV_Account.sol";
import {mROX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {mRe7BTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7BTC_Account.sol";
import {mRe7YIELD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7YIELD_Account.sol";
import {mSL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mSL_Account.sol";
import {mTBILL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mTBILL_Account.sol";
import {mevBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mevBTC_Account.sol";
import {msyrupUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSD_Account.sol";
import {msyrupUSDp_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSDp_Account.sol";
import {sAID_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sAID_Account.sol";
import {sUSD3_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSD3_Account.sol";
import {sthUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {weETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";
import {ILiquidLaneAdapter, MAX_TOKENS_TO_REDEEM} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LiquidLaneAdapterAllTokensBenchmarkTest is Test {
    using Math for uint256;

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    address internal constant PRIME_TOKEN = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address internal curator = makeAddr("curator");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");

    BenchmarkVaultRegistry internal vaultFactory;
    AdapterFactory internal adapterFactory;
    AccountRegistry internal accountRegistry;
    BenchmarkLiquidLaneVault internal vault;
    LiquidLaneAdapter internal adapter;

    struct TokenBenchSpec {
        string symbol;
        uint48 maxDelay;
        uint48 cooldown;
        uint256 maxAverageRequests;
    }

    struct AccountGasBench {
        uint256 totalAssetsGas;
        uint256 syncGas;
    }

    function testCalculatesAllTokenCooldownsAndRequestCounts() public pure {
        TokenBenchSpec[] memory specs = _tokenBenchSpecs();

        assertEq(specs.length, 36);
        assertLe(specs.length, MAX_TOKENS_TO_REDEEM);

        uint256 totalMaxAverageRequests;
        for (uint256 i; i < specs.length; ++i) {
            uint48 expectedCooldown = _cooldown(specs[i].maxDelay);
            assertEq(specs[i].cooldown, expectedCooldown, specs[i].symbol);
            assertEq(specs[i].maxAverageRequests, uint256(specs[i].maxDelay).ceilDiv(expectedCooldown), specs[i].symbol);
            assertLe(specs[i].maxAverageRequests, 10, specs[i].symbol);
            totalMaxAverageRequests += specs[i].maxAverageRequests;
        }
        assertEq(totalMaxAverageRequests, 186);
    }

    function testBenchmarkOnboardsAllTokensToLiquidLaneAdapter() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for all-token LiquidLaneAdapter onboarding benchmark");

        vm.pauseGasMetering();
        vm.createSelectFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        vm.startPrank(curator);
        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        for (uint256 i; i < tokens.length; ++i) {
            adapter.addTokenToRedeem(tokens[i]);
        }
        uint256 onboardingGas = gasBefore - gasleft();

        vm.pauseGasMetering();
        vm.stopPrank();
        assertEq(adapter.getTokensToRedeemLength(), specs.length);
        _logBench(specs, onboardingGas);
    }

    function testBenchmarkTotalAssetsAndSyncForEachAccount() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for account totalAssets/sync benchmark");

        vm.pauseGasMetering();
        vm.createSelectFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        vm.startPrank(curator);
        for (uint256 i; i < tokens.length; ++i) {
            adapter.addTokenToRedeem(tokens[i]);
        }
        vm.stopPrank();

        AccountGasBench[] memory benches = _benchmarkAccountGas(specs, tokens);

        assertEq(benches.length, specs.length);
        for (uint256 i; i < benches.length; ++i) {
            assertGt(benches[i].totalAssetsGas, 0, specs[i].symbol);
            assertGt(benches[i].syncGas, 0, specs[i].symbol);
        }
    }

    function _setUpAdapter() internal {
        vaultFactory = new BenchmarkVaultRegistry();
        vault = new BenchmarkLiquidLaneVault(MAINNET_USDC);
        vaultFactory.add(address(vault));

        adapterFactory = new AdapterFactory(curator);
        accountRegistry = new AccountRegistry(curator);

        LiquidLaneAdapter implementation =
            new LiquidLaneAdapter(address(vaultFactory), address(adapterFactory), address(accountRegistry));

        vm.startPrank(curator);
        adapterFactory.whitelist(address(implementation));

        ILiquidLaneAdapter.InitParams memory params =
            ILiquidLaneAdapter.InitParams({pauser: pauser, unpauser: unpauser});
        adapter = LiquidLaneAdapter(adapterFactory.create(1, curator, abi.encode(address(vault), abi.encode(params))));
        vm.stopPrank();
    }

    function _registerTokenFactories(TokenBenchSpec[] memory specs) internal returns (address[] memory tokens) {
        tokens = new address[](specs.length);

        vm.startPrank(curator);
        for (uint256 i; i < specs.length; ++i) {
            MigratablesFactory accountFactory = new MigratablesFactory(curator);
            IAccount implementation = _deployImplementation(i, address(accountFactory));
            address token = implementation.TOKEN_TO_REDEEM();

            accountFactory.whitelist(address(implementation));
            accountRegistry.setAccountFactory(MAINNET_USDC, token, address(accountFactory));
            tokens[i] = token;
        }
        vm.stopPrank();
    }

    function _benchmarkAccountGas(TokenBenchSpec[] memory specs, address[] memory tokens)
        internal
        returns (AccountGasBench[] memory benches)
    {
        benches = new AccountGasBench[](specs.length);

        uint256 totalTotalAssetsGas;
        uint256 totalSyncGas;

        for (uint256 i; i < specs.length; ++i) {
            address account = adapter.accounts(tokens[i]);
            assertGt(account.code.length, 0, specs[i].symbol);

            vm.resumeGasMetering();
            uint256 gasBefore = gasleft();
            uint256 assets = IAccount(account).totalAssets();
            uint256 totalAssetsGas = gasBefore - gasleft();

            gasBefore = gasleft();
            IAccount(account).sync();
            uint256 syncGas = gasBefore - gasleft();
            vm.pauseGasMetering();

            benches[i] = AccountGasBench({totalAssetsGas: totalAssetsGas, syncGas: syncGas});
            totalTotalAssetsGas += totalAssetsGas;
            totalSyncGas += syncGas;

            emit log_named_string("token", specs[i].symbol);
            emit log_named_address("account", account);
            emit log_named_uint("totalAssets", assets);
            emit log_named_uint("totalAssets gas", totalAssetsGas);
            emit log_named_uint("sync gas", syncGas);
        }

        emit log_named_uint("accounts benchmarked", specs.length);
        emit log_named_uint("total totalAssets gas", totalTotalAssetsGas);
        emit log_named_uint("total sync gas", totalSyncGas);
    }

    function _tokenBenchSpecs() internal pure returns (TokenBenchSpec[] memory specs) {
        specs = new TokenBenchSpec[](36);
        specs[0] = _spec("ACRDX", 1 days);
        specs[1] = _spec("CarryTradeUSDTRYLeverage", 2 days);
        specs[2] = _spec("DUSD", 12 hours);
        specs[3] = _spec("JAAA", 1 days);
        specs[4] = _spec("JTRSY", 1 days);
        specs[5] = _spec("PRIME", 1 days);
        specs[6] = _spec("PST", 7 days);
        specs[7] = _spec("StockMarketTRBasisTrade", 2 days);
        specs[8] = _spec("deJAAA", 1 days);
        specs[9] = _spec("deJTRSY", 1 days);
        specs[10] = _spec("mAPOLLO", 3 days);
        specs[11] = _spec("mBASIS", 7 days);
        specs[12] = _spec("mBTC", 7 days);
        specs[13] = _spec("mEDGE", 3 days);
        specs[14] = _spec("mEVUSD", 3 days);
        specs[15] = _spec("mFARM", 7 days);
        specs[16] = _spec("mFONE", 35 days);
        specs[17] = _spec("mGLOBAL", 65 days);
        specs[18] = _spec("mHYPER", 3 days);
        specs[19] = _spec("mHyperBTC", 7 days);
        specs[20] = _spec("mHyperETH", 7 days);
        specs[21] = _spec("mM1USD", 17 days);
        specs[22] = _spec("mMEV", 3 days);
        specs[23] = _spec("mROX", 3 days);
        specs[24] = _spec("mRe7BTC", 24 days);
        specs[25] = _spec("mRe7YIELD", 24 days);
        specs[26] = _spec("mSL", 3 days);
        specs[27] = _spec("mTBILL", 3 days);
        specs[28] = _spec("mevBTC", 7 days);
        specs[29] = _spec("msyrupUSD", 7 days);
        specs[30] = _spec("msyrupUSDp", 3 days);
        specs[31] = _spec("sAID", 62 days);
        specs[32] = _spec("sUSD3", 30 days);
        specs[33] = _spec("sthUSD", 7 days);
        specs[34] = _spec("weETH", 14 days);
        specs[35] = _spec("wstETH", 5 days);
    }

    function _deployImplementation(uint256 index, address factory) internal returns (IAccount implementation) {
        if (index == 0) {
            return IAccount(
                address(
                    new ACRDX_Account(makeAddr("ACRDX_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)
                )
            );
        }
        if (index == 1) {
            return IAccount(
                address(new CarryTradeUSDTRYLeverage_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER))
            );
        }
        if (index == 2) {
            return IAccount(address(new DUSD_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 3) {
            return IAccount(
                address(new JAAA_Account(makeAddr("JAAA_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER))
            );
        }
        if (index == 4) {
            return IAccount(
                address(
                    new JTRSY_Account(makeAddr("JTRSY_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)
                )
            );
        }
        if (index == 5) {
            return IAccount(
                address(
                    new PRIME_Account(
                        makeAddr("PRIME_ORACLE"), factory, PRIME_TOKEN, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER
                    )
                )
            );
        }
        if (index == 6) {
            return IAccount(
                address(
                    new PST_Account(
                        factory, address(new BenchmarkHumaTrancheVault()), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER
                    )
                )
            );
        }
        if (index == 7) {
            return IAccount(
                address(new StockMarketTRBasisTrade_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER))
            );
        }
        if (index == 8) {
            return IAccount(
                address(
                    new deJAAA_Account(makeAddr("deJAAA_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)
                )
            );
        }
        if (index == 9) {
            return IAccount(
                address(
                    new deJTRSY_Account(
                        makeAddr("deJTRSY_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER
                    )
                )
            );
        }
        if (index == 10) {
            return IAccount(address(new mAPOLLO_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 11) {
            return IAccount(address(new mBASIS_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 12) {
            return IAccount(address(new mBTC_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 13) {
            return IAccount(address(new mEDGE_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 14) {
            return IAccount(address(new mEVUSD_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 15) {
            return IAccount(address(new mFARM_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 16) {
            return IAccount(address(new mFONE_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 17) {
            return IAccount(address(new mGLOBAL_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 18) {
            return IAccount(address(new mHYPER_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 19) {
            return IAccount(address(new mHyperBTC_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 20) {
            return IAccount(address(new mHyperETH_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 21) {
            return IAccount(address(new mM1USD_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 22) {
            return IAccount(address(new mMEV_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 23) {
            return IAccount(address(new mROX_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 24) {
            return IAccount(address(new mRe7BTC_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 25) {
            return IAccount(address(new mRe7YIELD_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 26) {
            return IAccount(address(new mSL_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 27) {
            return IAccount(address(new mTBILL_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 28) {
            return IAccount(address(new mevBTC_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 29) {
            return IAccount(address(new msyrupUSD_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 30) {
            return IAccount(address(new msyrupUSDp_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 31) {
            return IAccount(address(new sAID_Account(factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)));
        }
        if (index == 32) {
            return IAccount(
                address(
                    new sUSD3_Account(makeAddr("sUSD3_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)
                )
            );
        }
        if (index == 33) {
            return IAccount(
                address(
                    new sthUSD_Account(makeAddr("sthUSD_ORACLE"), factory, COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER)
                )
            );
        }
        if (index == 34) {
            return IAccount(
                address(
                    new weETH_Account(
                        EETH,
                        WETH,
                        WEETH,
                        makeAddr("weETH_ORACLE"),
                        factory,
                        makeAddr("ETHERFI_LIQUIDITY_POOL"),
                        makeAddr("ETHERFI_REDEMPTION_MANAGER"),
                        COW_SWAP_SETTLEMENT,
                        makeAddr("ETHERFI_WITHDRAW_REQUEST_NFT"),
                        COW_SWAP_VAULT_RELAYER
                    )
                )
            );
        }
        return IAccount(
            address(
                new wstETH_Account(
                    STETH,
                    makeAddr("wstETH_ORACLE"),
                    WSTETH,
                    factory,
                    LIDO_WITHDRAWAL_QUEUE,
                    COW_SWAP_SETTLEMENT,
                    COW_SWAP_VAULT_RELAYER
                )
            )
        );
    }

    function _spec(string memory symbol, uint48 maxDelay) internal pure returns (TokenBenchSpec memory spec) {
        uint48 cooldown = _cooldown(maxDelay);
        spec = TokenBenchSpec({
            symbol: symbol,
            maxDelay: maxDelay,
            cooldown: cooldown,
            maxAverageRequests: uint256(maxDelay).ceilDiv(cooldown)
        });
    }

    function _cooldown(uint48 maxDelay) internal pure returns (uint48) {
        uint48 cooldown = maxDelay / 10;
        return cooldown < 1 days ? uint48(1 days) : cooldown;
    }

    function _logBench(TokenBenchSpec[] memory specs, uint256 onboardingGas) internal {
        uint256 totalMaxAverageRequests;
        emit log_named_uint("tokens onboarded", specs.length);
        emit log_named_uint("all-token onboarding gas", onboardingGas);

        for (uint256 i; i < specs.length; ++i) {
            totalMaxAverageRequests += specs[i].maxAverageRequests;
            emit log_named_string("token", specs[i].symbol);
            emit log_named_uint("maxDelay", specs[i].maxDelay);
            emit log_named_uint("cooldown", specs[i].cooldown);
            emit log_named_uint("maxAverageRequests", specs[i].maxAverageRequests);
        }

        emit log_named_uint("total maxAverageRequests", totalMaxAverageRequests);
    }

    function _skipWithoutRpc(string memory rpcUrl, string memory reason) internal {
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, reason);
        }
    }
}

contract BenchmarkVaultRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract BenchmarkLiquidLaneVault {
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
}

contract BenchmarkHumaTrancheVault {
    function addRedemptionRequest(uint256) external {}

    function disburse() external {}

    function withdrawAfterPoolClosure() external {}
}
