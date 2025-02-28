// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {console2} from "forge-std/Script.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SymbioticCoreInit} from "../integration/SymbioticCoreInit.sol";

import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../src/interfaces/vault/v1.1/IVaultTokenized.sol";

contract MigrateScript is SymbioticCoreInit {
    using Math for uint256;

    error InvalidMigration();

    uint256 public constant MIN_EXIT_WINDOW = 7 days;

    function run(
        address vault,
        uint64 newVersion,
        address flashFeeReceiver,
        uint256 flashFeeRate,
        string calldata name,
        string calldata symbol
    ) public {
        SymbioticCoreInit.run(0);

        vm.startBroadcast();
        (,, address owner) = vm.readCallers();

        uint64 oldVersion = IMigratableEntity(vault).version();

        if (oldVersion >= newVersion) {
            revert InvalidMigration();
        }

        if (oldVersion == 2 && newVersion == 3) {
            revert InvalidMigration(); // Impossible to migrate from tokenized to non-tokenized
        }

        uint64 currentVersion = oldVersion;
        if (oldVersion == 1 || oldVersion == 2) {
            currentVersion = oldVersion == 1 ? 3 : 4;
            symbioticCore.vaultFactory.migrate(
                vault,
                currentVersion,
                abi.encode(
                    IVault.MigrateParams({
                        epochDurationSetEpochsDelay: MIN_EXIT_WINDOW.ceilDiv(IVault(vault).epochDuration()) + 2,
                        flashLoanEnabled: flashFeeReceiver != address(0),
                        flashFeeRate: flashFeeRate,
                        flashFeeReceiver: flashFeeReceiver,
                        epochDurationSetRoleHolder: owner,
                        flashLoanEnabledSetRoleHolder: owner,
                        flashFeeRateSetRoleHolder: owner,
                        flashFeeReceiverSetRoleHolder: owner
                    })
                )
            );

            console2.log("Successful! From version ", oldVersion, "to ", currentVersion);
        }

        if (currentVersion == 3 && currentVersion < newVersion) {
            currentVersion = 4;
            symbioticCore.vaultFactory.migrate(
                vault, currentVersion, abi.encode(IVaultTokenized.MigrateParamsTokenized({name: name, symbol: symbol}))
            );

            console2.log("Successful! From version ", oldVersion, "to ", currentVersion);
        }

        if (currentVersion < newVersion) {
            currentVersion = 5;
            symbioticCore.vaultFactory.migrate(vault, currentVersion, new bytes(0));

            console2.log("Successful! From version ", oldVersion, "to ", currentVersion);
        }

        console2.log("Completed! From vesion", oldVersion, "to ", newVersion);

        vm.stopBroadcast();
    }
}
