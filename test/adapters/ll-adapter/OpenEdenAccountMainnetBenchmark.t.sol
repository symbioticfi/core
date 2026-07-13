// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {MAX_REDEEM_QUEUE_LENGTH} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {IOpenEdenExpress} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";

import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IOpenEdenExpressBenchmark is IOpenEdenExpress {
    function OPERATOR_ROLE() external view returns (bytes32);

    function assetRegistry() external view returns (address);

    function convertRedeemRequestsDelay() external view returns (uint256);

    function getPendingRedeemQueueLength() external view returns (uint256);

    function kycManager() external view returns (address);

    function priceOracle() external view returns (address);

    function processPendingRedeems(uint256 length, uint256 totalAsset) external;

    function redeemMinimum() external view returns (uint256);
}

interface IOpenEdenKycManagerBenchmark {
    function WHITELIST_ROLE() external view returns (bytes32);

    function grantKyc(address account) external;
}

contract OpenEdenAccountMainnetBenchmarkTest is Test {
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant HYBOND = 0x1204371AC0e5176f4B8c5B2F16C2Bec551b6FC1a;
    address internal constant HYBOND_EXPRESS = 0xD84C2571E05a59108Ead1c600D16133f0710E569;
    address internal constant HYBOND_EXPRESS_IMPLEMENTATION = 0xaA15d34a8D921FBA9De5Ec72Ba11feF49BC1fb36;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint256 internal constant BENCHMARK_BLOCK = 25_524_292;

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IOpenEdenExpressBenchmark internal constant EXPRESS = IOpenEdenExpressBenchmark(HYBOND_EXPRESS);

    string internal mainnetRpcUrl;
    address internal account;
    address internal implementation;
    address internal oracle;
    address internal priceOracle;
    address internal assetRegistry;
    address internal operator;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(mainnetRpcUrl).length == 0) {
            return;
        }

        vm.createSelectFork(mainnetRpcUrl, BENCHMARK_BLOCK);
        assertEq(
            address(uint160(uint256(vm.load(HYBOND_EXPRESS, ERC1967_IMPLEMENTATION_SLOT)))),
            HYBOND_EXPRESS_IMPLEMENTATION
        );
        assertEq(EXPRESS.getRedeemQueueLength(), 0);

        _deployAccount();
        priceOracle = EXPRESS.priceOracle();
        assetRegistry = EXPRESS.assetRegistry();

        bytes32 operatorRole = EXPRESS.OPERATOR_ROLE();
        operator = IAccessControlEnumerable(HYBOND_EXPRESS).getRoleMember(operatorRole, 0);
    }

    function testBenchmarkTotalAssetsAcrossFinalQueueLengths() public {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for OpenEden mainnet fork benchmarks");
        }

        vm.pauseGasMetering();

        emit log("OpenEdenAccount.totalAssets() gas with real Express final-queue entries on a mainnet fork");
        uint256 expectedAssets;
        _benchmark(0, expectedAssets);
        expectedAssets += _addFinalRequests(1);
        _benchmark(1, expectedAssets);
        expectedAssets += _addFinalRequests(9);
        _benchmark(10, expectedAssets);
        expectedAssets += _addFinalRequests(15);
        _benchmark(25, expectedAssets);
        expectedAssets += _addFinalRequests(MAX_REDEEM_QUEUE_LENGTH - 1 - EXPRESS.getRedeemQueueLength());
        _benchmark(MAX_REDEEM_QUEUE_LENGTH - 1, expectedAssets);
        _addFinalRequests(1);
        expectedAssets = Math.mulDiv(EXPRESS.redeemInfo(account), OpenEdenOracle(oracle).getPrice(), 1e30);
        _benchmark(MAX_REDEEM_QUEUE_LENGTH, expectedAssets);
    }

    function _benchmark(uint256 queueLength, uint256 expectedAssets) internal {
        assertEq(EXPRESS.getRedeemQueueLength(), queueLength);

        vm.cool(account);
        vm.cool(oracle);
        vm.cool(HYBOND);
        vm.cool(HYBOND_EXPRESS);
        vm.cool(USDC);
        vm.cool(priceOracle);
        vm.cool(assetRegistry);

        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        uint256 assets = IAccount(account).totalAssets();
        uint256 gasUsed = gasBefore - gasleft();
        vm.pauseGasMetering();

        assertEq(assets, expectedAssets);
        emit log_named_uint("queue length", queueLength);
        emit log_named_uint("total assets", assets);
        emit log_named_uint("gas", gasUsed);
    }

    function _deployAccount() internal {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        oracle = address(new OpenEdenOracle(1, type(uint256).max, HYBOND, HYBOND_EXPRESS));
        implementation = address(
            new OpenEdenAccount(oracle, address(factory), TOKEN_COOLDOWN, HYBOND, HYBOND_EXPRESS, COW_SWAP_SETTLEMENT)
        );
        factory.whitelist(implementation);
        account =
            factory.create(1, address(this), abi.encode(address(new OpenEdenBenchmarkVault()), makeAddr("adapter")));

        IOpenEdenExpressBenchmark express = IOpenEdenExpressBenchmark(HYBOND_EXPRESS);
        address kycManager = express.kycManager();
        bytes32 whitelistRole = IOpenEdenKycManagerBenchmark(kycManager).WHITELIST_ROLE();
        address whitelistOperator = IAccessControlEnumerable(kycManager).getRoleMember(whitelistRole, 0);
        vm.prank(whitelistOperator);
        IOpenEdenKycManagerBenchmark(kycManager).grantKyc(account);
    }

    function _addFinalRequests(uint256 count) internal returns (uint256 expectedAssets) {
        uint256 tokenAmount = EXPRESS.redeemMinimum();
        uint256 finalQueueLength = EXPRESS.getRedeemQueueLength();

        for (uint256 i; i < count; ++i) {
            deal(HYBOND, account, tokenAmount);
            IAccount(account).sync();
        }

        assertEq(EXPRESS.getPendingRedeemQueueLength(), count);
        (, uint256 grossAssets, uint256 netAssets) = EXPRESS.previewRedeem(tokenAmount);
        vm.warp(block.timestamp + EXPRESS.convertRedeemRequestsDelay() + 1);

        vm.prank(operator);
        EXPRESS.processPendingRedeems(count, grossAssets * count);

        assertEq(EXPRESS.getPendingRedeemQueueLength(), 0);
        assertEq(EXPRESS.getRedeemQueueLength(), finalQueueLength + count);
        expectedAssets = netAssets * count;
    }
}

contract OpenEdenBenchmarkVault {
    address public constant asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
}
