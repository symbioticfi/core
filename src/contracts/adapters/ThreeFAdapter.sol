// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {
    IThreeFAdapter,
    IThreeFRequest,
    IThreeFRequestCallback,
    IThreeFVaultController,
    IThreeFWhitelist,
    Offer,
    YIELD_PRECISION
} from "../../interfaces/adapters/IThreeFAdapter.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title ThreeFAdapter
/// @notice VaultV2 adapter for 3F bridge facilitator requests.
contract ThreeFAdapter is Adapter, IThreeFAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* IMMUTABLES */

    /// @inheritdoc IThreeFAdapter
    address public immutable REQUEST_WHITELIST;

    /* STATE VARIABLES */

    /// @inheritdoc IThreeFAdapter
    address public offerSigner;
    /// @inheritdoc IThreeFAdapter
    mapping(address request => Position) public positions;
    /// @inheritdoc IThreeFAdapter
    uint256 public realizedPrincipal;
    /// @inheritdoc IThreeFAdapter
    uint256 public outstandingPrincipal;
    /// @inheritdoc IThreeFAdapter
    uint256 public perRequestMaxCollateral;
    /// @inheritdoc IThreeFAdapter
    uint256 public minRequestYield;
    /// @inheritdoc IThreeFAdapter
    uint256 public maxConcurrentLoans;

    /// @dev Open (consumed, unredeemed) requests; backs isRequest/activeLoans/activeRequests.
    EnumerableSet.AddressSet private _activeRequests;

    /// @dev Opens allocatable capacity only during the just-in-time request callback.
    bool internal transient _inConsume;

    /* CONSTRUCTOR */

    constructor(address requestWhitelist, address adapterFactory, address vaultFactory)
        Adapter(vaultFactory, adapterFactory)
    {
        REQUEST_WHITELIST = requestWhitelist;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IThreeFAdapter
    function setOfferSigner(address signer) public onlyOwner {
        offerSigner = signer;

        emit SetOfferSigner(signer);
    }

    /// @inheritdoc IThreeFAdapter
    function setExposureLimits(uint256 perRequestMaxCollateral_, uint256 minRequestYield_, uint256 maxConcurrentLoans_)
        public
        onlyOwner
    {
        perRequestMaxCollateral = perRequestMaxCollateral_;
        minRequestYield = minRequestYield_;
        maxConcurrentLoans = maxConcurrentLoans_;

        emit SetExposureLimits(perRequestMaxCollateral_, minRequestYield_, maxConcurrentLoans_);
    }

    /// @inheritdoc IThreeFRequestCallback
    function onRequestConsumed(Offer calldata, bytes calldata, uint256 principal, uint256 yieldAmount) public {
        if (
            IThreeFWhitelist(REQUEST_WHITELIST).isWhitelisted(msg.sender)
                != IThreeFWhitelist.WhitelistStatus.Whitelisted
        ) {
            revert NotAttested();
        }
        if (IThreeFRequest(msg.sender).asset() != IERC4626(vault).asset()) {
            revert AssetMismatch();
        }
        if (perRequestMaxCollateral > 0 && principal > perRequestMaxCollateral) {
            revert PerRequestCapExceeded();
        }
        if (minRequestYield > 0 && yieldAmount < principal.mulDiv(minRequestYield, YIELD_PRECISION, Math.Rounding.Ceil))
        {
            revert YieldTooLow();
        }
        if (maxConcurrentLoans > 0 && _activeRequests.length() >= maxConcurrentLoans) {
            revert TooManyLoans();
        }

        uint256 freeAssets = freeAssets();
        if (freeAssets < principal) {
            _inConsume = true;
            uint256 pulled =
                IUniversalDelegator(IVaultV2(vault).delegator()).allocateExact(address(this), principal - freeAssets);
            _inConsume = false;

            if (pulled < principal - freeAssets) {
                revert InsufficientLiquidity();
            }
        }

        realizedPrincipal = realizedPrincipal.saturatingSub(Math.min(principal, freeAssets));

        IERC20(IERC4626(vault).asset()).forceApprove(msg.sender, principal);

        positions[msg.sender] = Position(principal, yieldAmount, uint48(block.timestamp), false);
        _activeRequests.add(msg.sender);
        outstandingPrincipal += principal;

        emit PositionOpened(msg.sender, principal, yieldAmount);
    }

    /// @inheritdoc IThreeFAdapter
    function redeem(address[] calldata requests) public nonReentrant {
        for (uint256 i; i < requests.length; ++i) {
            if (!_activeRequests.contains(requests[i]) || !IThreeFVaultController(requests[i]).canWithdraw()) {
                continue;
            }

            (,, uint256 pAssets, uint256 yAssets) =
                IThreeFVaultController(requests[i]).burnAll(address(this), address(this));

            outstandingPrincipal -= positions[requests[i]].principal;
            realizedPrincipal += pAssets;
            positions[requests[i]].redeemed = true;
            _activeRequests.remove(requests[i]);

            emit PositionRedeemed(requests[i], pAssets, yAssets);
        }
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view returns (bytes4) {
        if (offerSigner != address(0) && SignatureChecker.isValidSignatureNow(offerSigner, hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }

        return 0xffffffff;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IThreeFAdapter
    function isRequest(address request) public view returns (bool) {
        return _activeRequests.contains(request);
    }

    /// @inheritdoc IThreeFAdapter
    function activeLoans() public view returns (uint256) {
        return _activeRequests.length();
    }

    /// @inheritdoc IThreeFAdapter
    function activeRequests() public view returns (address[] memory) {
        return _activeRequests.values();
    }

    /// @inheritdoc IAdapter
    function allocatable() public view override(Adapter, IAdapter) returns (uint256) {
        return _inConsume ? super.allocatable() : 0;
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + outstandingPrincipal;
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public override(Adapter, IAdapter) onlyDelegator returns (uint256 deallocated) {
        deallocated = super.deallocate(amount);
        realizedPrincipal = realizedPrincipal.saturatingSub(deallocated);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Marks just-in-time assets transferred into the adapter as allocated.
    function _allocate(uint256 amount) internal pure override returns (uint256) {
        return amount;
    }

    /// @dev Live 3F request principal is illiquid until request redemption.
    function _deallocate(uint256) internal pure override returns (uint256) {
        return 0;
    }
}
