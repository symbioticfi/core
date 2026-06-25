// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";
import {CoWSwapConverter} from "./common/CoWSwapConverter.sol";
import {MerklClaimer} from "./common/MerklClaimer.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IEulerAdapter} from "../../interfaces/adapters/IEulerAdapter.sol";
import {IEulerLendVaultFactory} from "../../interfaces/adapters/euler_adapter/IEulerLendVaultFactory.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EulerAdapter
/// @notice VaultV2 adapter for Euler Lend positions.
contract EulerAdapter is Adapter, CoWSwapConverter, MerklClaimer, IEulerAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Trusted Euler EVK factory used to validate Lend vaults.
    address internal immutable EULER_LEND_VAULT_FACTORY;

    /* STATE VARIABLES */

    /// @inheritdoc IEulerAdapter
    address public lendVault;

    /// @inheritdoc IEulerAdapter
    uint256 public totalShares;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address merklDistributor,
        address cowSwapSettlement,
        address eulerLendVaultFactory
    ) Adapter(vaultFactory, adapterFactory) CoWSwapConverter(cowSwapSettlement) MerklClaimer(merklDistributor) {
        EULER_LEND_VAULT_FACTORY = eulerLendVaultFactory;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return freeAssets() + IERC4626(lendVault).previewRedeem(totalShares);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        if (tokenIn == lendVault || tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IEulerAdapter
    function deposit(uint256 amount) public returns (uint256 shares) {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        shares = IERC4626(lendVault).deposit(amount, address(this));
        if (shares == 0) {
            revert InsufficientAmount();
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Supplies asset from the calling vault into the configured Euler Lend vault.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try this.deposit(amount) returns (uint256 shares) {
            totalShares += shares;
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from the configured Euler Lend vault when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        amount = Math.min(
            amount,
            Math.min(IERC4626(lendVault).previewRedeem(totalShares), IERC4626(lendVault).maxWithdraw(address(this)))
        );
        if (amount == 0) {
            return 0;
        }

        try IERC4626(lendVault).withdraw(amount, address(this), address(this)) returns (uint256 shares) {
            totalShares -= shares;
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Initializes and permanently binds the Euler Lend vault.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        if (
            params.lendVault == address(0)
                || !IEulerLendVaultFactory(EULER_LEND_VAULT_FACTORY).isProxy(params.lendVault)
                || IERC4626(params.lendVault).asset() != IERC4626(vault).asset()
        ) {
            revert InvalidEulerLendVault();
        }

        lendVault = params.lendVault;

        IERC20(IERC4626(vault).asset()).forceApprove(params.lendVault, type(uint256).max);

        emit Initialize(params.lendVault);
    }
}
