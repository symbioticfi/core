// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {BaseSlasher} from "src/contracts/slasher/BaseSlasher.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {BaseDelegatorHints} from "./DelegatorHints.sol";
import {OptInServiceHints} from "./OptInServiceHints.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract BaseSlasherHints is Hints, BaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable OPT_IN_SERVICE_HINTS;
    address public immutable SLASHER_HINTS;
    address public immutable VETO_SLASHER_HINTS;

    constructor(
        address baseDelegatorHints,
        address optInServiceHints
    ) BaseSlasher(address(0), address(0), address(0), address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        OPT_IN_SERVICE_HINTS = optInServiceHints;
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

        bytes memory hints;
        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            hints = abi.encode(
                SlashableStakeHints({stakeHints: stakeHints, cumulativeSlashFromHint: cumulativeSlashFromHint})
            );
        }

        return hints;
    }

    function optInHints(
        address slasher,
        address network,
        address operator,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory networkVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).NETWORK_VAULT_OPT_IN_SERVICE(), network, BaseSlasher(slasher).vault(), timestamp
        );

        bytes memory operatorVaultOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).OPERATOR_VAULT_OPT_IN_SERVICE(), operator, BaseSlasher(slasher).vault(), timestamp
        );

        bytes memory operatorNetworkOptInHint = OptInServiceHints(OPT_IN_SERVICE_HINTS).optInHint(
            BaseSlasher(slasher).OPERATOR_NETWORK_OPT_IN_SERVICE(), operator, network, timestamp
        );

        bytes memory hints;
        if (
            networkVaultOptInHint.length > 0 || operatorVaultOptInHint.length > 0 || operatorNetworkOptInHint.length > 0
        ) {
            hints = abi.encode(
                OptInHints({
                    networkVaultOptInHint: networkVaultOptInHint,
                    operatorVaultOptInHint: operatorVaultOptInHint,
                    operatorNetworkOptInHint: operatorNetworkOptInHint
                })
            );
        }

        return hints;
    }

    function onSlashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory delegatorOnSlashHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).onSlashHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), network, operator, captureTimestamp
        );

        bytes memory hints;
        if (delegatorOnSlashHints.length > 0) {
            hints = abi.encode(OnSlashHints({delegatorOnSlashHints: delegatorOnSlashHints}));
        }

        return hints;
    }
}

contract SlasherHints is Hints, Slasher {
    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints)
        Slasher(address(0), address(0), address(0), address(0), address(0), address(0), 0)
    {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function slashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory optInHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).optInHints(slasher, network, operator, captureTimestamp);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);
        bytes memory onSlashHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).onSlashHints(slasher, network, operator, captureTimestamp);

        bytes memory hints;
        if (optInHints.length > 0 || slashableStakeHints.length > 0 || onSlashHints.length > 0) {
            hints = abi.encode(
                SlashHints({
                    optInHints: optInHints,
                    slashableStakeHints: slashableStakeHints,
                    onSlashHints: onSlashHints
                })
            );
        }

        return hints;
    }
}

contract VetoSlasherHints is Hints, VetoSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_SLASHER_HINTS;

    constructor(address baseSlasherHints)
        VetoSlasher(address(0), address(0), address(0), address(0), address(0), address(0), address(0), 0)
    {
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

        return _optimizeHint(
            slasher,
            abi.encodeWithSelector(VetoSlasher.resolverSharesAt.selector, network, resolver, timestamp, ""),
            abi.encodeWithSelector(VetoSlasher.resolverSharesAt.selector, network, resolver, timestamp, hint),
            hint
        );
    }

    function requestSlashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory optInHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).optInHints(slasher, network, operator, captureTimestamp);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);

        bytes memory hints;
        if (optInHints.length > 0 || slashableStakeHints.length > 0) {
            hints = abi.encode(RequestSlashHints({optInHints: optInHints, slashableStakeHints: slashableStakeHints}));
        }

        return hints;
    }

    function executeSlashHints(
        address slasher,
        address network,
        address operator,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, network, operator, captureTimestamp);
        bytes memory onSlashHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).onSlashHints(slasher, network, operator, captureTimestamp);

        bytes memory hints;
        if (slashableStakeHints.length > 0 || onSlashHints.length > 0) {
            hints =
                abi.encode(ExecuteSlashHints({slashableStakeHints: slashableStakeHints, onSlashHints: onSlashHints}));
        }

        return hints;
    }

    function vetoSlashHints(
        address slasher,
        address network,
        address resolver,
        uint48 captureTimestamp
    ) external returns (bytes memory) {
        bytes memory resolverSharesHint = resolverSharesHint(slasher, network, resolver, captureTimestamp);

        bytes memory hints;
        if (resolverSharesHint.length > 0) {
            hints = abi.encode(VetoSlashHints({resolverSharesHint: resolverSharesHint}));
        }

        return hints;
    }

    function setResolverSharesHints(
        address slasher,
        address network,
        address resolver,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory resolverSharesHint = resolverSharesHint(slasher, network, resolver, timestamp);

        bytes memory hints;
        if (resolverSharesHint.length > 0) {
            hints = abi.encode(SetResolverSharesHints({resolverSharesHint: resolverSharesHint}));
        }

        return hints;
    }
}
