// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IThreeFAdapter, MAX_REQUESTS} from "../../interfaces/adapters/IThreeFAdapter.sol";
import {IThreeFRequest} from "../../interfaces/adapters/3f-adapter/IThreeFRequest.sol";
import {IThreeFRequestCallback} from "../../interfaces/adapters/3f-adapter/IThreeFRequestCallback.sol";
import {IThreeFWhitelist} from "../../interfaces/adapters/3f-adapter/IThreeFWhitelist.sol";
import {Offer, YIELD_PRECISION} from "../../interfaces/adapters/3f-adapter/ThreeFTypes.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title ThreeFAdapter
/// @notice VaultV2 adapter for 3F bridge facilitator requests.
contract ThreeFAdapter is Adapter, IThreeFAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IThreeFAdapter
    address public immutable REQUEST_WHITELIST;

    /* STATE VARIABLES */

    /// @inheritdoc IThreeFAdapter
    address public offerSigner;
    /// @inheritdoc IThreeFAdapter
    uint256 public minYieldPerRequest;
    /// @inheritdoc IThreeFAdapter
    uint256 public minAssetsPerRequest;
    /// @inheritdoc IThreeFAdapter
    uint256 public maxAssetsPerRequest;

    /// @inheritdoc IThreeFAdapter
    address[] public requests;
    /// @inheritdoc IThreeFAdapter
    mapping(address request => uint256 index) public requestIndex;

    /// @dev Opens allocatable capacity only during the just-in-time request callback.
    bool internal transient _inConsume;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address requestWhitelist)
        Adapter(vaultFactory, adapterFactory)
    {
        REQUEST_WHITELIST = requestWhitelist;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view returns (bytes4) {
        return SignatureChecker.isValidSignatureNow(offerSigner, hash, signature)
            ? IERC1271.isValidSignature.selector
            : bytes4(0xffffffff);
    }

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        return _inConsume ? super.allocatable() : 0;
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256 assets) {
        assets = freeAssets();
        uint256 length = requests.length;
        for (uint256 i; i < length; ++i) {
            address request = requests[i];
            if (IThreeFRequest(request).canWithdraw()) {
                (uint256 ptShares, uint256 ytShares) = IThreeFRequest(request).balancesOf(address(this));
                (uint256 pAssets, uint256 yAssets) = IThreeFRequest(request).convertToAssets(ptShares, ytShares);
                assets += pAssets + yAssets;
            } else {
                (uint256 ptShares,) = IThreeFRequest(request).balancesOf(address(this));
                assets += ptShares;
            }
        }
    }

    /// @inheritdoc IThreeFAdapter
    function getMaxAssets() public returns (uint256 assets) {
        address delegator = IVaultV2(vault).delegator();
        if (IUniversalDelegator(delegator).sweepPending() > 0) {
            return 0;
        }
        return Math.min(
            IUniversalDelegator(delegator).limitOf(address(this)).saturatingSub(totalAssets()),
            IVaultV2(vault).withdrawable()
        );
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc IThreeFAdapter
    function setOfferSigner(address newOfferSigner) public onlyOwner {
        offerSigner = newOfferSigner;

        emit SetOfferSigner(newOfferSigner);
    }

    /// @inheritdoc IThreeFAdapter
    function setLimitsPerRequest(
        uint256 newMinYieldPerRequest,
        uint256 newMinAssetsPerRequest,
        uint256 newMaxAssetsPerRequest
    ) public onlyOwner {
        minYieldPerRequest = newMinYieldPerRequest;
        minAssetsPerRequest = newMinAssetsPerRequest;
        maxAssetsPerRequest = newMaxAssetsPerRequest;

        emit SetLimitsPerRequest(newMinYieldPerRequest, newMinAssetsPerRequest, newMaxAssetsPerRequest);
    }

    /* PUBLIC FUNCTIONS (3F REQUEST) */

    /// @inheritdoc IThreeFRequestCallback
    function onRequestConsumed(Offer calldata offer, bytes calldata, uint256 principalAssets, uint256 yieldAssets)
        public
    {
        if (requests.length >= MAX_REQUESTS) {
            revert TooManyRequests();
        }
        if (requestIndex[msg.sender] > 0) {
            revert AlreadyRequest();
        }
        if (principalAssets < minAssetsPerRequest) {
            revert TooSmallRequest();
        }
        if (principalAssets > maxAssetsPerRequest) {
            revert TooLargeRequest();
        }
        if (principalAssets > 0 && yieldAssets.mulDiv(YIELD_PRECISION, principalAssets) < minYieldPerRequest) {
            revert TooLowYield();
        }

        if (
            IThreeFWhitelist(REQUEST_WHITELIST).isWhitelisted(msg.sender)
                != IThreeFWhitelist.WhitelistStatus.Whitelisted
        ) {
            revert NotRequest();
        }

        address asset = IERC4626(vault).asset();
        if (asset != IThreeFRequest(msg.sender).asset()) {
            revert WrongAsset();
        }

        if (principalAssets > 0) {
            _inConsume = true;
            if (
                IUniversalDelegator(IVaultV2(vault).delegator()).allocateExact(address(this), principalAssets)
                    < principalAssets
            ) {
                revert InsufficientAllocate();
            }
            _inConsume = false;

            IERC20(asset).forceApprove(msg.sender, principalAssets);
        }

        requests.push(msg.sender);
        requestIndex[msg.sender] = requests.length;

        emit OnRequestConsumed(msg.sender, offer, principalAssets, yieldAssets);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IThreeFAdapter
    function finalizeRequest(address request) public nonReentrant {
        address lastRequest = requests[requests.length - 1];
        uint256 index = requestIndex[request];
        requests.pop();
        requestIndex[request] = 0;
        if (request != lastRequest) {
            requests[index - 1] = lastRequest;
            requestIndex[lastRequest] = index;
        }

        IThreeFRequest(request).burnAll(address(this), address(this));

        emit FinalizeRequest(request);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Marks just-in-time assets transferred into the adapter as allocated.
    function _allocate(uint256 amount) internal override returns (uint256) {
        return amount;
    }

    /// @dev Live 3F request principal is illiquid until request finalization.
    function _deallocate(uint256) internal override returns (uint256) {
        return 0;
    }
}
