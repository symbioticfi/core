// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployFullAdapterOverlayTestnetScript} from "../../script/deploy/testnet/DeployFullAdapterOverlayTestnet.s.sol";
import {DeployFullCoreLiquidLaneTestnetScript} from "../../script/deploy/testnet/DeployFullCoreLiquidLaneTestnet.s.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {IAdapterRegistry} from "../../src/interfaces/IAdapterRegistry.sol";
import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {
    MockAaveAToken,
    MockAavePool,
    MockAavePoolDataProvider,
    MockMorphoAdapterRegistry,
    MockMorphoVaultFactory
} from "../mocks/HoodiScenarioProtocolMocks.sol";
import {Token} from "../mocks/Token.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeployFullCoreLiquidLaneOverlayBaseHarness is DeployFullCoreLiquidLaneTestnetScript {
    address internal immutable ACTOR;

    constructor(address actor) {
        ACTOR = actor;
    }

    function _broadcast() internal view override returns (bool) {
        return false;
    }

    function _scriptOwner() internal view override returns (address) {
        return ACTOR;
    }
}

contract DeployFullAdapterOverlayTestnetHarness is DeployFullAdapterOverlayTestnetScript {
    address internal immutable ACTOR;

    constructor(address actor) {
        ACTOR = actor;
    }

    function _broadcast() internal view override returns (bool) {
        return false;
    }

    function _scriptOwner() internal view override returns (address) {
        return ACTOR;
    }
}

