// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Registry as SymbioticRegistry} from "../../src/contracts/common/Registry.sol";
import {Entity as SymbioticEntity} from "../../src/contracts/common/Entity.sol";
import {Factory as SymbioticFactory} from "../../src/contracts/common/Factory.sol";
import {MigratableEntity as SymbioticMigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {MigratablesFactory as SymbioticMigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {StaticDelegateCallable as SymbioticStaticDelegateCallable} from
    "../../src/contracts/common/StaticDelegateCallable.sol";
import {Vault as SymbioticVault} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized as SymbioticVaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {VaultFactory as SymbioticVaultFactory} from "../../src/contracts/VaultFactory.sol";
import {BaseDelegator as SymbioticBaseDelegator} from "../../src/contracts/delegator/BaseDelegator.sol";
import {NetworkRestakeDelegator as SymbioticNetworkRestakeDelegator} from
    "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator as SymbioticFullRestakeDelegator} from
    "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator as SymbioticOperatorSpecificDelegator} from
    "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator as SymbioticOperatorNetworkSpecificDelegator} from
    "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {DelegatorFactory as SymbioticDelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {BaseSlasher as SymbioticBaseSlasher} from "../../src/contracts/slasher/BaseSlasher.sol";
import {Slasher as SymbioticSlasher, ISlasher as ISymbioticSlasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher as SymbioticVetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {SlasherFactory as SymbioticSlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry as SymbioticNetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {
    OperatorRegistry as SymbioticOperatorRegistry,
    IOperatorRegistry as ISymbioticOperatorRegistry
} from "../../src/contracts/OperatorRegistry.sol";
import {MetadataService as SymbioticMetadataService} from "../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService as SymbioticNetworkMiddlewareService} from
    "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService as SymbioticOptInService} from "../../src/contracts/service/OptInService.sol";
import {VaultConfigurator as SymbioticVaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";

interface SymbioticCoreImportsContracts {}
