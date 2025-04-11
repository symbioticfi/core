// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseDelegatorHints} from "./DelegatorHints.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {Hints} from "./Hints.sol";
import {ISlasher} from "../../interfaces/slasher/ISlasher.sol";
import {IVaultStorage} from "../../interfaces/vault/IVaultStorage.sol";
import {IVetoSlasher} from "../../interfaces/slasher/IVetoSlasher.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract BaseSlasherHints is Hints {
    using Checkpoints for Checkpoints.Trace256;

    address public immutable BASE_DELEGATOR_HINTS;
    address public immutable SLASHER_HINTS;
    address public immutable VETO_SLASHER_HINTS;

    address public vault;
    bool public isBurnerHook;
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

    constructor(
        address baseDelegatorHints
    ) {
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
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher, abi.encodeCall(BaseSlasherHints.cumulativeSlashHintInternal, (subnetwork, operator, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function slashableStakeHints(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory hints) {
        bytes memory stakeHints = BaseDelegatorHints(BASE_DELEGATOR_HINTS).stakeHints(
            IVaultStorage(IBaseSlasher(slasher).vault()).delegator(), subnetwork, operator, captureTimestamp
        );

        bytes memory cumulativeSlashFromHint = cumulativeSlashHint(slasher, subnetwork, operator, captureTimestamp);

        if (stakeHints.length > 0 || cumulativeSlashFromHint.length > 0) {
            hints = abi.encode(
                IBaseSlasher.SlashableStakeHints({
                    stakeHints: stakeHints,
                    cumulativeSlashFromHint: cumulativeSlashFromHint
                })
            );
        }
    }
}

contract SlasherHints is Hints {
    address public immutable BASE_SLASHER_HINTS;

    address public vault;
    bool public isBurnerHook;
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

    constructor(
        address baseSlasherHints
    ) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function slashHints(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory hints) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            hints = abi.encode(ISlasher.SlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }
}

contract VetoSlasherHints is Hints {
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    address public immutable BASE_SLASHER_HINTS;

    address public vault;
    bool public isBurnerHook;
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp;
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

    IVetoSlasher.SlashRequest[] public slashRequests;
    uint48 public vetoDuration;
    uint256 public resolverSetEpochsDelay;
    mapping(bytes32 subnetwork => Checkpoints.Trace208 value) internal _resolver;

    constructor(
        address baseSlasherHints
    ) {
        BASE_SLASHER_HINTS = baseSlasherHints;
    }

    function resolverHintInternal(
        bytes32 subnetwork,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _resolver[subnetwork].upperLookupRecentCheckpoint(timestamp);
    }

    function resolverHint(
        address slasher,
        bytes32 subnetwork,
        uint48 timestamp
    ) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                slasher, abi.encodeCall(VetoSlasherHints.resolverHintInternal, (subnetwork, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function requestSlashHints(
        address slasher,
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) external view returns (bytes memory hints) {
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (slashableStakeHints.length > 0) {
            hints = abi.encode(IVetoSlasher.RequestSlashHints({slashableStakeHints: slashableStakeHints}));
        }
    }

    function executeSlashHints(address slasher, uint256 slashIndex) external view returns (bytes memory hints) {
        (bytes32 subnetwork, address operator,, uint48 captureTimestamp,,) =
            IVetoSlasher(slasher).slashRequests(slashIndex);

        bytes memory captureResolverHint = resolverHint(slasher, subnetwork, captureTimestamp);
        bytes memory currentResolverHint = resolverHint(slasher, subnetwork, Time.timestamp() - 1);
        bytes memory slashableStakeHints =
            BaseSlasherHints(BASE_SLASHER_HINTS).slashableStakeHints(slasher, subnetwork, operator, captureTimestamp);

        if (captureResolverHint.length > 0 || currentResolverHint.length > 0 || slashableStakeHints.length > 0) {
            hints = abi.encode(
                IVetoSlasher.ExecuteSlashHints({
                    captureResolverHint: captureResolverHint,
                    currentResolverHint: currentResolverHint,
                    slashableStakeHints: slashableStakeHints
                })
            );
        }
    }

    function vetoSlashHints(address slasher, uint256 slashIndex) external view returns (bytes memory hints) {
        (bytes32 subnetwork,,, uint48 captureTimestamp,,) = IVetoSlasher(slasher).slashRequests(slashIndex);

        bytes memory captureResolverHint = resolverHint(slasher, subnetwork, captureTimestamp);
        bytes memory currentResolverHint = resolverHint(slasher, subnetwork, Time.timestamp() - 1);

        if (captureResolverHint.length > 0 || currentResolverHint.length > 0) {
            hints = abi.encode(
                IVetoSlasher.VetoSlashHints({
                    captureResolverHint: captureResolverHint,
                    currentResolverHint: currentResolverHint
                })
            );
        }
    }

    function setResolverHints(
        address slasher,
        bytes32 subnetwork,
        uint48 timestamp
    ) external view returns (bytes memory hints) {
        bytes memory resolverHint_ = resolverHint(slasher, subnetwork, timestamp);

        if (resolverHint_.length > 0) {
            hints = abi.encode(IVetoSlasher.SetResolverHints({resolverHint: resolverHint_}));
        }
    }
}
