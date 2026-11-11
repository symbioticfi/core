// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FrontendLiquidityLens} from "../../../src/contracts/adapters/utils/FrontendLiquidityLens.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @dev Read-only replay of the two LI.FI inventories involved in VAULT-SOLVER-1B.
contract FrontendLiquidityLensBatchMainnetTest is Test {
    FrontendLiquidityLens internal constant LEGACY = FrontendLiquidityLens(0x0A7e3aDb47840779F4D85e7406c5Fb65205F0f63);
    address internal constant KPK = 0x97C0BAefCF688A8389108a0893144ae0a1408B3a;
    address internal constant OTHER = 0x59CDDE0D345c0eE6ED453FE7d3fb365Fe0721E85;

    FrontendLiquidityLens internal lens;
    bool internal hasKpk;
    bool internal hasOther;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;
        vm.createSelectFork(rpcUrl, vm.envOr("MAINNET_FORK_BLOCK", uint256(26_390_430)));
        if (address(LEGACY).code.length == 0) return;
        lens = FrontendLiquidityLens(
            address(new TransparentUpgradeableProxy(address(new FrontendLiquidityLens()), address(this), ""))
        );
        hasKpk = KPK.code.length > 0;
        hasOther = OTHER.code.length > 0;
    }

    function test_MainnetBatchKpkMatchesDeployedLens() public {
        if (!hasKpk) vm.skip(true, "archive RPC and deployed incident contracts required");
        _check(KPK);
    }

    function test_MainnetBatchOtherMatchesDeployedLens() public {
        if (!hasOther) vm.skip(true, "archive RPC and deployed incident contracts required");
        _check(OTHER);
    }

    function _check(address adapter) internal {
        uint256 length = ILiquidLaneAdapter(adapter).getTokensToRedeemLength();
        assertGt(length, 1, "fixture must exercise shared capacity reuse");
        address[] memory tokens = new address[](length);
        for (uint256 i; i < length; ++i) {
            tokens[i] = ILiquidLaneAdapter(adapter).tokensToRedeem(i);
        }
        uint256 snapshot = vm.snapshotState();
        uint256[] memory expected = new uint256[](length);
        uint256 before = gasleft();
        for (uint256 i; i < length; ++i) {
            expected[i] = LEGACY.getMaxAssets(adapter, tokens[i]);
        }
        uint256 legacyGas = before - gasleft();
        vm.revertToState(snapshot);

        before = gasleft();
        FrontendLiquidityLens.MaxAssetsResult[] memory results = lens.getMaxAssetsBatch(adapter, tokens);
        uint256 batchGas = before - gasleft();
        assertEq(results.length, length);
        for (uint256 i; i < length; ++i) {
            assertTrue(results[i].success, "batch token read failed");
            assertEq(results[i].maxAssets, expected[i], "capacity differs from deployed lens");
        }
        assertLt(batchGas, legacyGas / 2, "batch must eliminate repeated cascade execution");
        emit log_named_uint("routes", length);
        emit log_named_uint("legacy gas", legacyGas);
        emit log_named_uint("batch gas", batchGas);
    }
}
