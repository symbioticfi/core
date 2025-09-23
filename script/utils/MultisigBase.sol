// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BatchScript} from "@forge-safe/BatchScript.sol";

/// @notice Script to execute any transactions via Gnosis Safe
contract MultisigBase is BatchScript {
    modifier setChainAlias(
        string memory chainAlias
    ) {
        vm.setEnv("CHAIN", chainAlias);
        _;
    }

    modifier setWalletType(
        string memory walletType
    ) {
        vm.setEnv("WALLET_TYPE", walletType);
        _;
    }

    /// @notice The main script entrypoint
    /// @param send If true, will execute the transaction. If false, will simulate
    /// @param multisig Address of the multisig
    /// @param chainAlias Chain alias
    /// @param targets Array of target addresses
    /// @param txns Array of calldata of the transactions to execute
    function run(
        bool send,
        address multisig,
        string memory chainAlias,
        string memory walletType,
        address[] memory targets,
        bytes[] memory txns
    ) public setChainAlias(chainAlias) setWalletType(walletType) isBatch(multisig) {
        require(targets.length == txns.length, "Parameters length mismatch");

        for (uint256 i = 0; i < targets.length; i++) {
            addToBatch(targets[i], 0, txns[i]);
        }
        // Execute batch
        executeBatch(send);
    }
}
