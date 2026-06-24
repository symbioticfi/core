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
        IUniversalDelegator(market.restakingDelegator).allocateAll(depositShares / 30);

        _exerciseWithdrawals(market.restakingVault);
        _exerciseWithdrawalQueue(market.restakingVault);

        IAppAdapter(market.restakingAppAdapter).release(_units(market.asset, 2));
        IAppAdapter(market.restakingAppAdapter).slash(_units(market.asset, 3));

        _logRestaking(label, market);
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
        uint256 assets = IERC4626(vault).maxWithdraw(ACTOR);
        if (assets > 0) {
            IERC4626(vault).withdraw(assets / 100, ACTOR, ACTOR);
        }

        uint256 shares = IERC20(vault).balanceOf(ACTOR);
        if (shares > 0) {
            IERC4626(vault).redeem(shares / 100, ACTOR, ACTOR);
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
        IWithdrawalQueue(queue).claim(tokenId, ACTOR);
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
        deployed.networkRegistry = 0x9432A6F14d3E7bdFBB82e3A29C384365A3932e3f;
        deployed.operatorRegistry = 0xdE1EF2838BC5f1fBb45A05E0e2F05fdF0c546fB0;
        deployed.networkMiddlewareService = 0x2b0D0cB55E969121Bd0C7d5e1B05EcA67E6b053F;
        deployed.usdc = 0x8a69ABF3f55D8b5db1F506bc9D0E47196de74315;
        deployed.aUsd = 0xd663591573DeF8092B1156c4a8e497646Ec9FaE7;
        deployed.mFone = 0x3d75e7A8f8D0B62403DC2fB55021Fb024DEb24dd;
        deployed.mGlobal = 0x5E3f3E4f175d9fF702c08F3ca8a2E0EB98B7463d;
        deployed.aavePool = 0x2b1858b6F2B0Dc66FfB5e6d5aB2962b1Be02a0F3;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0x3E3AAeC5c8489cd8d323d08f8418C91302A8b95c,
            delegator: 0xF0Df59Cc56F41baCC26D94A7c96D1f4E6bd2e3E1,
            liquidLaneAdapter: 0x8DCC2515dE40c62d09125db5551de02603C70190,
            appAdapter: 0x1aA064632dc04b659c13e0420C8A36D8A1613Fd6,
            aaveAdapter: 0x4037fE29E2981D01C7bb6Ae5BE40927497F60aA3,
            morphoAdapter: 0x7A8D62B28faAd13Ca35aA1c0b1A37D81dB903529,
            morphoVault: 0x557DB3FB865F0DdBbE2619a15c933ec2034ef6B5,
            restakingVault: 0x81012fDcf7a4f53efCBCE2193D1531E09b2f676B,
            restakingDelegator: 0x5bdE352Cc38a7d26bfbE13E5cd2dCed3FdF9A7b3,
            restakingAppAdapter: 0xCF2F3D3962027098e926fD58F61985c844d52516
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0xc3eA8A191fE74478F8c349bbDe938b44EeCA0025,
            delegator: 0x98292b68Ee20D0dc487291f2FB906F0EbC0A856F,
            liquidLaneAdapter: 0x797390393A8a5b65e93A0E4E4A5fCDe06B94Bd3F,
            appAdapter: 0xAAD87c1600A811D9Cf59FB7A1c3E25d519CeD899,
            aaveAdapter: 0xF353F6aAE44A946B33f2Bd7D8305C72b643C49c7,
            morphoAdapter: 0x75a5Fa31fc58d32C77f1133C7459f773d9bCca45,
            morphoVault: 0x1ca29C3Ea7B41e2E2aE4662caD496792DD7cf360,
            restakingVault: 0x595698180Ca666A41236a8383DbE77a23Fa0Dd85,
            restakingDelegator: 0x23BF7AB3140324eD191c4142f12B260AbAe74fE1,
            restakingAppAdapter: 0x40B96b3dFfdF9559cbE0EDD5e36cBB7470D40AC7
        });
    }

    function _sepolia() internal pure returns (Deployment memory deployed) {
        deployed.networkRegistry = 0xff3E2A14BE3A357fF6e7bB2Dc34af4Ee96EBB3ab;
        deployed.operatorRegistry = 0xCa0E444534b52CFEEAe18646f0B1a4066e68Be51;
        deployed.networkMiddlewareService = 0x2addAEcC745199f1185EEabd0E1738eA77661173;
        deployed.usdc = 0xa5a802F686ed273F9BA4603c77794178f8147060;
        deployed.aUsd = 0x1497bdEBe6A511422e28D4B382f9980185221016;
        deployed.mFone = 0x3d64FffE3B30b597c678A6F805Da2014f9FF02Cf;
        deployed.mGlobal = 0xB430d436F9A38caD72792D9234307f7b8a57373d;
        deployed.aavePool = 0x383D7C70Efb1764A1b7cAF9F797946d8f47701f1;
        deployed.usdcMarket = Market({
            asset: deployed.usdc,
            vault: 0xC35E0b958EBC20740C4cA9298C26E674dF4C01Eb,
            delegator: 0x87B887115510d6E98A48A0c913C2bb87f3a5d701,
            liquidLaneAdapter: 0x6d3456D8DcDD4F3e8a506275E22eBB9653a7bD79,
            appAdapter: 0xb1500111dCfB046b295dC98C37916D5E24ad4992,
            aaveAdapter: 0x4a05692CE0022281f3dfB6FfCEeaA6E6974F24C3,
            morphoAdapter: 0x38b3FFD1784cdD8D7311cd728dc47F019701B669,
            morphoVault: 0xA6e8b107F6dF78B135593791c29942196649589A,
            restakingVault: 0x9Da9F07b3697D2d881714f8c05Cd214b3363971c,
            restakingDelegator: 0x5b7d9502B9EEE07bb58C637EEA6737a4bA0dF0bA,
            restakingAppAdapter: 0xBe4292d00DA71e934165C7f564B4549731575505
        });
        deployed.aUsdMarket = Market({
            asset: deployed.aUsd,
            vault: 0xB829C7c5b10A5b187310880832Fa6711098C3357,
            delegator: 0x7ea889f9edE4b2D0f09786019Ba06a84B9939e19,
            liquidLaneAdapter: 0xC06382F350618dBFf760369F3d42294aDa8F1277,
            appAdapter: 0xe7bf21cA1749F5BAF0f3f9A0400e8BF3A775C0F0,
            aaveAdapter: 0x024aA5B1f4d1266572AD179065D4c927045BFC7c,
            morphoAdapter: 0x418e67A2d32c2ed3d596432EE0705cDA2Aa5C31e,
            morphoVault: 0xAeD1a05dAb749e28Ee0Ed4D96eb754f875154AB9,
            restakingVault: 0xc90983C7D938F33f2D632FaEF3258a1cA4241F60,
            restakingDelegator: 0x483Ae44A6615455121eBE65808621f0b436De4d7,
            restakingAppAdapter: 0xF40c4AFfac1eC16B91Eaf2FbF6FD0a5715318A8B
        });
    }
}
