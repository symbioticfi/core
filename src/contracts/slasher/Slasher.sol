// SPDX-License-Identifier: BUSL-1.1
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
    ) external onlyNetworkMiddleware(subnetwork) returns (uint256 slashedAmount) {
        SlashHints memory slashHints;
        if (hints.length > 0) {
            slashHints = abi.decode(hints, (SlashHints));
        }

        address vault_ = vault;
        if (
            captureTimestamp < Time.timestamp() - IVault(vault_).epochDuration() || captureTimestamp >= Time.timestamp()
        ) {
            revert InvalidCaptureTimestamp();
        }

        _checkLatestSlashedCaptureTimestamp(subnetwork, captureTimestamp);

        slashedAmount =
            Math.min(amount, slashableStake(subnetwork, operator, captureTimestamp, slashHints.slashableStakeHints));
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        if (latestSlashedCaptureTimestamp[subnetwork] < captureTimestamp) {
            latestSlashedCaptureTimestamp[subnetwork] = captureTimestamp;
        }

        _updateCumulativeSlash(subnetwork, operator, slashedAmount);

        IBaseDelegator(IVault(vault_).delegator()).onSlash(
            subnetwork, operator, slashedAmount, captureTimestamp, new bytes(0)
        );

        IVault(vault_).onSlash(slashedAmount, captureTimestamp);

        emit Slash(subnetwork, operator, slashedAmount, captureTimestamp);
    }
}
