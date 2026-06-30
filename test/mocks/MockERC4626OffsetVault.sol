// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC4626OffsetVault is ERC4626 {
    using SafeERC20 for IERC20;

    uint8 internal constant SHARES_DECIMALS = 18;

    address public delegator;

    constructor(IERC20 asset_) ERC20("Mock ERC4626 Offset Vault", "mERC4626") ERC4626(asset_) {}

    function decimalsOffset() external view returns (uint8) {
        return _decimalsOffset();
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function increaseTotalAssets(uint256 assets) external {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
    }

    function decreaseTotalAssets(uint256 assets, address receiver) external {
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    function accrueInterest() external pure returns (uint256 managementFeeShares, uint256 performanceFeeShares) {}

    function _decimalsOffset() internal view override returns (uint8) {
        uint8 assetDecimals = IERC20Metadata(asset()).decimals();
        return assetDecimals >= SHARES_DECIMALS ? 0 : SHARES_DECIMALS - assetDecimals;
    }
}
