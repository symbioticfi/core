// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {Entity} from "../../src/contracts/common/Entity.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../mocks/Token.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultV2FeeRegistryMock is IFeeRegistry {
    uint256 internal immutable MANAGEMENT_FEE;
    uint256 internal immutable PERFORMANCE_FEE;
    address internal immutable MANAGEMENT_FEE_RECIPIENT;
    address internal immutable PERFORMANCE_FEE_RECIPIENT;

    constructor(
        uint256 managementFee,
        uint256 performanceFee,
        address managementFeeRecipient,
        address performanceFeeRecipient
    ) {
        MANAGEMENT_FEE = managementFee;
        PERFORMANCE_FEE = performanceFee;
        MANAGEMENT_FEE_RECIPIENT = managementFeeRecipient;
        PERFORMANCE_FEE_RECIPIENT = performanceFeeRecipient;
    }

    function getManagementFee(address) external view returns (uint256) {
        return MANAGEMENT_FEE;
    }

    function getManagementFeeRecipient(address) external view returns (address) {
        return MANAGEMENT_FEE_RECIPIENT;
    }

    function getPerformanceFee(address) external view returns (uint256) {
        return PERFORMANCE_FEE;
    }

    function getPerformanceFeeRecipient(address) external view returns (address) {
        return PERFORMANCE_FEE_RECIPIENT;
    }
}

contract VaultV2MigratableEntityMock is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}
}

contract VaultV2EntityMock is Entity {
    constructor(address factory, uint64 type_) Entity(factory, type_) {}
}

contract VaultV2FeeRegistryApiTest is Test {
    function test_feeRegistryAndVaultExposeSnapshotFeeApi() public pure {
        assertEq(IFeeRegistry.getManagementFee.selector, bytes4(keccak256("getManagementFee(address)")));
        assertEq(
            IFeeRegistry.getManagementFeeRecipient.selector, bytes4(keccak256("getManagementFeeRecipient(address)"))
        );
        assertEq(IFeeRegistry.getPerformanceFee.selector, bytes4(keccak256("getPerformanceFee(address)")));
        assertEq(
            IFeeRegistry.getPerformanceFeeRecipient.selector, bytes4(keccak256("getPerformanceFeeRecipient(address)"))
        );
        assertEq(IVaultV2.lastManagementFee.selector, bytes4(keccak256("lastManagementFee()")));
        assertEq(IVaultV2.lastPerformanceFee.selector, bytes4(keccak256("lastPerformanceFee()")));
        assertEq(IVaultV2.getAccrueInterest.selector, bytes4(keccak256("getAccrueInterest()")));
    }
}

contract VaultV2BehaviorTest is Test {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    Token internal collateral;
    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    AdapterRegistry internal adapterRegistry;
    VaultV2FeeRegistryMock internal feeRegistry;

    function setUp() public {
        collateral = new Token("Collateral");
        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        adapterRegistry = new AdapterRegistry();
        adapterRegistry.initialize(address(this));
        feeRegistry = new VaultV2FeeRegistryMock(7, 11, address(this), address(this));

        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new VaultV2MigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(0x1),
                    address(feeRegistry),
                    address(vaultFactory),
                    address(0x2),
                    address(adapterRegistry),
                    address(delegatorFactory),
                    address(new WithdrawalQueue())
                )
            )
        );

        for (uint64 i; i < UNIVERSAL_DELEGATOR_TYPE; ++i) {
            delegatorFactory.whitelist(address(new VaultV2EntityMock(address(delegatorFactory), i)));
        }
        delegatorFactory.whitelist(
            address(
                new UniversalDelegator(
                    UNIVERSAL_DELEGATOR_TYPE, address(vaultFactory), address(adapterRegistry), address(delegatorFactory)
                )
            )
        );
    }

    function test_MaxDepositAndMaxMintApplyWhitelistAndLimit() public {
        VaultV2 vault = _createVault(true, true, 100);

        assertEq(vault.maxDeposit(bob), 0);
        assertEq(vault.maxMint(bob), 0);
        assertEq(vault.maxDeposit(alice), 100);
        assertEq(vault.maxMint(alice), vault.previewDeposit(100));

        IERC20(address(collateral)).transfer(address(vault), 40);

        assertEq(vault.maxDeposit(alice), 60);
        assertEq(vault.maxMint(alice), vault.previewDeposit(60));
    }

    function test_InitializeSnapshotsCurrentFees() public {
        VaultV2 vault = _createVault(false, false, 0);

        assertEq(vault.lastManagementFee(), 7);
        assertEq(vault.lastPerformanceFee(), 11);
    }

    function _createVault(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        returns (VaultV2 vault)
    {
        address vaultAddress = vaultFactory.create(
            VAULT_V2_VERSION,
            address(this),
            abi.encode(
                IVaultV2.InitParams({
                    name: "Vault",
                    symbol: "vTKN",
                    asset: address(collateral),
                    burner: address(0xB),
                    depositWhitelist: depositWhitelist,
                    depositorToWhitelist: alice,
                    isDepositLimit: isDepositLimit,
                    depositLimit: depositLimit,
                    defaultAdminRoleHolder: address(this),
                    depositWhitelistSetRoleHolder: address(this),
                    depositorWhitelistRoleHolder: address(this),
                    isDepositLimitSetRoleHolder: address(this),
                    depositLimitSetRoleHolder: address(this)
                })
            )
        );

        address delegator = delegatorFactory.create(
            UNIVERSAL_DELEGATOR_TYPE,
            abi.encode(
                vaultAddress,
                abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: address(this),
                        addAdapterRoleHolder: address(this),
                        removeAdapterRoleHolder: address(this),
                        setAdapterLimitsRoleHolder: address(this),
                        setAutoAllocateAdaptersRoleHolder: address(this),
                        swapAdaptersRoleHolder: address(this),
                        allocateRoleHolder: address(this),
                        deallocateRoleHolder: address(this),
                        adapters: new address[](0),
                        absoluteLimits: new uint256[](0),
                        shareLimits: new uint256[](0)
                    })
                )
            )
        );

        vault = VaultV2(vaultAddress);
        vault.setDelegator(delegator);
    }
}
