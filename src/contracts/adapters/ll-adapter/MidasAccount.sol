// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";
import {CutoffAccount} from "./common/CutoffAccount.sol";

import {AggregatorV3Interface} from "./oracles/libraries/ChainlinkPriceFeed.sol";

import {IMidasAccount, REQUEST_STATUS_PENDING} from "../../../interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasDataFeed, IMidasOracle} from "../../../interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {IMidasRedemptionVault} from "../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DateTimeLib} from "solady/utils/DateTimeLib.sol";

/// @title MidasAccount
/// @notice Base account for Midas redemption integrations.
abstract contract MidasAccount is CooldownAccount, IMidasAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_TOKEN;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_VAULT;

    /* STATE VARIABLES */

    /// @inheritdoc IMidasAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        REDEMPTION_TOKEN = redemptionToken;
        REDEMPTION_VAULT = redemptionVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value in vault assets.
    function _pendingAssets() internal view virtual returns (uint256);

    /// @dev Returns held fallback redemption-token value plus pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        if (REDEMPTION_TOKEN != _asset) {
            assets += _redemptionTokenToAssets(REDEMPTION_TOKEN, IERC20(REDEMPTION_TOKEN).balanceOf(address(this)));
        }

        assets += _pendingAssets();
    }

    /// @dev Clears Midas redemption requests that are no longer pending.
    function _finalizeRequests() internal virtual override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i - 1]);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            requestIds[i - 1] = requestIds[requestIds.length - 1];
            requestIds.pop();
        }
    }

    /// @dev Submits held token-to-redeem inventory to the Midas redemption vault.
    function _requestRedeem() internal virtual override returns (bool) {
        (address dataFeed,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).tokensConfig(_asset);
        requestIds.push(
            uint64(
                IMidasRedemptionVault(REDEMPTION_VAULT)
                    .redeemRequest(
                        dataFeed == address(0) ? REDEMPTION_TOKEN : _asset,
                        IERC20(TOKEN_TO_REDEEM).balanceOf(address(this))
                    )
            )
        );
        return true;
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal virtual override {
        super._initialize(initialVersion, initOwner, data);

        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_VAULT, type(uint256).max);
    }
}

/// @title MidasCompAccount
/// @notice Midas account that prices pending requests at the current oracle rate.
contract MidasCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the compounding Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using the current oracle rate.
    function _pendingAssets() internal view override returns (uint256) {
        uint256 amount;
        for (uint256 i; i < requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken,,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                amount += amountMToken;
            }
        }
        return _tokenToRedeemToAssets(amount);
    }
}

/// @title MidasNonCompAccount
/// @notice Midas account that prices pending requests at their creation-time rate.
contract MidasNonCompAccount is MidasAccount {
    using Math for uint256;

    /* CONSTRUCTOR */

    /// @notice Creates the non-compounding Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using each request's locked rate.
    function _pendingAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken, uint256 mTokenRate, uint256 tokenOutRate) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                assets += _tokenToRedeemToAssets(amountMToken, mTokenRate) * 1e18 / tokenOutRate;
            }
        }
    }
}

/// @title CutoffMidasAccount
/// @notice Midas account for cutoff-cohort redemptions: pending requests compound until the cohort
///         pricing date, then freeze at the first vault-feed print at/after it.
contract CutoffMidasAccount is MidasAccount, CutoffAccount {
    /* IMMUTABLES */

    /// @dev Cutoff day for monthly schedules.
    uint256 public immutable CUTOFF_DAY;
    /// @dev Initial cutoff year for monthly schedules.
    uint256 public immutable INITIAL_YEAR;
    /// @dev Initial cutoff month for monthly schedules.
    uint256 public immutable INITIAL_MONTH;
    /// @dev Initial cutoff timestamp.
    uint48 internal immutable INITIAL_CUTOFF;
    /// @dev Window before a cutoff during which new requests may be submitted.
    uint48 internal immutable PRE_CUTOFF_WINDOW;

    /* STATE VARIABLES */

    /// @dev Redemption request bucket.
    mapping(uint64 requestId => uint48 bucket) public requestToBucket;

    /* CONSTRUCTOR */

    /// @notice Creates the cutoff-cohort Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        uint48 initialCutoff,
        address tokenToRedeem,
        uint48 preCutoffWindow,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {
        INITIAL_CUTOFF = initialCutoff;
        PRE_CUTOFF_WINDOW = preCutoffWindow;
        (INITIAL_YEAR, INITIAL_MONTH, CUTOFF_DAY) = DateTimeLib.timestampToDate(initialCutoff);
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc CutoffAccount
    function timestampToBucket(uint48 timestamp) public view override returns (uint48 bucket) {
        if (timestamp < INITIAL_CUTOFF) {
            return 0;
        }

        (uint256 year, uint256 month,) = DateTimeLib.timestampToDate(timestamp);
        bucket = uint48((year - INITIAL_YEAR) * 12 + month - INITIAL_MONTH);
        if (timestamp >= DateTimeLib.dateToTimestamp(year, month, CUTOFF_DAY)) {
            ++bucket;
        }
    }

    /// @inheritdoc CutoffAccount
    function bucketToTimestamp(uint48 bucket) public view override returns (uint48 timestamp) {
        if (bucket == 0) {
            return 0;
        }

        uint256 month = INITIAL_MONTH + bucket - 2;
        return uint48(DateTimeLib.dateToTimestamp(INITIAL_YEAR + month / 12, month % 12 + 1, CUTOFF_DAY));
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Finalizes existing requests and submits a new request only inside the pre-cutoff window.
    function _sync() internal virtual override {
        _finalizeRequests();

        if (
            (msg.sender == owner()
                    || (block.timestamp + PRE_CUTOFF_WINDOW >= nextCutoff()
                        && (lastRequestTimestamp == 0 || block.timestamp >= lastRequestTimestamp + COOLDOWN)))
                && IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)) > 0
        ) {
            _requestRedeem();
            lastRequestTimestamp = uint48(block.timestamp);
        }
    }

    function _requestRedeem() internal virtual override returns (bool) {
        super._requestRedeem();
        requestToBucket[requestIds[requestIds.length - 1]] = currentBucket();
        return true;
    }

    /// @dev Returns pending request value priced by cutoff cohorts. Fulfilled-but-unsynced requests are
    ///      skipped: Midas pays the assets and marks the request processed atomically, and the stale
    ///      cohort entry is only cleared on the next sync.
    function _pendingAssets() internal view override returns (uint256 assets) {
        address aggregator = IMidasDataFeed(IMidasOracle(ORACLE).DATA_FEED()).aggregator();
        for (uint256 i; i < requestIds.length; ++i) {
            uint64 requestId = requestIds[i];
            (,, uint8 status, uint256 amountMToken,,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestId);
            if (status == REQUEST_STATUS_PENDING) {
                (uint80 roundId, int256 answer,, uint256 timestamp,) =
                    AggregatorV3Interface(aggregator).latestRoundData();
                uint48 nextBucketTimestamp = bucketToTimestamp(requestToBucket[requestId] + 1);
                while (timestamp >= nextBucketTimestamp) {
                    --roundId;
                    (, answer,, timestamp,) = AggregatorV3Interface(aggregator).getRoundData(roundId);
                }
                if (answer <= 0) {
                    revert InvalidCutoffPrice();
                }
                assets += _tokenToRedeemToAssets(
                    amountMToken, uint256(answer) * 10 ** (18 - AggregatorV3Interface(aggregator).decimals())
                );
            }
        }
    }
}
