// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../../src/interfaces/vault/IWithdrawalQueue.sol";
import {IRegistry} from "../../../src/interfaces/common/IRegistry.sol";
import {INetworkMiddlewareService} from "../../../src/interfaces/service/INetworkMiddlewareService.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMintableToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface INetworkRegistryExercise is IRegistry {
    function registerNetwork() external;
}

interface IOperatorRegistryExercise is IRegistry {
    function registerOperator() external;
}

interface IMockAavePoolExercise {
    function accrueYield(address asset, address account, uint256 amount) external;
}

interface IMockMorphoVaultExercise {
    function donateYield(uint256 amount) external;
}

contract ExerciseFullCoreLiquidLaneTestnetScript is Script {
    address internal constant ACTOR = 0xc056736be7C05790667CDb678c03eb09F616E157;

    struct Deployment {
        address networkRegistry;
        address operatorRegistry;
        address networkMiddlewareService;
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
        address aavePool;
        Market usdcMarket;
        Market aUsdMarket;
    }

    struct Market {
        address asset;
        address vault;
        address delegator;
        address liquidLaneAdapter;
        address appAdapter;
        address aaveAdapter;
        address morphoAdapter;
        address morphoVault;
        address restakingVault;
        address restakingDelegator;
        address restakingAppAdapter;
    }

    function run() external virtual {
        Deployment memory deployed = _deployment();

        vm.startBroadcast();
        _registerNetworkAndMiddleware(deployed);
        _mintAndApprove(deployed);
        _exerciseBaseMarket("USDC", deployed, deployed.usdcMarket);
        _exerciseBaseMarket("aUSD", deployed, deployed.aUsdMarket);
        _exerciseRestakingMarket("USDC restaking", deployed.usdcMarket);
        _exerciseRestakingMarket("aUSD restaking", deployed.aUsdMarket);
        _createDelayedDebt("USDC", deployed.usdcMarket);
        _createDelayedDebt("aUSD", deployed.aUsdMarket);
        vm.stopBroadcast();
    }

    function _exerciseBaseMarket(string memory label, Deployment memory deployed, Market memory market) internal {
        console2.log("exercise base", label, market.vault);

        uint256 depositA = _units(market.asset, 10_000);
        uint256 depositB = _units(market.asset, 2500);
        IERC4626(market.vault).deposit(depositA, ACTOR);
        IERC4626(market.vault).deposit(depositB, ACTOR);

        address[] memory autoAdapters = new address[](3);
        autoAdapters[0] = market.aaveAdapter;
        autoAdapters[1] = market.morphoAdapter;
        autoAdapters[2] = market.appAdapter;
        IUniversalDelegator(market.delegator).setAutoAllocateAdapters(autoAdapters);
        IUniversalDelegator(market.delegator).setLimits(market.aaveAdapter, type(uint128).max, MAX_SHARE / 3);
        IUniversalDelegator(market.delegator).setLimits(market.morphoAdapter, type(uint128).max, MAX_SHARE / 3);
        IUniversalDelegator(market.delegator).setLimits(market.appAdapter, type(uint128).max, MAX_SHARE / 3);

        IUniversalDelegator(market.delegator).allocate(market.aaveAdapter, _units(market.asset, 2000));
        IUniversalDelegator(market.delegator).allocate(market.morphoAdapter, _units(market.asset, 1500));
        IUniversalDelegator(market.delegator).allocate(market.appAdapter, _units(market.asset, 1000));
        IUniversalDelegator(market.delegator).allocateAll(_units(market.asset, 500));

        _pushAaveYield(deployed.aavePool, market);
        _pushMorphoYield(market);
        IVaultV2(market.vault).accrueInterest();

        IUniversalDelegator(market.delegator).swapAdapters(market.aaveAdapter, market.morphoAdapter);
        IUniversalDelegator(market.delegator).deallocate(market.aaveAdapter, _units(market.asset, 250));
        IUniversalDelegator(market.delegator).deallocate(market.morphoAdapter, _units(market.asset, 175));
        IUniversalDelegator(market.delegator).allocateExact(market.morphoAdapter, _units(market.asset, 300));
        IUniversalDelegator(market.delegator).deallocateAll(_units(market.asset, 200));
        IUniversalDelegator(market.delegator).deallocateExact(_units(market.asset, 150));

        _exerciseLiquidLane(market, deployed.mFone, deployed.mGlobal);
        _exerciseWithdrawals(market.vault);
        _exerciseWithdrawalQueue(market.vault);

        IAppAdapter(market.appAdapter).reward(market.asset, _units(market.asset, 30));
        IAppAdapter(market.appAdapter).release(_units(market.asset, 5));
        IAppAdapter(market.appAdapter).slash(_units(market.asset, 7));

        _logMarket(label, market);
    }

    function _exerciseRestakingMarket(string memory label, Market memory market) internal {
        console2.log("exercise restaking", label, market.restakingVault);

        uint256 childShares = IERC20(market.vault).balanceOf(ACTOR);
        uint256 depositShares = childShares / 5;
        if (depositShares == 0) {
            console2.log("skip restaking, no child vault shares");
            return;
        }

        IERC20(market.vault).approve(market.restakingVault, type(uint256).max);
        IERC4626(market.restakingVault).deposit(depositShares, ACTOR);

        address[] memory autoAdapters = new address[](1);
        autoAdapters[0] = market.restakingAppAdapter;
        IUniversalDelegator(market.restakingDelegator).setAutoAllocateAdapters(autoAdapters);
        IUniversalDelegator(market.restakingDelegator)
            .setLimits(market.restakingAppAdapter, type(uint128).max, MAX_SHARE);
        IUniversalDelegator(market.restakingDelegator).allocate(market.restakingAppAdapter, depositShares / 2);

        IAppAdapter(market.restakingAppAdapter).reward(market.asset, _units(market.asset, 15));
        IUniversalDelegator(market.restakingDelegator).deallocate(market.restakingAppAdapter, depositShares / 20);
        IUniversalDelegator(market.restakingDelegator).deallocateAll(depositShares / 25);

        _exerciseRestakingTail(market, depositShares);

        _logRestaking(label, market);
    }

    function _exerciseRestakingTail(Market memory market, uint256 depositShares) internal {
        IUniversalDelegator(market.restakingDelegator).allocateAll(depositShares / 30);

        _exerciseWithdrawals(market.restakingVault);
        _exerciseWithdrawalQueue(market.restakingVault);

        uint256 releaseAmount = _min(_units(market.asset, 2), IAppAdapter(market.restakingAppAdapter).slashable());
        if (releaseAmount > 0) {
            IAppAdapter(market.restakingAppAdapter).release(releaseAmount);
        }

        uint256 slashAmount = _min(_units(market.asset, 3), IAppAdapter(market.restakingAppAdapter).slashable());
        if (slashAmount > 0) {
            IAppAdapter(market.restakingAppAdapter).slash(slashAmount);
        }
    }

    function _exerciseLiquidLane(Market memory market, address mFone, address mGlobal) internal {
        ILiquidLaneAdapter adapter = ILiquidLaneAdapter(market.liquidLaneAdapter);
        adapter.setReceiver(ACTOR);

        uint256 acquireAmount = _units(market.asset, 8);
        IERC20(market.asset).approve(market.liquidLaneAdapter, type(uint256).max);
        adapter.depositToAcquire(mFone, acquireAmount);
        adapter.withdrawToAcquire(mFone, _units(market.asset, 1));

        uint256 mFoneIn = _units(mFone, 10);
        IMintableToken(mFone).mint(market.liquidLaneAdapter, mFoneIn);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: ACTOR, tokenIn: mFone, amountIn: mFoneIn, amountOut: _units(market.asset, 10)
            })
        );

        uint256 mGlobalIn = _units(mGlobal, 12);
        IMintableToken(mGlobal).mint(market.liquidLaneAdapter, mGlobalIn);
        adapter.swap(
            ILiquidLaneAdapter.Swap({
                recipient: ACTOR, tokenIn: mGlobal, amountIn: mGlobalIn, amountOut: _units(market.asset, 6)
            })
        );

        IUniversalDelegator(market.delegator).deallocate(market.liquidLaneAdapter, _units(market.asset, 5));
    }

    function _exerciseWithdrawals(address vault) internal {
        if (IUniversalDelegator(IVaultV2(vault).delegator()).sweepPending() > 0) {
            return;
        }

        uint256 assets = _min(IERC4626(vault).maxWithdraw(ACTOR), IVaultV2(vault).freeAssets());
        if (assets > 0) {
            IERC4626(vault).withdraw(assets / 100, ACTOR, ACTOR);
        }

        if (IUniversalDelegator(IVaultV2(vault).delegator()).sweepPending() > 0) {
            return;
        }

        uint256 shares = IERC20(vault).balanceOf(ACTOR);
        uint256 redeemableShares = IERC4626(vault).previewDeposit(IVaultV2(vault).freeAssets());
        shares = _min(shares / 100, redeemableShares);
        if (shares > 0) {
            IERC4626(vault).redeem(shares, ACTOR, ACTOR);
        }
    }

    function _exerciseWithdrawalQueue(address vault) internal {
        uint256 shares = IERC20(vault).balanceOf(ACTOR) / 50;
        if (shares == 0) {
            return;
        }

        address queue = IVaultV2(vault).withdrawalQueue();
        IERC20(vault).approve(queue, type(uint256).max);
        uint256 tokenId = IWithdrawalQueue(queue).requestRedeem(shares, ACTOR);
        IWithdrawalQueue(queue).fill();
        (uint256 claimableAssets, uint256 claimableShares) = IWithdrawalQueue(queue).claimable(tokenId);
        if (claimableAssets > 0 || claimableShares > 0) {
            IWithdrawalQueue(queue).claim(tokenId, ACTOR);
        }
    }

    function _createDelayedDebt(string memory label, Market memory market) internal {
        console2.log("create delayed debt", label);
        IUniversalDelegator(market.restakingDelegator)
            .forceDeallocate(market.restakingAppAdapter, IERC20(market.vault).balanceOf(market.restakingAppAdapter) / 3);
        IUniversalDelegator(market.delegator).forceDeallocate(market.appAdapter, _units(market.asset, 100));
        IUniversalDelegator(market.delegator).sweepPending();
        IUniversalDelegator(market.restakingDelegator).sweepPending();
    }

    function _pushAaveYield(address aavePool, Market memory market) internal {
        uint256 amount = _units(market.asset, 111);
        IERC20(market.asset).approve(aavePool, type(uint256).max);
        IMockAavePoolExercise(aavePool).accrueYield(market.asset, market.aaveAdapter, amount);
    }

    function _pushMorphoYield(Market memory market) internal {
        uint256 amount = _units(market.asset, 77);
        IERC20(market.asset).approve(market.morphoVault, type(uint256).max);
        IMockMorphoVaultExercise(market.morphoVault).donateYield(amount);
    }

    function _registerNetworkAndMiddleware(Deployment memory deployed) internal {
        if (!IRegistry(deployed.networkRegistry).isEntity(ACTOR)) {
            INetworkRegistryExercise(deployed.networkRegistry).registerNetwork();
        }
        if (!IRegistry(deployed.operatorRegistry).isEntity(ACTOR)) {
            IOperatorRegistryExercise(deployed.operatorRegistry).registerOperator();
        }
        if (INetworkMiddlewareService(deployed.networkMiddlewareService).middleware(ACTOR) != ACTOR) {
            INetworkMiddlewareService(deployed.networkMiddlewareService).setMiddleware(ACTOR);
        }
    }

    function _mintAndApprove(Deployment memory deployed) internal {
        _mint(deployed.usdc);
        _mint(deployed.aUsd);
        _mint(deployed.mFone);
        _mint(deployed.mGlobal);

        _approveBase(deployed.usdcMarket);
        _approveBase(deployed.aUsdMarket);
    }

    function _approveBase(Market memory market) internal {
        IERC20(market.asset).approve(market.vault, type(uint256).max);
        IERC20(market.asset).approve(market.appAdapter, type(uint256).max);
        IERC20(market.asset).approve(market.restakingAppAdapter, type(uint256).max);
    }

    function _mint(address token) internal {
        IMintableToken(token).mint(ACTOR, _units(token, 1_000_000));
    }

    function _units(address token, uint256 amount) internal view returns (uint256) {
        return amount * 10 ** IERC20Metadata(token).decimals();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _logMarket(string memory label, Market memory market) internal view {
        console2.log(label, "vault totalAssets", IERC4626(market.vault).totalAssets());
        console2.log(label, "vault shares", IERC20(market.vault).balanceOf(ACTOR));
        console2.log(label, "aave assets", IAppAdapter(market.aaveAdapter).totalAssets());
        console2.log(label, "morpho assets", IAppAdapter(market.morphoAdapter).totalAssets());
        console2.log(label, "app slashable", IAppAdapter(market.appAdapter).slashable());
    }

    function _logRestaking(string memory label, Market memory market) internal view {
        console2.log(label, "vault totalAssets", IERC4626(market.restakingVault).totalAssets());
        console2.log(label, "vault shares", IERC20(market.restakingVault).balanceOf(ACTOR));
        console2.log(label, "app slashable", IAppAdapter(market.restakingAppAdapter).slashable());
    }

    function _deployment() internal view returns (Deployment memory deployed) {
        if (block.chainid == 560_048) {
            deployed = _hoodi();
        } else if (block.chainid == 11_155_111) {
            deployed = _sepolia();
        } else {
            revert("unsupported chain");
        }
    }

    function _hoodi() internal pure returns (Deployment memory deployed) {
        deployed.networkRegistry = 0x231e9c011c9B7D4Db670c4048157c12827e609c9;
        deployed.operatorRegistry = 0xD71a1C85741A802cc6E734091585E4Ee9C3a284b;
        deployed.networkMiddlewareService = 0x7bD4b3B1Ffaa1D670FbF20968F88Df76D0674581;
        deployed.usdc = 0x7CBD6c85A278a7586E9D1cF737b5BF2433AE69DD;
        deployed.aUsd = 0x84345D59A3a8c9acc0704595E608bE38a714b4FA;
        deployed.mFone = 0xB47e49F0e9beF4bB7d665B8385133825F7bCFbEd;
        deployed.mGlobal = 0x931E73562091aBFC583273D0E3BCB28c43268778;
        deployed.aavePool = 0x56c409f6b039464cfBA1D41B08017884a6979622;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0xEA31853a6E277C3CfE1B3022a520752dC97ECA7f,
            delegator: 0xfD7f10a63f69c23a6661B45334D4F84950c1D807,
            liquidLaneAdapter: 0xb793c2619BA1516CFc03E7B7ece576C4f63F3D60,
            appAdapter: 0x76658BAb9AbBBf9a7E5f17ACC02493e615aBDEe9,
            aaveAdapter: 0x1209a3409Ef220A4473C055ebfC0D2110c947B87,
            morphoAdapter: 0x7dFA5DF0d721c149Dc621398B0fE29C45F18D0ed,
            morphoVault: 0x5451d30B53E592fDa7ae2564aD13Fb863E018133,
            restakingVault: 0xC93Bb3cdb153e1F0a755266526119334c694910d,
            restakingDelegator: 0xCadd1C7B7b8a883f906c156A45db421135172D25,
            restakingAppAdapter: 0x11E4096c46D73F19d5D7e5760241344c9d1066a1
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0x7bB16960bd74e2e66D140A8B78Fc1fd3b25e2b37,
            delegator: 0x145C2C522B6002A7A281e796cEF3571403ae2bc2,
            liquidLaneAdapter: 0x153F41092e8Cb3397AF23D8eeAF5F5FDa81459c1,
            appAdapter: 0x235bb217D662e8A1912e1AbFCaeCED4Eb066C185,
            aaveAdapter: 0xcef689ED096E9d7066816B0c070FfBa18984DA16,
            morphoAdapter: 0x2cF891aa6BA7894bA5bd20d096E10ED68F78FF4f,
            morphoVault: 0x616D8A52B1946c14408a0a1e73Aa3C6DD393261B,
            restakingVault: 0x86D89860bc8aF2aFf160D4C6Aa4AA798C2C1B119,
            restakingDelegator: 0xCEf78FC3D8458bAacd9414164e421Bd707Eb3688,
            restakingAppAdapter: 0xC41f5e7182c4468aaf0165822Ad9C31f37126003
        });
    }

    function _sepolia() internal pure returns (Deployment memory deployed) {
        deployed.networkRegistry = 0x563F39055db11b2a64D7b8C883F002968b5458B8;
        deployed.operatorRegistry = 0x5579DDc08A6754e2AAbAFcd6E77555391a7887E0;
        deployed.networkMiddlewareService = 0xf4A8dA61336e9900A1975B2a1f9bA5f338Db68fF;
        deployed.usdc = 0x49F2Db28897860b065FfD5509BD8E75FA450fD91;
        deployed.aUsd = 0x062bcE0Ec64D8f5a5b7dCCb7bFA3eb11bE0AcaE0;
        deployed.mFone = 0x0E338C168597971eC7B0E77278653B6ae76Bc6A7;
        deployed.mGlobal = 0x0a1530B52d37Cc69faE82B9D91Add40653c96ED8;
        deployed.aavePool = 0x68c461F159655b3172F199a41c5E0A702ed1A3A4;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x901344F68462455Beff6C828122367686d1a3228,
            delegator: 0xF3e91325234acB1b1c0C1a86CA03Db56CeBf261C,
            liquidLaneAdapter: 0x3517004E6930f8227D3755C0b54e75725D2E4B6A,
            appAdapter: 0x6a4E0150674f8462EF2ff8dd7E6f762FDd8BAd71,
            aaveAdapter: 0xBdf43Dc53b8927B58aBaA1B8B1401972430183de,
            morphoAdapter: 0x4980E28f817dF01a563800E89Ec6dd67f0aD62c3,
            morphoVault: 0x9747832929d2Cd53001295B0CaCbCBB37f2119f5,
            restakingVault: 0xFa43030F06554F8B508E4D7406d41b945C6cDb67,
            restakingDelegator: 0xB69d138949062d5235d7b80EcE7a4d575bE5bdAf,
            restakingAppAdapter: 0x3dfae2c8478C1c15FF2A82E1B53ffB2CD19f309e
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0xEB3BdBE738019c0c6dbE44Cf2E17Aa2A8eF15b6f,
            delegator: 0x0Daa83cd0833D794bb206F951b19BF6267E28117,
            liquidLaneAdapter: 0x012FFe59De90b4D5dAc92c373c7a6C8C1e9EcFdA,
            appAdapter: 0x1F538fB15f23f519a063c5B4DBBc8cDF3F60aBa3,
            aaveAdapter: 0x05005C99b04657408c7ad46447E6cAa784Da124b,
            morphoAdapter: 0xA1c33567305e3B9A541d1ACbd7142caC7efB3A7D,
            morphoVault: 0x6bD08Af2FA05274519472cDF69fF8De25B7Bd6F1,
            restakingVault: 0x3d7acb7AF52Cb5Ff46257F45B6eB3a9E7Fb0525c,
            restakingDelegator: 0x229DBd6104A3a7121150e6b953e70E3B5828f7a1,
            restakingAppAdapter: 0x4653aD535f6AEabE069B5884dd8619b998e038B5
        });
    }
}