contract DeployFullAdapterOverlayTestnetTest is Test {
    function test_DeploysOverlayAdaptersOnExistingLiquidLaneDeployment() public {
        address owner = address(this);
        DeployFullCoreLiquidLaneOverlayBaseHarness base = new DeployFullCoreLiquidLaneOverlayBaseHarness(owner);
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory baseData = base.runBase(
            DeployFullCoreLiquidLaneTestnetScript.DeployParams({
                owner: owner,
                marketMaker: owner,
                cowSwapSettlement: address(0),
                cowSwapVaultRelayer: address(0),
                usdc: address(0),
                aUsd: address(0),
                mFone: address(0),
                mGlobal: address(0),
                mFoneRedemptionVault: address(0),
                mGlobalRedemptionVault: address(0),
                merklDistributor: address(0),
                mintAmount: 0,
                liquidLaneLimit: type(uint128).max,
                minDiscount: 0
            })
        );
        uint256 initialUsdcAdapters = IUniversalDelegator(baseData.liquidLane.usdcDelegator).getAdaptersLength();
        uint256 initialAUsdAdapters = IUniversalDelegator(baseData.liquidLane.aUsdDelegator).getAdaptersLength();

        DeployFullAdapterOverlayTestnetHarness overlay = new DeployFullAdapterOverlayTestnetHarness(owner);
        DeployFullAdapterOverlayTestnetScript.OverlayDeployments memory deployed = overlay.runBase(
            DeployFullAdapterOverlayTestnetScript.DeployParams({
                owner: owner,
                marketMaker: owner,
                vaultFactory: address(baseData.core.vaultFactory),
                adapterRegistry: address(baseData.v2.adapterRegistry),
                networkMiddlewareService: address(baseData.core.networkMiddlewareService),
                cowSwapSettlement: address(0),
                cowSwapVaultRelayer: address(0),
                merklDistributor: address(0),
                usdc: baseData.tokens.usdc,
                aUsd: baseData.tokens.aUsd,
                usdcVault: baseData.liquidLane.usdcVault,
                usdcDelegator: baseData.liquidLane.usdcDelegator,
                aUsdVault: baseData.liquidLane.aUsdVault,
                aUsdDelegator: baseData.liquidLane.aUsdDelegator,
                adapterLimit: type(uint128).max
            })
        );

        _assertOverlay(deployed, baseData, owner, initialUsdcAdapters, initialAUsdAdapters);
        _assertMockProtocolsAreOwnerConfigurable(deployed, owner);
    }

    function _assertOverlay(
        DeployFullAdapterOverlayTestnetScript.OverlayDeployments memory deployed,
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory baseData,
        address owner,
        uint256 initialUsdcAdapters,
        uint256 initialAUsdAdapters
    ) internal view {
        assertEq(Ownable(deployed.appAdapterFactory).owner(), owner);
        assertEq(Ownable(deployed.aaveAdapterFactory).owner(), owner);
        assertEq(Ownable(deployed.morphoAdapterFactory).owner(), owner);
        assertEq(AdapterFactory(deployed.appAdapterFactory).implementation(1), deployed.appAdapterImplementation);
        assertEq(AdapterFactory(deployed.aaveAdapterFactory).implementation(1), deployed.aaveAdapterImplementation);
        assertEq(AdapterFactory(deployed.morphoAdapterFactory).implementation(1), deployed.morphoAdapterImplementation);
        assertGt(deployed.merklDistributor.code.length, 0);

        assertEq(IAppAdapter(deployed.usdcAppAdapter).asset(), baseData.tokens.usdc);
        assertEq(IAppAdapter(deployed.usdcAppAdapter).burner(), deployed.usdcBurner);
        assertEq(IAppAdapter(deployed.aUsdAppAdapter).asset(), baseData.tokens.aUsd);
        assertEq(IAppAdapter(deployed.aUsdAppAdapter).burner(), deployed.aUsdBurner);

        assertEq(
            MockAavePool(deployed.mockAavePool).getReserveAToken(baseData.tokens.usdc), deployed.mockAaveUsdcAToken
        );
        assertEq(
            MockAavePool(deployed.mockAavePool).getReserveAToken(baseData.tokens.aUsd), deployed.mockAaveAusdAToken
        );
        assertEq(IAaveV3Adapter(deployed.usdcAaveAdapter).aToken(), deployed.mockAaveUsdcAToken);
        assertEq(IAaveV3Adapter(deployed.aUsdAaveAdapter).aToken(), deployed.mockAaveAusdAToken);
        assertEq(IMerklClaimer(deployed.usdcAaveAdapter).MERKL_DISTRIBUTOR(), deployed.merklDistributor);
        assertEq(IMerklClaimer(deployed.aUsdAaveAdapter).MERKL_DISTRIBUTOR(), deployed.merklDistributor);

        assertTrue(MockMorphoVaultFactory(deployed.mockMorphoVaultFactory).isVaultV2(deployed.mockMorphoVaultUsdc));
        assertTrue(MockMorphoVaultFactory(deployed.mockMorphoVaultFactory).isVaultV2(deployed.mockMorphoVaultAusd));
        _assertMorphoRegistryContains(deployed.mockMorphoAdapterRegistry, deployed.mockMorphoVaultUsdc);
        _assertMorphoRegistryContains(deployed.mockMorphoAdapterRegistry, deployed.mockMorphoVaultAusd);
        assertEq(IMorphoVaultV2Adapter(deployed.usdcMorphoAdapter).morphoVault(), deployed.mockMorphoVaultUsdc);
        assertEq(IMorphoVaultV2Adapter(deployed.aUsdMorphoAdapter).morphoVault(), deployed.mockMorphoVaultAusd);
        assertEq(IMerklClaimer(deployed.usdcMorphoAdapter).MERKL_DISTRIBUTOR(), deployed.merklDistributor);
        assertEq(IMerklClaimer(deployed.aUsdMorphoAdapter).MERKL_DISTRIBUTOR(), deployed.merklDistributor);

        _assertDelegatorOverlay(
            address(baseData.v2.adapterRegistry),
            baseData.liquidLane.usdcVault,
            baseData.liquidLane.usdcDelegator,
            deployed.usdcAppAdapter,
            deployed.usdcAaveAdapter,
            deployed.usdcMorphoAdapter,
            initialUsdcAdapters
        );
        _assertDelegatorOverlay(
            address(baseData.v2.adapterRegistry),
            baseData.liquidLane.aUsdVault,
            baseData.liquidLane.aUsdDelegator,
            deployed.aUsdAppAdapter,
            deployed.aUsdAaveAdapter,
            deployed.aUsdMorphoAdapter,
            initialAUsdAdapters
        );
    }

    function _assertDelegatorOverlay(
        address adapterRegistry,
        address vault,
        address delegator,
        address appAdapter,
        address aaveAdapter,
        address morphoAdapter,
        uint256 initialAdapters
    ) internal view {
        assertEq(IUniversalDelegator(delegator).getAdaptersLength(), initialAdapters + 3);
        assertEq(IUniversalDelegator(delegator).adapters(initialAdapters), appAdapter);
        assertEq(IUniversalDelegator(delegator).adapters(initialAdapters + 1), aaveAdapter);
        assertEq(IUniversalDelegator(delegator).adapters(initialAdapters + 2), morphoAdapter);
        assertTrue(IAdapterRegistry(adapterRegistry).isWhitelisted(vault, appAdapter));
        assertTrue(IAdapterRegistry(adapterRegistry).isWhitelisted(vault, aaveAdapter));
        assertTrue(IAdapterRegistry(adapterRegistry).isWhitelisted(vault, morphoAdapter));
        _assertLimits(delegator, appAdapter);
        _assertLimits(delegator, aaveAdapter);
        _assertLimits(delegator, morphoAdapter);
    }

    function _assertLimits(address delegator, address adapter) internal view {
        assertEq(IUniversalDelegator(delegator).absoluteLimitOf(adapter), type(uint128).max);
        assertEq(IUniversalDelegator(delegator).shareLimitOf(adapter), MAX_SHARE);
    }

    function _assertMorphoRegistryContains(address registry, address account) internal view {
        (bool success, bytes memory data) =
            registry.staticcall(abi.encodeCall(MockMorphoAdapterRegistry.isInRegistry, (account)));
        assertTrue(success);
        assertTrue(abi.decode(data, (bool)));
    }

    function _assertMockProtocolsAreOwnerConfigurable(
        DeployFullAdapterOverlayTestnetScript.OverlayDeployments memory deployed,
        address owner
    ) internal {
        address nonOwner = makeAddr("overlayMockProtocolNonOwner");
        Token extraAaveAsset = new Token("Extra Overlay Aave Asset");
        MockAaveAToken extraAToken = new MockAaveAToken(address(extraAaveAsset), owner);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        MockAavePool(deployed.mockAavePool).setReserveToken(address(extraAaveAsset), address(extraAToken));

        vm.startPrank(owner);
        MockAavePool(deployed.mockAavePool).setReserveToken(address(extraAaveAsset), address(extraAToken));
        extraAToken.setPool(deployed.mockAavePool);
        MockAavePoolDataProvider(deployed.mockAaveDataProvider)
            .setReserveToken(address(extraAaveAsset), address(extraAToken));
        vm.stopPrank();

        assertEq(MockAavePool(deployed.mockAavePool).getReserveAToken(address(extraAaveAsset)), address(extraAToken));
        (address configuredAToken,,) =
            MockAavePoolDataProvider(deployed.mockAaveDataProvider).getReserveTokensAddresses(address(extraAaveAsset));
        assertEq(configuredAToken, address(extraAToken));

        Token extraMorphoAsset = new Token("Extra Overlay Morpho Asset");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        MockMorphoAdapterRegistry(deployed.mockMorphoAdapterRegistry).setInRegistry(address(0xBEEF), true);

        vm.prank(owner);
        (bool success, bytes memory returnData) = deployed.mockMorphoVaultFactory
            .call(abi.encodeCall(MockMorphoVaultFactory.createVault, (address(extraMorphoAsset))));
        assertTrue(success);
        (, address extraMorphoVault) = abi.decode(returnData, (address, address));

        vm.prank(owner);
        MockMorphoAdapterRegistry(deployed.mockMorphoAdapterRegistry).setInRegistry(extraMorphoVault, true);

        assertTrue(MockMorphoVaultFactory(deployed.mockMorphoVaultFactory).isVaultV2(extraMorphoVault));
        _assertMorphoRegistryContains(deployed.mockMorphoAdapterRegistry, extraMorphoVault);
    }
}
