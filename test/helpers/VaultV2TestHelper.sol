// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Hints} from "../../src/contracts/hints/Hints.sol";
import {VaultV2Storage} from "../../src/contracts/vault/VaultV2Storage.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

contract VaultV2TestHelper is VaultV2Storage, Hints {
    using Checkpoints for Checkpoints.Trace256;

    constructor() VaultV2Storage(address(0), address(0), address(0), address(0), address(0)) {}

    function _cumulSharesToBucketLatestInternal() external view internalFunction returns (uint256) {
        return _cumulSharesToBucket.latest();
    }

    function _cumulSharesToBucketUpperLookupRecentInternal(uint256 shares)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _cumulSharesToBucket.upperLookupRecent(shares);
    }

    function _cumulSharesToBucketAtInternal(uint32 pos) external view internalFunction returns (uint256, uint256) {
        Checkpoints.Checkpoint256 memory checkpoint = _cumulSharesToBucket.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _cumulSharesToBucketLengthInternal() external view internalFunction returns (uint256) {
        return _cumulSharesToBucket.length();
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

    function _withdrawalSharesUpperLookupRecentInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawalShares[bucket].upperLookupRecent(timestamp);
    }

    function _withdrawalsUpperLookupRecentInternal(uint208 bucket, uint48 timestamp)
        external
        view
        internalFunction
        returns (uint256)
    {
        return _withdrawals[bucket].upperLookupRecent(timestamp);
    }

    function _withdrawalSharesCumulativeAtInternal(uint32 pos)
        external
        view
        internalFunction
        returns (uint256, uint256)
    {
        Checkpoints.Checkpoint256 memory checkpoint = _withdrawalSharesCumulative.at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    function _withdrawalSharesCumulativeLengthInternal() external view internalFunction returns (uint256) {
        return _withdrawalSharesCumulative.length();
    }

    function cumulSharesToBucketLatest(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._cumulSharesToBucketLatestInternal, ())),
            (uint256)
        );
    }

    function cumulSharesToBucketUpperLookupRecent(address vault, uint256 shares) public view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._cumulSharesToBucketUpperLookupRecentInternal, (shares))
            ),
            (uint256)
        );
    }

    function cumulSharesToBucketAt(address vault, uint32 pos) external view returns (uint256, uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._cumulSharesToBucketAtInternal, (pos))),
            (uint256, uint256)
        );
    }

    function cumulSharesToBucketLength(address vault) external view returns (uint256) {
        return abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultV2TestHelper._cumulSharesToBucketLengthInternal, ())),
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

    function withdrawalSharesCumulativeAt(address vault, uint32 pos) external view returns (uint256, uint256) {
        return abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeCall(VaultV2TestHelper._withdrawalSharesCumulativeAtInternal, (pos))
            ),
            (uint256, uint256)
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
}
