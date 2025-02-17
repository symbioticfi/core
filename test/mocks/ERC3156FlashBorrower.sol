// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../src/interfaces/vault/v1.1.0/IVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract ERC3156FlashBorrower is IERC3156FlashBorrower {
    using SafeERC20 for IERC20;

    address public immutable VAULT;
    bytes32 public RETURN_VALUE;

    constructor(
        address vault
    ) {
        VAULT = vault;
    }

    function run(uint256 amount, bytes32 returnValue, bytes calldata data) external {
        RETURN_VALUE = returnValue;
        IERC3156FlashLender(VAULT).flashLoan(
            IERC3156FlashBorrower(address(this)), IVault(VAULT).collateral(), amount, data
        );
    }

    function onFlashLoan(
        address, /* initiator */
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        bool flag = abi.decode(data, (bool));
        if (flag) {
            IERC20(token).safeTransfer(msg.sender, amount + fee);
        }

        return RETURN_VALUE;
    }
}
