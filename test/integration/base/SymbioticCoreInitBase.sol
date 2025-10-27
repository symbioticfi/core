// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreImports.sol";

import "../SymbioticUtils.sol";
import {SymbioticCoreConstants} from "../SymbioticCoreConstants.sol";
import {SymbioticCoreBytecode} from "../SymbioticCoreBytecode.sol";
import {SymbioticCoreBindingsBase} from "./SymbioticCoreBindingsBase.sol";

import {Token} from "../../mocks/Token.sol";
import {FeeOnTransferToken} from "../../mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract SymbioticCoreInitBase is SymbioticUtils, SymbioticCoreBindingsBase {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;

    struct InitCoreLocalVars {
        VmSafe.CallerMode callerMode;
        address deployer;
        address vaultImpl;
        address vaultTokenizedImpl;
        address networkRestakeDelegatorImpl;
        address fullRestakeDelegatorImpl;
        address operatorSpecificDelegatorImpl;
        address operatorNetworkSpecificDelegatorImpl;
        address slasherImpl;
        address vetoSlasherImpl;
    }

    struct GetVaultLocalVars {
        bool depositWhitelist;
        bytes vaultParams;
        uint256 roleHolders;
        address[] networkLimitSetRoleHolders;
        address[] operatorNetworkLimitSetRoleHolders;
        address[] operatorNetworkSharesSetRoleHolders;
        bytes delegatorParams;
        bytes slasherParams;
        Vm.CallerMode callerMode;
        address deployer;
        address vault;
    }

    struct VaultParams {
        address owner;
        address collateral;
        address burner;
        uint48 epochDuration;
        address[] whitelistedDepositors;
        uint256 depositLimit;
        uint64 delegatorIndex;
        address hook;
        address network;
        bool withSlasher;
        uint64 slasherIndex;
        uint48 vetoDuration;
    }

    // General config

    bool public SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = false;

    // Vaults-related config

    uint256 public SYMBIOTIC_CORE_MIN_EPOCH_DURATION = 60 minutes;
    uint256 public SYMBIOTIC_CORE_MAX_EPOCH_DURATION = 60 days;
    uint256 public SYMBIOTIC_CORE_MIN_VETO_DURATION = 5 minutes;
    uint256 public SYMBIOTIC_CORE_MAX_VETO_DURATION = 14 days;
    uint64[] public SYMBIOTIC_CORE_DELEGATOR_TYPES = [0, 1, 2];
    uint64[] public SYMBIOTIC_CORE_SLASHER_TYPES = [0, 1];

    // Staker-related config

    uint256 public SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18 = 100_000_000 * 1e18;
    uint256 public SYMBIOTIC_CORE_MIN_TOKENS_TO_DEPOSIT_TIMES_1e18 = 0.001 * 1e18;
    uint256 public SYMBIOTIC_CORE_MAX_TOKENS_TO_DEPOSIT_TIMES_1e18 = 10_000 * 1e18;

    // Delegation-related config

    uint256 public SYMBIOTIC_CORE_MIN_MAX_NETWORK_LIMIT_TIMES_1e18 = 0.001 * 1e18;
    uint256 public SYMBIOTIC_CORE_MAX_MAX_NETWORK_LIMIT_TIMES_1e18 = 2_000_000_000 * 1e18;
    uint256 public SYMBIOTIC_CORE_MIN_NETWORK_LIMIT_TIMES_1e18 = 0.001 * 1e18;
    uint256 public SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_TIMES_1e18 = 2_000_000_000 * 1e18;
    uint256 public SYMBIOTIC_CORE_MIN_OPERATOR_NETWORK_LIMIT_TIMES_1e18 = 0.001 * 1e18;
    uint256 public SYMBIOTIC_CORE_MAX_OPERATOR_NETWORK_LIMIT_TIMES_1e18 = 2_000_000_000 * 1e18;
    uint256 public SYMBIOTIC_CORE_MIN_OPERATOR_NETWORK_SHARES = 1000;
    uint256 public SYMBIOTIC_CORE_MAX_OPERATOR_NETWORK_SHARES = 1e18;

    SymbioticCoreConstants.Core public symbioticCore;

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _initCore_SymbioticCore() internal virtual {
        symbioticCore = SymbioticCoreConstants.core();
    }

    // if useExisting is true, the core is not deployed, but the addresses are returned
    function _initCore_SymbioticCore(bool useExisting) internal virtual returns (SymbioticCoreConstants.Core memory) {
        if (useExisting) {
            // return existing core
            symbioticCore = SymbioticCoreConstants.core();
        } else {
            InitCoreLocalVars memory vars;
            (vars.callerMode,, vars.deployer) = vm.readCallers();

            _stopBroadcastWhenCallerModeIsSingle(vars.callerMode);
            _startBroadcastWhenCallerModeIsNotRecurrent(vars.callerMode, vars.deployer);

            _deployCoreFactories(vars.deployer);
            _deployCoreRegistries();
            _deployCoreServices();
            _whitelistVaultImplementations();
            _whitelistDelegatorImplementations();
            _whitelistSlasherImplementations();

            _stopBroadcastWhenCallerModeIsNotRecurrent(vars.callerMode);
        }
        return symbioticCore;
    }

    function _deployCreate2(bytes32 salt, bytes memory baseCode, bytes memory constructorArgs)
        internal
        returns (address deployed)
    {
        bytes memory creationCode;
        assembly {
            creationCode := mload(0x40)
            let w := not(0x1f)
            let baseCodeLen := mload(baseCode)
            // Copy `baseCode` one word at a time, backwards.
            for { let o := and(add(baseCodeLen, 0x20), w) } 1 {} {
                mstore(add(creationCode, o), mload(add(baseCode, o)))
                o := add(o, w) // `sub(o, 0x20)`.
                if iszero(o) { break }
            }
            let constructorArgsLen := mload(constructorArgs)
            let output := add(creationCode, baseCodeLen)
            // Copy `constructorArgs` one word at a time, backwards.
            for { let o := and(add(constructorArgsLen, 0x20), w) } 1 {} {
                mstore(add(output, o), mload(add(constructorArgs, o)))
                o := add(o, w) // `sub(o, 0x20)`.
                if iszero(o) { break }
            }
            let totalLen := add(baseCodeLen, constructorArgsLen)
            let last := add(add(creationCode, 0x20), totalLen)
            mstore(last, 0) // Zeroize the slot after the bytes.
            mstore(creationCode, totalLen) // Store the length.
            mstore(0x40, add(last, 0x20)) // Allocate memory.
        }
        return Create2.deploy(0, salt, creationCode);
    }

    function _deployCoreFactories(address deployer) internal virtual {
        bytes memory constructorArgs = abi.encode(deployer);
        symbioticCore.vaultFactory = ISymbioticVaultFactory(
            _deployCreate2(bytes32("vaultFactory"), SymbioticCoreBytecode.vaultFactory(), constructorArgs)
        );
        symbioticCore.delegatorFactory = ISymbioticDelegatorFactory(
            _deployCreate2(bytes32("delegatorFactory"), SymbioticCoreBytecode.delegatorFactory(), constructorArgs)
        );
        symbioticCore.slasherFactory = ISymbioticSlasherFactory(
            _deployCreate2(bytes32("slasherFactory"), SymbioticCoreBytecode.slasherFactory(), constructorArgs)
        );
    }

    function _deployCoreRegistries() internal virtual {
        symbioticCore.networkRegistry = ISymbioticNetworkRegistry(
            _deployCreate2(bytes32("networkRegistry"), SymbioticCoreBytecode.networkRegistry(), "")
        );
        symbioticCore.operatorRegistry = ISymbioticOperatorRegistry(
            _deployCreate2(bytes32("operatorRegistry"), SymbioticCoreBytecode.operatorRegistry(), "")
        );
    }

    function _deployCoreServices() internal virtual {
        address operatorRegistry = address(symbioticCore.operatorRegistry);
        address networkRegistry = address(symbioticCore.networkRegistry);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address delegatorFactory = address(symbioticCore.delegatorFactory);
        address slasherFactory = address(symbioticCore.slasherFactory);
        bytes memory constructorArgs;

        constructorArgs = abi.encode(operatorRegistry);
        symbioticCore.operatorMetadataService = ISymbioticMetadataService(
            _deployCreate2(bytes32("operatorMetadataService"), SymbioticCoreBytecode.metadataService(), constructorArgs)
        );

        constructorArgs = abi.encode(networkRegistry);
        symbioticCore.networkMetadataService = ISymbioticMetadataService(
            _deployCreate2(bytes32("networkMetadataService"), SymbioticCoreBytecode.metadataService(), constructorArgs)
        );

        constructorArgs = abi.encode(networkRegistry);
        symbioticCore.networkMiddlewareService = ISymbioticNetworkMiddlewareService(
            _deployCreate2(
                bytes32("networkMiddlewareService"), SymbioticCoreBytecode.networkMiddlewareService(), constructorArgs
            )
        );

        constructorArgs = abi.encode(operatorRegistry, vaultFactory, "OperatorVaultOptInService");
        symbioticCore.operatorVaultOptInService = ISymbioticOptInService(
            _deployCreate2(bytes32("operatorVaultOptInService"), SymbioticCoreBytecode.optInService(), constructorArgs)
        );

        constructorArgs = abi.encode(operatorRegistry, networkRegistry, "OperatorNetworkOptInService");
        symbioticCore.operatorNetworkOptInService = ISymbioticOptInService(
            _deployCreate2(
                bytes32("operatorNetworkOptInService"), SymbioticCoreBytecode.optInService(), constructorArgs
            )
        );

        constructorArgs = abi.encode(vaultFactory, delegatorFactory, slasherFactory);
        symbioticCore.vaultConfigurator = ISymbioticVaultConfigurator(
            _deployCreate2(bytes32("vaultConfigurator"), SymbioticCoreBytecode.vaultConfigurator(), constructorArgs)
        );
    }

    function _whitelistVaultImplementations() internal virtual {
        address delegatorFactory = address(symbioticCore.delegatorFactory);
        address slasherFactory = address(symbioticCore.slasherFactory);
        address vaultFactory = address(symbioticCore.vaultFactory);
        bytes memory constructorArgs = abi.encode(delegatorFactory, slasherFactory, vaultFactory);

        symbioticCore.vaultFactory
            .whitelist(_deployCreate2(bytes32("vault"), SymbioticCoreBytecode.vault(), constructorArgs));
        symbioticCore.vaultFactory
            .whitelist(
                _deployCreate2(bytes32("vaultTokenized"), SymbioticCoreBytecode.vaultTokenized(), constructorArgs)
            );
    }

    function _whitelistDelegatorImplementations() internal virtual {
        ISymbioticDelegatorFactory factory = symbioticCore.delegatorFactory;
        address factoryAddress = address(factory);
        address networkRegistry = address(symbioticCore.networkRegistry);
        address operatorRegistry = address(symbioticCore.operatorRegistry);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address operatorVaultOptInService = address(symbioticCore.operatorVaultOptInService);
        address operatorNetworkOptInService = address(symbioticCore.operatorNetworkOptInService);
        address implementation;
        uint256 typeIndex;
        bytes memory constructorArgs;

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            factoryAddress,
            typeIndex
        );
        implementation = _deployCreate2(
            bytes32("networkRestakeDelegator"), SymbioticCoreBytecode.networkRestakeDelegator(), constructorArgs
        );
        factory.whitelist(implementation);

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            factoryAddress,
            typeIndex
        );
        implementation = _deployCreate2(
            bytes32("fullRestakeDelegator"), SymbioticCoreBytecode.fullRestakeDelegator(), constructorArgs
        );
        factory.whitelist(implementation);

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(
            operatorRegistry,
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            factoryAddress,
            typeIndex
        );
        implementation = _deployCreate2(
            bytes32("operatorSpecificDelegator"), SymbioticCoreBytecode.operatorSpecificDelegator(), constructorArgs
        );
        factory.whitelist(implementation);

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(
            operatorRegistry,
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            factoryAddress,
            typeIndex
        );
        implementation = _deployCreate2(
            bytes32("operatorNetworkSpecificDelegator"),
            SymbioticCoreBytecode.operatorNetworkSpecificDelegator(),
            constructorArgs
        );
        factory.whitelist(implementation);
    }

    function _whitelistSlasherImplementations() internal virtual {
        ISymbioticSlasherFactory factory = symbioticCore.slasherFactory;
        address factoryAddress = address(factory);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address networkMiddlewareService = address(symbioticCore.networkMiddlewareService);
        address networkRegistry = address(symbioticCore.networkRegistry);
        address implementation;
        uint256 typeIndex;
        bytes memory constructorArgs;

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(vaultFactory, networkMiddlewareService, factoryAddress, typeIndex);
        implementation = _deployCreate2(bytes32("slasher"), SymbioticCoreBytecode.slasher(), constructorArgs);
        factory.whitelist(implementation);

        typeIndex = factory.totalTypes();
        constructorArgs = abi.encode(vaultFactory, networkMiddlewareService, networkRegistry, factoryAddress, typeIndex);
        implementation = _deployCreate2(bytes32("vetoSlasher"), SymbioticCoreBytecode.vetoSlasher(), constructorArgs);
        factory.whitelist(implementation);
    }

    // ------------------------------------------------------------ TOKEN-RELATED HELPERS ------------------------------------------------------------ //

    function _getToken_SymbioticCore() internal virtual returns (address) {
        return address(new Token("Token"));
    }

    function _getFeeOnTransferToken_SymbioticCore() internal virtual returns (address) {
        return address(new FeeOnTransferToken("Token"));
    }

    function _getSupportedTokens_SymbioticCore() internal virtual returns (address[] memory supportedTokens) {
        string[] memory supportedTokensStr = SymbioticCoreConstants.supportedTokens();
        supportedTokens = new address[](supportedTokensStr.length);
        for (uint256 i; i < supportedTokensStr.length; ++i) {
            supportedTokens[i] = SymbioticCoreConstants.token(supportedTokensStr[i]);
        }
    }

    // ------------------------------------------------------------ VAULT-RELATED HELPERS ------------------------------------------------------------ //

    function _getVault_SymbioticCore(address collateral) internal virtual returns (address) {
        (Vm.CallerMode callerMode,, address owner) = vm.readCallers();

        _stopBroadcastWhenCallerModeIsSingleOrRecurrent(callerMode);

        uint48 epochDuration = 7 days;
        uint48 vetoDuration = 1 days;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;
        (address vault,,) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: owner,
            version: 1,
            owner: owner,
            vaultParams: abi.encode(
                ISymbioticVault.InitParams({
                    collateral: collateral,
                    burner: 0x000000000000000000000000000000000000dEaD,
                    epochDuration: epochDuration,
                    depositWhitelist: false,
                    isDepositLimit: false,
                    depositLimit: 0,
                    defaultAdminRoleHolder: owner,
                    depositWhitelistSetRoleHolder: owner,
                    depositorWhitelistRoleHolder: owner,
                    isDepositLimitSetRoleHolder: owner,
                    depositLimitSetRoleHolder: owner
                })
            ),
            delegatorIndex: 0,
            delegatorParams: abi.encode(
                ISymbioticNetworkRestakeDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: 0x0000000000000000000000000000000000000000,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                })
            ),
            withSlasher: true,
            slasherIndex: 1,
            slasherParams: abi.encode(
                ISymbioticVetoSlasher.InitParams({
                    baseParams: ISymbioticBaseSlasher.BaseParams({isBurnerHook: true}),
                    vetoDuration: vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            )
        });

        _startBroadcastWhenCallerModeIsRecurrent(callerMode, owner);

        return vault;
    }

    function _getVault_SymbioticCore(VaultParams memory params) internal virtual returns (address vault) {
        GetVaultLocalVars memory vars;
        vars.depositWhitelist = params.whitelistedDepositors.length != 0;

        vars.vaultParams = abi.encode(
            ISymbioticVault.InitParams({
                collateral: params.collateral,
                burner: params.burner,
                epochDuration: params.epochDuration,
                depositWhitelist: vars.depositWhitelist,
                isDepositLimit: params.depositLimit != 0,
                depositLimit: params.depositLimit,
                defaultAdminRoleHolder: params.owner,
                depositWhitelistSetRoleHolder: params.owner,
                depositorWhitelistRoleHolder: params.owner,
                isDepositLimitSetRoleHolder: params.owner,
                depositLimitSetRoleHolder: params.owner
            })
        );

        vars.roleHolders = 1;
        if (params.hook != address(0) && params.hook != params.owner) {
            vars.roleHolders = 2;
        }
        vars.networkLimitSetRoleHolders = new address[](vars.roleHolders);
        vars.operatorNetworkLimitSetRoleHolders = new address[](vars.roleHolders);
        vars.operatorNetworkSharesSetRoleHolders = new address[](vars.roleHolders);
        vars.networkLimitSetRoleHolders[0] = params.owner;
        vars.operatorNetworkLimitSetRoleHolders[0] = params.owner;
        vars.operatorNetworkSharesSetRoleHolders[0] = params.owner;
        if (vars.roleHolders > 1) {
            vars.networkLimitSetRoleHolders[1] = params.hook;
            vars.operatorNetworkLimitSetRoleHolders[1] = params.hook;
            vars.operatorNetworkSharesSetRoleHolders[1] = params.hook;
        }

        if (params.delegatorIndex == 0) {
            vars.delegatorParams = abi.encode(
                ISymbioticNetworkRestakeDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: params.owner, hook: params.hook, hookSetRoleHolder: params.owner
                    }),
                    networkLimitSetRoleHolders: vars.networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: vars.operatorNetworkSharesSetRoleHolders
                })
            );
        } else if (params.delegatorIndex == 1) {
            vars.delegatorParams = abi.encode(
                ISymbioticFullRestakeDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: params.owner, hook: params.hook, hookSetRoleHolder: params.owner
                    }),
                    networkLimitSetRoleHolders: vars.networkLimitSetRoleHolders,
                    operatorNetworkLimitSetRoleHolders: vars.operatorNetworkLimitSetRoleHolders
                })
            );
        } else if (params.delegatorIndex == 2) {
            vars.delegatorParams = abi.encode(
                ISymbioticOperatorSpecificDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: params.owner, hook: params.hook, hookSetRoleHolder: params.owner
                    }),
                    networkLimitSetRoleHolders: vars.networkLimitSetRoleHolders,
                    operator: params.owner
                })
            );
        } else if (params.delegatorIndex == 3) {
            vars.delegatorParams = abi.encode(
                ISymbioticOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: params.owner, hook: params.hook, hookSetRoleHolder: params.owner
                    }),
                    network: params.network,
                    operator: params.owner
                })
            );
        }

        if (params.slasherIndex == 0) {
            vars.slasherParams = abi.encode(
                ISymbioticSlasher.InitParams({
                    baseParams: ISymbioticBaseSlasher.BaseParams({isBurnerHook: params.burner != address(0)})
                })
            );
        } else if (params.slasherIndex == 1) {
            vars.slasherParams = abi.encode(
                ISymbioticVetoSlasher.InitParams({
                    baseParams: ISymbioticBaseSlasher.BaseParams({isBurnerHook: params.burner != address(0)}),
                    vetoDuration: params.vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            );
        }

        (vars.callerMode,, vars.deployer) = vm.readCallers();
        _stopBroadcastWhenCallerModeIsSingleOrRecurrent(vars.callerMode);

        (vars.vault,,) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: vars.deployer,
            version: 1,
            owner: params.owner,
            vaultParams: vars.vaultParams,
            delegatorIndex: params.delegatorIndex,
            delegatorParams: vars.delegatorParams,
            withSlasher: params.withSlasher,
            slasherIndex: params.slasherIndex,
            slasherParams: vars.slasherParams
        });

        if (vars.depositWhitelist) {
            for (uint256 i; i < params.whitelistedDepositors.length; ++i) {
                _setDepositorWhitelistStatus_SymbioticCore(
                    params.owner, vars.vault, params.whitelistedDepositors[i], true
                );
            }
        }
        _startBroadcastWhenCallerModeIsRecurrent(vars.callerMode, params.owner);

        return vars.vault;
    }

    function _getVaultRandom_SymbioticCore(address[] memory operators, address collateral)
        internal
        virtual
        returns (address)
    {
        uint256 count_ = 0;
        uint64[] memory delegatorTypes = new uint64[](SYMBIOTIC_CORE_DELEGATOR_TYPES.length);
        for (uint64 i; i < SYMBIOTIC_CORE_DELEGATOR_TYPES.length; ++i) {
            if (SYMBIOTIC_CORE_DELEGATOR_TYPES[i] == 3) {
                continue;
            }
            if (operators.length == 0 && SYMBIOTIC_CORE_DELEGATOR_TYPES[i] == 2) {
                continue;
            }
            delegatorTypes[count_] = SYMBIOTIC_CORE_DELEGATOR_TYPES[i];
            ++count_;
        }
        assembly ("memory-safe") {
            mstore(delegatorTypes, count_)
        }
        uint64 delegatorIndex = _randomPick_Symbiotic(delegatorTypes);

        count_ = 0;
        uint64[] memory slasherTypes = new uint64[](SYMBIOTIC_CORE_SLASHER_TYPES.length);
        for (uint64 i; i < SYMBIOTIC_CORE_SLASHER_TYPES.length; ++i) {
            if (false) {
                continue;
            }
            slasherTypes[count_] = SYMBIOTIC_CORE_SLASHER_TYPES[i];
            ++count_;
        }
        assembly ("memory-safe") {
            mstore(slasherTypes, count_)
        }
        uint64 slasherIndex = _randomPick_Symbiotic(slasherTypes);

        (Vm.CallerMode callerMode,, address deployer) = vm.readCallers();

        _stopBroadcastWhenCallerModeIsSingleOrRecurrent(callerMode);

        uint48 epochDuration =
            uint48(_randomWithBounds_Symbiotic(SYMBIOTIC_CORE_MIN_EPOCH_DURATION, SYMBIOTIC_CORE_MAX_EPOCH_DURATION));

        address vault = _getVault_SymbioticCore(
            VaultParams({
                owner: operators.length == 0 ? deployer : _randomPick_Symbiotic(operators),
                collateral: collateral,
                burner: 0x000000000000000000000000000000000000dEaD,
                epochDuration: epochDuration,
                whitelistedDepositors: new address[](0),
                depositLimit: 0,
                delegatorIndex: delegatorIndex,
                hook: address(0),
                network: address(0),
                withSlasher: true,
                slasherIndex: slasherIndex,
                vetoDuration: uint48(
                    _randomWithBounds_Symbiotic(
                        SYMBIOTIC_CORE_MIN_VETO_DURATION, Math.min(SYMBIOTIC_CORE_MAX_VETO_DURATION, epochDuration)
                    )
                )
            })
        );
        _startBroadcastWhenCallerModeIsRecurrent(callerMode, deployer);
        return vault;
    }

    function _vaultValidating_SymbioticCore(address vault, bytes32 subnetwork) internal virtual returns (bool) {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        bool delegatorSpecificCondition;
        if (type_ == 0) {
            delegatorSpecificCondition = ISymbioticNetworkRestakeDelegator(delegator).networkLimit(subnetwork) > 0;
        } else if (type_ == 1) {
            delegatorSpecificCondition = ISymbioticFullRestakeDelegator(delegator).networkLimit(subnetwork) > 0;
        } else if (type_ == 2) {
            delegatorSpecificCondition = ISymbioticOperatorSpecificDelegator(delegator).networkLimit(subnetwork) > 0;
        } else if (type_ == 3) {
            delegatorSpecificCondition =
                ISymbioticOperatorNetworkSpecificDelegator(delegator).network() == subnetwork.network()
                    && ISymbioticOperatorNetworkSpecificDelegator(delegator).maxNetworkLimit(subnetwork) > 0;
        }

        return delegatorSpecificCondition;
    }

    // ------------------------------------------------------------ OPERATOR-RELATED HELPERS ------------------------------------------------------------ //

    function _getOperator_SymbioticCore() internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getAccount_Symbiotic();
        _operatorRegister_SymbioticCore(operator.addr);
        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(address vault) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        _operatorOptIn_SymbioticCore(operator.addr, vault);

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(address[] memory vaults) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _operatorOptIn_SymbioticCore(operator.addr, vaults[i]);
        }

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(address vault, address network)
        internal
        virtual
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        _operatorOptIn_SymbioticCore(operator.addr, vault);
        _operatorOptIn_SymbioticCore(operator.addr, network);

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(address[] memory vaults, address[] memory networks)
        internal
        virtual
        equalLengthsAddressAddress_Symbiotic(vaults, networks)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _operatorOptIn_SymbioticCore(operator.addr, vaults[i]);
        }

        for (uint256 i; i < networks.length; ++i) {
            _operatorOptIn_SymbioticCore(operator.addr, networks[i]);
        }

        return operator;
    }

    function _operatorRegister_SymbioticCore(address operator) internal virtual {
        _registerOperator_SymbioticCore(symbioticCore, operator);
    }

    function _operatorOptIn_SymbioticCore(address operator, address where) internal virtual {
        if (symbioticCore.vaultFactory.isEntity(where)) {
            _optInVault_SymbioticCore(symbioticCore, operator, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            _optInNetwork_SymbioticCore(symbioticCore, operator, where);
        } else {
            revert("Invalid address for opt-in");
        }
    }

    function _operatorOptInWeak_SymbioticCore(address operator, address where) internal virtual {
        bool alreadyOptedIn;
        if (symbioticCore.vaultFactory.isEntity(where)) {
            alreadyOptedIn = symbioticCore.operatorVaultOptInService.isOptedIn(operator, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            alreadyOptedIn = symbioticCore.operatorNetworkOptInService.isOptedIn(operator, where);
        }

        if (alreadyOptedIn) {
            return;
        }

        _operatorOptIn_SymbioticCore(operator, where);
    }

    function _operatorOptOut_SymbioticCore(address operator, address where) internal virtual {
        if (symbioticCore.vaultFactory.isEntity(where)) {
            _optOutVault_SymbioticCore(symbioticCore, operator, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            _optOutNetwork_SymbioticCore(symbioticCore, operator, where);
        } else {
            revert("Invalid address for opt-in");
        }
    }

    function _operatorOptInSignature_SymbioticCore(Vm.Wallet memory operator, address where)
        internal
        virtual
        returns (bytes memory)
    {
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);

        address service;
        uint256 nonce;
        if (symbioticCore.vaultFactory.isEntity(where)) {
            service = address(symbioticCore.operatorVaultOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            service = address(symbioticCore.operatorNetworkOptInService);
            nonce = symbioticCore.operatorNetworkOptInService.nonces(operator.addr, where);
        } else {
            revert("Invalid address for opt-in");
        }

        bytes32 digest = computeOptInDigest_SymbioticCore(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        return abi.encodePacked(r, s, v);
    }

    function _operatorOptOutSignature_SymbioticCore(Vm.Wallet memory operator, address where)
        internal
        virtual
        returns (bytes memory)
    {
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);

        address service;
        uint256 nonce;
        if (symbioticCore.vaultFactory.isEntity(where)) {
            service = address(symbioticCore.operatorVaultOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            service = address(symbioticCore.operatorNetworkOptInService);
            nonce = symbioticCore.operatorNetworkOptInService.nonces(operator.addr, where);
        } else {
            revert("Invalid address for opt-out");
        }

        bytes32 digest = computeOptOutDigest_SymbioticCore(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        return abi.encodePacked(r, s, v);
    }

    function computeOptInDigest_SymbioticCore(
        address service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view virtual returns (bytes32) {
        bytes32 OPT_IN_TYPEHASH = keccak256("OptIn(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_IN_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator_SymbioticCore(service);

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function computeOptOutDigest_SymbioticCore(
        address service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view virtual returns (bytes32) {
        bytes32 OPT_OUT_TYPEHASH = keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_OUT_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator_SymbioticCore(service);

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _computeDomainSeparator_SymbioticCore(address service) internal view virtual returns (bytes32) {
        bytes32 DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        (, string memory name, string memory version,,,,) = IERC5267(service).eip712Domain();
        bytes32 NAME_HASH = keccak256(bytes(name));
        bytes32 VERSION_HASH = keccak256(bytes(version));
        uint256 chainId = block.chainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, service));
    }

    function _operatorPossibleValidating_SymbioticCore(address operator, address vault, bytes32 subnetwork)
        internal
        virtual
        returns (bool)
    {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        bool delegatorSpecificCondition;
        if (type_ == 0) {
            delegatorSpecificCondition = ISymbioticNetworkRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && ISymbioticNetworkRestakeDelegator(delegator).operatorNetworkShares(subnetwork, operator) > 0;
        } else if (type_ == 1) {
            delegatorSpecificCondition = ISymbioticFullRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && ISymbioticFullRestakeDelegator(delegator).operatorNetworkLimit(subnetwork, operator) > 0;
        } else if (type_ == 2) {
            delegatorSpecificCondition = ISymbioticOperatorSpecificDelegator(delegator).operator() == operator
                && ISymbioticOperatorSpecificDelegator(delegator).networkLimit(subnetwork) > 0;
        } else if (type_ == 3) {
            delegatorSpecificCondition = ISymbioticOperatorNetworkSpecificDelegator(delegator).operator() == operator
                && ISymbioticOperatorNetworkSpecificDelegator(delegator).network() == subnetwork.network()
                && ISymbioticOperatorSpecificDelegator(delegator).maxNetworkLimit(subnetwork) > 0;
        }

        return symbioticCore.operatorVaultOptInService.isOptedIn(operator, vault) && delegatorSpecificCondition;
    }

    function _operatorConfirmedValidating_SymbioticCore(address operator, address vault, bytes32 subnetwork)
        internal
        virtual
        returns (bool)
    {
        return _operatorPossibleValidating_SymbioticCore(operator, vault, subnetwork)
            && symbioticCore.operatorNetworkOptInService.isOptedIn(operator, subnetwork.network());
    }

    // ------------------------------------------------------------ NETWORK-RELATED HELPERS ------------------------------------------------------------ //

    function _getNetwork_SymbioticCore() internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getAccount_Symbiotic();
        _networkRegister_SymbioticCore(network.addr);

        return network;
    }

    function _getNetworkWithMiddleware_SymbioticCore(address middleware) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getAccount_Symbiotic();
        _networkRegister_SymbioticCore(network.addr);
        _networkSetMiddleware_SymbioticCore(network.addr, middleware);

        return network;
    }

    function _getNetworkWithMaxNetworkLimits_SymbioticCore(uint96 identifier, address vault, uint256 maxNetworkLimit)
        internal
        virtual
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimits_SymbioticCore(
        address middleware,
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsRandom_SymbioticCore(uint96 identifier, address vault)
        internal
        virtual
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vault, identifier);

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsRandom_SymbioticCore(
        address middleware,
        uint96 identifier,
        address vault
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vault, identifier);

        return network;
    }

    function _getNetworkWithMaxNetworkLimits_SymbioticCore(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
        }

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimits_SymbioticCore(
        address middleware,
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
        }

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsRandom_SymbioticCore(uint96[] memory identifiers, address[] memory vaults)
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vaults[i], identifiers[i]);
        }

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsRandom_SymbioticCore(
        address middleware,
        uint96[] memory identifiers,
        address[] memory vaults
    ) internal virtual equalLengthsUint96Address_Symbiotic(identifiers, vaults) returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        for (uint256 i; i < vaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vaults[i], identifiers[i]);
        }

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsWithResolvers_SymbioticCore(
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit,
        address resolver
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);
        _setResolver_SymbioticCore(network.addr, vault, identifier, resolver);

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsWithResolvers_SymbioticCore(
        address middleware,
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit,
        address resolver
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);
        _setResolver_SymbioticCore(network.addr, vault, identifier, resolver);

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsWithResolversRandom_SymbioticCore(
        uint96 identifier,
        address vault,
        address resolver
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vault, identifier);
        _setResolver_SymbioticCore(network.addr, vault, identifier, resolver);

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsWithResolversRandom_SymbioticCore(
        address middleware,
        uint96 identifier,
        address vault,
        address resolver
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vault, identifier);
        _setResolver_SymbioticCore(network.addr, vault, identifier, resolver);

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsWithResolvers_SymbioticCore(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits,
        address[] memory resolvers
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        equalLengthsUint96Address_Symbiotic(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
            _setResolver_SymbioticCore(network.addr, vaults[i], identifiers[i], resolvers[i]);
        }

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsWithResolvers_SymbioticCore(
        address middleware,
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits,
        address[] memory resolvers
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        equalLengthsUint96Address_Symbiotic(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
            _setResolver_SymbioticCore(network.addr, vaults[i], identifiers[i], resolvers[i]);
        }

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsWithResolversRandom_SymbioticCore(
        uint96[] memory identifiers,
        address[] memory vaults,
        address[] memory resolvers
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Address_Symbiotic(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vaults[i], identifiers[i]);
            _setResolver_SymbioticCore(network.addr, vaults[i], identifiers[i], resolvers[i]);
        }

        return network;
    }

    function _getNetworkWithMiddlewareWithMaxNetworkLimitsWithResolversRandom_SymbioticCore(
        address middleware,
        uint96[] memory identifiers,
        address[] memory vaults,
        address[] memory resolvers
    )
        internal
        virtual
        equalLengthsUint96Address_Symbiotic(identifiers, vaults)
        equalLengthsUint96Address_Symbiotic(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetworkWithMiddleware_SymbioticCore(middleware);

        for (uint256 i; i < vaults.length; ++i) {
            _networkSetMaxNetworkLimitRandom_SymbioticCore(network.addr, vaults[i], identifiers[i]);
            _setResolver_SymbioticCore(network.addr, vaults[i], identifiers[i], resolvers[i]);
        }

        return network;
    }

    function _networkRegister_SymbioticCore(address network) internal virtual {
        _registerNetwork_SymbioticCore(symbioticCore, network);
    }

    function _networkSetMiddleware_SymbioticCore(address network, address middleware) internal virtual {
        _setMiddleware_SymbioticCore(symbioticCore, network, middleware);
    }

    function _networkSetMaxNetworkLimit_SymbioticCore(
        address network,
        address vault,
        uint96 identifier,
        uint256 maxNetworkLimit
    ) internal virtual {
        _setMaxNetworkLimit_SymbioticCore(network, vault, identifier, maxNetworkLimit);
    }

    function _networkSetMaxNetworkLimitRandom_SymbioticCore(address network, address vault, uint96 identifier)
        internal
        virtual
    {
        address collateral = ISymbioticVault(vault).collateral();
        uint256 amount = _randomWithBounds_Symbiotic(
            _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MIN_MAX_NETWORK_LIMIT_TIMES_1e18, collateral),
            _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MAX_MAX_NETWORK_LIMIT_TIMES_1e18, collateral)
        );
        if (
            ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).maxNetworkLimit(network.subnetwork(identifier))
                == amount
        ) {
            return;
        }
        _networkSetMaxNetworkLimit_SymbioticCore(network, vault, identifier, amount);
    }

    function _networkSetMaxNetworkLimitReset_SymbioticCore(address network, address vault, uint96 identifier)
        internal
        virtual
    {
        if (
            ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).maxNetworkLimit(network.subnetwork(identifier))
                == 0
        ) {
            return;
        }
        _networkSetMaxNetworkLimit_SymbioticCore(network, vault, identifier, 0);
    }

    function _networkSetResolver_SymbioticCore(address network, address vault, uint96 identifier, address resolver)
        internal
        virtual
    {
        _setResolver_SymbioticCore(network, vault, identifier, resolver);
    }

    function _networkPossibleUtilizing_SymbioticCore(
        address network,
        uint96 identifier,
        address vault,
        address operator
    ) internal virtual returns (bool) {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();
        bytes32 subnetwork = network.subnetwork(identifier);

        bool delegatorSpecificCondition;
        if (type_ == 0) {
            delegatorSpecificCondition = ISymbioticNetworkRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && ISymbioticNetworkRestakeDelegator(delegator).operatorNetworkShares(subnetwork, operator) > 0;
        } else if (type_ == 1) {
            delegatorSpecificCondition = ISymbioticFullRestakeDelegator(delegator).networkLimit(subnetwork) > 0
                && ISymbioticFullRestakeDelegator(delegator).operatorNetworkLimit(subnetwork, operator) > 0;
        } else if (type_ == 2) {
            delegatorSpecificCondition = ISymbioticOperatorSpecificDelegator(delegator).operator() == operator
                && ISymbioticOperatorSpecificDelegator(delegator).networkLimit(subnetwork) > 0;
        } else if (type_ == 3) {
            delegatorSpecificCondition = ISymbioticOperatorNetworkSpecificDelegator(delegator).operator() == operator
                && ISymbioticOperatorNetworkSpecificDelegator(delegator).network() == subnetwork.network()
                && ISymbioticOperatorNetworkSpecificDelegator(delegator).maxNetworkLimit(subnetwork) > 0;
        }

        return symbioticCore.operatorVaultOptInService.isOptedIn(operator, vault)
            && symbioticCore.operatorNetworkOptInService.isOptedIn(operator, network) && delegatorSpecificCondition;
    }

    // ------------------------------------------------------------ STAKER-RELATED HELPERS ------------------------------------------------------------ //

    function _getStaker_SymbioticCore(address[] memory possibleTokens) internal virtual returns (Vm.Wallet memory);

    function _getStakerWithStake_SymbioticCore(address[] memory possibleTokens, address vault)
        internal
        virtual
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory staker = _getStaker_SymbioticCore(possibleTokens);

        _stakerDepositRandom_SymbioticCore(staker.addr, vault);

        return staker;
    }

    function _getStakerWithStake_SymbioticCore(address[] memory possibleTokens, address[] memory vaults)
        internal
        virtual
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory staker = _getStaker_SymbioticCore(possibleTokens);

        for (uint256 i; i < vaults.length; ++i) {
            _stakerDepositRandom_SymbioticCore(staker.addr, vaults[i]);
        }

        return staker;
    }

    function _stakerDeposit_SymbioticCore(address staker, address vault, uint256 amount) internal virtual {
        _deposit_SymbioticCore(staker, vault, amount);
    }

    function _stakerDepositRandom_SymbioticCore(address staker, address vault) internal virtual {
        address collateral = ISymbioticVault(vault).collateral();

        if (ISymbioticVault(vault).depositWhitelist()) {
            return;
        }

        uint256 minAmount = _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MIN_TOKENS_TO_DEPOSIT_TIMES_1e18, collateral);
        uint256 amount = _randomWithBounds_Symbiotic(
            minAmount, _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MAX_TOKENS_TO_DEPOSIT_TIMES_1e18, collateral)
        );

        if (ISymbioticVault(vault).isDepositLimit()) {
            uint256 depositLimit = ISymbioticVault(vault).depositLimit();
            uint256 activeStake = ISymbioticVault(vault).activeStake();
            amount = Math.min(depositLimit - Math.min(activeStake, depositLimit), amount);
        }

        if (amount >= minAmount) {
            _stakerDeposit_SymbioticCore(staker, vault, amount);
        }
    }

    function _stakerWithdraw_SymbioticCore(address staker, address vault, uint256 amount) internal virtual {
        _withdraw_SymbioticCore(staker, vault, amount);
    }

    function _stakerWithdrawRandom_SymbioticCore(address staker, address vault) internal virtual {
        uint256 balance = ISymbioticVault(vault).activeBalanceOf(staker);

        if (balance == 0) {
            return;
        }

        uint256 amount = _randomWithBounds_Symbiotic(1, balance);

        _stakerWithdraw_SymbioticCore(staker, vault, amount);
    }

    function _stakerRedeem_SymbioticCore(address staker, address vault, uint256 shares) internal virtual {
        _redeem_SymbioticCore(staker, vault, shares);
    }

    function _stakerClaim_SymbioticCore(address staker, address vault, uint256 epoch) internal virtual {
        _claim_SymbioticCore(staker, vault, epoch);
    }

    function _stakerClaimBatch_SymbioticCore(address staker, address vault, uint256[] memory epochs) internal virtual {
        _claimBatch_SymbioticCore(staker, vault, epochs);
    }

    // ------------------------------------------------------------ CURATOR-RELATED HELPERS ------------------------------------------------------------ //

    function _curatorSetHook_SymbioticCore(address curator, address vault, address hook) internal virtual {
        _setHook_SymbioticCore(curator, vault, hook);
    }

    function _curatorSetNetworkLimit_SymbioticCore(address curator, address vault, bytes32 subnetwork, uint256 amount)
        internal
        virtual
    {
        _setNetworkLimit_SymbioticCore(curator, vault, subnetwork, amount);
    }

    function _curatorSetNetworkLimitRandom_SymbioticCore(address curator, address vault, bytes32 subnetwork)
        internal
        virtual
        returns (bool)
    {
        address collateral = ISymbioticVault(vault).collateral();
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        uint256 minAmount = _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MIN_NETWORK_LIMIT_TIMES_1e18, collateral);
        uint256 maxAmount = _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MAX_NETWORK_LIMIT_TIMES_1e18, collateral);

        uint256 amount;
        if (type_ == 0 || type_ == 1 || type_ == 2) {
            uint256 maxNetworkLimit = ISymbioticBaseDelegator(delegator).maxNetworkLimit(subnetwork);
            if (maxNetworkLimit < minAmount) {
                _curatorSetNetworkLimitReset_SymbioticCore(curator, vault, subnetwork);
                return false;
            }
            amount = _randomWithBounds_Symbiotic(minAmount, Math.min(maxNetworkLimit, maxAmount));
        }

        if (ISymbioticNetworkRestakeDelegator(delegator).networkLimit(subnetwork) == amount) {
            return true;
        }
        _curatorSetNetworkLimit_SymbioticCore(curator, vault, subnetwork, amount);
        return true;
    }

    function _curatorSetNetworkLimitReset_SymbioticCore(address curator, address vault, bytes32 subnetwork)
        internal
        virtual
    {
        if (ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).networkLimit(subnetwork) == 0) {
            return;
        }
        _curatorSetNetworkLimit_SymbioticCore(curator, vault, subnetwork, 0);
    }

    function _curatorSetOperatorNetworkShares_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) internal virtual {
        _setOperatorNetworkShares_SymbioticCore(curator, vault, subnetwork, operator, shares);
    }

    function _curatorSetOperatorNetworkSharesRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
        uint256 shares = _randomWithBounds_Symbiotic(
            SYMBIOTIC_CORE_MIN_OPERATOR_NETWORK_SHARES, SYMBIOTIC_CORE_MAX_OPERATOR_NETWORK_SHARES
        );
        if (
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator())
                    .operatorNetworkShares(subnetwork, operator) == shares
        ) {
            return true;
        }
        _setOperatorNetworkShares_SymbioticCore(curator, vault, subnetwork, operator, shares);
        return true;
    }

    function _curatorSetOperatorNetworkSharesReset_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual {
        if (
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator())
                    .operatorNetworkShares(subnetwork, operator) == 0
        ) {
            return;
        }
        _setOperatorNetworkShares_SymbioticCore(curator, vault, subnetwork, operator, 0);
    }

    function _curatorSetOperatorNetworkLimit_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) internal virtual {
        _setOperatorNetworkLimit_SymbioticCore(curator, vault, subnetwork, operator, amount);
    }

    function _curatorSetOperatorNetworkLimitRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
        address collateral = ISymbioticVault(vault).collateral();
        uint256 amount = _randomWithBounds_Symbiotic(
            _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MIN_OPERATOR_NETWORK_LIMIT_TIMES_1e18, collateral),
            _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_MAX_OPERATOR_NETWORK_LIMIT_TIMES_1e18, collateral)
        );
        if (
            ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator())
                    .operatorNetworkLimit(subnetwork, operator) == amount
        ) {
            return true;
        }
        _setOperatorNetworkLimit_SymbioticCore(curator, vault, subnetwork, operator, amount);
        return true;
    }

    function _curatorSetOperatorNetworkLimitReset_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual {
        if (
            ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator())
                    .operatorNetworkLimit(subnetwork, operator) == 0
        ) {
            return;
        }
        _setOperatorNetworkLimit_SymbioticCore(curator, vault, subnetwork, operator, 0);
    }

    function _curatorDelegateNetworkRandom_SymbioticCore(address curator, address vault, bytes32 subnetwork)
        internal
        virtual
        returns (bool)
    {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        if (type_ == 0) {
            return _curatorSetNetworkLimitRandom_SymbioticCore(curator, vault, subnetwork);
        } else if (type_ == 1) {
            return _curatorSetNetworkLimitRandom_SymbioticCore(curator, vault, subnetwork);
        } else if (type_ == 2) {
            return false;
        } else if (type_ == 3) {
            return false;
        }
        return false;
    }

    function _curatorDelegateNetworkHasRoles_SymbioticCore(
        address curator,
        address vault,
        bytes32 /* subnetwork */
    )
        internal
        virtual
        returns (bool)
    {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        if (type_ == 0) {
            return IAccessControl(delegator)
                .hasRole(ISymbioticNetworkRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator);
        } else if (type_ == 1) {
            return IAccessControl(delegator)
                .hasRole(ISymbioticFullRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator);
        } else if (type_ == 2) {
            return false;
        } else if (type_ == 3) {
            return false;
        }

        return false;
    }

    function _curatorDelegateOperatorRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        if (type_ == 0) {
            return _curatorSetOperatorNetworkSharesRandom_SymbioticCore(curator, vault, subnetwork, operator);
        } else if (type_ == 1) {
            return _curatorSetOperatorNetworkLimitRandom_SymbioticCore(curator, vault, subnetwork, operator);
        } else if (type_ == 2) {
            if (ISymbioticOperatorSpecificDelegator(delegator).operator() == operator) {
                return _curatorSetNetworkLimitRandom_SymbioticCore(curator, vault, subnetwork);
            }
            return false;
        } else if (type_ == 3) {
            return false;
        }
        return false;
    }

    function _curatorDelegateOperatorHasRoles_SymbioticCore(
        address curator,
        address vault,
        bytes32, /* subnetwork */
        address operator
    ) internal virtual returns (bool) {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        if (type_ == 0) {
            return IAccessControl(delegator)
                .hasRole(ISymbioticNetworkRestakeDelegator(delegator).OPERATOR_NETWORK_SHARES_SET_ROLE(), curator);
        } else if (type_ == 1) {
            return IAccessControl(delegator)
                .hasRole(ISymbioticFullRestakeDelegator(delegator).OPERATOR_NETWORK_LIMIT_SET_ROLE(), curator);
        } else if (type_ == 2) {
            if (ISymbioticOperatorSpecificDelegator(delegator).operator() == operator) {
                return IAccessControl(delegator)
                    .hasRole(ISymbioticOperatorSpecificDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator);
            }
            return false;
        } else if (type_ == 3) {
            return false;
        }

        return false;
    }

    function _curatorDelegateRandom_SymbioticCore(address curator, address vault, bytes32 subnetwork, address operator)
        internal
        virtual
        returns (bool)
    {
        return _curatorDelegateNetworkRandom_SymbioticCore(curator, vault, subnetwork)
            && _curatorDelegateOperatorRandom_SymbioticCore(curator, vault, subnetwork, operator);
    }

    function _curatorDelegateHasRoles_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
        return _curatorDelegateNetworkHasRoles_SymbioticCore(curator, vault, subnetwork)
            && _curatorDelegateOperatorHasRoles_SymbioticCore(curator, vault, subnetwork, operator);
    }

    function _curatorDelegateToNetworkInternal_SymbioticCore(address curator, address vault, bytes32 subnetwork)
        internal
        virtual
        returns (bool curatorFound, bool success)
    {
        if (_curatorDelegateNetworkHasRoles_SymbioticCore(curator, vault, subnetwork)) {
            success = _curatorDelegateNetworkRandom_SymbioticCore(curator, vault, subnetwork);
            return (true, success);
        }
        return (false, false);
    }

    function _curatorDelegateToOperatorInternal_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool curatorFound, bool success) {
        if (_curatorDelegateOperatorHasRoles_SymbioticCore(curator, vault, subnetwork, operator)) {
            success = _curatorDelegateOperatorRandom_SymbioticCore(curator, vault, subnetwork, operator);
            return (true, success);
        }
        return (false, false);
    }

    function _curatorSetDepositWhitelist_SymbioticCore(address curator, address vault, bool status) internal virtual {
        _setDepositWhitelist_SymbioticCore(curator, vault, status);
    }

    function _curatorSetDepositorWhitelistStatus_SymbioticCore(
        address curator,
        address vault,
        address account,
        bool status
    ) internal virtual {
        _setDepositorWhitelistStatus_SymbioticCore(curator, vault, account, status);
    }

    function _curatorSetIsDepositLimit_SymbioticCore(address curator, address vault, bool status) internal virtual {
        _setIsDepositLimit_SymbioticCore(curator, vault, status);
    }

    function _curatorSetDepositLimit_SymbioticCore(address curator, address vault, uint256 limit) internal virtual {
        _setDepositLimit_SymbioticCore(curator, vault, limit);
    }

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _stopBroadcastWhenCallerModeIsSingle(Vm.CallerMode callerMode) internal virtual;

    function _startBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode, address deployer) internal virtual;

    function _stopBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode) internal virtual;

    function _startBroadcastWhenCallerModeIsRecurrent(Vm.CallerMode callerMode, address deployer) internal virtual;

    function _stopBroadcastWhenCallerModeIsSingleOrRecurrent(Vm.CallerMode callerMode) internal virtual;
}
