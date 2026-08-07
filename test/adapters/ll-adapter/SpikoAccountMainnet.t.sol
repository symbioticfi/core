// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SPKCC_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/SPKCC_Account.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";

import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {ISpikoAccount} from "../../../src/interfaces/adapters/ll-adapter/spiko/ISpikoAccount.sol";
import {ISpikoRedemption} from "../../../src/interfaces/adapters/ll-adapter/spiko/ISpikoRedemption.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Test} from "forge-std/Test.sol";

contract SpikoAccountMainnetTest is Test {
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant SPKCC = 0x4f33aCf823E6eEb697180d553cE0c710124C8D59;
    address internal constant SPKCC_NAV_FEED = 0x9e37DBF40fE5Fe9320E45fe6B95b000aa05459A9;
    address internal constant SPIKO_REDEMPTION = 0xDA5599f04e9b437C8394b0c2BC68B502A66ebFe8;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testSPKCCMainnetTopology() public {
        _selectMainnetFork();

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = new SPKCC_Account(address(factory), COW_SWAP_SETTLEMENT);
        ISpikoAccount spikoAccount = ISpikoAccount(address(implementation));
        ChainlinkOracle oracle = ChainlinkOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), SPKCC);
        assertEq(spikoAccount.REDEMPTION(), SPIKO_REDEMPTION);
        assertEq(spikoAccount.SETTLEMENT_TOKEN(), USDC);
        assertEq(spikoAccount.SETTLEMENT_DURATION(), 30 days);
        assertEq(IERC20Metadata(SPKCC).symbol(), "SPKCC");
        assertEq(IERC20Metadata(SPKCC).decimals(), 5);

        assertEq(oracle.AGGREGATOR_0(), SPKCC_NAV_FEED);
        assertEq(oracle.AGGREGATOR_1(), address(0));
        assertEq(oracle.STALENESS_DURATION_0(), 30 hours);
        assertEq(oracle.STALENESS_DURATION_1(), 0);
        assertEq(oracle.MIN_PRICE(), 0.5e18);
        assertEq(oracle.MAX_PRICE(), 2e18);
        assertEq(ISpikoNavFeed(SPKCC_NAV_FEED).getDataFeedId(), bytes32("SPKCC_NAV"));
        assertGt(oracle.getPrice(), 0);
    }

    function testSPKCCMainnetFiatOnlyRouteLeavesTokensHeld() public {
        _selectMainnetFork();

        MigratablesFactory factory = new MigratablesFactory(address(this));
        IAccount implementation = new SPKCC_Account(address(factory), COW_SWAP_SETTLEMENT);
        factory.whitelist(address(implementation));
        ISpikoAccount account = ISpikoAccount(
            factory.create(1, address(this), abi.encode(address(new SpikoMainnetVault(USDC)), address(this)))
        );
        uint256 amount = 100e5;
        uint256 redemptionBalanceBefore = IERC20(SPKCC).balanceOf(SPIKO_REDEMPTION);
        deal(SPKCC, address(account), amount);

        address[] memory outputs = ISpikoRedemption(SPIKO_REDEMPTION).outputsFor(IERC20(SPKCC));
        assertFalse(_contains(outputs, USDC), "SPKCC is ready for USDC review");

        account.sync();

        assertEq(IERC20(SPKCC).balanceOf(address(account)), amount);
        assertEq(IERC20(SPKCC).balanceOf(SPIKO_REDEMPTION), redemptionBalanceBefore);
        assertEq(account.pendingId(), bytes32(0));
        assertEq(account.requestNonce(), 0);
        assertGt(account.totalAssets(), 0);
    }

    function _selectMainnetFork() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for SPKCC mainnet checks");
        }
        vm.createSelectFork(mainnetRpcUrl);
    }

    function _contains(address[] memory values, address value) internal pure returns (bool) {
        uint256 length = values.length;
        for (uint256 i; i < length; ++i) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }
}

interface ISpikoNavFeed {
    function getDataFeedId() external view returns (bytes32);
}

contract SpikoMainnetVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}
