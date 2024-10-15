// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegatorHints} from "./DelegatorHints.sol";
import {BaseSlasher} from "../slasher/BaseSlasher.sol";
import {Hints} from "./Hints.sol";
import {Slasher} from "../slasher/Slasher.sol";
import {Vault} from "../vault/Vault.sol";
import {VetoSlasher} from "../slasher/VetoSlasher.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract BaseSlasherHints is Hints, BaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable SLASHER_HINTS;
    address public immutable VETO_SLASHER_HINTS;

    constructor(
        address baseDelegatorHints
    ) BaseSlasher(address(0), address(0), address(0), 0) {
        BASE_DELEGATOR_HINTS = baseDelegatorHints;
        SLASHER_HINTS = address(new SlasherHints(address(this)));
        VETO_SLASHER_HINTS = address(new VetoSlasherHints(address(this)));
    }

    function cumulativeSlashHintInternal(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _cumulativeSlash[subnetwork][operator].upperLookupRecentCheckpoint(timestamp);
    }

    function cumulativeSlashHint(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 timestamp
    ) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher, abi.encodeCall(BaseSlasherHints.cumulativeSlashHintInternal, (subnetwork, operator, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function slashableStakeHints(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory stakeHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeHints(
            Vault(BaseSlasher(slasher).vault()).delegator(), subnetwork, operator, captureTimestamp
        );

        bytes memory cumulativeSlashFromHint = cumulativeSlashHint(slasher, subnetwork, operator, captureTimestamp);

        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            return abi.encode(
                SlashableStakeHints({stakeHints: stakeHints, cumulativeSlashFromHint: cumulativeSlashFromHint})
            );
        }
    }
}

contract SlasherHints is Hints, Slasher {
    address public immutable BASE_SLASHER_HINTS;

    constructor(
        address baseSlasherHints
    ) Slasher(address(0), address(0), address(0), 0) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function slashHints(
        address slasher,
        address msgSender,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            return abi.encode(SlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }
}

contract VetoSlasherHints is Hints, VetoSlasher {
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    address public immutable BASE_SLASHER_HINTS;

    constructor(
        address baseSlasherHints
    ) VetoSlasher(address(0), address(0), address(0), address(0), 0) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function resolverHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _resolver[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function resolverHint(address slasher, bytes32 subnetwork, uint48 timestamp) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher, abi.encodeCall(VetoSlasherHints.resolverHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function requestSlashHints(
        address slasher,
        address msgSender,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            return abi.encode(RequestSlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }

    function executeSlashHints(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory captureResolverHint = resolverHint(slasher, subnetwork, captureTimestamp);
        bytes memory currentResolverHint = resolverHint(slasher, subnetwork, Time.timestamp() - 1);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (captureResolverHint.length > 0 || currentResolverHint.length > 0 || slashableStakeHints.length > 0) {
            return abi.encode(
                ExecuteSlashHints({
                    captureResolverHint: captureResolverHint,
                    currentResolverHint: currentResolverHint,
                    slashableStakeHints: slashableStakeHints
                })
            );
        }
    }

    function vetoSlashHints(
        address slasher,
        bytes32 subnetwork,
        uint48 captureTimestamp
    ) external view returns (bytes memory) {
        bytes memory captureResolverHint = resolverHint(slasher, subnetwork, captureTimestamp);
        bytes memory currentResolverHint = resolverHint(slasher, subnetwork, Time.timestamp() - 1);

        if (captureResolverHint.length > 0 || currentResolverHint.length > 0) {
            return abi.encode(
                VetoSlashHints({captureResolverHint: captureResolverHint, currentResolverHint: currentResolverHint})
            );
        }
    }

    function setResolverHints(
        address slasher,
        bytes32 subnetwork,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory resolverHint_ = resolverHint(slasher, subnetwork, timestamp);

        if (resolverHint_.length > 0) {
            return abi.encode(SetResolverHints({resolverHint: resolverHint_}));
        }
    }
}
