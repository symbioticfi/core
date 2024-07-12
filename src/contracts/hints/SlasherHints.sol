// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseSlasher} from "src/contracts/slasher/BaseSlasher.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {BaseDelegatorHints} from "./DelegatorHints.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract BaseSlasherHints is Hints, BaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public baseDelegatorHints;

    constructor(address baseDelegatorHints_)
        BaseSlasher(address(0), address(0), address(0), address(0), address(0), address(0), 0)
    {
        baseDelegatorHints = baseDelegatorHints_;
    }

    function slashableStakeHintsInner(
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (SlashableStakeHints memory) {
        (,,, uint32 cumulativeSlashToHint) =
            _cumulativeSlash[network][operator].upperLookupRecentCheckpoint(Time.timestamp());

        return SlashableStakeHints({
            stakeHints: BaseDelegatorHints(baseDelegatorHints).stakeHints(
                Vault(vault).delegator(), network, operator, captureTimestamp
            ),
            cumulativeSlashFromHint: abi.encode(cumulativeSlashToHint)
        });
    }

    function slashableStakeHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        return _selfStaticDelegateCall(
            slasher,
            abi.encodeWithSelector(
                BaseSlasherHints.slashableStakeHintsInner.selector, network, operator, captureTimestamp
            )
        );
    }
}
