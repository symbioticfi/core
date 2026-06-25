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
        deployed.networkRegistry = 0xb2EfA49BB2Aa418ac55bA7DdaA1Cf647F7fb465f;
        deployed.operatorRegistry = 0xca9cc351C8165d22D0Fd0831C560474b94be5CcD;
        deployed.networkMiddlewareService = 0xf431e69aa7329CaDBc44AF07504cadA9817975F9;
        deployed.usdc = 0x9B97F7eDAbd9Ef43cAcE2eaFDD1DE5721aE3Bdd3;
        deployed.aUsd = 0x17Eef10B14D727fB700918687e4d1D0D323efB5D;
        deployed.mFone = 0xA684911e92b8E4Dd27046331B849Bbd6dbca0fA2;
        deployed.mGlobal = 0x2Ee6f1A395Bce7a7c5bF1D07bAaF9F8A0828A8d3;
        deployed.aavePool = 0x5BFe1C93bD7271C484724C5f393bAD586Eb8c3fD;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x005BC9715A57f8593e4Dd826e5A16638B9870F7C,
            delegator: 0xFE49B8bB32573984e2981402735dC88052819a0b,
            liquidLaneAdapter: 0x788Ab0D58bC7E5537109064F95875013c886ACC8,
            appAdapter: 0xad2Ae2C332BDEb092CE223c09baA52525a653c85,
            aaveAdapter: 0x23643a0221e0359C536c4c86F2205EE9f4Ec82a2,
            morphoAdapter: 0xE653D691e4eC52708C04D02CeCdAcFCC761aEd9d,
            morphoVault: 0xAfe11A1e8009d3c0bD66E80cbf89A3c850b84A1c,
            restakingVault: 0x3b57e1c45F83B7D1A59F0373761f8C7561DA49Ac,
            restakingDelegator: 0xCfC66aD1edB63fb749899c2e15Be519b11a23331,
            restakingAppAdapter: 0x1f2792Ab4F5b7F5bF364796f804170c51Dd6d1e5
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0xf712E351D127E8f3524fA72C8BA66eb900bcDcEd,
            delegator: 0xB20EA67d178bD84Fb66F31E6c34db749D44915Fe,
            liquidLaneAdapter: 0x9292Ad3e9C3747cFA31885657B5A458002205281,
            appAdapter: 0xe2f82636DE875cac4e9aeD2453BE10eBA7890f80,
            aaveAdapter: 0x39470c2B20B593B51ABde7AbeBaFb894e3973Da3,
            morphoAdapter: 0xFC4dc57fF3De7096CfA9b70f07962c18268bF456,
            morphoVault: 0x0ef46FA00C67E0AE2265AedE1cA00Bc4d0e0673a,
            restakingVault: 0x1975370f91D9332f8F28873f327c7174045c949A,
            restakingDelegator: 0x0FfE0A001E243d0cFbF018CA4c946b12a5EA18e6,
            restakingAppAdapter: 0xEeb5ef49e2095DfE510C99d1f4F0b460443E2605
        });
    }

    function _sepolia() internal pure returns (Deployment memory deployed) {
        deployed.networkRegistry = 0x653618ea4AE1112b0Bb78E208605A3897A4fD5Dd;
        deployed.operatorRegistry = 0x8ccf50CEC5D9A4fE992707c199ce3E5D88F4181a;
        deployed.networkMiddlewareService = 0x4036F988198D5dEBC069bA8666c1005C27ed3dA3;
        deployed.usdc = 0xc06ea690d3eC9a85E1e1603f366f13c50d80afD3;
        deployed.aUsd = 0x4DB97050730c79f69716C2c8d551DD21c49ac1a5;
        deployed.mFone = 0x5702FDa445cff75bbCA4e24c1e18f38f4A6b2176;
        deployed.mGlobal = 0xb547DCEcfC86FCC7B2964A4d9A2d5e8CFc407593;
        deployed.aavePool = 0x68239eA4BB513AD538d31aDD4D942219B46a954C;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x0c5675268bd6CbcD99F901e11A35612E8A7BB70a,
            delegator: 0x8476371c8CA4878d11d319CD04c3193C20b1403f,
            liquidLaneAdapter: 0x8F38656B85fb440018c109A5118aFfDfD923721c,
            appAdapter: 0x7b12722529041C5D69044770739B033F2D77Ac79,
            aaveAdapter: 0xf4201dd8af805855BDC4328780a2583dc898d37a,
            morphoAdapter: 0xDE8900997bf9d06f50F5F70c717B14EB1cfD086d,
            morphoVault: 0xF97CfBeF4675b7A21CBd385ffDb2b4C5cd581C83,
            restakingVault: 0x18265861301096aB32BB80B0c5292570Edb9BD14,
            restakingDelegator: 0x6Dc363d90c0f4AFf807A6b59764b0B00f85e7b77,
            restakingAppAdapter: 0xB65590B67AB9C27D9a5EAC24846dB97c86Ede07d
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0xb7227ac48307557616f7e003aAd5Be83Eb2eA85E,
            delegator: 0x12536a564d6676b17Ca1C179b8913b5D8047e8f4,
            liquidLaneAdapter: 0xe4eb1E756F2d78F77B9ebE304515fA61B2451A33,
            appAdapter: 0x4188b5D7091FaCBeB32d2CbCD7a6804D9D75be2b,
            aaveAdapter: 0x352cA87107C77aAD830D23B578a45dCf04eC1b73,
            morphoAdapter: 0xc646cfEDc9227f1cDEab7a0f04AebCb95d7e358a,
            morphoVault: 0x0a774e2187a1Fc4C228178A84e0a9ED4bBabaE61,
            restakingVault: 0x6C34202EF76095A8299D8496D831BDc3FeD96C3C,
            restakingDelegator: 0xb76189891Fe2ce6F9eCE827722694C628E938C41,
            restakingAppAdapter: 0xeeCa62d98BD60529b89c2cbe9a89358d138FdFc3
        });
    }
}
