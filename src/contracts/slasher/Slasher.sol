// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {ISlasher} from "src/interfaces/slasher/ISlasher.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Slasher is BaseSlasher, ISlasher {
    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address slasherFactory
    )
        BaseSlasher(
            vaultFactory,
            networkMiddlewareService,
            networkVaultOptInService,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            slasherFactory
        )
    {}

    /**
     * @inheritdoc ISlasher
     */
    function slash(
        address network,
        address operator,
        uint256 amount
    ) external onlyNetworkMiddleware(network) returns (uint256) {
        uint256 operateNetworkStake = IBaseDelegator(IVault(vault).delegator()).operatorNetworkStake(network, operator);
        if (amount == 0 || operateNetworkStake == 0) {
            revert InsufficientSlash();
        }

        if (amount > operateNetworkStake) {
            amount = operateNetworkStake;
        }

        _checkOptIns(network, operator);

        _callOnSlash(network, operator, amount);

        return amount;
    }
}
