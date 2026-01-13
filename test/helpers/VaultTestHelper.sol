// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Hints} from "../../src/contracts/hints/Hints.sol";
import {VaultStorage} from "../../src/contracts/vault/VaultStorage.sol";
import {Checkpoints} from "../../src/contracts/libraries/Checkpoints.sol";

contract VaultTestHelper is VaultStorage, Hints {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;

    constructor() VaultStorage(address(0), address(0)) {}

    function _timeToBucketLatestInternal() external view internalFunction returns (uint208) {
        return _timeToBucket.latest();
    }

    function _timeToBucketAtInternal(uint32 pos) external view internalFunction returns (uint48, uint208) {
        Checkpoints.Checkpoint208 memory checkpoint = _timeToBucket.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _timeToBucketLengthInternal() external view internalFunction returns (uint256) {
        return _timeToBucket.length();
    }

    function _withdrawalSharesPrefixesLatestInternal() external view internalFunction returns (uint256) {
        return _withdrawalSharesPrefixes.latest();
    }

    function _withdrawalSharesPrefixesUpperLookupRecentInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawalSharesPrefixes.upperLookupRecent(timestamp);
    }

    function _withdrawalSharesPrefixesAtInternal(uint32 pos) external view internalFunction returns (uint48, uint256) {
        Checkpoints.Checkpoint256 memory checkpoint = _withdrawalSharesPrefixes.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _withdrawalSharesPrefixesLengthInternal() external view internalFunction returns (uint256) {
        return _withdrawalSharesPrefixes.length();
    }

    function timeToBucketLatest(address vault) external view returns (uint208) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._timeToBucketLatestInternal, ())), (uint208)
        );
    }

    function timeToBucketAt(address vault, uint32 pos) external view returns (uint48, uint208) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._timeToBucketAtInternal, (pos))),
            (uint48, uint208)
        );
    }

    function timeToBucketLength(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._timeToBucketLengthInternal, ())), (uint256)
        );
    }

    function withdrawalSharesPrefixesLatest(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._withdrawalSharesPrefixesLatestInternal, ())),
            (uint256)
        );
    }

    function withdrawalSharesPrefixesUpperLookupRecent(address vault, uint48 timestamp)
        external
        view
        returns (uint256)
    {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultTestHelper._withdrawalSharesPrefixesUpperLookupRecentInternal, (timestamp))
            ),
            (uint256)
        );
    }

    function withdrawalSharesPrefixesAt(address vault, uint32 pos) external view returns (uint48, uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._withdrawalSharesPrefixesAtInternal, (pos))),
            (uint48, uint256)
        );
    }

    function withdrawalSharesPrefixesLength(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultTestHelper._withdrawalSharesPrefixesLengthInternal, ())),
            (uint256)
        );
    }
}
