// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFactory} from "../../../src/interfaces/common/IFactory.sol";
import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract V2UpgradeBaseScript is ScriptBase {
    function whitelistVaultV2(address vaultV2) public virtual returns (bytes memory data, address target) {
        target = address(SymbioticCoreConstants.core().vaultFactory);
        data = abi.encodeCall(IMigratablesFactory.whitelist, (vaultV2));
        sendTransaction(target, data);

        assert(IMigratableEntity(vaultV2).FACTORY() == target);
        assert(IMigratablesFactory(target).implementation(VAULT_V2_VERSION) == vaultV2);

        Logs.log(string.concat("Whitelist VaultV2", "\n    vaultV2:", vm.toString(vaultV2)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }

    function whitelistUniversalDelegator(address universalDelegator)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = address(SymbioticCoreConstants.core().delegatorFactory);
        data = abi.encodeCall(IFactory.whitelist, (universalDelegator));
        sendTransaction(target, data);

        assert(IEntity(universalDelegator).TYPE() == UNIVERSAL_DELEGATOR_TYPE);
        assert(IFactory(target).implementation(UNIVERSAL_DELEGATOR_TYPE) == universalDelegator);

        Logs.log(
            string.concat("Whitelist UniversalDelegator", "\n    universalDelegator:", vm.toString(universalDelegator))
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }

    function whitelistUniversalSlasher(address universalSlasher)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = address(SymbioticCoreConstants.core().slasherFactory);
        data = abi.encodeCall(IFactory.whitelist, (universalSlasher));
        sendTransaction(target, data);

        assert(IEntity(universalSlasher).TYPE() == UNIVERSAL_SLASHER_TYPE);
        assert(IFactory(target).implementation(UNIVERSAL_SLASHER_TYPE) == universalSlasher);

        Logs.log(string.concat("Whitelist UniversalSlasher", "\n    universalSlasher:", vm.toString(universalSlasher)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
