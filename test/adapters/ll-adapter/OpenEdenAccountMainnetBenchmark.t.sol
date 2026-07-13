// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {MAX_REDEEM_QUEUE_LENGTH} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {IOpenEdenExpress} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";

contract OpenEdenAccountMainnetBenchmarkTest is Test {
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant HYBOND = 0x1204371AC0e5176f4B8c5B2F16C2Bec551b6FC1a;
    address internal constant HYBOND_EXPRESS = 0xD84C2571E05a59108Ead1c600D16133f0710E569;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint48 internal constant TOKEN_COOLDOWN = 1 days;
    uint256 internal constant TOKEN_AMOUNT = 1 ether;
    uint256 internal constant REDEEM_ASSET_AMOUNT = 1_200_000;
    uint256 internal constant FEE_ASSET_AMOUNT = 1000;

    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testBenchmarkTotalAssetsAcrossFinalQueueLengths() public {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for OpenEden mainnet fork benchmarks");
        }

        vm.pauseGasMetering();
        _createFork();

        MigratablesFactory factory = new MigratablesFactory(address(this));
        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, HYBOND, HYBOND_EXPRESS);
        OpenEdenAccount implementation = new OpenEdenAccount(
            address(oracle), address(factory), TOKEN_COOLDOWN, HYBOND, HYBOND_EXPRESS, COW_SWAP_SETTLEMENT
        );
        factory.whitelist(address(implementation));
        address account =
            factory.create(1, address(this), abi.encode(address(new OpenEdenBenchmarkVault()), makeAddr("adapter")));

        emit log("OpenEdenAccount.totalAssets() gas on a mainnet fork");
        _benchmark(account, address(implementation), address(oracle), 0, false);
        _benchmark(account, address(implementation), address(oracle), 1, true);
        _benchmark(account, address(implementation), address(oracle), 10, true);
        _benchmark(account, address(implementation), address(oracle), 25, true);
        _benchmark(account, address(implementation), address(oracle), MAX_REDEEM_QUEUE_LENGTH - 1, true);
        _benchmark(account, address(implementation), address(oracle), MAX_REDEEM_QUEUE_LENGTH, true);
    }

    function _benchmark(address account, address implementation, address oracle, uint256 queueLength, bool hasRedeem)
        internal
    {
        vm.clearMockedCalls();
        vm.mockCall(
            HYBOND_EXPRESS, abi.encodeCall(IOpenEdenExpress.pendingRedeemInfo, (account)), abi.encode(uint256(0))
        );
        vm.mockCall(
            HYBOND_EXPRESS,
            abi.encodeCall(IOpenEdenExpress.redeemInfo, (account)),
            abi.encode(hasRedeem ? TOKEN_AMOUNT : 0)
        );

        if (hasRedeem) {
            vm.mockCall(
                HYBOND_EXPRESS, abi.encodeCall(IOpenEdenExpress.getRedeemQueueLength, ()), abi.encode(queueLength)
            );
            if (queueLength < MAX_REDEEM_QUEUE_LENGTH) {
                for (uint256 i; i < queueLength; ++i) {
                    address receiver = i + 1 == queueLength ? account : address(uint160(0x1000 + i));
                    vm.mockCall(
                        HYBOND_EXPRESS,
                        abi.encodeCall(IOpenEdenExpress.getRedeemQueueInfo, (i)),
                        abi.encode(
                            receiver,
                            receiver,
                            TOKEN_AMOUNT,
                            uint256(0),
                            REDEEM_ASSET_AMOUNT,
                            FEE_ASSET_AMOUNT,
                            block.timestamp,
                            bytes32(i)
                        )
                    );
                }
            }
        }

        vm.cool(account);
        vm.cool(implementation);
        vm.cool(oracle);
        vm.cool(HYBOND);
        vm.cool(HYBOND_EXPRESS);
        vm.cool(USDC);

        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        uint256 assets = IAccount(account).totalAssets();
        uint256 gasUsed = gasBefore - gasleft();
        vm.pauseGasMetering();

        assertEq(assets, hasRedeem ? _expectedAssets(oracle, queueLength) : 0);
        emit log_named_uint("queue length", queueLength);
        emit log_named_uint("gas", gasUsed);
    }

    function _expectedAssets(address oracle, uint256 queueLength) internal view returns (uint256) {
        if (queueLength < MAX_REDEEM_QUEUE_LENGTH) {
            return REDEEM_ASSET_AMOUNT - FEE_ASSET_AMOUNT;
        }
        return OpenEdenOracle(oracle).getPrice() / 1e12;
    }

    function _createFork() internal {
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }
}

contract OpenEdenBenchmarkVault {
    address public constant asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
}
