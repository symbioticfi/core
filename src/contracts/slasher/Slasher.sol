// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {ISlasher} from "../../interfaces/slasher/ISlasher.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Slasher is BaseSlasher, ISlasher {
    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address slasherFactory,
        uint64 entityType
    ) BaseSlasher(vaultFactory, networkMiddlewareService, slasherFactory, entityType) {}

    /**
     * @inheritdoc ISlasher
     */
    function slash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external nonReentrant onlyNetworkMiddleware(subnetwork) returns (uint256 slashedAmount) {
        SlashHints memory slashHints;
        if (hints.length > 0) {
            slashHints = abi.decode(hints, (SlashHints));
        }

        if (captureTimestamp < Time.timestamp() - IVault(vault).epochDuration() || captureTimestamp >= Time.timestamp())
        {
            revert InvalidCaptureTimestamp();
        }

        (uint256 slashableStake_, uint256 stakeAt) =
            _slashableStake(subnetwork, operator, captureTimestamp, slashHints.slashableStakeHints);
        slashedAmount = Math.min(amount, slashableStake_);
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _updateLatestSlashedCaptureTimestamp(subnetwork, operator, captureTimestamp);

        _updateCumulativeSlash(subnetwork, operator, slashedAmount);

        _delegatorOnSlash(
            subnetwork,
            operator,
            slashedAmount,
            captureTimestamp,
            abi.encode(ISlasher.DelegatorData({slashableStake: slashableStake_, stakeAt: stakeAt}))
        );

        _vaultOnSlash(slashedAmount, captureTimestamp);

        _burnerOnSlash(subnetwork, operator, slashedAmount, captureTimestamp);

        emit Slash(subnetwork, operator, slashedAmount, captureTimestamp);
    }

    function __initialize(address, /* vault_ */ bytes memory data) internal override returns (BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        return params.baseParams;
    }
}
