// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployLiquidLaneScript} from "../../script/deploy/adapters/DeployLiquidLane.s.sol";
import {MidasOracle} from "../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IMidasDataFeed, IMidasOracle} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";

contract DeploymentMarketAggregatorMock {
    uint8 public immutable decimals;
    int256 internal immutable _answer;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        _answer = answer_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }
}

contract DeploymentAdjustedAggregatorMock is DeploymentMarketAggregatorMock {
    address public immutable underlyingFeed;

    constructor(address underlyingFeed_, int256 adjustedAnswer) DeploymentMarketAggregatorMock(8, adjustedAnswer) {
        underlyingFeed = underlyingFeed_;
    }
}

contract DeploymentMidasDataFeedMock {
    uint256 internal immutable _price;
    address public immutable aggregator;

    constructor(uint256 price_, address aggregator_) {
        _price = price_;
        aggregator = aggregator_;
    }

    function getDataInBase18() external view returns (uint256) {
        return _price;
    }
}

contract DeployLiquidLaneScriptHarness is DeployLiquidLaneScript {
    address internal immutable _testVaultFactory;

    constructor(address vaultFactory_) {
        _testVaultFactory = vaultFactory_;
    }

    function validateOraclePrice(address oracle) external view {
        _validateOraclePrice(oracle);
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }

    function _coreVaultFactory() internal view override returns (address) {
        return _testVaultFactory;
    }
}

contract DeployLiquidLaneTest is Test {
    address internal constant MGLOBAL_MARKET_AGGREGATOR = 0x66Aa9fcD63DF74e1f67A9452E6E59Fbc67f75E38;

    DeployLiquidLaneScriptHarness internal harness;

    function setUp() public {
        harness = new DeployLiquidLaneScriptHarness(makeAddr("vaultFactory"));
    }

    function testValidatesUnadjustedMarketPrice() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, 100_000_000);
        harness.validateOraclePrice(_oracle(1e18, address(market)));
    }

    function testValidatesMarketPriceWithEighteenDecimals() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(18, 1e18);
        harness.validateOraclePrice(_oracle(1e18, address(market)));
    }

    function testValidatesMarketPriceWithTwentyDecimals() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(20, 1e20);
        harness.validateOraclePrice(_oracle(1e18, address(market)));
    }

    function testAllowsExactlyHalfPercentDeviation() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, 100_000_000);
        harness.validateOraclePrice(_oracle(1_005_000_000_000_000_000, address(market)));
    }

    function testRejectsDeviationAboveHalfPercent() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, 100_000_000);
        address oracle = _oracle(1_005_000_000_000_000_001, address(market));
        vm.expectRevert(bytes("oracle price exceeds 0.5% market deviation"));
        harness.validateOraclePrice(oracle);
    }

    function testUnwrapsAdjustedAggregatorAndRejectsSevenPercentDiscount() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, 100_000_000);
        DeploymentAdjustedAggregatorMock adjusted = new DeploymentAdjustedAggregatorMock(address(market), 93_000_000);
        address oracle = _oracle(930_000_000_000_000_000, address(adjusted));

        vm.expectRevert(bytes("oracle price exceeds 0.5% market deviation"));
        harness.validateOraclePrice(oracle);
    }

    function testRejectsZeroMarketAnswer() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, 0);
        address oracle = _oracle(1e18, address(market));
        vm.expectRevert(bytes("invalid market price"));
        harness.validateOraclePrice(oracle);
    }

    function testRejectsNegativeMarketAnswer() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(8, -1);
        address oracle = _oracle(1e18, address(market));
        vm.expectRevert(bytes("invalid market price"));
        harness.validateOraclePrice(oracle);
    }

    function testRejectsPositiveMarketAnswerThatNormalizesToZero() public {
        DeploymentMarketAggregatorMock market = new DeploymentMarketAggregatorMock(20, 99);
        address oracle = _oracle(1e18, address(market));
        vm.expectRevert(bytes("invalid market price"));
        harness.validateOraclePrice(oracle);
    }

    function testRunValidatesAllSevenMainnetOraclePrices() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        address mGlobalDataFeed = vm.envOr("MGLOBAL_DATA_FEED", address(0));
        if (bytes(rpcUrl).length == 0 || mGlobalDataFeed == address(0)) {
            vm.skip(true, "ETH_RPC_URL and MGLOBAL_DATA_FEED are required for the production deployment check");
        }

        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }

        DeployLiquidLaneScriptHarness forkHarness = new DeployLiquidLaneScriptHarness(makeAddr("forkVaultFactory"));
        DeployLiquidLaneScript.LiquidLaneDeploymentData memory data = forkHarness.run(mGlobalDataFeed);

        address mGlobalOracle = IAccount(data.mGLOBAL.implementation).ORACLE();
        assertEq(IMidasOracle(mGlobalOracle).DATA_FEED(), mGlobalDataFeed);
        assertEq(IMidasDataFeed(mGlobalDataFeed).aggregator(), MGLOBAL_MARKET_AGGREGATOR);
        assertGt(MidasOracle(mGlobalOracle).getPrice(), 0);
    }

    function _oracle(uint256 price, address aggregator) internal returns (address) {
        DeploymentMidasDataFeedMock dataFeed = new DeploymentMidasDataFeedMock(price, aggregator);
        return address(new MidasOracle(1, type(uint256).max, address(dataFeed)));
    }
}
