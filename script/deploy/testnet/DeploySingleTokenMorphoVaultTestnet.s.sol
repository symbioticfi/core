// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../utils/Logs.sol";
import {MockMorphoVaultFactory, MockMorphoVaultHarness} from "../../../test/mocks/HoodiScenarioProtocolMocks.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMintableToken {
    function mint(address to, uint256 amount) external;
}

contract DeploySingleTokenMorphoVaultTestnetScript is Script {
    address internal constant DEFAULT_OWNER = 0xc056736be7C05790667CDb678c03eb09F616E157;
    address internal constant DEFAULT_ASSET = 0x809e6c18bC13Cc7C9F7b8000d74243BAaccE84d7;

    address internal constant DEFAULT_VAULT_FACTORY = 0x158Bb64B79CADa5a259d46cc2354db9D018D9f3E;
    address internal constant DEFAULT_DELEGATOR_FACTORY = 0x4B1EeDad825D63633fa876627dA085dF62617C7f;
    address internal constant DEFAULT_ADAPTER_REGISTRY = 0xE01351c458c33932d8d39c98069e50FE809FeF6a;
    address internal constant DEFAULT_MORPHO_ADAPTER_FACTORY = 0x9dD4Cd6A5Ad3E040023b9D4CCCc76f9e2B7E55DA;
    address internal constant DEFAULT_MORPHO_VAULT_FACTORY = 0x954Ec5857fBa5B5041bb982B9bda128d513165BE;
    address internal constant DEFAULT_MORPHO_ADAPTER_REGISTRY = 0xd52FAE9f5F1260FA00712F23c0b6fD19acDC3f8a;

    struct DeployConfig {
        address owner;
        address asset;
        address vaultFactory;
        address delegatorFactory;
        address adapterRegistry;
        address morphoAdapterFactory;
        address morphoVaultFactory;
        address morphoAdapterRegistry;
        uint256 topUpAmount;
        string vaultName;
        string vaultSymbol;
    }

    struct DeploymentData {
        address vault;
        address delegator;
        address morphoVault;
        address morphoAdapter;
        uint256 topUpAmount;
    }

    function run() external returns (DeploymentData memory data) {
        DeployConfig memory config = _config();

        vm.startBroadcast();
        data = _deploy(config);
        vm.stopBroadcast();

        _validate(config, data);
        _log(config, data);
    }

    function _deploy(DeployConfig memory config) internal returns (DeploymentData memory data) {
        data.topUpAmount = config.topUpAmount;

        data.vault =
            IMigratablesFactory(config.vaultFactory).create(VAULT_V2_VERSION, config.owner, _vaultParams(config));
        data.delegator = IVaultV2(data.vault).delegator();

        data.morphoVault = address(new MockMorphoVaultHarness(config.asset, config.morphoAdapterRegistry));
        MockMorphoVaultFactory(config.morphoVaultFactory).setVault(data.morphoVault, true);

        address[] memory converters = new address[](0);
        data.morphoAdapter = AdapterFactory(config.morphoAdapterFactory)
            .create(
                1,
                config.owner,
                abi.encode(
                    data.vault,
                    abi.encode(
                        IMorphoVaultV2Adapter.InitParams({morphoVault: data.morphoVault, converters: converters})
                    )
                )
            );

        IAdapterRegistry(config.adapterRegistry).setWhitelistedStatus(data.vault, data.morphoAdapter, true);
        IUniversalDelegator(data.delegator).addAdapter(data.morphoAdapter);
        IUniversalDelegator(data.delegator).setLimits(data.morphoAdapter, type(uint128).max, MAX_SHARE);

        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = data.morphoAdapter;
        IUniversalDelegator(data.delegator).setAutoAllocateAdapters(autoAllocateAdapters);

        IMintableToken(config.asset).mint(config.owner, config.topUpAmount);
        IERC20(config.asset).approve(data.vault, config.topUpAmount);
        IERC4626(data.vault).deposit(config.topUpAmount, config.owner);
    }

    function _config() internal view returns (DeployConfig memory config) {
        config.owner = vm.envOr("TESTNET_OWNER", DEFAULT_OWNER);
        config.asset = vm.envOr("TESTNET_ASSET", DEFAULT_ASSET);
        config.vaultFactory = vm.envOr("TESTNET_VAULT_FACTORY", DEFAULT_VAULT_FACTORY);
        config.delegatorFactory = vm.envOr("TESTNET_DELEGATOR_FACTORY", DEFAULT_DELEGATOR_FACTORY);
        config.adapterRegistry = vm.envOr("TESTNET_ADAPTER_REGISTRY", DEFAULT_ADAPTER_REGISTRY);
        config.morphoAdapterFactory = vm.envOr("TESTNET_MORPHO_ADAPTER_FACTORY", DEFAULT_MORPHO_ADAPTER_FACTORY);
        config.morphoVaultFactory = vm.envOr("TESTNET_MORPHO_VAULT_FACTORY", DEFAULT_MORPHO_VAULT_FACTORY);
        config.morphoAdapterRegistry = vm.envOr("TESTNET_MORPHO_ADAPTER_REGISTRY", DEFAULT_MORPHO_ADAPTER_REGISTRY);

        uint256 defaultTopUpAmount = 1_000_000 * 10 ** IERC20Metadata(config.asset).decimals();
        config.topUpAmount = vm.envOr("TESTNET_TOP_UP_AMOUNT", defaultTopUpAmount);

        string memory symbol = IERC20Metadata(config.asset).symbol();
        config.vaultName = vm.envOr("TESTNET_VAULT_NAME", string.concat("Testnet ", symbol, " Morpho Vault"));
        config.vaultSymbol = vm.envOr("TESTNET_VAULT_SYMBOL", string.concat("t", symbol, "-M-V"));
    }

    function _vaultParams(DeployConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(
            IVaultV2.InitParams({
                name: config.vaultName,
                symbol: config.vaultSymbol,
                asset: config.asset,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: type(uint256).max,
                isDepositLimit: true,
                defaultAdminRoleHolder: config.owner,
                managementFeeRoleHolder: config.owner,
                performanceFeeRoleHolder: config.owner,
                depositLimitSetRoleHolder: config.owner,
                depositorWhitelistRoleHolder: config.owner,
                isDepositLimitSetRoleHolder: config.owner,
                depositWhitelistSetRoleHolder: config.owner,
                delegatorParams: abi.encode(_delegatorParams(config.owner))
            })
        );
    }

    function _delegatorParams(address owner) internal pure returns (IUniversalDelegator.InitParams memory params) {
        params = IUniversalDelegator.InitParams({
            allocateRoleHolder: owner,
            deallocateRoleHolder: owner,
            forceDeallocateRoleHolder: owner,
            addAdapterRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            defaultAdminRoleHolder: owner,
            removeAdapterRoleHolder: owner,
            setAdapterLimitsRoleHolder: owner,
            setAutoAllocateAdaptersRoleHolder: owner
        });
    }

    function _validate(DeployConfig memory config, DeploymentData memory data) internal view {
        assert(IERC4626(data.vault).asset() == config.asset);
        assert(IVaultV2(data.vault).delegator() == data.delegator);
        assert(IAdapterRegistry(config.adapterRegistry).isWhitelisted(data.vault, data.morphoAdapter));
        assert(MockMorphoVaultFactory(config.morphoVaultFactory).isVaultV2(data.morphoVault));
        assert(IMorphoVaultV2Adapter(data.morphoAdapter).morphoVault() == data.morphoVault);
        assert(IUniversalDelegator(data.delegator).getAdaptersLength() == 1);
        assert(IUniversalDelegator(data.delegator).adapters(0) == data.morphoAdapter);
        assert(IUniversalDelegator(data.delegator).autoAllocateAdapters(0) == data.morphoAdapter);
        assert(IUniversalDelegator(data.delegator).absoluteLimitOf(data.morphoAdapter) == type(uint128).max);
        assert(IUniversalDelegator(data.delegator).shareLimitOf(data.morphoAdapter) == MAX_SHARE);
        uint256 ownerShares = IERC20(data.vault).balanceOf(config.owner);
        assert(ownerShares > 0);
        assert(IERC4626(data.vault).convertToAssets(ownerShares) == data.topUpAmount);
        assert(IVaultV2(data.vault).freeAssets() == 0);
        assert(IUniversalDelegator(data.delegator).totalAssets() == data.topUpAmount);
        assert(IMorphoVaultV2Adapter(data.morphoAdapter).totalAssets() == data.topUpAmount);
    }

    function _log(DeployConfig memory config, DeploymentData memory data) internal {
        Logs.log("DeploySingleTokenMorphoVaultTestnet deployment");
        _log("owner", config.owner);
        _log("asset", config.asset);
        _log("vault", data.vault);
        _log("delegator", data.delegator);
        _log("morphoVault", data.morphoVault);
        _log("morphoAdapter", data.morphoAdapter);
        Logs.log(string.concat("topUpAmount:", vm.toString(data.topUpAmount)));
    }

    function _log(string memory key, address value) internal {
        Logs.log(string.concat(key, ":", vm.toString(value)));
    }
}
