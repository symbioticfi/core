// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/V2UpgradeBase.s.sol";
import {Logs} from "../utils/Logs.sol";

// forge script script/upgrade/V2Upgrade.s.sol:V2UpgradeScript --rpc-url RPC/hoodi --broadcast

contract V2UpgradeScript is V2UpgradeBaseScript {
    // Address of the deployed VaultV2 implementation.
    address constant VAULT_V2 = 0x0000000000000000000000000000000000000000;
    // Address of the deployed UniversalDelegator implementation.
    address constant UNIVERSAL_DELEGATOR = 0x0000000000000000000000000000000000000000;
    // Address of the deployed UniversalSlasher implementation.
    address constant UNIVERSAL_SLASHER = 0x0000000000000000000000000000000000000000;

    function run() public {
        (bytes memory whitelistVaultData, address whitelistVaultTarget) = whitelistVaultV2(VAULT_V2);
        (bytes memory whitelistDelegatorData, address whitelistDelegatorTarget) =
            whitelistUniversalDelegator(UNIVERSAL_DELEGATOR);
        (bytes memory whitelistSlasherData, address whitelistSlasherTarget) =
            whitelistUniversalSlasher(UNIVERSAL_SLASHER);

        Logs.log(
            string.concat(
                "V2Upgrade data:",
                "\n    whitelistVaultData:",
                vm.toString(whitelistVaultData),
                "\n    whitelistVaultTarget:",
                vm.toString(whitelistVaultTarget),
                "\n    whitelistDelegatorData:",
                vm.toString(whitelistDelegatorData),
                "\n    whitelistDelegatorTarget:",
                vm.toString(whitelistDelegatorTarget),
                "\n    whitelistSlasherData:",
                vm.toString(whitelistSlasherData),
                "\n    whitelistSlasherTarget:",
                vm.toString(whitelistSlasherTarget)
            )
        );
    }
}
