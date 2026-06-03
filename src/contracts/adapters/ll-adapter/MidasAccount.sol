// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CoWSwapConverter} from "../common/CoWSwapConverter.sol";
import {Account} from "./Account.sol";

import {IMidasAccount, REQUEST_STATUS_PENDING} from "../../../interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IAccount} from "../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IOracle} from "../../../interfaces/adapters/ll-adapter/IOracle.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MidasAccount
/// @notice Base account for Midas redemption integrations.
abstract contract MidasAccount is Account, CoWSwapConverter, IMidasAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMidasAccount
    uint48 public immutable COOLDOWN;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_TOKEN;
    /// @inheritdoc IMidasAccount
    address public immutable REDEMPTION_VAULT;

    /* STATE VARIABLES */

    /// @inheritdoc IMidasAccount
    uint48 public lastRequestTimestamp;
    /// @dev Midas redemption request ids.
    uint256[] internal _requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(factory, oracle, tokenToRedeem) CoWSwapConverter(cowSwapSettlement, cowSwapVaultRelayer) {
        COOLDOWN = cooldown;
        REDEMPTION_TOKEN = redemptionToken;
        REDEMPTION_VAULT = redemptionVault;
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    function requestRedeem() public onlyOwner {
        sync();

        if (!_requestRedeem()) {
            revert NoRedeemableAssets();
        }
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public override {
        sync();

        if (tokenIn == _asset || tokenIn == TOKEN_TO_REDEEM) {
            revert InvalidTokenIn();
        }
        if (tokenOut != _asset) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
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

    /// @dev Synchronizes Midas redemption requests and submits held inventory when cooldown permits.
    function _sync() internal override {
        for (uint256 i = _requestIds.length; i > 0; --i) {
            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i - 1]);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            _requestIds[i - 1] = _requestIds[_requestIds.length - 1];
            _requestIds.pop();
        }

        if (lastRequestTimestamp > 0 && block.timestamp < lastRequestTimestamp + COOLDOWN) {
            return;
        }

        if (_requestRedeem()) {
            lastRequestTimestamp = uint48(block.timestamp);
        }
    }

    function _requestRedeem() internal returns (bool success) {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amount == 0) {
            return false;
        }
        (address dataFeed,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).tokensConfig(_asset);
        _requestIds.push(
            IMidasRedemptionVault(REDEMPTION_VAULT)
                .redeemRequest(dataFeed == address(0) ? REDEMPTION_TOKEN : _asset, amount)
        );
        return true;
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);
        IAccount.InitParams memory params = abi.decode(data, (IAccount.InitParams));

        IERC20(_asset).forceApprove(REDEMPTION_VAULT, type(uint256).max);
        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_VAULT, type(uint256).max);

        __CoWSwapConverter_init(params.converters);
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
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            redemptionToken,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using the current oracle rate.
    function _pendingAssets() internal view override returns (uint256) {
        uint256 price = IOracle(ORACLE).getPrice();
        uint256 amount;
        for (uint256 i; i < _requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken,,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                amount += amountMToken;
            }
        }
        return _tokenToRedeemToAssets(amount, price);
    }
}

/// @title MidasNonCompAccount
/// @notice Midas account that prices pending requests at their creation-time rate.
contract MidasNonCompAccount is MidasAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the non-compounding Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    )
        MidasAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            redemptionToken,
            redemptionVault,
            cowSwapSettlement,
            cowSwapVaultRelayer
        )
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value using each request's locked rate.
    function _pendingAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < _requestIds.length; ++i) {
            (,, uint8 status, uint256 amountMToken, uint256 mTokenRate,) =
                IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestIds[i]);
            if (status == REQUEST_STATUS_PENDING) {
                assets += _tokenToRedeemToAssets(amountMToken, mTokenRate);
            }
        }
    }
}
