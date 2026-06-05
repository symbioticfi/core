// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {MidasAccount} from "../../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
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
import {MigratablesFactory} from "../../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IMidasRedemptionVault} from "../../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MidasTokensToRedeemMainnetTest is Test {
    struct TokenSpec {
        string symbol;
        uint48 maxWithdrawalDelay;
    }

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

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
        assertEq(account.COOLDOWN(), _cooldown(spec.maxWithdrawalDelay));
        assertTrue(account.isConverter(address(this)));
        assertEq(account.adapter(), adapter);
        assertEq(account.vault(), address(vault));
        assertEq(
            MidasOracle(account.ORACLE()).DATA_FEED(), address(IMidasRedemptionVault(redemptionVault).mTokenDataFeed())
        );
        assertGt(MidasOracle(account.ORACLE()).getPrice(), 0);
        assertEq(IERC20(token).allowance(address(account), redemptionVault), type(uint256).max);
        assertEq(IAccount(address(account)).totalAssets(), 0);
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
            return new mFONE_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        }
        if (index == 1) return new mTBILL_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 2) return new mGLOBAL_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 3) return new mHYPER_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 4) return new mM1USD_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 5) return new mHyperBTC_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 6) return new mRe7YIELD_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 7) return new mHyperETH_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 8) return new mSL_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 9) return new mAPOLLO_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 10) return new mROX_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 11) return new msyrupUSDp_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 12) return new mEVUSD_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 13) return new mEDGE_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 14) return new mMEV_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 15) return new mBASIS_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 16) return new mRe7BTC_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 17) return new mBTC_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 18) return new mevBTC_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 19) return new msyrupUSD_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 20) return new mFARM_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        if (index == 21) {
            return new CarryTradeUSDTRYLeverage_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
        }
        return new StockMarketTRBasisTrade_Account(address(factory), COW_SWAP_SETTLEMENT, COW_SWAP_VAULT_RELAYER);
    }

    function _ethereumCompSpec(string memory symbol, uint48 maxWithdrawalDelay)
        internal
        pure
        returns (TokenSpec memory spec)
    {
        spec = TokenSpec(symbol, maxWithdrawalDelay);
    }

    function _cooldown(uint48 maxWithdrawalDelay) internal pure returns (uint48) {
        uint48 cooldownDays = maxWithdrawalDelay / 10 / 1 days;
        if (cooldownDays == 0) {
            return 1 days;
        }
        return cooldownDays * 1 days;
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
