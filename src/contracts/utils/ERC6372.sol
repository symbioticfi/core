// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract ERC6372 is IERC6372 {
    /**
     * @inheritdoc IERC6372
     */
    function clock() public view virtual returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @inheritdoc IERC6372
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        return "mode=timestamp";
    }
}
