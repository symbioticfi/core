// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Hints} from "../../src/contracts/hints/Hints.sol";
import {VaultV2Storage} from "../../src/contracts/vault/VaultV2Storage.sol";
import {Checkpoints} from "../../src/contracts/libraries/CheckpointsV2.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

contract VaultV2TestHelper is VaultV2Storage, Hints {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;

    constructor() VaultV2Storage(address(0), address(0), address(0), address(0), address(0)) {}

    function _unlockToBucketLatestInternal() external view internalFunction returns (uint208) {
        return _unlockToBucket.latest();
    }

    function _unlockToBucketUpperLookupRecentInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (uint208)
    {
        return _unlockToBucket.upperLookupRecent(timestamp);
    }

    function _unlockToBucketUpperLookupRecentCheckpointInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _unlockToBucket.upperLookupRecentCheckpoint(timestamp);
    }

    function _unlockToBucketAtInternal(uint32 pos) external view internalFunction returns (uint48, uint208) {
        Checkpoints.Checkpoint208 memory checkpoint = _unlockToBucket.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _unlockToBucketLengthInternal() external view internalFunction returns (uint256) {
        return _unlockToBucket.length();
    }

    function _withdrawalSharesCumulativeLatestInternal() external view internalFunction returns (uint256) {
        return _withdrawalSharesCumulative.latest();
    }

    function _withdrawalSharesCumulativeUpperLookupRecentInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawalSharesCumulative.upperLookupRecent(timestamp);
    }

    function _withdrawalSharesCumulativeUpperLookupRecentCheckpointInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _withdrawalSharesCumulative.upperLookupRecentCheckpoint(timestamp);
    }

    function _withdrawalSharesCumulativeOfUpperLookupRecentCheckpointInternal(address account, uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _withdrawalSharesCumulativeOf[account].upperLookupRecentCheckpoint(timestamp);
    }

    function _withdrawalSharesUpperLookupRecentInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawalShares[bucket].upperLookupRecent(timestamp);
    }

    function _withdrawalSharesUpperLookupRecentCheckpointInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _withdrawalShares[bucket].upperLookupRecentCheckpoint(timestamp);
    }

    function _withdrawalsUpperLookupRecentInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawals[bucket].upperLookupRecent(timestamp);
    }

    function _withdrawalsUpperLookupRecentCheckpointInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _withdrawals[bucket].upperLookupRecentCheckpoint(timestamp);
    }

    function _withdrawalSharesCumulativeAtInternal(uint32 pos)
        external
        view
        internalFunction
        returns (uint48, uint256)
    {
        Checkpoints.Checkpoint256 memory checkpoint = _withdrawalSharesCumulative.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _withdrawalSharesCumulativeLengthInternal() external view internalFunction returns (uint256) {
        return _withdrawalSharesCumulative.length();
    }

    function _unclaimedRawInternal() external view internalFunction returns (int256) {
        return _unclaimedRaw;
    }

    function unlockToBucketLatest(address vault) external view returns (uint208) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._unlockToBucketLatestInternal, ())),
            (uint208)
        );
    }

    function unlockToBucketUpperLookupRecent(address vault, uint48 timestamp) public view returns (uint208) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._unlockToBucketUpperLookupRecentInternal, (timestamp))
            ),
            (uint208)
        );
    }

    function unlockToBucketHint(address vault, uint48 timestamp) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._unlockToBucketUpperLookupRecentCheckpointInternal, (timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function unlockToBucketAt(address vault, uint32 pos) external view returns (uint48, uint208) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._unlockToBucketAtInternal, (pos))),
            (uint48, uint208)
        );
    }

    function unlockToBucketLength(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._unlockToBucketLengthInternal, ())),
            (uint256)
        );
    }

    function withdrawalSharesCumulativeLatest(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalSharesCumulativeLatestInternal, ())
            ),
            (uint256)
        );
    }

    function unclaimedRaw(address vault) external view returns (int256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._unclaimedRawInternal, ())),
            (int256)
        );
    }

    function withdrawalSharesCumulativeUpperLookupRecent(address vault, uint48 timestamp)
        external
        view
        returns (uint256)
    {
        return abi.decode(
            _selfStaticDelegateCall(
                vault,
                abi.encodeCall(VaultV2TestHelper._withdrawalSharesCumulativeUpperLookupRecentInternal, (timestamp))
            ),
            (uint256)
        );
    }

    function withdrawalSharesCumulativeHint(address vault, uint48 timestamp) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault,
                abi.encodeCall(
                    VaultV2TestHelper._withdrawalSharesCumulativeUpperLookupRecentCheckpointInternal, (timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function withdrawalSharesUpperLookupRecent(address vault, uint208 bucket, uint48 timestamp)
        external
        view
        returns (uint256)
    {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalSharesUpperLookupRecentInternal, (bucket, timestamp))
            ),
            (uint256)
        );
    }

    function withdrawalSharesHint(address vault, uint208 bucket, uint48 timestamp)
        public
        view
        returns (bytes memory hint)
    {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault,
                abi.encodeCall(
                    VaultV2TestHelper._withdrawalSharesUpperLookupRecentCheckpointInternal, (bucket, timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function withdrawalsUpperLookupRecent(address vault, uint208 bucket, uint48 timestamp)
        external
        view
        returns (uint256)
    {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalsUpperLookupRecentInternal, (bucket, timestamp))
            ),
            (uint256)
        );
    }

    function withdrawalsHint(address vault, uint208 bucket, uint48 timestamp) public view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault,
                abi.encodeCall(VaultV2TestHelper._withdrawalsUpperLookupRecentCheckpointInternal, (bucket, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }

    function withdrawalSharesCumulativeAt(address vault, uint32 pos) external view returns (uint48, uint256) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalSharesCumulativeAtInternal, (pos))
            ),
            (uint48, uint256)
        );
    }

    function withdrawalSharesCumulativeLength(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalSharesCumulativeLengthInternal, ())
            ),
            (uint256)
        );
    }

    function withdrawalSharesCumulativeOfHint(address vault, address account, uint48 timestamp)
        public
        view
        returns (bytes memory hint)
    {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault,
                abi.encodeCall(
                    VaultV2TestHelper._withdrawalSharesCumulativeOfUpperLookupRecentCheckpointInternal,
                    (account, timestamp)
                )
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }
}
