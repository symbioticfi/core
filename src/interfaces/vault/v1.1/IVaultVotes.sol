// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultTokenized} from "./IVaultTokenized.sol";

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

interface IVaultVotes is IVaultTokenized, IERC5805 {
    error InvalidData();
    error SafeSupplyExceeded();
}
