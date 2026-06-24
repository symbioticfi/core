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
        deployed.networkRegistry = 0x88f36d74Efb884BeB7F593FCa9928dda05A0a636;
        deployed.operatorRegistry = 0xF788d06C24f0E0C9C615603C3124c082AbDA0C66;
        deployed.networkMiddlewareService = 0x90CbE0dFa282550866b2DbCF448E3155c55EEdbe;
        deployed.usdc = 0xd8B34955B4DF1E102ee3b1e3fe90acd14bd7959d;
        deployed.aUsd = 0xc5B6ddB87D8E353D9B19f1174cc360f965f0d449;
        deployed.mFone = 0x57f38F73deCC242f198a6CF2a7a275bc948F940E;
        deployed.mGlobal = 0x9109c84202D8b5339Ebe3900A8253140bF97a9aC;
        deployed.aavePool = 0x853082811D1640D249647330ed7A7f8a042f14cd;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x01784C037944cFF8a1600305C8aB3AEE143d98BF,
            delegator: 0xf7F8708eA3985161D66F60392479553e83302D5c,
            liquidLaneAdapter: 0x3D4A6d98680e91E8cD31e0082DA32a42AA431cE1,
            appAdapter: 0xDCB1D3C69b30838B7d20CF95FF7EC1d9ba6f241B,
            aaveAdapter: 0x8a4710dd2B59efdfa222b928AF0Ffe3e3565331d,
            morphoAdapter: 0xc3fecE012e63Ea1d5d59c55D0CFcf77F1A435F5a,
            morphoVault: 0x1d3875B0bC9B0552E63b4BD47C81EDDBFc6aA2DE,
            restakingVault: 0x551A09A35B3d1fCFb0914e3c007AC12bD47A06E8,
            restakingDelegator: 0x4100B9F7925C453DFd37f8b47EC7Ba464F93C634,
            restakingAppAdapter: 0x5fDd5d27A733AaD2E381dBfB4aCB5413b283C1C9
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0x3D04Bd88b0136aA1D1f7781beAC6366291eF161C,
            delegator: 0x2645084246FF05F0D86c7DC39a06c779A1976584,
            liquidLaneAdapter: 0xf0A3D0B540D7675Ca790188e0dDA68A610f26029,
            appAdapter: 0xb4F9f67df9c12A79FEDc1aA0438f366507D6676F,
            aaveAdapter: 0x33c18BA17969f867484F321D1B7aA615AF2B556f,
            morphoAdapter: 0x2654ef4A071CD68f01219F95E42f400b76c54eb7,
            morphoVault: 0xFb039136bDcd2F6c4F83eDc331A6e153393EDab5,
            restakingVault: 0xdE0D4E8EB4b0152c80Ff9eD7Db8E5944cd5cCAA7,
            restakingDelegator: 0xb78090C124c1c6AF4c01F00154BDAE09077F002F,
            restakingAppAdapter: 0x6A4b8bEA63125Cd056E57a9C27398ee007477DB6
        });
    }

    function _sepolia() internal pure returns (Deployment memory deployed) {
        deployed.networkRegistry = 0xbd24ba4DcFe4e7FFC49Eb12bD37A3a5E767284B4;
        deployed.operatorRegistry = 0x9900B5a4832C7F08704641d1565Ebf599f5760cE;
        deployed.networkMiddlewareService = 0xe59e1c492210C28aCF52D3a73fa61aA8539536Cf;
        deployed.usdc = 0xeD16Cd1EDc840d76ceBfda0CccA7374Ec555FBa6;
        deployed.aUsd = 0xE168Eb1E6C915d702816385782bBAD6aA3DFbBc4;
        deployed.mFone = 0x00A9E1C091Eec6F231BA2ec6e952cb7D0Cd6a4F5;
        deployed.mGlobal = 0x51d93a672532510B38e2e2421Ac1A314EFeBB127;
        deployed.aavePool = 0xbeeDBa4d672a1e29fce4d3AdDAd76336D7Ed6FEa;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x1690f4E1ee1234Fd32E051DDb8dfF284CDFF6e09,
            delegator: 0x1fFa9500505cC3eAE08432B3ee25d52025Ba11a4,
            liquidLaneAdapter: 0xDC17B4132DeC09736cf11cDf1989906084479540,
            appAdapter: 0x049C1BfdbB7b1FEC29969f94a6e51E16E40273Bc,
            aaveAdapter: 0xcFcBD38a14723A1bFD06e23D87e605f0cd47aA6c,
            morphoAdapter: 0x895CC54Be0A27bf9aCC29e663e0D8Da1195d4186,
            morphoVault: 0x6003D3C637479efbA5d2CB1B479c902BAE67a858,
            restakingVault: 0xB2Bb124Fd4dF7AE6581acE92c4F75CCD393825eF,
            restakingDelegator: 0x3236809a86dA39072a743e3Dc5Aac314Df024d31,
            restakingAppAdapter: 0x19B7500592b1E7B1e22467d07A39aD2f6B24c0d0
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0x6B53f82Aaf121B26Eb9ad044a6738BdE8f64E41E,
            delegator: 0xF2EA4b566938e495a6dc4c88a85445A79537b017,
            liquidLaneAdapter: 0xB0c2BACD43f5F9601A038C39d87AA1a918a5F0dE,
            appAdapter: 0x20c2E58DE7ef9F19574256C8a79AAF7b3c2e603C,
            aaveAdapter: 0x29116DbDD0F40Efe61B4f2461F17799c7e509589,
            morphoAdapter: 0xf9c01a838409538F5AC8A9374E2EA4CB56112F85,
            morphoVault: 0x8f69ee6cD7Ae4b96a98f82E9832DC5661Ee89bA2,
            restakingVault: 0x40799384C5237Bc63767C1e2FfA22b19873364B6,
            restakingDelegator: 0xDA9FA7ef4C1eCFf9B59ea1CD2588eF7AC3e18E84,
            restakingAppAdapter: 0x896d1A4A6855CA052fFc509fC97575A5822C1e0e
        });
    }
}
