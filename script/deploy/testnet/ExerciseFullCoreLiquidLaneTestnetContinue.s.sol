// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ExerciseFullCoreLiquidLaneTestnetScript} from "./ExerciseFullCoreLiquidLaneTestnet.s.sol";

import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ExerciseFullCoreLiquidLaneTestnetContinueScript is ExerciseFullCoreLiquidLaneTestnetScript {
    function run() external override {
        Deployment memory deployed = _deployment();

        vm.startBroadcast();
        _continueRestakingMarket("USDC restaking", deployed.usdcMarket);
        _continueRestakingMarket("aUSD restaking", deployed.aUsdMarket);
        _createDelayedDebt("USDC", deployed.usdcMarket);
        _createDelayedDebt("aUSD", deployed.aUsdMarket);
        vm.stopBroadcast();
    }

    function _continueRestakingMarket(string memory label, Market memory market) internal {
        console2.log("continue restaking", label, market.restakingVault);

        uint256 restakingShares = IERC20(market.restakingVault).balanceOf(ACTOR);
        if (restakingShares == 0) {
            uint256 childShares = IERC20(market.vault).balanceOf(ACTOR);
            uint256 depositShares = childShares / 5;
            if (depositShares == 0) {
                console2.log("skip restaking continuation, no child vault shares");
                return;
            }
            IERC20(market.vault).approve(market.restakingVault, type(uint256).max);
            IERC4626(market.restakingVault).deposit(depositShares, ACTOR);
            restakingShares = IERC20(market.restakingVault).balanceOf(ACTOR);
        }

        address[] memory autoAdapters = new address[](1);
        autoAdapters[0] = market.restakingAppAdapter;
        IUniversalDelegator(market.restakingDelegator).setAutoAllocateAdapters(autoAdapters);
        IUniversalDelegator(market.restakingDelegator)
            .setLimits(market.restakingAppAdapter, type(uint128).max, MAX_SHARE);

        if (IAppAdapter(market.restakingAppAdapter).slashable() == 0) {
            IUniversalDelegator(market.restakingDelegator).allocate(market.restakingAppAdapter, restakingShares / 2);
            IAppAdapter(market.restakingAppAdapter).reward(market.asset, _units(market.asset, 15));
        }

        IUniversalDelegator(market.restakingDelegator).deallocate(market.restakingAppAdapter, restakingShares / 20);
        IUniversalDelegator(market.restakingDelegator).deallocateAll(restakingShares / 25);
        IUniversalDelegator(market.restakingDelegator).allocateAll(restakingShares / 30);

        _exerciseWithdrawals(market.restakingVault);
        _exerciseWithdrawalQueue(market.restakingVault);

        IAppAdapter(market.restakingAppAdapter).release(_units(market.asset, 2));
        IAppAdapter(market.restakingAppAdapter).slash(_units(market.asset, 3));

        _logRestaking(label, market);
    }
}
