// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./DeployVaultBase.sol";

contract DeployVaultTokenizedBase is DeployVaultBase {
    constructor(
        DeployVaultParams memory params,
        bytes memory vaultParamsEncoded
    ) DeployVaultBase(params, vaultParamsEncoded) {}
}
