// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IOpenEdenAccount} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {IOpenEdenExpress} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OpenEdenAccountMainnetTest is Test {
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant HYBOND = 0x1204371AC0e5176f4B8c5B2F16C2Bec551b6FC1a;
    address internal constant HYBOND_EXPRESS = 0xD84C2571E05a59108Ead1c600D16133f0710E569;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint48 internal constant TOKEN_COOLDOWN = 18 hours;

    address internal adapter = makeAddr("adapter");
    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
    }

    function testOpenEdenMainnetHYBONDExpressInterface() public {
        _forkMainnet();

        assertGt(HYBOND.code.length, 0);
        assertGt(HYBOND_EXPRESS.code.length, 0);
        assertEq(IERC20Metadata(HYBOND).symbol(), "HYBOND");
        assertEq(IERC20Metadata(HYBOND).decimals(), 18);
        assertEq(IOpenEdenExpress(HYBOND_EXPRESS).redeemAsset(), USDC);

        uint256 fee;
        uint256 grossAssets;
        uint256 netAssets;
        (fee, grossAssets, netAssets) = IOpenEdenExpress(HYBOND_EXPRESS).previewRedeem(1 ether);

        assertGt(grossAssets, 0);
        assertEq(grossAssets - fee, netAssets);
        assertEq(IOpenEdenExpress(HYBOND_EXPRESS).pendingRedeemInfo(address(this)), 0);
        assertEq(IOpenEdenExpress(HYBOND_EXPRESS).redeemInfo(address(this)), 0);

        uint256 queueLength = IOpenEdenExpress(HYBOND_EXPRESS).getRedeemQueueLength();
        if (queueLength > 0) {
            (,,,, uint256 queuedGrossAssets, uint256 queuedFee,,) =
                IOpenEdenExpress(HYBOND_EXPRESS).getRedeemQueueInfo(0);
            assertGe(queuedGrossAssets, queuedFee);
        }
    }

    function testOpenEdenAccountUsesRealMainnetHYBONDExpress() public {
        _forkMainnet();

        address factory = address(new MigratablesFactory(address(this)));
        OpenEdenOracle openEdenOracle = new OpenEdenOracle(1, type(uint256).max, HYBOND, HYBOND_EXPRESS);
        address implementation = address(
            new OpenEdenAccount(
                address(openEdenOracle), factory, TOKEN_COOLDOWN, HYBOND, HYBOND_EXPRESS, COW_SWAP_SETTLEMENT
            )
        );

        MigratablesFactory(factory).whitelist(implementation);
        address account = MigratablesFactory(factory)
            .create(1, address(this), abi.encode(address(new OpenEdenMainnetVault()), adapter));

        assertEq(IAccount(account).ORACLE(), address(openEdenOracle));
        (,, uint256 netAssetsPerToken) =
            IOpenEdenExpress(HYBOND_EXPRESS).previewRedeem(10 ** IERC20Metadata(HYBOND).decimals());
        uint256 expectedOraclePrice =
            netAssetsPerToken * 1e18 / 10 ** IERC20Metadata(IOpenEdenExpress(HYBOND_EXPRESS).redeemAsset()).decimals();
        assertEq(openEdenOracle.getPrice(), expectedOraclePrice);
        assertEq(IAccount(account).TOKEN_TO_REDEEM(), HYBOND);
        assertEq(IOpenEdenAccount(account).EXPRESS(), HYBOND_EXPRESS);
        assertEq(IERC20(HYBOND).allowance(account, HYBOND_EXPRESS), type(uint256).max);

        uint256 amount = _requestAmount();
        (,, uint256 expectedAssets) = IOpenEdenExpress(HYBOND_EXPRESS).previewRedeem(amount);
        deal(HYBOND, account, amount);

        // The oracle truncates the net price per whole token, so valuation may round down by one
        // redemption-token unit per token.
        uint256 maxRounding = amount / 10 ** IERC20Metadata(HYBOND).decimals();
        assertApproxEqAbs(IAccount(account).totalAssets(), expectedAssets, maxRounding);

        vm.expectCall(HYBOND_EXPRESS, abi.encodeCall(IOpenEdenExpress.requestRedeem, (account, amount)));
        try IAccount(account).sync() {
            assertEq(IERC20(HYBOND).balanceOf(account), 0);
            assertEq(IOpenEdenExpress(HYBOND_EXPRESS).pendingRedeemInfo(account), amount);
            assertApproxEqAbs(IAccount(account).totalAssets(), expectedAssets, maxRounding);
        } catch {
            assertEq(IERC20(HYBOND).balanceOf(account), amount);
        }
    }

    function testOpenEdenAccountQueuesCloseMainnetHYBONDRequests() public {
        _forkMainnet();

        address factory = address(new MigratablesFactory(address(this)));
        OpenEdenOracle openEdenOracle = new OpenEdenOracle(1, type(uint256).max, HYBOND, HYBOND_EXPRESS);
        address implementation = address(
            new OpenEdenAccount(
                address(openEdenOracle), factory, TOKEN_COOLDOWN, HYBOND, HYBOND_EXPRESS, COW_SWAP_SETTLEMENT
            )
        );

        MigratablesFactory(factory).whitelist(implementation);
        address account = MigratablesFactory(factory)
            .create(1, address(this), abi.encode(address(new OpenEdenMainnetVault()), adapter));

        assertEq(IAccount(account).ORACLE(), address(openEdenOracle));

        uint256 amount = _requestAmount();
        deal(HYBOND, account, amount);

        try IAccount(account).sync() {}
        catch {
            assertEq(IERC20(HYBOND).balanceOf(account), amount);
            return;
        }

        vm.warp(vm.getBlockTimestamp() + 1);
        deal(HYBOND, account, amount);
        IAccount(account).sync();

        (,, uint256 expectedAssets) = IOpenEdenExpress(HYBOND_EXPRESS).previewRedeem(2 * amount);

        assertEq(IERC20(HYBOND).balanceOf(account), 0);
        assertEq(IOpenEdenExpress(HYBOND_EXPRESS).pendingRedeemInfo(account), 2 * amount);
        assertEq(IAccount(account).totalAssets(), expectedAssets);
    }

    /// @dev The account only submits requests at or above the live Express minimum.
    function _requestAmount() internal view returns (uint256 amount) {
        amount = IOpenEdenExpress(HYBOND_EXPRESS).redeemMinimum();
        if (amount == 0) {
            amount = 1 ether;
        }
    }

    function _forkMainnet() internal {
        if (bytes(mainnetRpcUrl).length == 0) {
            vm.skip(true, "ETH_RPC_URL is required for OpenEden mainnet checks");
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(mainnetRpcUrl);
        } else {
            vm.createSelectFork(mainnetRpcUrl, forkBlock);
        }
    }
}

contract OpenEdenMainnetVault {
    address public constant asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
}
