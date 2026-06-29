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

    /* VIEW FUNCTIONS */

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view returns (bytes4) {
        if (offerSigner != address(0) && SignatureChecker.isValidSignatureNow(offerSigner, hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }

        return 0xffffffff;
    }

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
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256 assets) {
        assets = freeAssets() + outstandingPrincipal;
    }

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc IThreeFAdapter
    function setOfferSigner(address signer) public onlyOwner {
        offerSigner = signer;

        emit SetOfferSigner(signer);
    }

    /// @inheritdoc IThreeFAdapter
    function setExposureLimits(uint256 perRequestMaxCollateral_, uint256 minRequestYield_) public onlyOwner {
        perRequestMaxCollateral = perRequestMaxCollateral_;
        minRequestYield = minRequestYield_;

        emit SetExposureLimits(perRequestMaxCollateral_, minRequestYield_);
    }

    /* PUBLIC FUNCTIONS (3F REQUEST) */

    /// @inheritdoc IThreeFRequestCallback
    function onRequestConsumed(Offer calldata, bytes calldata, uint256 principal, uint256 yieldAmount) public {
        if (
            IThreeFWhitelist(REQUEST_WHITELIST).isWhitelisted(msg.sender)
                != IThreeFWhitelist.WhitelistStatus.Whitelisted
        ) {
            revert NotAttested();
        }

        address asset = IERC4626(vault).asset();
        if (IThreeFRequest(msg.sender).asset() != asset) {
            revert AssetMismatch();
        }
        if (_activeRequests.contains(msg.sender)) {
            revert RequestAlreadyActive();
        }
        if (perRequestMaxCollateral > 0 && principal > perRequestMaxCollateral) {
            revert PerRequestCapExceeded();
        }
        if (minRequestYield > 0 && yieldAmount < principal.mulDiv(minRequestYield, YIELD_PRECISION, Math.Rounding.Ceil))
        {
            revert YieldTooLow();
        }

        uint256 freeAssets = freeAssets();
        if (freeAssets < principal) {
            uint256 missingAssets = principal - freeAssets;

            _inConsume = true;
            uint256 pulled =
                IUniversalDelegator(IVaultV2(vault).delegator()).allocateExact(address(this), missingAssets);
            _inConsume = false;

            if (pulled < missingAssets) {
                revert InsufficientLiquidity();
            }
        }

        realizedPrincipal = realizedPrincipal.saturatingSub(Math.min(principal, freeAssets));

        IERC20(asset).forceApprove(msg.sender, principal);

        positions[msg.sender] = Position(principal, yieldAmount, uint48(block.timestamp), false);
        _activeRequests.add(msg.sender);
        outstandingPrincipal += principal;

        emit PositionOpened(msg.sender, principal, yieldAmount);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IThreeFAdapter
    function redeem(address[] calldata requests) public nonReentrant {
        uint256 length = requests.length;
        for (uint256 i; i < length; ++i) {
            address request = requests[i];
            if (!_activeRequests.contains(request) || !IThreeFVaultController(request).canWithdraw()) {
                continue;
            }

            (,, uint256 pAssets, uint256 yAssets) =
                IThreeFVaultController(request).burnAll(address(this), address(this));

            outstandingPrincipal -= positions[request].principal;
            realizedPrincipal += pAssets;
            positions[request].redeemed = true;
            _activeRequests.remove(request);

            emit PositionRedeemed(request, pAssets, yAssets);
        }
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
