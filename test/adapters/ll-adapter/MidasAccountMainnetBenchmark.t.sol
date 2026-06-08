// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MidasCompAccount, MidasNonCompAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IMidasRedemptionVault} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MidasAccountMainnetBenchmarkTest is Test {
    address internal constant MAINNET_MTBILL = 0xDD629E5241CbC5919847783e6C96B2De4754e438;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_STANDARD_REDEMPTION_VAULT = 0xF6e51d24F4793Ac5e71e0502213a9BBE3A6d4517;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    uint256 internal constant FINALIZED_MAINNET_REQUEST_IDS = 20;
    uint256 internal constant REQUEST_AMOUNT = 1e18;

    uint256[] internal requestCounts;
    uint256[] internal largeRequestCounts;
    string internal mainnetRpcUrl;
    MainnetAssetVault internal vault;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        requestCounts.push(1);
        requestCounts.push(5);
        requestCounts.push(10);
        requestCounts.push(20);

        largeRequestCounts.push(100);
        largeRequestCounts.push(500);
        largeRequestCounts.push(1000);

        if (bytes(mainnetRpcUrl).length == 0) {
            return;
        }

        vm.createSelectFork(mainnetRpcUrl);
        vault = new MainnetAssetVault(MAINNET_USDC);
    }

    function testBenchmarkTotalAssetsForPendingMainnetMidasRequests() public {
        _skipWithoutMainnetRpc();

        emit log("MidasAccount.totalAssets() gas for pending mainnet mTBILL Standard Redemption requests");
        for (uint256 i; i < requestCounts.length; ++i) {
            uint256 n = requestCounts[i];
            MidasNonCompAccountBenchHarness nonCompAccount = _deployNonCompAccount();
            _createPendingRedeemRequests(nonCompAccount, n);
            _logTotalAssetsGas("non-comp", n, address(nonCompAccount));

            MidasCompAccountBenchHarness compAccount = _deployCompAccount();
            _createPendingRedeemRequests(compAccount, n);
            _logTotalAssetsGas("comp", n, address(compAccount));
        }
    }

    function testBenchmarkFinalizeRedeemForHistoricalMainnetMidasRequests() public {
        _skipWithoutMainnetRpc();

        emit log("MidasAccount.sync() gas for historical finalized mainnet mTBILL Standard Redemption requests");
        for (uint256 i; i < requestCounts.length; ++i) {
            _benchmarkFinalizeRedeem(requestCounts[i]);
        }
        for (uint256 i; i < largeRequestCounts.length; ++i) {
            _benchmarkFinalizeRedeem(largeRequestCounts[i]);
        }
    }

    function testBenchmarkTotalAssetsForSeededPendingMainnetMidasRequests() public {
        _skipWithoutMainnetRpc();

        emit log("MidasAccount.totalAssets() gas for seeded pending mainnet mTBILL Standard Redemption requests");
        for (uint256 i; i < largeRequestCounts.length; ++i) {
            uint256 n = largeRequestCounts[i];
            MidasNonCompAccountBenchHarness nonCompAccount = _deployNonCompAccount();
            uint256 pendingRequestId = _createOnePendingRequestAndClear(nonCompAccount);
            for (uint256 requestId; requestId < n; ++requestId) {
                nonCompAccount.pushRequestId(pendingRequestId);
            }
            _logTotalAssetsGas("non-comp seeded-pending", n, address(nonCompAccount));

            MidasCompAccountBenchHarness compAccount = _deployCompAccount();
            pendingRequestId = _createOnePendingRequestAndClear(compAccount);
            for (uint256 requestId; requestId < n; ++requestId) {
                compAccount.pushRequestId(pendingRequestId);
            }
            _logTotalAssetsGas("comp seeded-pending", n, address(compAccount));
        }
    }

    function _createPendingRedeemRequests(MidasNonCompAccountBenchHarness account, uint256 count) internal {
        for (uint256 i; i < count; ++i) {
            deal(MAINNET_MTBILL, address(account), REQUEST_AMOUNT);
            account.sync();
        }

        assertEq(account.requestIdsLength(), count);
        assertEq(IERC20(MAINNET_MTBILL).balanceOf(address(account)), 0);
    }

    function _createPendingRedeemRequests(MidasCompAccountBenchHarness account, uint256 count) internal {
        for (uint256 i; i < count; ++i) {
            deal(MAINNET_MTBILL, address(account), REQUEST_AMOUNT);
            account.sync();
        }

        assertEq(account.requestIdsLength(), count);
        assertEq(IERC20(MAINNET_MTBILL).balanceOf(address(account)), 0);
    }

    function _createOnePendingRequestAndClear(MidasNonCompAccountBenchHarness account)
        internal
        returns (uint256 pendingRequestId)
    {
        _createPendingRedeemRequests(account, 1);
        pendingRequestId = account.requestIdAt(0);
        account.clearRequestIds();
    }

    function _createOnePendingRequestAndClear(MidasCompAccountBenchHarness account)
        internal
        returns (uint256 pendingRequestId)
    {
        _createPendingRedeemRequests(account, 1);
        pendingRequestId = account.requestIdAt(0);
        account.clearRequestIds();
    }

    function _logTotalAssetsGas(string memory mode, uint256 count, address account) internal {
        uint256 gasBefore = gasleft();
        uint256 assets = IAccount(account).totalAssets();
        uint256 gasUsed = gasBefore - gasleft();

        assertGt(assets, 0);
        _logGas("totalAssets", mode, count, gasUsed);
    }

    function _deployNonCompAccount() internal returns (MidasNonCompAccountBenchHarness account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MidasOracle oracle =
            new MidasOracle(address(IMidasRedemptionVault(MAINNET_STANDARD_REDEMPTION_VAULT).mTokenDataFeed()));
        MidasNonCompAccountBenchHarness implementation = new MidasNonCompAccountBenchHarness(
            address(oracle),
            address(factory),
            0,
            MAINNET_MTBILL,
            MAINNET_USDC,
            MAINNET_STANDARD_REDEMPTION_VAULT,
            COW_SWAP_SETTLEMENT
        );
        factory.whitelist(address(implementation));
        account = MidasNonCompAccountBenchHarness(factory.create(1, address(this), _initData(MAINNET_MTBILL)));
    }

    function _deployCompAccount() internal returns (MidasCompAccountBenchHarness account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MidasOracle oracle =
            new MidasOracle(address(IMidasRedemptionVault(MAINNET_STANDARD_REDEMPTION_VAULT).mTokenDataFeed()));
        MidasCompAccountBenchHarness implementation = new MidasCompAccountBenchHarness(
            address(oracle),
            address(factory),
            0,
            MAINNET_MTBILL,
            MAINNET_USDC,
            MAINNET_STANDARD_REDEMPTION_VAULT,
            COW_SWAP_SETTLEMENT
        );
        factory.whitelist(address(implementation));
        account = MidasCompAccountBenchHarness(factory.create(1, address(this), _initData(MAINNET_MTBILL)));
    }

    function _initData(address) internal returns (bytes memory) {
        return abi.encode(address(vault), makeAddr("adapter"));
    }

    function _benchmarkFinalizeRedeem(uint256 count) internal {
        MidasNonCompAccountBenchHarness account = _deployNonCompAccount();
        for (uint256 requestId; requestId < count; ++requestId) {
            account.pushRequestId(requestId % FINALIZED_MAINNET_REQUEST_IDS);
        }

        uint256 gasBefore = gasleft();
        account.sync();
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(account.requestIdsLength(), 0);
        _logGas("sync", "finalized", count, gasUsed);
    }

    function _logGas(string memory fn, string memory mode, uint256 count, uint256 gasUsed) internal {
        emit log_named_string("function", fn);
        emit log_named_string("mode", mode);
        emit log_named_uint("requests", count);
        emit log_named_uint("gas", gasUsed);
    }

    function _skipWithoutMainnetRpc() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for mainnet fork benchmarks");
        }
    }
}

contract MidasNonCompAccountBenchHarness is MidasNonCompAccount {
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    )
        MidasNonCompAccount(
            oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement
        )
    {}

    function pushRequestId(uint256 requestId) external {
        requestIds.push(uint64(requestId));
    }

    function requestIdAt(uint256 index) external view returns (uint256) {
        return requestIds[index];
    }

    function requestIdsLength() external view returns (uint256) {
        return requestIds.length;
    }

    function clearRequestIds() external {
        delete requestIds;
    }
}

contract MidasCompAccountBenchHarness is MidasCompAccount {
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasCompAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    function requestIdsLength() external view returns (uint256) {
        return requestIds.length;
    }

    function pushRequestId(uint256 requestId) external {
        requestIds.push(uint64(requestId));
    }

    function requestIdAt(uint256 index) external view returns (uint256) {
        return requestIds[index];
    }

    function clearRequestIds() external {
        delete requestIds;
    }
}

contract MainnetAssetVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}
