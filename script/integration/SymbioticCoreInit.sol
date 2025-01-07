// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../test/integration/SymbioticCoreImports.sol";

import "./SymbioticInit.sol";
import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";
import {SymbioticCoreBindings} from "./SymbioticCoreBindings.sol";

import {Token} from "../../test/mocks/Token.sol";
import {FeeOnTransferToken} from "../../test/mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SymbioticCoreInit is SymbioticInit, SymbioticCoreBindings {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SymbioticSubnetwork for bytes32;
    using SymbioticSubnetwork for address;

    // General config

    string public SYMBIOTIC_CORE_PROJECT_ROOT = "";
    bool public SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = true;

    // Vaults-related config

    uint256 public SYMBIOTIC_CORE_MIN_EPOCH_DURATION = 60 minutes;
    uint256 public SYMBIOTIC_CORE_MAX_EPOCH_DURATION = 21 days;
    uint256 public SYMBIOTIC_CORE_MIN_VETO_DURATION = 5 minutes;
    uint256 public SYMBIOTIC_CORE_MAX_VETO_DURATION = 7 days;
    uint64[] public SYMBIOTIC_CORE_DELEGATOR_TYPES = [0, 1, 2, 3];
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

    function run(
        uint256 seed
    ) public virtual override {
        SymbioticInit.run(seed);

        _initCore_SymbioticCore(SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT);
    }

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _initCore_SymbioticCore() internal virtual {
        symbioticCore = SymbioticCoreConstants.core();
    }

    function _initCore_SymbioticCore(
        bool useExisting
    ) internal virtual {
        if (useExisting) {
            _initCore_SymbioticCore();
        } else {
            ISymbioticVaultFactory vaultFactory = ISymbioticVaultFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultFactory.sol/VaultFactory.json"),
                    abi.encode(tx.origin)
                )
            );
            ISymbioticDelegatorFactory delegatorFactory = ISymbioticDelegatorFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/DelegatorFactory.sol/DelegatorFactory.json"),
                    abi.encode(tx.origin)
                )
            );
            ISymbioticSlasherFactory slasherFactory = ISymbioticSlasherFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/SlasherFactory.sol/SlasherFactory.json"),
                    abi.encode(tx.origin)
                )
            );
            ISymbioticNetworkRegistry networkRegistry = ISymbioticNetworkRegistry(
                deployCode(string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkRegistry.sol/NetworkRegistry.json"))
            );
            ISymbioticOperatorRegistry operatorRegistry = ISymbioticOperatorRegistry(
                deployCode(string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OperatorRegistry.sol/OperatorRegistry.json"))
            );
            ISymbioticMetadataService operatorMetadataService = ISymbioticMetadataService(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/MetadataService.sol/MetadataService.json"),
                    abi.encode(address(operatorRegistry))
                )
            );
            ISymbioticMetadataService networkMetadataService = ISymbioticMetadataService(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/MetadataService.sol/MetadataService.json"),
                    abi.encode(address(networkRegistry))
                )
            );
            ISymbioticNetworkMiddlewareService networkMiddlewareService = ISymbioticNetworkMiddlewareService(
                deployCode(
                    string.concat(
                        SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkMiddlewareService.sol/NetworkMiddlewareService.json"
                    ),
                    abi.encode(address(networkRegistry))
                )
            );
            ISymbioticOptInService operatorVaultOptInService = ISymbioticOptInService(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OptInService.sol/OptInService.json"),
                    abi.encode(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService")
                )
            );
            ISymbioticOptInService operatorNetworkOptInService = ISymbioticOptInService(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/OptInService.sol/OptInService.json"),
                    abi.encode(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
                )
            );

            address vaultImpl = deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/Vault.sol/Vault.json"),
                abi.encode(address(delegatorFactory), address(slasherFactory), address(vaultFactory))
            );
            vaultFactory.whitelist(vaultImpl);

            address vaultTokenizedImpl = deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultTokenized.sol/VaultTokenized.json"),
                abi.encode(address(delegatorFactory), address(slasherFactory), address(vaultFactory))
            );
            vaultFactory.whitelist(vaultTokenizedImpl);

            address networkRestakeDelegatorImpl = deployCode(
                string.concat(
                    SYMBIOTIC_CORE_PROJECT_ROOT, "out/NetworkRestakeDelegator.sol/NetworkRestakeDelegator.json"
                ),
                abi.encode(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            );
            delegatorFactory.whitelist(networkRestakeDelegatorImpl);

            address fullRestakeDelegatorImpl = deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/FullRestakeDelegator.sol/FullRestakeDelegator.json"),
                abi.encode(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            );
            delegatorFactory.whitelist(fullRestakeDelegatorImpl);

            address operatorSpecificDelegatorImpl = deployCode(
                string.concat(
                    SYMBIOTIC_CORE_PROJECT_ROOT, "out/OperatorSpecificDelegator.sol/OperatorSpecificDelegator.json"
                ),
                abi.encode(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            );
            delegatorFactory.whitelist(operatorSpecificDelegatorImpl);

            address slasherImpl = deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/Slasher.sol/Slasher.json"),
                abi.encode(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            );
            slasherFactory.whitelist(slasherImpl);

            address vetoSlasherImpl = deployCode(
                string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VetoSlasher.sol/VetoSlasher.json"),
                abi.encode(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            );
            slasherFactory.whitelist(vetoSlasherImpl);

            ISymbioticVaultConfigurator vaultConfigurator = ISymbioticVaultConfigurator(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultConfigurator.sol/VaultConfigurator.json"),
                    abi.encode(address(vaultFactory), address(delegatorFactory), address(slasherFactory))
                )
            );

            symbioticCore = SymbioticCoreConstants.Core({
                vaultFactory: vaultFactory,
                delegatorFactory: delegatorFactory,
                slasherFactory: slasherFactory,
                networkRegistry: networkRegistry,
                networkMetadataService: networkMetadataService,
                networkMiddlewareService: networkMiddlewareService,
                operatorRegistry: operatorRegistry,
                operatorMetadataService: operatorMetadataService,
                operatorVaultOptInService: operatorVaultOptInService,
                operatorNetworkOptInService: operatorNetworkOptInService,
                vaultConfigurator: vaultConfigurator
            });
        }
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

    function _getVault_SymbioticCore(
        address collateral
    ) internal virtual returns (address) {
        address owner = tx.origin;
        uint48 epochDuration = 7 days;
        uint48 vetoDuration = 1 days;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;
        (address vault,,) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: tx.origin,
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

        return vault;
    }

    function _getVault_SymbioticCore(
        address owner,
        address collateral,
        address burner,
        uint48 epochDuration,
        address[] memory whitelistedDepositors,
        uint256 depositLimit,
        uint64 delegatorIndex,
        address hook,
        address network,
        bool withSlasher,
        uint64 slasherIndex,
        uint48 vetoDuration
    ) internal virtual returns (address) {
        bool depositWhitelist = whitelistedDepositors.length != 0;

        bytes memory vaultParams = abi.encode(
            ISymbioticVault.InitParams({
                collateral: collateral,
                burner: burner,
                epochDuration: epochDuration,
                depositWhitelist: depositWhitelist,
                isDepositLimit: depositLimit != 0,
                depositLimit: depositLimit,
                defaultAdminRoleHolder: owner,
                depositWhitelistSetRoleHolder: owner,
                depositorWhitelistRoleHolder: owner,
                isDepositLimitSetRoleHolder: owner,
                depositLimitSetRoleHolder: owner
            })
        );

        uint256 roleHolders = 1;
        if (hook != address(0) && hook != owner) {
            roleHolders = 2;
        }
        address[] memory networkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](roleHolders);
        networkLimitSetRoleHolders[0] = owner;
        operatorNetworkLimitSetRoleHolders[0] = owner;
        operatorNetworkSharesSetRoleHolders[0] = owner;
        if (roleHolders > 1) {
            networkLimitSetRoleHolders[1] = hook;
            operatorNetworkLimitSetRoleHolders[1] = hook;
            operatorNetworkSharesSetRoleHolders[1] = hook;
        }

        bytes memory delegatorParams;
        if (delegatorIndex == 0) {
            delegatorParams = abi.encode(
                ISymbioticNetworkRestakeDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                })
            );
        } else if (delegatorIndex == 1) {
            delegatorParams = abi.encode(
                ISymbioticFullRestakeDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                })
            );
        } else if (delegatorIndex == 2) {
            delegatorParams = abi.encode(
                ISymbioticOperatorSpecificDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operator: owner
                })
            );
        } else if (delegatorIndex == 3) {
            delegatorParams = abi.encode(
                ISymbioticOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: ISymbioticBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    network: network,
                    operator: owner
                })
            );
        }

        bytes memory slasherParams;
        if (slasherIndex == 0) {
            slasherParams = abi.encode(
                ISymbioticSlasher.InitParams({
                    baseParams: ISymbioticBaseSlasher.BaseParams({isBurnerHook: burner != address(0)})
                })
            );
        } else if (slasherIndex == 1) {
            slasherParams = abi.encode(
                ISymbioticVetoSlasher.InitParams({
                    baseParams: ISymbioticBaseSlasher.BaseParams({isBurnerHook: burner != address(0)}),
                    vetoDuration: vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            );
        }

        (address vault,,) = _createVault_SymbioticCore({
            symbioticCore: symbioticCore,
            who: tx.origin,
            version: 1,
            owner: owner,
            vaultParams: vaultParams,
            delegatorIndex: delegatorIndex,
            delegatorParams: delegatorParams,
            withSlasher: withSlasher,
            slasherIndex: slasherIndex,
            slasherParams: slasherParams
        });

        if (depositWhitelist) {
            for (uint256 i; i < whitelistedDepositors.length; ++i) {
                _setDepositorWhitelistStatus_SymbioticCore(owner, vault, whitelistedDepositors[i], true);
            }
        }

        return vault;
    }

    function _getVaultRandom_SymbioticCore(
        address[] memory operators,
        address collateral
    ) internal virtual returns (address) {
        uint48 epochDuration =
            uint48(_randomWithBounds_Symbiotic(SYMBIOTIC_CORE_MIN_EPOCH_DURATION, SYMBIOTIC_CORE_MAX_EPOCH_DURATION));
        uint48 vetoDuration = uint48(
            _randomWithBounds_Symbiotic(
                SYMBIOTIC_CORE_MIN_VETO_DURATION, Math.min(SYMBIOTIC_CORE_MAX_VETO_DURATION, epochDuration / 2)
            )
        );

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

        return _getVault_SymbioticCore(
            operators.length == 0 ? tx.origin : _randomPick_Symbiotic(operators),
            collateral,
            0x000000000000000000000000000000000000dEaD,
            epochDuration,
            new address[](0),
            0,
            delegatorIndex,
            address(0),
            address(0),
            true,
            slasherIndex,
            vetoDuration
        );
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
            delegatorSpecificCondition = ISymbioticOperatorNetworkSpecificDelegator(delegator).network()
                == subnetwork.network()
                && ISymbioticOperatorNetworkSpecificDelegator(delegator).maxNetworkLimit(subnetwork) > 0;
        }

        return delegatorSpecificCondition;
    }

    // ------------------------------------------------------------ OPERATOR-RELATED HELPERS ------------------------------------------------------------ //

    function _operatorRegister_SymbioticCore(
        address operator
    ) internal virtual {
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

    function _operatorOptInSignature_SymbioticCore(
        Vm.Wallet memory operator,
        address where
    ) internal virtual returns (bytes memory) {
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

    function _operatorOptOutSignature_SymbioticCore(
        Vm.Wallet memory operator,
        address where
    ) internal virtual returns (bytes memory) {
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

    function _computeDomainSeparator_SymbioticCore(
        address service
    ) internal view virtual returns (bytes32) {
        bytes32 DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        (, string memory name, string memory version,,,,) = IERC5267(service).eip712Domain();
        bytes32 NAME_HASH = keccak256(bytes(name));
        bytes32 VERSION_HASH = keccak256(bytes(version));
        uint256 chainId = block.chainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, service));
    }

    function _operatorPossibleValidating_SymbioticCore(
        address operator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool) {
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

    function _operatorConfirmedValidating_SymbioticCore(
        address operator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool) {
        return _operatorPossibleValidating_SymbioticCore(operator, vault, subnetwork)
            && symbioticCore.operatorNetworkOptInService.isOptedIn(operator, subnetwork.network());
    }

    // ------------------------------------------------------------ NETWORK-RELATED HELPERS ------------------------------------------------------------ //

    function _networkRegister_SymbioticCore(
        address network
    ) internal virtual {
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

    function _networkSetMaxNetworkLimitRandom_SymbioticCore(
        address network,
        address vault,
        uint96 identifier
    ) internal virtual {
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

    function _networkSetMaxNetworkLimitReset_SymbioticCore(
        address network,
        address vault,
        uint96 identifier
    ) internal virtual {
        if (
            ISymbioticBaseDelegator(ISymbioticVault(vault).delegator()).maxNetworkLimit(network.subnetwork(identifier))
                == 0
        ) {
            return;
        }
        _networkSetMaxNetworkLimit_SymbioticCore(network, vault, identifier, 0);
    }

    function _networkSetResolver_SymbioticCore(
        address network,
        address vault,
        uint96 identifier,
        address resolver
    ) internal virtual {
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

    function _getStaker_SymbioticCore(
        address[] memory possibleTokens
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory staker = _getAccount_Symbiotic();

        for (uint256 i; i < possibleTokens.length; ++i) {
            _deal_Symbiotic(
                possibleTokens[i],
                staker.addr,
                _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18, possibleTokens[i])
            );
        }

        return staker;
    }

    function _getStakerWithStake_SymbioticCore(
        address[] memory possibleTokens,
        address vault
    ) internal virtual returns (Vm.Wallet memory) {
        Vm.Wallet memory staker = _getStaker_SymbioticCore(possibleTokens);

        _stakerDepositRandom_SymbioticCore(staker.addr, vault);

        return staker;
    }

    function _getStakerWithStake_SymbioticCore(
        address[] memory possibleTokens,
        address[] memory vaults
    ) internal virtual returns (Vm.Wallet memory) {
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

    function _curatorSetNetworkLimit_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        uint256 amount
    ) internal virtual {
        _setNetworkLimit_SymbioticCore(curator, vault, subnetwork, amount);
    }

    function _curatorSetNetworkLimitRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool) {
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

    function _curatorSetNetworkLimitReset_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork
    ) internal virtual {
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
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).operatorNetworkShares(
                subnetwork, operator
            ) == shares
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
            ISymbioticNetworkRestakeDelegator(ISymbioticVault(vault).delegator()).operatorNetworkShares(
                subnetwork, operator
            ) == 0
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
            ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).operatorNetworkLimit(
                subnetwork, operator
            ) == amount
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
            ISymbioticFullRestakeDelegator(ISymbioticVault(vault).delegator()).operatorNetworkLimit(
                subnetwork, operator
            ) == 0
        ) {
            return;
        }
        _setOperatorNetworkLimit_SymbioticCore(curator, vault, subnetwork, operator, 0);
    }

    function _curatorDelegateNetworkRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool) {
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
    ) internal virtual returns (bool) {
        address delegator = ISymbioticVault(vault).delegator();
        uint64 type_ = ISymbioticEntity(delegator).TYPE();

        if (type_ == 0) {
            return IAccessControl(delegator).hasRole(
                ISymbioticNetworkRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator
            );
        } else if (type_ == 1) {
            return IAccessControl(delegator).hasRole(
                ISymbioticFullRestakeDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator
            );
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
            return IAccessControl(delegator).hasRole(
                ISymbioticNetworkRestakeDelegator(delegator).OPERATOR_NETWORK_SHARES_SET_ROLE(), curator
            );
        } else if (type_ == 1) {
            return IAccessControl(delegator).hasRole(
                ISymbioticFullRestakeDelegator(delegator).OPERATOR_NETWORK_LIMIT_SET_ROLE(), curator
            );
        } else if (type_ == 2) {
            if (ISymbioticOperatorSpecificDelegator(delegator).operator() == operator) {
                return IAccessControl(delegator).hasRole(
                    ISymbioticOperatorSpecificDelegator(delegator).NETWORK_LIMIT_SET_ROLE(), curator
                );
            }
            return false;
        } else if (type_ == 3) {
            return false;
        }

        return false;
    }

    function _curatorDelegateRandom_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator
    ) internal virtual returns (bool) {
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

    function _curatorDelegateToNetworkInternal_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork
    ) internal virtual returns (bool curatorFound, bool success) {
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
}
