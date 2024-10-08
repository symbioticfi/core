// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {IOptInService} from "../../interfaces/service/IOptInService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OptInService is StaticDelegateCallable, EIP712, IOptInService {
    using Checkpoints for Checkpoints.Trace208;

    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHO_REGISTRY;

    /**
     * @inheritdoc IOptInService
     */
    address public immutable WHERE_REGISTRY;

    bytes32 private constant OPT_IN_TYPEHASH =
        keccak256("OptIn(address who,address where,uint256 nonce,uint48 deadline)");

    bytes32 private constant OPT_OUT_TYPEHASH =
        keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)");

    /**
     * @inheritdoc IOptInService
     */
    mapping(address who => mapping(address where => uint256 nonce)) public nonces;

    mapping(address who => mapping(address where => Checkpoints.Trace208 value)) internal _isOptedIn;

    modifier checkDeadline(
        uint48 deadline
    ) {
        if (deadline < Time.timestamp()) {
            revert ExpiredSignature();
        }
        _;
    }

    constructor(address whoRegistry, address whereRegistry, string memory name) EIP712(name, "1") {
        WHO_REGISTRY = whoRegistry;
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc IOptInService
     */
    function isOptedInAt(
        address who,
        address where,
        uint48 timestamp,
        bytes calldata hint
    ) external view returns (bool) {
        return _isOptedIn[who][where].upperLookupRecent(timestamp, hint) == 1;
    }

    /**
     * @inheritdoc IOptInService
     */
    function isOptedIn(address who, address where) public view returns (bool) {
        return _isOptedIn[who][where].latest() == 1;
    }

    /**
     * @inheritdoc IOptInService
     */
    function optIn(
        address where
    ) external {
        _optIn(msg.sender, where);
    }

    /**
     * @inheritdoc IOptInService
     */
    function optIn(
        address who,
        address where,
        uint48 deadline,
        bytes calldata signature
    ) external checkDeadline(deadline) {
        if (!SignatureChecker.isValidSignatureNow(who, _hash(true, who, where, deadline), signature)) {
            revert InvalidSignature();
        }

        _optIn(who, where);
    }

    /**
     * @inheritdoc IOptInService
     */
    function optOut(
        address where
    ) external {
        _optOut(msg.sender, where);
    }

    /**
     * @inheritdoc IOptInService
     */
    function optOut(
        address who,
        address where,
        uint48 deadline,
        bytes calldata signature
    ) external checkDeadline(deadline) {
        if (!SignatureChecker.isValidSignatureNow(who, _hash(false, who, where, deadline), signature)) {
            revert InvalidSignature();
        }

        _optOut(who, where);
    }

    /**
     * @inheritdoc IOptInService
     */
    function increaseNonce(
        address where
    ) external {
        _increaseNonce(msg.sender, where);
    }

    function _optIn(address who, address where) internal {
        if (!IRegistry(WHO_REGISTRY).isEntity(who)) {
            revert NotWho();
        }

        if (!IRegistry(WHERE_REGISTRY).isEntity(where)) {
            revert NotWhereEntity();
        }

        if (isOptedIn(who, where)) {
            revert AlreadyOptedIn();
        }

        _isOptedIn[who][where].push(Time.timestamp(), 1);

        _increaseNonce(who, where);

        emit OptIn(who, where);
    }

    function _optOut(address who, address where) internal {
        (, uint48 latestTimestamp, uint208 latestValue) = _isOptedIn[who][where].latestCheckpoint();

        if (latestValue == 0) {
            revert NotOptedIn();
        }

        if (latestTimestamp == Time.timestamp()) {
            revert OptOutCooldown();
        }

        _isOptedIn[who][where].push(Time.timestamp(), 0);

        _increaseNonce(who, where);

        emit OptOut(who, where);
    }

    function _hash(bool ifOptIn, address who, address where, uint48 deadline) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(ifOptIn ? OPT_IN_TYPEHASH : OPT_OUT_TYPEHASH, who, where, nonces[who][where], deadline)
            )
        );
    }

    function _increaseNonce(address who, address where) internal {
        unchecked {
            ++nonces[who][where];
        }

        emit IncreaseNonce(who, where);
    }
}
