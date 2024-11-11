// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Imports.sol";

import {Constants as SymbioticCoreConstants} from "./Constants.sol";
import {Counter as SymbioticCoreCounter} from "./Counter.sol";
import {Bindings as SymbioticBindings} from "./Bindings.sol";

import {Token} from "../mocks/Token.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SymbioticInit is SymbioticCoreCounter, SymbioticBindings {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // General config

    string public SYMBIOTIC_CORE_PROJECT_ROOT = "";
    uint256 public SYMBIOTIC_CORE_INIT_TIMESTAMP = 1_731_324_431;
    uint256 public SYMBIOTIC_CORE_INIT_BLOCK = 21_164_139;
    uint256 public SYMBIOTIC_CORE_BLOCK_TIME = 12;
    bool public USE_EXISTING_DEPLOYMENT = false;

    // Staker-related config

    uint256 public TOKENS_TO_SET_TIMES_1e18 = 100_000_000 * 1e18;
    uint256 public MIN_TOKENS_TO_DEPOSIT_TIMES_1e18 = 0.001 * 1e18;
    uint256 public MAX_TOKENS_TO_DEPOSIT_TIMES_1e18 = 10_000 * 1e18;

    SymbioticCoreConstants.Core symbioticCore;

    function setUp() public virtual {
        try vm.activeFork() {
            vm.rollFork(SYMBIOTIC_CORE_INIT_BLOCK);
        } catch {
            vm.warp(SYMBIOTIC_CORE_INIT_TIMESTAMP);
            vm.roll(SYMBIOTIC_CORE_INIT_BLOCK);
        }

        _initCore_SymbioticCore(USE_EXISTING_DEPLOYMENT);
    }

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _initCore_SymbioticCore() internal {
        symbioticCore = SymbioticCoreConstants.core();
    }

    function _initCore_SymbioticCore(
        bool useExisting
    ) internal {
        if (useExisting) {
            _initCore_SymbioticCore();
        } else {
            ISymbioticVaultFactory vaultFactory = ISymbioticVaultFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/VaultFactory.sol/VaultFactory.json"),
                    abi.encode(address(this))
                )
            );
            ISymbioticDelegatorFactory delegatorFactory = ISymbioticDelegatorFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/DelegatorFactory.sol/DelegatorFactory.json"),
                    abi.encode(address(this))
                )
            );
            ISymbioticSlasherFactory slasherFactory = ISymbioticSlasherFactory(
                deployCode(
                    string.concat(SYMBIOTIC_CORE_PROJECT_ROOT, "out/SlasherFactory.sol/SlasherFactory.json"),
                    abi.encode(address(this))
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

    function random_SymbioticCore() internal returns (uint256) {
        return uint256(keccak256(abi.encode(vm.getBlockTimestamp(), vm.getBlockNumber(), count())));
    }

    function random_SymbioticCore(
        uint256 seed
    ) internal returns (uint256) {
        return uint256(keccak256(abi.encode(vm.getBlockTimestamp(), vm.getBlockNumber(), count(), seed)));
    }

    function _getAccount_SymbioticCore() internal returns (Vm.Wallet memory) {
        return vm.createWallet(random_SymbioticCore());
    }

    function _skipBlocks_SymbioticCore(
        uint256 number
    ) internal {
        try vm.activeFork() {
            vm.rollFork(vm.getBlockNumber() + number);
        } catch {
            vm.warp(vm.getBlockTimestamp() + number * SYMBIOTIC_CORE_BLOCK_TIME);
            vm.roll(vm.getBlockNumber() + number);
        }
    }

    function _contains_SymbioticCore(address[] memory array, address element) internal returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    function _contains_SymbioticCore(Vm.Wallet[] memory array, Vm.Wallet memory element) internal returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i].addr == element.addr) {
                return true;
            }
        }
        return false;
    }

    modifier equalLengthsAddressAddress_SymbioticCore(address[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Address_SymbioticCore(uint96[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Uint256_SymbioticCore(uint96[] memory a, uint256[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    // ------------------------------------------------------------ TOKEN-RELATED HELPERS ------------------------------------------------------------ //

    function _getToken_SymbioticCore() internal returns (address) {
        return address(new Token("Token"));
    }

    function _getFeeOnTransferToken_SymbioticCore() internal returns (address) {
        return address(new FeeOnTransferToken("Token"));
    }

    function _getSupportedTokens_SymbioticCore() internal returns (address[] memory supportedTokens) {
        string[] memory supportedTokensStr = SymbioticCoreConstants.supportedTokens();
        supportedTokens = new address[](supportedTokensStr.length);
        for (uint256 i; i < supportedTokensStr.length; i++) {
            supportedTokens[i] = SymbioticCoreConstants.token(supportedTokensStr[i]);
        }
    }

    function _chooseToken_SymbioticCore(
        address[] memory tokens
    ) internal returns (address) {
        return tokens[bound(random_SymbioticCore(), 0, tokens.length - 1)];
    }

    // ------------------------------------------------------------ VAULT-RELATED HELPERS ------------------------------------------------------------ //

    function _getVault_SymbioticCore(
        address collateral
    ) internal returns (address) {
        address owner = address(this);
        uint48 epochDuration = 7 days;
        uint48 vetoDuration = 1 days;

        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;
        (address vault,,) = symbioticCore.vaultConfigurator.create(
            ISymbioticVaultConfigurator.InitParams({
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
            })
        );

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
        bool withSlasher,
        uint64 slasherIndex,
        uint48 vetoDuration
    ) internal returns (address) {
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

        (address vault,,) = symbioticCore.vaultConfigurator.create(
            ISymbioticVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: vaultParams,
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );

        if (depositWhitelist) {
            for (uint256 i; i < whitelistedDepositors.length; ++i) {
                _setDepositorWhitelistStatus_SymbioticCore(owner, vault, whitelistedDepositors[i], true);
            }
        }

        return vault;
    }

    // ------------------------------------------------------------ OPERATOR-RELATED HELPERS ------------------------------------------------------------ //

    function _getOperator_SymbioticCore() internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getAccount_SymbioticCore();
        _registerOperator_SymbioticCore(symbioticCore, operator.addr);
        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(
        address vault
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        _optIn_SymbioticCore(symbioticCore, operator.addr, vault);

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(address vault, address network) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        _optIn_SymbioticCore(symbioticCore, operator.addr, vault);
        _optIn_SymbioticCore(symbioticCore, operator.addr, network);

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(
        address[] memory vaults
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _optIn_SymbioticCore(symbioticCore, operator.addr, vaults[i]);
        }

        return operator;
    }

    function _getOperatorWithOptIns_SymbioticCore(
        address[] memory vaults,
        address[] memory networks
    ) internal equalLengthsAddressAddress_SymbioticCore(vaults, networks) returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _optIn_SymbioticCore(symbioticCore, operator.addr, vaults[i]);
        }

        for (uint256 i; i < networks.length; ++i) {
            _optIn_SymbioticCore(symbioticCore, operator.addr, networks[i]);
        }

        return operator;
    }

    function _operatorOptIn_SymbioticCore(address operator, address where) internal {
        _optIn_SymbioticCore(symbioticCore, operator, where);
    }

    function _operatorOptOut_SymbioticCore(address operator, address where) internal {
        _optOut_SymbioticCore(symbioticCore, operator, where);
    }

    function _operatorOptInSignature_SymbioticCore(Vm.Wallet memory operator, address where) internal {
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);

        address service;
        uint256 nonce;
        if (symbioticCore.vaultFactory.isEntity(where)) {
            service = address(symbioticCore.operatorVaultOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            service = address(symbioticCore.operatorNetworkOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else {
            revert("Invalid address for opt-in");
        }

        bytes32 digest = computeOptInDigest_SymbioticCore(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
    }

    function _operatorOptOutSignature_SymbioticCore(Vm.Wallet memory operator, address where) internal {
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);

        address service;
        uint256 nonce;
        if (symbioticCore.vaultFactory.isEntity(where)) {
            service = address(symbioticCore.operatorVaultOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            service = address(symbioticCore.operatorNetworkOptInService);
            nonce = symbioticCore.operatorVaultOptInService.nonces(operator.addr, where);
        } else {
            revert("Invalid address for opt-out");
        }

        bytes32 digest = computeOptOutDigest_SymbioticCore(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
    }

    function computeOptInDigest_SymbioticCore(
        address service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view returns (bytes32) {
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
    ) internal view returns (bytes32) {
        bytes32 OPT_OUT_TYPEHASH = keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_OUT_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator_SymbioticCore(service);

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _computeDomainSeparator_SymbioticCore(
        address service
    ) internal view returns (bytes32) {
        bytes32 DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        (, string memory name, string memory version,,,,) = IERC5267(service).eip712Domain();
        bytes32 NAME_HASH = keccak256(bytes(name));
        bytes32 VERSION_HASH = keccak256(bytes(version));
        uint256 chainId = block.chainid;

        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, service));
    }

    // ------------------------------------------------------------ NETWORK-RELATED HELPERS ------------------------------------------------------------ //

    function _getNetwork_SymbioticCore() internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getAccount_SymbioticCore();
        _registerNetwork_SymbioticCore(symbioticCore, network.addr);

        return network;
    }

    function _getNetworkWithMaxNetworkLimits_SymbioticCore(
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);

        return network;
    }

    function _getNetworkWithMaxNetworkLimits_SymbioticCore(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits
    )
        internal
        equalLengthsUint96Address_SymbioticCore(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
        }

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsAndResolvers_SymbioticCore(
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit,
        address resolver
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        _setMaxNetworkLimit_SymbioticCore(network.addr, vault, identifier, maxNetworkLimit);
        _setResolver_SymbioticCore(network.addr, vault, identifier, resolver);

        return network;
    }

    function _getNetworkWithMaxNetworkLimits_SymbioticCore(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits,
        address[] memory resolvers
    )
        internal
        equalLengthsUint96Address_SymbioticCore(identifiers, vaults)
        equalLengthsUint96Uint256_SymbioticCore(identifiers, maxNetworkLimits)
        equalLengthsUint96Address_SymbioticCore(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork_SymbioticCore();

        for (uint256 i; i < vaults.length; ++i) {
            _setMaxNetworkLimit_SymbioticCore(network.addr, vaults[i], identifiers[i], maxNetworkLimits[i]);
            _setResolver_SymbioticCore(network.addr, vaults[i], identifiers[i], resolvers[i]);
        }

        return network;
    }

    function _networkSetMaxNetworkLimit(
        address network,
        address vault,
        uint96 identifier,
        uint256 maxNetworkLimit
    ) internal {
        _setMaxNetworkLimit_SymbioticCore(network, vault, identifier, maxNetworkLimit);
    }

    function _networkSetResolver(address network, address vault, uint96 identifier, address resolver) internal {
        _setResolver_SymbioticCore(network, vault, identifier, resolver);
    }

    // ------------------------------------------------------------ STAKER-RELATED HELPERS ------------------------------------------------------------ //

    function _getStaker_SymbioticCore(
        address[] memory possibleTokens
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory staker = _getAccount_SymbioticCore();

        for (uint256 i; i < possibleTokens.length; ++i) {
            uint256 decimals = ERC20(possibleTokens[i]).decimals();
            deal(possibleTokens[i], staker.addr, TOKENS_TO_SET_TIMES_1e18.mulDiv(10 ** decimals, 1e18), true); // should cover most cases
        }

        return staker;
    }

    function _getStakerWithStakes_SymbioticCore(
        address[] memory possibleTokens,
        address[] memory vaults
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory staker = _getStaker_SymbioticCore(possibleTokens);

        for (uint256 i; i < vaults.length; ++i) {
            address collateral = ISymbioticVault(vaults[i]).collateral();
            uint256 decimals = ERC20(collateral).decimals();

            uint256 amount = bound(
                random_SymbioticCore(),
                MIN_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18),
                MAX_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18)
            );

            _deposit_SymbioticCore(staker.addr, vaults[i], amount);
        }

        return staker;
    }

    function _stakerDeposit_SymbioticCore(address staker, address vault, uint256 amount) internal {
        _deposit_SymbioticCore(staker, vault, amount);
    }

    function _stakerDepositRandom_SymbioticCore(address staker, address vault) internal {
        address collateral = ISymbioticVault(vault).collateral();
        uint256 decimals = ERC20(collateral).decimals();

        uint256 amount = bound(
            random_SymbioticCore(),
            MIN_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18),
            MAX_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18)
        );

        _stakerDeposit_SymbioticCore(staker, vault, amount);
    }

    function _stakerWithdraw_SymbioticCore(address staker, address vault, uint256 amount) internal {
        _withdraw_SymbioticCore(staker, vault, amount);
    }

    function _stakerWithdrawRandom_SymbioticCore(address staker, address vault) internal {
        uint256 balance = ISymbioticVault(vault).activeBalanceOf(staker);

        uint256 amount = bound(random_SymbioticCore(), 1, balance);

        _stakerWithdraw_SymbioticCore(staker, vault, amount);
    }

    function _stakerRedeem_SymbioticCore(address staker, address vault, uint256 shares) internal {
        _redeem_SymbioticCore(staker, vault, shares);
    }

    function _stakerClaim_SymbioticCore(address staker, address vault, uint256 epoch) internal {
        _claim_SymbioticCore(staker, vault, epoch);
    }

    function _stakerClaimBatch_SymbioticCore(address staker, address vault, uint256[] memory epochs) internal {
        _claimBatch_SymbioticCore(staker, vault, epochs);
    }

    function _stakerSetDepositWhitelist_SymbioticCore(address staker, address vault, bool status) internal {
        _setDepositWhitelist_SymbioticCore(staker, vault, status);
    }

    function _stakerSetDepositorWhitelistStatus_SymbioticCore(
        address staker,
        address vault,
        address account,
        bool status
    ) internal {
        _setDepositorWhitelistStatus_SymbioticCore(staker, vault, account, status);
    }

    function _stakerSetIsDepositLimit_SymbioticCore(address staker, address vault, bool status) internal {
        _setIsDepositLimit_SymbioticCore(staker, vault, status);
    }

    function _stakerSetDepositLimit_SymbioticCore(address staker, address vault, uint256 limit) internal {
        _setDepositLimit_SymbioticCore(staker, vault, limit);
    }

    // ------------------------------------------------------------ CURATOR-RELATED HELPERS ------------------------------------------------------------ //

    function _curatorSetHook_SymbioticCore(address curator, address vault, address hook) internal {
        _setHook_SymbioticCore(curator, vault, hook);
    }

    function _curatorSetHook_SymbioticCore(address vault, address hook) internal {
        _curatorSetHook_SymbioticCore(address(this), vault, hook);
    }

    function _curatorSetNetworkLimit_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        uint256 amount
    ) internal {
        _setNetworkLimit_SymbioticCore(curator, vault, subnetwork, amount);
    }

    function _curatorSetNetworkLimit_SymbioticCore(address vault, bytes32 subnetwork, uint256 amount) internal {
        _curatorSetNetworkLimit_SymbioticCore(address(this), vault, subnetwork, amount);
    }

    function _curatorSetOperatorNetworkShares_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) internal {
        _setOperatorNetworkShares_SymbioticCore(curator, vault, subnetwork, operator, shares);
    }

    function _curatorSetOperatorNetworkShares_SymbioticCore(
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) internal {
        _curatorSetOperatorNetworkShares_SymbioticCore(address(this), vault, subnetwork, operator, shares);
    }

    function _curatorSetOperatorNetworkLimit_SymbioticCore(
        address curator,
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) internal {
        _setOperatorNetworkLimit_SymbioticCore(curator, vault, subnetwork, operator, amount);
    }

    function _curatorSetOperatorNetworkLimit_SymbioticCore(
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) internal {
        _curatorSetOperatorNetworkLimit_SymbioticCore(address(this), vault, subnetwork, operator, amount);
    }
}
