// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseSlasher} from "src/contracts/slasher/BaseSlasher.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {BaseDelegatorHints} from "./DelegatorHints.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract BaseSlasherHints is Hints, BaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable SLASHER_HINTS;
    address public immutable VETO_SLASHER_HINTS;

    constructor(address baseDelegatorHints) BaseSlasher(address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        SLASHER_HINTS = address(new SlasherHints(address(this)));
        VETO_SLASHER_HINTS = address(new VetoSlasherHints(address(this)));
    }

    function cumulativeSlashHintInternal(
        address network,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _cumulativeSlash[network][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function cumulativeSlashHint(
        address slasher,
        address network,
        address operator,
        uint48 timestamp
    ) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            slasher,
            abi.encodeWithSelector(BaseSlasherHints.cumulativeSlashHintInternal.selector, network, operator, timestamp)
        );

        return _optimizeHint(
            slasher,
            abi.encodeWithSelector(BaseSlasher.cumulativeSlashAt.selector, network, operator, timestamp, ""),
            abi.encodeWithSelector(BaseSlasher.cumulativeSlashAt.selector, network, operator, timestamp, hint),
            hint
        );
    }

    function slashableStakeHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory stakeHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, captureTimestamp
        );

        bytes memory cumulativeSlashFromHint = cumulativeSlashHint(slasher, network, operator, captureTimestamp);

        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            return abi.encode(
                SlashableStakeHints({stakeHints: stakeHints, cumulativeSlashFromHint: cumulativeSlashFromHint})
            );
        }
    }
}

contract SlasherHints is Hints, Slasher {
    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints) Slasher(address(0), address(0), address(0), 0) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function slashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            return abi.encode(SlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }
}

contract VetoSlasherHints is Hints, VetoSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints) VetoSlasher(address(0), address(0), address(0), address(0), 0) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function resolverSharesHintInternal(
        address network,
        address resolver,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _resolverShares[network][resolver].upperLookupRecentCheckpoint(timestamp);
    }

    function resolverSharesHint(
        address slasher,
        address network,
        address resolver,
        uint48 timestamp
    ) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            slasher,
            abi.encodeWithSelector(VetoSlasherHints.resolverSharesHintInternal.selector, network, resolver, timestamp)
        );

        return abi.encode(hint);
    }

    function requestSlashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            return abi.encode(RequestSlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }

    function executeSlashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            return abi.encode(ExecuteSlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }

    function vetoSlashHints(
        address slasher,
        address network,
        address resolver,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, network, resolver, captureTimestamp);

        bytes memory hints;
        if (resolverSharesHint_.length > 0) {
            hints = abi.encode(VetoSlashHints({resolverSharesHint: resolverSharesHint_}));
        }

        return hints;
    }

    function setResolverSharesHints(
        address slasher,
        address network,
        address resolver,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory resolverSharesHint_ = resolverSharesHint(slasher, network, resolver, timestamp);

        bytes memory hints;
        if (resolverSharesHint_.length > 0) {
            hints = abi.encode(SetResolverSharesHints({resolverSharesHint: resolverSharesHint_}));
        }

        return hints;
    }
}
