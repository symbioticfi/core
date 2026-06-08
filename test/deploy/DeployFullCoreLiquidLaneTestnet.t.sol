// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployFullCoreLiquidLaneTestnetScript} from "../../script/deploy/testnet/DeployFullCoreLiquidLaneTestnet.s.sol";

import {ILiquidLaneAdapter} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccountRegistry} from "../../src/interfaces/adapters/ll-adapter/IAccountRegistry.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeployFullCoreLiquidLaneTestnetScriptHarness is DeployFullCoreLiquidLaneTestnetScript {
    function _broadcast() internal pure override returns (bool) {
        return false;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployFullCoreLiquidLaneTestnetTest is Test {
    function test_DeploysConfigurableLiquidLaneStackWithMocks() public {
        DeployFullCoreLiquidLaneTestnetScriptHarness script = new DeployFullCoreLiquidLaneTestnetScriptHarness();
        address owner = address(script);

        vm.mockCall(address(0xC05E7), abi.encodeWithSignature("vaultRelayer()"), abi.encode(address(0xC0A7)));

        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data = script.runBase(
            DeployFullCoreLiquidLaneTestnetScript.DeployParams({
                owner: owner,
                marketMaker: owner,
                cowSwapSettlement: address(0xC05E7),
                usdc: address(0),
                aUsd: address(0),
                mFone: address(0),
                mGlobal: address(0),
                mFoneRedemptionVault: address(0),
                mGlobalRedemptionVault: address(0),
                mintAmount: 1_000_000e18,
                liquidLaneLimit: 100_000e6,
                minDiscount: 1000
            })
        );

        assertEq(Ownable(address(data.core.vaultFactory)).owner(), owner);
        assertEq(Ownable(address(data.core.delegatorFactory)).owner(), owner);
        assertEq(Ownable(address(data.v2.adapterRegistry)).owner(), owner);

        assertGt(data.tokens.usdc.code.length, 0);
        assertGt(data.tokens.aUsd.code.length, 0);
        assertGt(data.tokens.mFone.code.length, 0);
        assertGt(data.tokens.mGlobal.code.length, 0);

        _assertVault(data.liquidLane.usdcVault, data.tokens.usdc, data.liquidLane.usdcDelegator);
        _assertVault(data.liquidLane.aUsdVault, data.tokens.aUsd, data.liquidLane.aUsdDelegator);

        _assertAdapter(
            data.liquidLane.usdcAdapter,
            data.liquidLane.usdcVault,
            data.liquidLane.usdcDelegator,
            data.accounts.accountRegistry,
            data.tokens.usdc,
            data.tokens.mFone,
            data.tokens.mGlobal,
            data.accounts.mFoneAccountFactory,
            data.accounts.mGlobalAccountFactory,
            data.liquidLaneLimit,
            data.minDiscount
        );
        _assertAdapter(
            data.liquidLane.aUsdAdapter,
            data.liquidLane.aUsdVault,
            data.liquidLane.aUsdDelegator,
            data.accounts.accountRegistry,
            data.tokens.aUsd,
            data.tokens.mFone,
            data.tokens.mGlobal,
            data.accounts.mFoneAccountFactory,
            data.accounts.mGlobalAccountFactory,
            data.liquidLaneLimit,
            data.minDiscount
        );
    }

    function _assertVault(address vault, address asset, address delegator) internal view {
        assertEq(IERC4626(vault).asset(), asset);
        assertEq(IVaultV2(vault).delegator(), delegator);
        assertEq(IUniversalDelegator(delegator).vault(), vault);
    }

    function _assertAdapter(
        address adapter,
        address vault,
        address delegator,
        address accountRegistry,
        address asset,
        address mFone,
        address mGlobal,
        address mFoneAccountFactory,
        address mGlobalAccountFactory,
        uint256 liquidLaneLimit,
        uint256 minDiscount
    ) internal view {
        assertEq(ILiquidLaneAdapter(adapter).vault(), vault);
        assertEq(IUniversalDelegator(delegator).getAdaptersLength(), 1);
        assertEq(IUniversalDelegator(delegator).adapters(0), adapter);
        assertEq(IUniversalDelegator(delegator).absoluteLimitOf(adapter), liquidLaneLimit);
        assertEq(IUniversalDelegator(delegator).shareLimitOf(adapter), MAX_SHARE);

        assertEq(IAccountRegistry(accountRegistry).accountFactories(asset, mFone), mFoneAccountFactory);
        assertEq(IAccountRegistry(accountRegistry).accountFactories(asset, mGlobal), mGlobalAccountFactory);
        assertEq(ILiquidLaneAdapter(adapter).getTokensToRedeemLength(), 2);
        assertEq(ILiquidLaneAdapter(adapter).tokensToRedeem(0), mFone);
        assertEq(ILiquidLaneAdapter(adapter).tokensToRedeem(1), mGlobal);
        assertGt(ILiquidLaneAdapter(adapter).accounts(mFone).code.length, 0);
        assertGt(ILiquidLaneAdapter(adapter).accounts(mGlobal).code.length, 0);
        assertEq(ILiquidLaneAdapter(adapter).limit(mFone), liquidLaneLimit);
        assertEq(ILiquidLaneAdapter(adapter).limit(mGlobal), liquidLaneLimit);
        assertEq(ILiquidLaneAdapter(adapter).minDiscount(mFone), minDiscount);
        assertEq(ILiquidLaneAdapter(adapter).minDiscount(mGlobal), minDiscount);
    }
}
