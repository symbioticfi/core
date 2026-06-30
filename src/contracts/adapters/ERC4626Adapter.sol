// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";
import {CoWSwapConverter} from "./common/CoWSwapConverter.sol";
import {MerklClaimer} from "./common/MerklClaimer.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IERC4626Adapter} from "../../interfaces/adapters/IERC4626Adapter.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ERC4626Adapter
/// @notice VaultV2 adapter for generic ERC4626 vault positions.
contract ERC4626Adapter is Adapter, CoWSwapConverter, MerklClaimer, IERC4626Adapter {
    using SafeERC20 for IERC20;

    /* STATE VARIABLES */

    /// @inheritdoc IERC4626Adapter
    address public erc4626Vault;

    /* CONSTRUCTOR */

    /// @notice Creates the ERC4626 adapter implementation.
    constructor(address vaultFactory, address adapterFactory, address merklDistributor, address cowSwapSettlement)
        Adapter(vaultFactory, adapterFactory)
        CoWSwapConverter(cowSwapSettlement)
        MerklClaimer(merklDistributor)
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        address curERC4626Vault = erc4626Vault;
        return freeAssets() + IERC4626(curERC4626Vault).previewRedeem(IERC20(curERC4626Vault).balanceOf(address(this)));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc CoWSwapConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data) public virtual override {
        if (tokenIn == erc4626Vault || tokenIn == IERC4626(vault).asset()) {
            revert InvalidTokenIn();
        }
        if (tokenOut != IERC4626(vault).asset()) {
            revert InvalidTokenOut();
        }
        super.convert(tokenIn, amountIn, tokenOut, data);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IERC4626Adapter
    function deposit(uint256 amount) public {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        if (IERC4626(erc4626Vault).deposit(amount, address(this)) == 0) {
            revert InsufficientAmount();
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deposits asset from the calling vault into the configured ERC4626 vault.
    function _allocate(uint256 amount) internal override returns (uint256) {
        try this.deposit(amount) {
            return amount;
        } catch {}
        return 0;
    }

    /// @dev Withdraws asset for the calling vault from the configured ERC4626 vault.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        address curERC4626Vault = erc4626Vault;
        amount = Math.min(amount, IERC4626(curERC4626Vault).maxWithdraw(address(this)));
        if (amount == 0) {
            return 0;
        }

        try IERC4626(curERC4626Vault).withdraw(amount, address(this), address(this)) returns (uint256) {
            return amount;
        } catch {}
        return 0;
    }

    /* INITIALIZATION */

    /// @dev Initializes and permanently binds the ERC4626 vault.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        __CoWSwapConverter_init(params.converters);

        address curERC4626Vault = params.erc4626Vault;
        if (curERC4626Vault == address(0) || IERC4626(curERC4626Vault).asset() != IERC4626(vault).asset()) {
            revert InvalidERC4626Vault();
        }

        erc4626Vault = curERC4626Vault;

        IERC20(IERC4626(vault).asset()).forceApprove(curERC4626Vault, type(uint256).max);

        emit Initialize(curERC4626Vault);
    }
}
