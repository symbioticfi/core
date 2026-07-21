// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeployLiquidLane2Script} from "../../script/deploy/adapters/DeployLiquidLane2.s.sol";
import {CentrifugeAccount} from "../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {AsyncRedeemOracle} from "../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {IAsyncRedeemAccount} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {ICooldownAccount} from "../../src/interfaces/adapters/ll-adapter/ICooldownAccount.sol";
import {IERC7575Share} from "../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployLiquidLane2ScriptHarness is DeployLiquidLane2Script {
    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployLiquidLane2Test is Test {
    DeployLiquidLane2ScriptHarness internal harness;

    address[6] internal tokens;
    address[6] internal asyncRedeemVaults;
    uint256[6] internal minPrices;
    uint256[6] internal maxPrices;

    function setUp() public {
        harness = new DeployLiquidLane2ScriptHarness();

        tokens =
            [harness.ACRDX(), harness.JAAA(), harness.JTRSY(), harness.DECRDX(), harness.DEJAAA(), harness.DEJTRSY()];
        minPrices = [
            harness.ACRDX_MIN_PRICE(),
            harness.JAAA_MIN_PRICE(),
            harness.JTRSY_MIN_PRICE(),
            harness.DECRDX_MIN_PRICE(),
            harness.DEJAAA_MIN_PRICE(),
            harness.DEJTRSY_MIN_PRICE()
        ];
        maxPrices = [
            harness.ACRDX_MAX_PRICE(),
            harness.JAAA_MAX_PRICE(),
            harness.JTRSY_MAX_PRICE(),
            harness.DECRDX_MAX_PRICE(),
            harness.DEJAAA_MAX_PRICE(),
            harness.DEJTRSY_MAX_PRICE()
        ];

        vm.mockCall(harness.USDC(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
        vm.mockCall(
            harness.COW_SWAP_SETTLEMENT(),
            abi.encodeWithSelector(ICoWSwapSettlement.vaultRelayer.selector),
            abi.encode(makeAddr("cowSwapVaultRelayer"))
        );

        for (uint256 i; i < tokens.length; ++i) {
            uint8 decimals = i == 1 || i == 2 ? 6 : 18;
            address asyncRedeemVault = address(uint160(0x1000 + i));
            asyncRedeemVaults[i] = asyncRedeemVault;

            vm.mockCall(tokens[i], abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(IERC7575Share.vault.selector, harness.USDC()),
                abi.encode(asyncRedeemVault)
            );
            vm.mockCall(
                asyncRedeemVault, abi.encodeWithSelector(IAsyncRedeemVault.asset.selector), abi.encode(harness.USDC())
            );
            vm.mockCall(
                asyncRedeemVault,
                abi.encodeWithSelector(IAsyncRedeemVault.convertToAssets.selector, 10 ** decimals),
                abi.encode(1e6)
            );
        }

        _stubOpenEden();
        _stubFigure();
        _stubMGlobal();
    }

    /// @dev Stubs the OpenEden HYBOND surface the deploy + validation reads (no proxy is created, so
    ///      only constructor getters and oracle `getPrice` are exercised).
    function _stubOpenEden() internal {
        vm.mockCall(harness.HYBOND(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("redeemAsset()"), abi.encode(harness.USDC()));
        // previewRedeem(tokenAmount) -> (fee, gross, net); net drives the 1e18-scaled oracle price.
        vm.mockCall(
            harness.HYBOND_EXPRESS(),
            abi.encodeWithSignature("previewRedeem(uint256)"),
            abi.encode(uint256(0), uint256(1_734_344), uint256(1_734_344))
        );
    }

    /// @dev Stubs the Figure PRIME/AUTO surface through the shared wYLDS yield vault.
    function _stubFigure() internal {
        address wylds = makeAddr("wYLDS");
        vm.mockCall(wylds, abi.encodeWithSignature("asset()"), abi.encode(harness.USDC()));
        vm.mockCall(wylds, abi.encodeWithSignature("convertToAssets(uint256)"), abi.encode(uint256(1e6)));

        address[2] memory figureTokens = [harness.PRIME(), harness.AUTO()];
        for (uint256 i; i < figureTokens.length; ++i) {
            vm.mockCall(figureTokens[i], abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
            vm.mockCall(figureTokens[i], abi.encodeWithSignature("asset()"), abi.encode(wylds));
            vm.mockCall(figureTokens[i], abi.encodeWithSignature("convertToAssets(uint256)"), abi.encode(uint256(1e6)));
        }
    }

    /// @dev Stubs the Midas mGLOBAL surface the account constructor + validation reads.
    function _stubMGlobal() internal {
        vm.mockCall(harness.MGLOBAL(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("mTokenDataFeed()"),
            abi.encode(harness.MGLOBAL_DATA_FEED())
        );
        address aggregator = makeAddr("mGlobalAggregator");
        vm.mockCall(harness.MGLOBAL_DATA_FEED(), abi.encodeWithSignature("aggregator()"), abi.encode(aggregator));
        vm.mockCall(
            aggregator, abi.encodeWithSignature("underlyingFeed()"), abi.encode(harness.MGLOBAL_MARKET_AGGREGATOR())
        );
        // getDataInBase18 must sit inside the mGLOBAL MidasOracle bounds (0.2514e18 .. 3.5202e18).
        vm.mockCall(
            harness.MGLOBAL_DATA_FEED(),
            abi.encodeWithSignature("getDataInBase18()"),
            abi.encode(uint256(935_361_270_000_000_000))
        );
    }

    function testRunDeploysAndWhitelistsAllCentrifugeAccountsWithoutRegisteringFactories() public {
        vm.recordLogs();
        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = harness.run();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        DeployLiquidLane2Script.AccountDeploymentData[6] memory deployments;
        deployments[0] = data.acrdx;
        deployments[1] = data.jaaa;
        deployments[2] = data.jtrsy;
        deployments[3] = data.deCRDX;
        deployments[4] = data.deJAAA;
        deployments[5] = data.deJTRSY;

        for (uint256 i; i < deployments.length; ++i) {
            _assertDeployment(deployments[i], i);
        }

        // The OpenEden (HYBOND), Figure (PRIME/AUTO) and Midas (mGLOBAL) accounts are deployed and
        // whitelisted but not registered, exactly like the Centrifuge ones.
        _assertNonCentrifugeDeployment(data.hybond, harness.HYBOND());
        _assertNonCentrifugeDeployment(data.prime, harness.PRIME());
        _assertNonCentrifugeDeployment(data.autoToken, harness.AUTO());
        _assertNonCentrifugeDeployment(data.mGlobal, harness.MGLOBAL());

        bytes32 whitelistTopic = keccak256("Whitelist(address)");
        bytes32 setAccountFactoryTopic = keccak256("SetAccountFactory(address,address,address)");
        uint256 whitelistEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == whitelistTopic) {
                ++whitelistEvents;
            }
            assertNotEq(logs[i].topics[0], setAccountFactoryTopic);
        }
        // 6 Centrifuge + HYBOND + PRIME + AUTO + mGLOBAL.
        assertEq(whitelistEvents, deployments.length + 4);
    }

    function _assertNonCentrifugeDeployment(DeployLiquidLane2Script.AccountDeploymentData memory data, address token)
        internal
        view
    {
        assertNotEq(data.oracle, address(0));
        assertNotEq(data.factory, address(0));
        assertNotEq(data.implementation, address(0));
        assertEq(Ownable(data.factory).owner(), harness.FACTORIES_OWNER());
        assertEq(MigratablesFactory(data.factory).implementation(1), data.implementation);
        assertEq(IMigratableEntity(data.implementation).FACTORY(), data.factory);
        assertEq(IAccount(data.implementation).ORACLE(), data.oracle);
        assertEq(IAccount(data.implementation).TOKEN_TO_REDEEM(), token);
    }

    function _assertDeployment(DeployLiquidLane2Script.AccountDeploymentData memory data, uint256 index) internal view {
        MigratablesFactory factory = MigratablesFactory(data.factory);
        AsyncRedeemOracle oracle = AsyncRedeemOracle(data.oracle);
        IAccount account = IAccount(data.implementation);

        assertNotEq(data.oracle, address(0));
        assertNotEq(data.factory, address(0));
        assertNotEq(data.implementation, address(0));
        assertEq(Ownable(data.factory).owner(), harness.FACTORIES_OWNER());
        assertEq(factory.lastVersion(), 1);
        assertEq(factory.implementation(1), data.implementation);
        assertEq(IMigratableEntity(data.implementation).FACTORY(), data.factory);
        assertEq(account.ORACLE(), data.oracle);
        assertEq(account.TOKEN_TO_REDEEM(), tokens[index]);
        assertEq(IAsyncRedeemAccount(data.implementation).REDEMPTION_TOKEN(), harness.USDC());
        assertEq(CentrifugeAccount(data.implementation).ASYNC_REDEEM_VAULT(), asyncRedeemVaults[index]);
        assertEq(ICooldownAccount(data.implementation).COOLDOWN(), 0);
        assertEq(ICoWSwapConverter(data.implementation).COW_SWAP_SETTLEMENT(), harness.COW_SWAP_SETTLEMENT());
        assertEq(oracle.ASYNC_REDEEM_VAULT(), asyncRedeemVaults[index]);
        assertEq(oracle.MIN_PRICE(), minPrices[index]);
        assertEq(oracle.MAX_PRICE(), maxPrices[index]);
        assertEq(oracle.getPrice(), 1e18);
    }
}
