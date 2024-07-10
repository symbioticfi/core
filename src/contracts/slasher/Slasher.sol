// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {ISlasher} from "src/interfaces/slasher/ISlasher.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Slasher is BaseSlasher, ISlasher {
    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address slasherFactory,
        uint64 entityType
    )
        BaseSlasher(
            vaultFactory,
            networkMiddlewareService,
            networkVaultOptInService,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            slasherFactory,
            entityType
        )
    {}

    /**
     * @inheritdoc ISlasher
     */
    function slash(
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external onlyNetworkMiddleware(network) returns (uint256 slashedAmount) {
        _checkOptIns(network, operator, captureTimestamp);

        if (captureTimestamp < Time.timestamp() - Math.min(IVault(vault).epochDuration(), Time.timestamp())) {
            revert InvalidCaptureTimestamp();
        }

        uint256 stakeAmount = IBaseDelegator(IVault(vault).delegator()).stakeAt(network, operator, captureTimestamp);
        slashedAmount = Math.min(
            amount,
            stakeAmount
                - Math.min(
                    slashAtDuring(network, operator, captureTimestamp, Time.timestamp() - captureTimestamp), stakeAmount
                )
        );
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _updateCumulativeSlash(network, operator, slashedAmount);

        _callOnSlash(network, operator, slashedAmount, captureTimestamp);

        emit Slash(network, operator, slashedAmount, captureTimestamp);
    }
}
