// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry as ISymbioticRegistry} from "../../src/interfaces/common/IRegistry.sol";
import {IEntity as ISymbioticEntity} from "../../src/interfaces/common/IEntity.sol";
import {IFactory as ISymbioticFactory} from "../../src/interfaces/common/IFactory.sol";
import {IMigratableEntity as ISymbioticMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory as ISymbioticMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IStaticDelegateCallable as ISymbioticStaticDelegateCallable} from
    "../../src/interfaces/common/IStaticDelegateCallable.sol";
import {IVault as ISymbioticVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized as ISymbioticVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";
import {IVaultFactory as ISymbioticVaultFactory} from "../../src/interfaces/IVaultFactory.sol";
import {IBaseDelegator as ISymbioticBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator as ISymbioticNetworkRestakeDelegator} from
    "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator as ISymbioticFullRestakeDelegator} from
    "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator as ISymbioticOperatorSpecificDelegator} from
    "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IOperatorNetworkSpecificDelegator as ISymbioticOperatorNetworkSpecificDelegator} from
    "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IDelegatorFactory as ISymbioticDelegatorFactory} from "../../src/interfaces/IDelegatorFactory.sol";
import {IBaseSlasher as ISymbioticBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher as ISymbioticSlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher as ISymbioticVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {ISlasherFactory as ISymbioticSlasherFactory} from "../../src/interfaces/ISlasherFactory.sol";
import {INetworkRegistry as ISymbioticNetworkRegistry} from "../../src/interfaces/INetworkRegistry.sol";
import {IOperatorRegistry as ISymbioticOperatorRegistry} from "../../src/interfaces/IOperatorRegistry.sol";
import {IMetadataService as ISymbioticMetadataService} from "../../src/interfaces/service/IMetadataService.sol";
import {INetworkMiddlewareService as ISymbioticNetworkMiddlewareService} from
    "../../src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService as ISymbioticOptInService} from "../../src/interfaces/service/IOptInService.sol";
import {IVaultConfigurator as ISymbioticVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {Checkpoints as SymbioticCheckpoints} from "../../src/contracts/libraries/Checkpoints.sol";
import {ERC4626Math as SymbioticERC4626Math} from "../../src/contracts/libraries/ERC4626Math.sol";
import {Subnetwork as SymbioticSubnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

interface SymbioticCoreImports {}
