// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ExecuteSlashMultisigBaseScript} from "./base/ExecuteSlashMultisigBase.s.sol";

contract ExecuteSlashMultisig is ExecuteSlashMultisigBaseScript {
    address public VAULT = address(0);
    uint256 public SLASH_INDEX = 0;
    address public MULTISIG = address(0);
    string public CHAIN_ALIAS = "mainnet";
    string public WALLET_TYPE = "local"; // local, ledger

    function run() external {
        run(VAULT, SLASH_INDEX, MULTISIG, CHAIN_ALIAS, WALLET_TYPE);
    }
}
