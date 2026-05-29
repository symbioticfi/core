// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MidasIssuer} from "../../../src/contracts/adapters/ll_adapter/issuers/MidasIssuer.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll_adapter/oracles/ChainlinkOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll_adapter/oracles/MidasOracle.sol";
import {IChainlinkOracle} from "../../../src/interfaces/adapters/ll_adapter/oracles/IChainlinkOracle.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MidasIssuerOraclesTest is Test {
    function testMidasIssuerReportsHeldTokenToRedeem() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault = new MockMidasRedemptionVault(address(tokenToRedeem));
        MidasIssuer issuer = new MidasIssuer(
            address(tokenToRedeem), address(asset), makeAddr("fallbackToken"), address(redemptionVault)
        );

        tokenToRedeem.mint(address(issuer), 100 ether);

        assertEq(issuer.totalAssets(), 100 ether);
    }

    function testMidasIssuerRedeemsIntoConfiguredAsset() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        address fallbackToken = makeAddr("fallbackToken");
        MockMidasRedemptionVault redemptionVault = new MockMidasRedemptionVault(address(tokenToRedeem));
        MidasIssuer issuer =
            new MidasIssuer(address(tokenToRedeem), address(asset), fallbackToken, address(redemptionVault));
        redemptionVault.setDataFeed(address(asset), makeAddr("dataFeed"));
        tokenToRedeem.mint(address(issuer), 100 ether);

        assertEq(issuer.redeem(), 100 ether);

        assertEq(redemptionVault.lastTokenOut(), address(asset));
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
        assertEq(tokenToRedeem.balanceOf(address(redemptionVault)), 100 ether);
        assertEq(issuer.totalAssets(), 0);
    }

    function testMidasIssuerRedeemsIntoFallbackTokenWhenAssetIsUnsupported() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        address fallbackToken = makeAddr("fallbackToken");
        MockMidasRedemptionVault redemptionVault = new MockMidasRedemptionVault(address(tokenToRedeem));
        MidasIssuer issuer =
            new MidasIssuer(address(tokenToRedeem), address(asset), fallbackToken, address(redemptionVault));
        tokenToRedeem.mint(address(issuer), 100 ether);

        assertEq(issuer.redeem(), 100 ether);

        assertEq(redemptionVault.lastTokenOut(), fallbackToken);
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
    }

    function testMidasIssuerRedeemDoesNothingWithNoBalance() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MidasIssuer issuer = new MidasIssuer(
            address(tokenToRedeem),
            makeAddr("asset"),
            makeAddr("fallbackToken"),
            address(new MockMidasRedemptionVault(address(tokenToRedeem)))
        );

        assertEq(issuer.redeem(), 0);
    }

    function testChainlinkOracleReturnsLatestPriceInBase18() public {
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, block.timestamp, 1);
        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        assertEq(oracle.getPrice(), 123e18);
    }

    function testChainlinkOracleMultipliesSecondAggregatorHop() public {
        MockChainlinkAggregator aggregator0 = new MockChainlinkAggregator(8);
        MockChainlinkAggregator aggregator1 = new MockChainlinkAggregator(18);
        aggregator0.setLatestRoundData(1, 2e8, block.timestamp, 1);
        aggregator1.setLatestRoundData(1, 3e18, block.timestamp, 1);
        ChainlinkOracle oracle =
            new ChainlinkOracle([address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]);

        assertEq(oracle.getPrice(), 6e18);
    }

    function testChainlinkOracleReturnsZeroForStalePrice() public {
        vm.warp(10 days);
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, block.timestamp - 2 days, 1);
        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        assertEq(oracle.getPrice(), 0);
    }

    function testChainlinkOracleRevertsWithNoFirstAggregator() public {
        vm.expectRevert(IChainlinkOracle.InvalidAggregator.selector);
        new ChainlinkOracle([address(0), makeAddr("aggregator")], [uint48(1 days), uint48(0)]);
    }

    function testMidasOracleReturnsFeedPrice() public {
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(42e18);
        MidasOracle oracle = new MidasOracle(address(dataFeed));

        assertEq(oracle.getPrice(), 42e18);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}

contract MockMidasRedemptionVault {
    address public immutable tokenToRedeem;
    address public lastTokenOut;
    uint256 public lastAmountMTokenIn;

    mapping(address token => address dataFeed) public dataFeedOf;

    constructor(address tokenToRedeem_) {
        tokenToRedeem = tokenToRedeem_;
    }

    function setDataFeed(address token, address dataFeed) public {
        dataFeedOf[token] = dataFeed;
    }

    function tokensConfig(address token)
        public
        view
        returns (address dataFeed, uint256 fee, uint256 allowance, bool stable)
    {
        dataFeed = dataFeedOf[token];
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) public {
        lastTokenOut = tokenOut;
        lastAmountMTokenIn = amountMTokenIn;
        IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn);
    }
}

contract MockChainlinkAggregator {
    uint8 public immutable decimals;
    string public constant description = "Mock";
    uint256 public constant version = 1;

    uint80 internal _roundId;
    int256 internal _answer;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setLatestRoundData(uint80 roundId, int256 answer, uint256 updatedAt, uint80 answeredInRound) public {
        _roundId = roundId;
        _answer = answer;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (roundId != _roundId) {
            revert("missing round");
        }
        return (roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}

contract MockMidasDataFeed {
    uint256 public answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function getDataInBase18() public view returns (uint256) {
        return answer;
    }
}
