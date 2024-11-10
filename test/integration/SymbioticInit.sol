// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./Imports.sol";

import {Constants} from "./Constants.sol";
import {Counter} from "./Counter.sol";

import {Token} from "../mocks/Token.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SymbioticInit is Counter, Test {
    using SafeERC20 for IERC20;
    using Math for uint256;

    Constants.Core symbioticCore;

    function setUp() public virtual {
        _initCore(false);
    }

    // -------------------------------- GENERAL HELPERS -------------------------------- //

    function _initCore() internal {
        symbioticCore = Constants.core();
    }

    function _initCore(
        bool useExisting
    ) internal {
        if (useExisting) {
            _initCore();
        } else {
            SymbioticVaultFactory vaultFactory = new SymbioticVaultFactory(address(this));
            SymbioticDelegatorFactory delegatorFactory = new SymbioticDelegatorFactory(address(this));
            SymbioticSlasherFactory slasherFactory = new SymbioticSlasherFactory(address(this));
            SymbioticNetworkRegistry networkRegistry = new SymbioticNetworkRegistry();
            SymbioticOperatorRegistry operatorRegistry = new SymbioticOperatorRegistry();
            SymbioticMetadataService operatorMetadataService = new SymbioticMetadataService(address(operatorRegistry));
            SymbioticMetadataService networkMetadataService = new SymbioticMetadataService(address(networkRegistry));
            SymbioticNetworkMiddlewareService networkMiddlewareService =
                new SymbioticNetworkMiddlewareService(address(networkRegistry));
            SymbioticOptInService operatorVaultOptInService =
                new SymbioticOptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
            SymbioticOptInService operatorNetworkOptInService = new SymbioticOptInService(
                address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService"
            );

            address vaultImpl =
                address(new SymbioticVault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
            vaultFactory.whitelist(vaultImpl);

            address networkRestakeDelegatorImpl = address(
                new SymbioticNetworkRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            );
            delegatorFactory.whitelist(networkRestakeDelegatorImpl);

            address fullRestakeDelegatorImpl = address(
                new SymbioticFullRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            );
            delegatorFactory.whitelist(fullRestakeDelegatorImpl);

            address operatorSpecificDelegatorImpl = address(
                new SymbioticOperatorSpecificDelegator(
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

            address slasherImpl = address(
                new SymbioticSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            );
            slasherFactory.whitelist(slasherImpl);

            address vetoSlasherImpl = address(
                new SymbioticVetoSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            );
            slasherFactory.whitelist(vetoSlasherImpl);

            SymbioticVaultConfigurator vaultConfigurator = new SymbioticVaultConfigurator(
                address(vaultFactory), address(delegatorFactory), address(slasherFactory)
            );

            symbioticCore = Constants.Core({
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

    function _getAccount() internal returns (Vm.Wallet memory) {
        return vm.createWallet(uint256(keccak256(abi.encode(block.number, count()))));
    }

    modifier equalLengthsAddressAddress(address[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Address(uint96[] memory a, address[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    modifier equalLengthsUint96Uint256(uint96[] memory a, uint256[] memory b) {
        require(a.length == b.length, "Arrays must have equal lengths");
        _;
    }

    // -------------------------------- TOKEN-RELATED HELPERS -------------------------------- //

    function _getToken() internal returns (address) {
        return address(new Token("Token"));
    }

    function _getTokenFeeOnTransfer() internal returns (address) {
        return address(new FeeOnTransferToken("Token"));
    }

    // -------------------------------- VAULT-RELATED HELPERS -------------------------------- //

    function _getVault(
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

    function _getVault(
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
                vm.startPrank(owner);
                SymbioticVault(vault).setDepositorWhitelistStatus(whitelistedDepositors[i], true);
                vm.stopPrank();
            }
        }

        return vault;
    }

    // -------------------------------- OPERATOR-RELATED HELPERS -------------------------------- //

    function _getOperator() internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getAccount();
        vm.startPrank(operator.addr);
        symbioticCore.operatorRegistry.registerOperator();
        vm.stopPrank();

        return operator;
    }

    function _getOperatorWithOptIns(
        address vault
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator();

        vm.startPrank(operator.addr);
        symbioticCore.operatorVaultOptInService.optIn(vault);
        vm.stopPrank();

        return operator;
    }

    function _getOperatorWithOptIns(address vault, address network) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator();

        vm.startPrank(operator.addr);
        symbioticCore.operatorVaultOptInService.optIn(vault);
        symbioticCore.operatorNetworkOptInService.optIn(network);
        vm.stopPrank();

        return operator;
    }

    function _getOperatorWithOptIns(
        address[] memory vaults
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator();

        for (uint256 i; i < vaults.length; ++i) {
            vm.startPrank(operator.addr);
            symbioticCore.operatorVaultOptInService.optIn(vaults[i]);
            vm.stopPrank();
        }

        return operator;
    }

    function _getOperatorWithOptIns(
        address[] memory vaults,
        address[] memory networks
    ) internal equalLengthsAddressAddress(vaults, networks) returns (Vm.Wallet memory) {
        Vm.Wallet memory operator = _getOperator();

        for (uint256 i; i < vaults.length; ++i) {
            vm.startPrank(operator.addr);
            symbioticCore.operatorVaultOptInService.optIn(vaults[i]);
            vm.stopPrank();
        }

        for (uint256 i; i < networks.length; ++i) {
            vm.startPrank(operator.addr);
            symbioticCore.operatorNetworkOptInService.optIn(networks[i]);
            vm.stopPrank();
        }

        return operator;
    }

    function _operatorOptIn(address operator, address where) internal {
        vm.startPrank(operator);
        if (symbioticCore.vaultFactory.isEntity(where)) {
            symbioticCore.operatorVaultOptInService.optIn(where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            symbioticCore.operatorNetworkOptInService.optIn(where);
        } else {
            revert("Invalid address for opt-in");
        }
        vm.stopPrank();
    }

    function _operatorOptOut(address operator, address where) internal {
        vm.startPrank(operator);
        if (symbioticCore.vaultFactory.isEntity(where)) {
            symbioticCore.operatorVaultOptInService.optOut(where);
        } else if (symbioticCore.networkRegistry.isEntity(where)) {
            symbioticCore.operatorNetworkOptInService.optOut(where);
        } else {
            revert("Invalid address for opt-in");
        }
        vm.stopPrank();
    }

    function _operatorOptInSignature(Vm.Wallet memory operator, address where) internal {
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

        bytes32 digest = computeOptInDigest(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
    }

    function _operatorOptOutSignature(Vm.Wallet memory operator, address where) internal {
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

        bytes32 digest = computeOptOutDigest(service, operator.addr, where, nonce, deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
    }

    function computeOptInDigest(
        address service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view returns (bytes32) {
        bytes32 OPT_IN_TYPEHASH = keccak256("OptIn(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_IN_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator(service);

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function computeOptOutDigest(
        address service,
        address who,
        address where,
        uint256 nonce,
        uint48 deadline
    ) internal view returns (bytes32) {
        bytes32 OPT_OUT_TYPEHASH = keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)");
        bytes32 structHash = keccak256(abi.encode(OPT_OUT_TYPEHASH, who, where, nonce, deadline));

        bytes32 domainSeparator = _computeDomainSeparator(service);

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _computeDomainSeparator(
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

    // -------------------------------- NETWORK-RELATED HELPERS -------------------------------- //

    function _getNetwork() internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getAccount();
        vm.startPrank(network.addr);
        symbioticCore.networkRegistry.registerNetwork();
        vm.stopPrank();

        return network;
    }

    function _getNetworkWithMaxNetworkLimits(
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork();

        address delegator = SymbioticVault(vault).delegator();

        vm.startPrank(network.addr);
        ISymbioticBaseDelegator(delegator).setMaxNetworkLimit(identifier, maxNetworkLimit);
        vm.stopPrank();

        return network;
    }

    function _getNetworkWithMaxNetworkLimits(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits
    )
        internal
        equalLengthsUint96Address(identifiers, vaults)
        equalLengthsUint96Uint256(identifiers, maxNetworkLimits)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork();

        for (uint256 i; i < vaults.length; ++i) {
            address delegator = SymbioticVault(vaults[i]).delegator();

            vm.startPrank(network.addr);
            ISymbioticBaseDelegator(delegator).setMaxNetworkLimit(identifiers[i], maxNetworkLimits[i]);
            vm.stopPrank();
        }

        return network;
    }

    function _getNetworkWithMaxNetworkLimitsAndResolvers(
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit,
        address resolver
    ) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory network = _getNetwork();

        address delegator = SymbioticVault(vault).delegator();
        address slasher = SymbioticVault(vault).slasher();

        if (SymbioticBaseSlasher(slasher).TYPE() != 1) {
            revert("Invalid slasher type");
        }

        vm.startPrank(network.addr);
        ISymbioticBaseDelegator(delegator).setMaxNetworkLimit(identifier, maxNetworkLimit);
        SymbioticVetoSlasher(slasher).setResolver(identifier, resolver, new bytes(0));
        vm.stopPrank();

        return network;
    }

    function _getNetworkWithMaxNetworkLimits(
        uint96[] memory identifiers,
        address[] memory vaults,
        uint256[] memory maxNetworkLimits,
        address[] memory resolvers
    )
        internal
        equalLengthsUint96Address(identifiers, vaults)
        equalLengthsUint96Uint256(identifiers, maxNetworkLimits)
        equalLengthsUint96Address(identifiers, resolvers)
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory network = _getNetwork();

        for (uint256 i; i < vaults.length; ++i) {
            address delegator = SymbioticVault(vaults[i]).delegator();
            address slasher = SymbioticVault(vaults[i]).slasher();

            if (SymbioticBaseSlasher(slasher).TYPE() != 1) {
                revert("Invalid slasher type");
            }
            vm.startPrank(network.addr);
            ISymbioticBaseDelegator(delegator).setMaxNetworkLimit(identifiers[i], maxNetworkLimits[i]);
            SymbioticVetoSlasher(slasher).setResolver(identifiers[i], resolvers[i], new bytes(0));
            vm.stopPrank();
        }

        return network;
    }

    function _networkSetMaxNetworkLimit(
        address network,
        uint96 identifier,
        address vault,
        uint256 maxNetworkLimit
    ) internal {
        address delegator = SymbioticVault(vault).delegator();

        vm.startPrank(network);
        ISymbioticBaseDelegator(delegator).setMaxNetworkLimit(identifier, maxNetworkLimit);
        vm.stopPrank();
    }

    function _networkSetResolver(address network, uint96 identifier, address vault, address resolver) internal {
        address slasher = SymbioticVault(vault).slasher();

        if (SymbioticBaseSlasher(slasher).TYPE() != 1) {
            revert("Invalid slasher type");
        }

        vm.startPrank(network);
        SymbioticVetoSlasher(slasher).setResolver(identifier, resolver, new bytes(0));
        vm.stopPrank();
    }

    // -------------------------------- STAKER-RELATED HELPERS -------------------------------- //

    function _getStaker(
        address[] memory possibleTokens
    ) internal returns (Vm.Wallet memory) {
        uint256 TOKENS_TO_SET_TIMES_1e18 = 100_000_000 * 1e18;

        Vm.Wallet memory staker = _getAccount();

        for (uint256 i; i < possibleTokens.length; ++i) {
            uint256 decimals = ERC20(possibleTokens[i]).decimals();
            deal(possibleTokens[i], staker.addr, TOKENS_TO_SET_TIMES_1e18.mulDiv(10 ** decimals, 1e18), true); // should cover most cases
        }

        return staker;
    }

    function _getStakerWithStakes(
        address[] memory possibleTokens,
        address[] memory vaults
    ) internal returns (Vm.Wallet memory) {
        uint256 MIN_TOKENS_TO_DEPOSIT_TIMES_1e18 = 0.001 * 1e18;
        uint256 MAX_TOKENS_TO_DEPOSIT_TIMES_1e18 = 1_000_000 * 1e18;

        Vm.Wallet memory staker = _getStaker(possibleTokens);

        for (uint256 i; i < vaults.length; ++i) {
            address collateral = SymbioticVault(vaults[i]).collateral();
            uint256 decimals = ERC20(possibleTokens[i]).decimals();

            uint256 seed = uint256(keccak256(abi.encode(staker.addr, i)));
            uint256 amount = bound(
                seed,
                MIN_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18),
                MAX_TOKENS_TO_DEPOSIT_TIMES_1e18.mulDiv(10 ** decimals, 1e18)
            );

            vm.startPrank(staker.addr);
            IERC20(collateral).forceApprove(vaults[i], amount);
            SymbioticVault(vaults[i]).deposit(staker.addr, amount);
            vm.stopPrank();
        }

        return staker;
    }
}
