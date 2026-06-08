// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployAaveV3AdapterBaseScript} from "script/deploy/base/DeployAaveV3AdapterBase.s.sol";
import {DeployMorphoVaultV2AdapterBaseScript} from "script/deploy/base/DeployMorphoVaultV2AdapterBase.s.sol";
import {DeployV2BaseScript} from "script/deploy/base/DeployV2Base.s.sol";
import {V2WhitelistAdaptersBaseScript} from "script/upgrade/base/V2WhitelistAdaptersBase.s.sol";
import {Logs} from "script/utils/Logs.sol";
import {ScriptBase} from "script/utils/ScriptBase.s.sol";

// forge script script/deploy/DeployAndWhitelistAaveMorpho.s.sol:DeployAndWhitelistAaveMorphoScript --rpc-url RPC/mainnet --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAndWhitelistAaveMorphoScript is ScriptBase {
    // Address that will own the new AdapterRegistry after both adapters are whitelisted.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000001;
    // Address that will own both adapter factories after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000001;
    // Address that will own the new ProtocolFeeRegistry.
    address public constant PROTOCOL_FEE_REGISTRY_OWNER = 0x0000000000000000000000000000000000000001;
    // AaveV3 pool used by the Aave adapter.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // MorphoVaultV2 dependencies used by the Morpho adapter.
    address public constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address public constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    // CoW Protocol dependencies used by adapter reward converters.
    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    // Mainnet Merkl Distributor used by adapter reward claimers.
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    // Vault scope for the adapter factories, or zero address for the global whitelist.
    address public constant VAULT = 0x0000000000000000000000000000000000000000;

    struct DeployParams {
        address adapterRegistryOwner;
        address adapterFactoryOwner;
        address protocolFeeRegistryOwner;
        address vault;
        address aavePool;
        address morphoVaultFactory;
        address morphoAdapterRegistry;
        address cowSwapSettlement;
        address merklDistributor;
    }

    struct DeploymentData {
        DeployV2BaseScript.DeploymentData v2;
        DeployAaveV3AdapterBaseScript.DeploymentData aave;
        DeployMorphoVaultV2AdapterBaseScript.DeploymentData morpho;
        bytes whitelistAaveFactoryData;
        address whitelistAaveFactoryTarget;
        bytes whitelistMorphoFactoryData;
        address whitelistMorphoFactoryTarget;
        bytes transferAdapterRegistryOwnershipData;
        address transferAdapterRegistryOwnershipTarget;
    }

    function run() public virtual returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({
                adapterRegistryOwner: ADAPTER_REGISTRY_OWNER,
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                protocolFeeRegistryOwner: PROTOCOL_FEE_REGISTRY_OWNER,
                vault: VAULT,
                aavePool: AAVE_POOL,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        address deployer = _scriptOwner();
        address adapterRegistryOwner = params.adapterRegistryOwner;
        require(deployer != address(0), "invalid deployer");
        require(adapterRegistryOwner != address(0), "invalid adapter registry owner");
        require(params.protocolFeeRegistryOwner != address(0), "invalid protocol fee registry owner");

        DeployParams memory deployParams = DeployParams({
            adapterRegistryOwner: deployer,
            adapterFactoryOwner: params.adapterFactoryOwner,
            protocolFeeRegistryOwner: params.protocolFeeRegistryOwner,
            vault: params.vault,
            aavePool: params.aavePool,
            morphoVaultFactory: params.morphoVaultFactory,
            morphoAdapterRegistry: params.morphoAdapterRegistry,
            cowSwapSettlement: params.cowSwapSettlement,
            merklDistributor: params.merklDistributor
        });

        data.v2 = _deployV2(deployParams);
        data.aave = _deployAave(params);
        data.morpho = _deployMorpho(params);

        address adapterRegistry = address(data.v2.adapterRegistry);
        (data.whitelistAaveFactoryData, data.whitelistAaveFactoryTarget) =
            _whitelistAdapterFactory(adapterRegistry, params.vault, data.aave.adapterFactory);
        (data.whitelistMorphoFactoryData, data.whitelistMorphoFactoryTarget) =
            _whitelistAdapterFactory(adapterRegistry, params.vault, data.morpho.adapterFactory);
        (data.transferAdapterRegistryOwnershipData, data.transferAdapterRegistryOwnershipTarget) =
            _transferAdapterRegistryOwnership(adapterRegistry, adapterRegistryOwner);

        Logs.log(
            string.concat(
                "DeployAndWhitelistAaveMorpho complete",
                "\n    adapterRegistry:",
                vm.toString(adapterRegistry),
                "\n    aaveAdapterFactory:",
                vm.toString(data.aave.adapterFactory),
                "\n    morphoAdapterFactory:",
                vm.toString(data.morpho.adapterFactory),
                "\n    vault:",
                vm.toString(params.vault),
                "\n    adapterRegistryOwner:",
                vm.toString(adapterRegistryOwner)
            )
        );
    }

    function _deployV2(DeployParams memory params)
        internal
        virtual
        returns (DeployV2BaseScript.DeploymentData memory data)
    {
        data = new DeployV2BaseScript().runBase(params.adapterRegistryOwner, params.protocolFeeRegistryOwner);
    }

    function _deployAave(DeployParams memory params)
        internal
        virtual
        returns (DeployAaveV3AdapterBaseScript.DeploymentData memory data)
    {
        DeployAaveV3AdapterBaseScript script = new DeployAaveV3AdapterBaseScript();
        data = script.runBase(
            DeployAaveV3AdapterBaseScript.DeployParams({
                adapterFactoryOwner: params.adapterFactoryOwner,
                aavePool: params.aavePool,
                cowSwapSettlement: params.cowSwapSettlement,
                merklDistributor: params.merklDistributor
            })
        );
    }

    function _deployMorpho(DeployParams memory params)
        internal
        virtual
        returns (DeployMorphoVaultV2AdapterBaseScript.DeploymentData memory data)
    {
        DeployMorphoVaultV2AdapterBaseScript script = new DeployMorphoVaultV2AdapterBaseScript();
        data = script.runBase(
            DeployMorphoVaultV2AdapterBaseScript.DeployParams({
                adapterFactoryOwner: params.adapterFactoryOwner,
                morphoVaultFactory: params.morphoVaultFactory,
                morphoAdapterRegistry: params.morphoAdapterRegistry,
                cowSwapSettlement: params.cowSwapSettlement,
                merklDistributor: params.merklDistributor
            })
        );
    }

    function _whitelistAdapterFactory(address adapterRegistry, address vault, address adapterFactory)
        internal
        virtual
        returns (bytes memory data, address target)
    {
        (data, target) =
            new V2WhitelistAdaptersBaseScript().whitelistAdapterFactory(adapterRegistry, vault, adapterFactory);
    }

    function _transferAdapterRegistryOwnership(address adapterRegistry, address newOwner)
        internal
        virtual
        returns (bytes memory data, address target)
    {
        target = adapterRegistry;
        data = abi.encodeCall(Ownable.transferOwnership, (newOwner));
        sendTransaction(target, data);

        assert(Ownable(adapterRegistry).owner() == newOwner);

        Logs.log(
            string.concat(
                "Transfer AdapterRegistry ownership",
                "\n    adapterRegistry:",
                vm.toString(adapterRegistry),
                "\n    owner:",
                vm.toString(newOwner)
            )
        );
        Logs.logSimulationLink(target, data);
    }

    function _scriptOwner() internal view virtual returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }
}
