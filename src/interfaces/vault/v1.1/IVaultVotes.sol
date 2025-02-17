// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

interface IVaultVotes is IERC5805 {
    error SafeSupplyExceeded();
    error ImproperMigration();
}
