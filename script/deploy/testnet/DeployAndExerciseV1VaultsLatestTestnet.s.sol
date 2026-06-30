// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IRegistry} from "../../../src/interfaces/common/IRegistry.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {
    IOperatorNetworkSpecificDelegator
} from "../../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {INetworkMiddlewareService} from "../../../src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {IVault, VAULT_VERSION} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized, VAULT_TOKENIZED_VERSION} from "../../../src/interfaces/vault/IVaultTokenized.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface INetworkRegistryV1Exercise is IRegistry {
    function registerNetwork() external;
}

interface IOperatorRegistryV1Exercise is IRegistry {
    function registerOperator() external;
}

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract DeployAndExerciseV1VaultsLatestTestnetScript is Script {
    uint256 internal constant VAULT_COUNT = 8;

    struct Core {
        address vaultConfigurator;
        address networkRegistry;
        address networkMiddlewareService;
        address operatorRegistry;
        address operatorVaultOptInService;
        address operatorNetworkOptInService;
    }

    struct Assets {
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
    }

    struct V1Vault {
        address vault;
        address delegator;
        address slasher;
        address asset;
        uint64 vaultVersion;
        uint64 delegatorType;
        uint64 slasherType;
        bool withSlasher;
        bool vetoWithResolver;
        uint96 subnetworkId;
        uint256 claimEpoch;
        uint256 depositAmount;
    }

    struct CreateConfig {
        uint64 vaultVersion;
        uint64 delegatorType;
        uint64 slasherType;
        bool withSlasher;
        bool vetoWithResolver;
        bytes vaultParams;
        bytes delegatorParams;
        bytes slasherParams;
    }

    event V1VaultCreated(
        uint256 indexed index,
        address indexed vault,
        address indexed delegator,
        address slasher,
        address asset,
        uint64 vaultVersion,
        uint64 delegatorType,
        uint64 slasherType,
        bool withSlasher
    );

    event V1VaultExercised(uint256 indexed index, address indexed vault, uint256 claimEpoch);

    function run() external {
        address owner = _scriptOwner();
        (Core memory core, Assets memory assets) = _latestDeployment();
        bool exerciseExisting = vm.envOr("TESTNET_V1_EXERCISE_EXISTING", false);
        bool slashOnly = vm.envOr("TESTNET_V1_SLASH_ONLY", false);

        vm.startBroadcast();

        if (slashOnly) {
            V1Vault[] memory vaults = _existingVaults(assets);
            _exerciseSlashers(vaults, owner);
            vm.stopBroadcast();
            _logSummary(vaults);
            return;
        }

        _registerAndOptBase(core, owner);
        _mintAssets(assets, owner);

        V1Vault[] memory vaults = exerciseExisting ? _existingVaults(assets) : _createVaults(core, assets, owner);
        _exerciseVaults(core, vaults, owner);

        vm.stopBroadcast();

        _logSummary(vaults);
    }

    function _createVaults(Core memory core, Assets memory assets, address owner)
        internal
        returns (V1Vault[] memory vaults)
    {
        vaults = new V1Vault[](VAULT_COUNT);
        for (uint256 i; i < VAULT_COUNT; ++i) {
            vaults[i] = _createVault(core, _assetAt(assets, i), owner, i);

            _optInIfNeeded(core.operatorVaultOptInService, owner, vaults[i].vault);

            emit V1VaultCreated(
                i,
                vaults[i].vault,
                vaults[i].delegator,
                vaults[i].slasher,
                vaults[i].asset,
                vaults[i].vaultVersion,
                vaults[i].delegatorType,
                vaults[i].slasherType,
                vaults[i].withSlasher
            );
            console2.log("v1 vault", i, vaults[i].vault);
            console2.log("  delegator", vaults[i].delegator);
            console2.log("  slasher", vaults[i].slasher);
        }
    }

    function _exerciseSlashers(V1Vault[] memory vaults, address owner) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _exerciseSlasher(vaults[i], owner);
        }
    }

    function _existingVaults(Assets memory assets) internal view returns (V1Vault[] memory vaults) {
        vaults = new V1Vault[](VAULT_COUNT);
        if (block.chainid == 560_048) {
            vaults[0] = _vaultData(
                assets.usdc,
                0,
                address(0x565776fd4250b08661a9D87da83872E6dF8DA19c),
                address(0xBbBD15A4147a84EBFf23a5F1B0638eAd2e18F17b),
                address(0)
            );
            vaults[1] = _vaultData(
                assets.aUsd,
                1,
                address(0xFDA32FC73d690dF12cfE6759587C6381b9e1a671),
                address(0xf5D6EB34d08263bF3CDE8e16b15CE56064E9Ada1),
                address(0x73c8F462a3B17A303322D61fD88D7bD5FED3bCf1)
            );
            vaults[2] = _vaultData(
                assets.mFone,
                2,
                address(0x71cFA131bd81796E052d243292751a262A6A1bB5),
                address(0xAcCe35D58eab1175247E749295cBB184237A6026),
                address(0x4428D333D625Fa89c7aB2F5198983C0d261767D3)
            );
            vaults[3] = _vaultData(
                assets.mGlobal,
                3,
                address(0x732caFE0A4bd2d8CEbF267FE7aA9515e8eeE8a92),
                address(0x72505F810A35B7BD75E835a9f2094BFe9E63f5b7),
                address(0x49d362090cFAa25B72cB8250eC640f555A8112c8)
            );
            vaults[4] = _vaultData(
                assets.usdc,
                4,
                address(0xD910d469a5B27e73506af62C7864B5894959FfA0),
                address(0x04E9F66b15146a2DF7203c11fc6C31FcEf0C78B5),
                address(0x329D32cEaF17de5d65E6Fa1C9bb673233FB5c01E)
            );
            vaults[5] = _vaultData(
                assets.aUsd,
                5,
                address(0x79258F5181C2A1a944b513441D1ED71b28239022),
                address(0x889bcB80b564e53cE033F9e25b2e3A28C526EfAb),
                address(0)
            );
            vaults[6] = _vaultData(
                assets.mFone,
                6,
                address(0x053acd38ED43C934752FF15CacddAb8839Fa1B56),
                address(0xAAAB65171058c7A620e4371C3c2cAEC3c52A7733),
                address(0xb0c914113405fB023b284838ba77a7d8AC2AFE62)
            );
            vaults[7] = _vaultData(
                assets.mGlobal,
                7,
                address(0x634F713150450c4dBA2fc3212Fc649aA71300a44),
                address(0xAfc45A099788BFCa288658890b78A493fC5FF0F3),
                address(0xd8e9C1b8A097C880Af38e7BF951B746Bb65B3FE1)
            );
            return vaults;
        }

        if (block.chainid != 11_155_111) {
            revert("existing v1 vaults not configured");
        }

        vaults[0] = _vaultData(
            assets.usdc,
            0,
            address(0xB109B4930ac95FC37DD2E70a44aABD1268F7265f),
            address(0xfE0287dAc3082a442a5E5ac0b3c9fCAFF68CB01b),
            address(0)
        );
        vaults[1] = _vaultData(
            assets.aUsd,
            1,
            address(0x5764A74AE8d53f862B87e2Be9677dA8094433B09),
            address(0x4D26e50DC505b9E763791Ecc596b5C62D8405565),
            address(0xbFF2626864C0eCaEbb2574b5f0cd50e338f4FA98)
        );
        vaults[2] = _vaultData(
            assets.mFone,
            2,
            address(0x3E6343222B1c419bFCC063AeE6a9d08f3135f62B),
            address(0xE2358406c11761ba180F80C595BC2Ac7Ba648C12),
            address(0x93dfA94eeb89Ea7644FA62dCd2f44ea457cC5c4A)
        );
        vaults[3] = _vaultData(
            assets.mGlobal,
            3,
            address(0x6FD29ba3601956Ea35eBa9a910852649e08D73Dd),
            address(0x336f30645b1af686DBD675cCC557799ADf89F2f0),
            address(0x007E85a5BC41E59D56102775fDB6A8283698600d)
        );
        vaults[4] = _vaultData(
            assets.usdc,
            4,
            address(0xd6c83453CF65680e1CB92292CF8848BBa069d85E),
            address(0x0D2d9Db4f25640aB21Ea2943448c5f9aa6BC1e2C),
            address(0x70F9aCf828cc942016ed7cA56F683aD8c70Db543)
        );
        vaults[5] = _vaultData(
            assets.aUsd,
            5,
            address(0xeD7Fa232AB2B48b02bEf1141729E94ffB8B016e1),
            address(0xcF3214cFB97ec954f406C5f39e2750bAf89222Ce),
            address(0)
        );
        vaults[6] = _vaultData(
            assets.mFone,
            6,
            address(0x52422bC714D5e920fD149E6D923c731aE49fd3cB),
            address(0x0457077c27dbB06C45a694009578Aa1092E47004),
            address(0xD4c8070fA057A09E67826cE93897B957F4386d13)
        );
        vaults[7] = _vaultData(
            assets.mGlobal,
            7,
            address(0xB3ea96F35f85A0Ba27201A52219Ad4B0B2c4325c),
            address(0x6a98137C0441579b57A50e071C9BE2EA291eeE0b),
            address(0x590a964674EBbF100BeD9f0b81309405D52CeECf)
        );
    }

    function _vaultData(address asset, uint256 index, address vault, address delegator, address slasher)
        internal
        view
        returns (V1Vault memory)
    {
        uint64 slasherType = uint64(index % 3 == 0 ? 1 : 0);
        return V1Vault({
            vault: vault,
            delegator: delegator,
            slasher: slasher,
            asset: asset,
            vaultVersion: index % 2 == 1 ? VAULT_TOKENIZED_VERSION : VAULT_VERSION,
            delegatorType: uint64(index % 4),
            slasherType: slasherType,
            withSlasher: index != 0 && index != 5,
            vetoWithResolver: slasherType == 1 && index % 2 == 1,
            subnetworkId: uint96(10_000 + index),
            claimEpoch: 0,
            depositAmount: _units(asset, 1000 + index * 100)
        });
    }

    function _createVault(Core memory core, address asset, address owner, uint256 index)
        internal
        returns (V1Vault memory vaultData)
    {
        CreateConfig memory config = _createConfig(asset, owner, index);

        (address vault, address delegator, address slasher) = IVaultConfigurator(core.vaultConfigurator)
            .create(
                IVaultConfigurator.InitParams({
                version: config.vaultVersion,
                owner: owner,
                vaultParams: config.vaultParams,
                delegatorIndex: config.delegatorType,
                delegatorParams: config.delegatorParams,
                withSlasher: config.withSlasher,
                slasherIndex: config.slasherType,
                slasherParams: config.slasherParams
            })
            );

        vaultData = V1Vault({
            vault: vault,
            delegator: delegator,
            slasher: slasher,
            asset: asset,
            vaultVersion: config.vaultVersion,
            delegatorType: config.delegatorType,
            slasherType: config.slasherType,
            withSlasher: config.withSlasher,
            vetoWithResolver: config.vetoWithResolver,
            subnetworkId: uint96(10_000 + index),
            claimEpoch: 0,
            depositAmount: _units(asset, 1000 + index * 100)
        });
    }

    function _createConfig(address asset, address owner, uint256 index)
        internal
        view
        returns (CreateConfig memory config)
    {
        config.delegatorType = uint64(index % 4);
        config.slasherType = uint64(index % 3 == 0 ? 1 : 0);
        config.vaultVersion = index % 2 == 1 ? VAULT_TOKENIZED_VERSION : VAULT_VERSION;
        config.withSlasher = index != 0 && index != 5;
        config.vetoWithResolver = config.slasherType == 1 && index % 2 == 1;
        config.vaultParams = _encodedVaultParams(
            asset,
            owner,
            index,
            config.withSlasher ? uint48(1 days) : uint48(2),
            config.vaultVersion == VAULT_TOKENIZED_VERSION
        );
        config.delegatorParams = _delegatorParams(owner, config.delegatorType);
        config.slasherParams = config.withSlasher ? _slasherParams(config.slasherType, index) : bytes("");
    }

    function _exerciseVaults(Core memory core, V1Vault[] memory vaults, address owner) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _configureVault(vaults[i], owner);
            _configureDelegator(vaults[i], owner);
            _exerciseDeposits(vaults[i], owner);
            _exerciseSlasher(vaults[i], owner);
            emit V1VaultExercised(i, vaults[i].vault, vaults[i].claimEpoch);
        }

        vm.sleep(6000);

        for (uint256 i; i < vaults.length; ++i) {
            _exerciseClaims(vaults[i], owner);
            _exerciseViews(core, vaults[i], owner);
        }
    }

    function _configureVault(V1Vault memory vault, address owner) internal {
        if (!IVault(vault.vault).isDepositorWhitelisted(owner)) {
            IVault(vault.vault).setDepositorWhitelistStatus(owner, true);
        }

        if (!IVault(vault.vault).depositWhitelist()) {
            IVault(vault.vault).setDepositWhitelist(true);
        }
        if (!IVault(vault.vault).isDepositLimit()) {
            IVault(vault.vault).setIsDepositLimit(true);
        }
        if (IVault(vault.vault).depositLimit() != vault.depositAmount * 20) {
            IVault(vault.vault).setDepositLimit(vault.depositAmount * 20);
        }

        if (IVault(vault.vault).depositWhitelist()) {
            IVault(vault.vault).setDepositWhitelist(false);
        }
        if (IVault(vault.vault).isDepositLimit()) {
            IVault(vault.vault).setIsDepositLimit(false);
        }
        if (IVault(vault.vault).depositLimit() != type(uint256).max) {
            IVault(vault.vault).setDepositLimit(type(uint256).max);
        }
    }

    function _configureDelegator(V1Vault memory vault, address owner) internal {
        bytes32 subnetwork = _subnetwork(owner, vault.subnetworkId);
        uint256 limit = vault.depositAmount * 10;

        if (IBaseDelegator(vault.delegator).maxNetworkLimit(subnetwork) != limit) {
            IBaseDelegator(vault.delegator).setMaxNetworkLimit(vault.subnetworkId, limit);
        }

        if (vault.delegatorType == 0) {
            if (INetworkRestakeDelegator(vault.delegator).networkLimit(subnetwork) != limit) {
                INetworkRestakeDelegator(vault.delegator).setNetworkLimit(subnetwork, limit);
            }
            if (INetworkRestakeDelegator(vault.delegator).operatorNetworkShares(subnetwork, owner) != 1) {
                INetworkRestakeDelegator(vault.delegator).setOperatorNetworkShares(subnetwork, owner, 1);
            }
        } else if (vault.delegatorType == 1) {
            if (IFullRestakeDelegator(vault.delegator).networkLimit(subnetwork) != limit) {
                IFullRestakeDelegator(vault.delegator).setNetworkLimit(subnetwork, limit);
            }
            if (IFullRestakeDelegator(vault.delegator).operatorNetworkLimit(subnetwork, owner) != limit) {
                IFullRestakeDelegator(vault.delegator).setOperatorNetworkLimit(subnetwork, owner, limit);
            }
        } else if (vault.delegatorType == 2) {
            if (IOperatorSpecificDelegator(vault.delegator).networkLimit(subnetwork) != limit) {
                IOperatorSpecificDelegator(vault.delegator).setNetworkLimit(subnetwork, limit);
            }
        }
    }

    function _exerciseDeposits(V1Vault memory vault, address owner) internal {
        IERC20(vault.asset).approve(vault.vault, type(uint256).max);
        IVault(vault.vault).deposit(owner, vault.depositAmount);
        IVault(vault.vault).activeBalanceOf(owner);
        IVault(vault.vault).slashableBalanceOf(owner);

        uint256 withdrawAmount = vault.depositAmount / 10;
        IVault(vault.vault).withdraw(owner, withdrawAmount);
        vault.claimEpoch = IVault(vault.vault).currentEpoch() + 1;

        uint256 shares = IVault(vault.vault).activeSharesOf(owner) / 10;
        if (shares > 0) {
            IVault(vault.vault).redeem(owner, shares);
        }
    }

    function _exerciseSlasher(V1Vault memory vault, address owner) internal {
        if (!vault.withSlasher) {
            return;
        }

        bytes32 subnetwork = _subnetwork(owner, vault.subnetworkId);

        if (vault.slasherType == 0) {
            uint48 captureTimestamp = _past(1);
            uint256 slashable = IBaseSlasher(vault.slasher).slashableStake(subnetwork, owner, captureTimestamp, "");
            if (slashable > 0) {
                ISlasher(vault.slasher).slash(subnetwork, owner, slashable / 20, captureTimestamp, "");
            }
            return;
        }

        uint48 capture = _past(1);
        uint256 vetoSlashable = IBaseSlasher(vault.slasher).slashableStake(subnetwork, owner, capture, "");
        if (vetoSlashable == 0) {
            return;
        }

        if (vault.vetoWithResolver) {
            if (IVetoSlasher(vault.slasher).resolver(subnetwork, "") != owner) {
                IVetoSlasher(vault.slasher).setResolver(vault.subnetworkId, owner, "");
                return;
            }
            uint256 slashIndex =
                IVetoSlasher(vault.slasher).requestSlash(subnetwork, owner, vetoSlashable / 20, capture, "");
            IVetoSlasher(vault.slasher).vetoSlash(slashIndex, "");
        } else {
            uint256 slashIndex =
                IVetoSlasher(vault.slasher).requestSlash(subnetwork, owner, vetoSlashable / 20, capture, "");
            IVetoSlasher(vault.slasher).executeSlash(slashIndex, "");
        }
    }

    function _exerciseClaims(V1Vault memory vault, address owner) internal {
        uint256 currentEpoch = IVault(vault.vault).currentEpoch();
        if (
            vault.claimEpoch != 0 && currentEpoch > vault.claimEpoch
                && IVault(vault.vault).withdrawalsOf(vault.claimEpoch, owner) > 0
        ) {
            IVault(vault.vault).claim(owner, vault.claimEpoch);
        }

        uint256 previousEpoch = currentEpoch == 0 ? 0 : currentEpoch - 1;
        if (previousEpoch != vault.claimEpoch && IVault(vault.vault).withdrawalsOf(previousEpoch, owner) > 0) {
            uint256[] memory epochs = new uint256[](1);
            epochs[0] = previousEpoch;
            IVault(vault.vault).claimBatch(owner, epochs);
        }
    }

    function _exerciseViews(Core memory core, V1Vault memory vault, address owner) internal view {
        bytes32 subnetwork = _subnetwork(owner, vault.subnetworkId);
        IVault(vault.vault).totalStake();
        IVault(vault.vault).activeBalanceOfAt(owner, _past(1), "");
        IBaseDelegator(vault.delegator).stake(subnetwork, owner);
        IRegistry(core.networkRegistry).isEntity(owner);
        IRegistry(core.operatorRegistry).isEntity(owner);
    }

    function _registerAndOptBase(Core memory core, address owner) internal {
        if (!IRegistry(core.networkRegistry).isEntity(owner)) {
            INetworkRegistryV1Exercise(core.networkRegistry).registerNetwork();
        }
        if (INetworkMiddlewareService(core.networkMiddlewareService).middleware(owner) != owner) {
            INetworkMiddlewareService(core.networkMiddlewareService).setMiddleware(owner);
        }
        if (!IRegistry(core.operatorRegistry).isEntity(owner)) {
            IOperatorRegistryV1Exercise(core.operatorRegistry).registerOperator();
        }
        _optInIfNeeded(core.operatorNetworkOptInService, owner, owner);
    }

    function _optInIfNeeded(address service, address who, address where) internal {
        if (!IOptInService(service).isOptedIn(who, where)) {
            IOptInService(service).optIn(where);
        }
    }

    function _mintAssets(Assets memory assets, address owner) internal {
        IMintableERC20(assets.usdc).mint(owner, _units(assets.usdc, 5_000_000));
        IMintableERC20(assets.aUsd).mint(owner, _units(assets.aUsd, 5_000_000));
        IMintableERC20(assets.mFone).mint(owner, _units(assets.mFone, 5_000_000));
        IMintableERC20(assets.mGlobal).mint(owner, _units(assets.mGlobal, 5_000_000));
    }

    function _vaultParams(address asset, address owner, uint256 index, uint48 epochDuration)
        internal
        pure
        returns (IVault.InitParams memory)
    {
        return IVault.InitParams({
            collateral: asset,
            burner: owner,
            epochDuration: epochDuration,
            depositWhitelist: index % 2 == 0,
            isDepositLimit: index % 3 == 0,
            depositLimit: type(uint256).max,
            defaultAdminRoleHolder: owner,
            depositWhitelistSetRoleHolder: owner,
            depositorWhitelistRoleHolder: owner,
            isDepositLimitSetRoleHolder: owner,
            depositLimitSetRoleHolder: owner
        });
    }

    function _encodedVaultParams(address asset, address owner, uint256 index, uint48 epochDuration, bool tokenized)
        internal
        view
        returns (bytes memory)
    {
        IVault.InitParams memory baseParams = _vaultParams(asset, owner, index, epochDuration);
        if (!tokenized) {
            return abi.encode(baseParams);
        }
        return abi.encode(
            IVaultTokenized.InitParamsTokenized({
                baseParams: baseParams,
                name: string.concat("Latest V1 Testnet Vault ", vm.toString(index)),
                symbol: string.concat("lv1-", vm.toString(index))
            })
        );
    }

    function _delegatorParams(address owner, uint64 delegatorType) internal pure returns (bytes memory) {
        IBaseDelegator.BaseParams memory baseParams =
            IBaseDelegator.BaseParams({defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: owner});
        address[] memory ownerList = _singleton(owner);

        if (delegatorType == 0) {
            return abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: ownerList,
                    operatorNetworkSharesSetRoleHolders: ownerList
                })
            );
        }
        if (delegatorType == 1) {
            return abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: ownerList,
                    operatorNetworkLimitSetRoleHolders: ownerList
                })
            );
        }
        if (delegatorType == 2) {
            return abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams, networkLimitSetRoleHolders: ownerList, operator: owner
                })
            );
        }
        return abi.encode(
            IOperatorNetworkSpecificDelegator.InitParams({baseParams: baseParams, network: owner, operator: owner})
        );
    }

    function _slasherParams(uint64 slasherType, uint256 index) internal pure returns (bytes memory) {
        IBaseSlasher.BaseParams memory baseParams = IBaseSlasher.BaseParams({isBurnerHook: false});
        if (slasherType == 0) {
            return abi.encode(ISlasher.InitParams({baseParams: baseParams}));
        }
        return abi.encode(
            IVetoSlasher.InitParams({
                baseParams: baseParams, vetoDuration: uint48(index % 2 == 0 ? 1 : 10), resolverSetEpochsDelay: 3
            })
        );
    }

    function _latestDeployment() internal view returns (Core memory core, Assets memory assets) {
        if (block.chainid == 560_048) {
            core = Core({
                vaultConfigurator: vm.envOr(
                    "TESTNET_V1_VAULT_CONFIGURATOR", address(0x4624f1066390cCDFCae3F525e3C1fCA2b6EEf63a)
                ),
                networkRegistry: vm.envOr(
                    "TESTNET_V1_NETWORK_REGISTRY", address(0xb2EfA49BB2Aa418ac55bA7DdaA1Cf647F7fb465f)
                ),
                networkMiddlewareService: vm.envOr(
                    "TESTNET_V1_NETWORK_MIDDLEWARE_SERVICE", address(0xf431e69aa7329CaDBc44AF07504cadA9817975F9)
                ),
                operatorRegistry: vm.envOr(
                    "TESTNET_V1_OPERATOR_REGISTRY", address(0xca9cc351C8165d22D0Fd0831C560474b94be5CcD)
                ),
                operatorVaultOptInService: vm.envOr(
                    "TESTNET_V1_OPERATOR_VAULT_OPT_IN_SERVICE", address(0xc2641656a17154C0a97ba5E45542546c15599276)
                ),
                operatorNetworkOptInService: vm.envOr(
                    "TESTNET_V1_OPERATOR_NETWORK_OPT_IN_SERVICE", address(0x8090EeF9fd4EFFe0864CF7451DaD68661bd95e49)
                )
            });
            assets = Assets({
                usdc: vm.envOr("TESTNET_V1_USDC", address(0x9B97F7eDAbd9Ef43cAcE2eaFDD1DE5721aE3Bdd3)),
                aUsd: vm.envOr("TESTNET_V1_AUSD", address(0x17Eef10B14D727fB700918687e4d1D0D323efB5D)),
                mFone: vm.envOr("TESTNET_V1_MFONE", address(0xA684911e92b8E4Dd27046331B849Bbd6dbca0fA2)),
                mGlobal: vm.envOr("TESTNET_V1_MGLOBAL", address(0x2Ee6f1A395Bce7a7c5bF1D07bAaF9F8A0828A8d3))
            });
        } else if (block.chainid == 11_155_111) {
            core = Core({
                vaultConfigurator: vm.envOr(
                    "TESTNET_V1_VAULT_CONFIGURATOR", address(0x0216b8363AA0682F4a1f77BC33bB15Be97689b23)
                ),
                networkRegistry: vm.envOr(
                    "TESTNET_V1_NETWORK_REGISTRY", address(0x653618ea4AE1112b0Bb78E208605A3897A4fD5Dd)
                ),
                networkMiddlewareService: vm.envOr(
                    "TESTNET_V1_NETWORK_MIDDLEWARE_SERVICE", address(0x4036F988198D5dEBC069bA8666c1005C27ed3dA3)
                ),
                operatorRegistry: vm.envOr(
                    "TESTNET_V1_OPERATOR_REGISTRY", address(0x8ccf50CEC5D9A4fE992707c199ce3E5D88F4181a)
                ),
                operatorVaultOptInService: vm.envOr(
                    "TESTNET_V1_OPERATOR_VAULT_OPT_IN_SERVICE", address(0x6989A4B9F67506F47932254B414aCc4F41D4e317)
                ),
                operatorNetworkOptInService: vm.envOr(
                    "TESTNET_V1_OPERATOR_NETWORK_OPT_IN_SERVICE", address(0xe548a3cF51EE51413D9F99dd39978CA0a4B9548E)
                )
            });
            assets = Assets({
                usdc: vm.envOr("TESTNET_V1_USDC", address(0xc06ea690d3eC9a85E1e1603f366f13c50d80afD3)),
                aUsd: vm.envOr("TESTNET_V1_AUSD", address(0x4DB97050730c79f69716C2c8d551DD21c49ac1a5)),
                mFone: vm.envOr("TESTNET_V1_MFONE", address(0x5702FDa445cff75bbCA4e24c1e18f38f4A6b2176)),
                mGlobal: vm.envOr("TESTNET_V1_MGLOBAL", address(0xb547DCEcfC86FCC7B2964A4d9A2d5e8CFc407593))
            });
        } else {
            revert("unsupported chain");
        }
    }

    function _assetAt(Assets memory assets, uint256 index) internal pure returns (address) {
        uint256 item = index % 4;
        if (item == 0) return assets.usdc;
        if (item == 1) return assets.aUsd;
        if (item == 2) return assets.mFone;
        return assets.mGlobal;
    }

    function _units(address token, uint256 amount) internal view returns (uint256) {
        return amount * 10 ** IERC20Metadata(token).decimals();
    }

    function _subnetwork(address network, uint96 identifier) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network)) << 96 | identifier);
    }

    function _past(uint48 secondsAgo) internal view returns (uint48) {
        return uint48(block.timestamp - secondsAgo);
    }

    function _singleton(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _scriptOwner() internal view returns (address owner) {
        (,, address origin) = vm.readCallers();
        owner = origin == address(0) ? msg.sender : origin;
    }

    function _logSummary(V1Vault[] memory vaults) internal view {
        console2.log("latest v1 deployment exercised", vaults.length);
        for (uint256 i; i < vaults.length; ++i) {
            console2.log("index", i);
            console2.log("  vault", vaults[i].vault);
            console2.log("  delegator", vaults[i].delegator);
            console2.log("  slasher", vaults[i].slasher);
            console2.log("  asset", vaults[i].asset);
        }
    }
}
