// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {Entity} from "../../src/contracts/common/Entity.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {IUniversalDelegator, UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../mocks/Token.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

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

contract VaultV2SixDecimalToken is Token {
    constructor() Token("Six Decimal Collateral") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
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
        assertEq(IVaultV2.virtualShares.selector, bytes4(keccak256("virtualShares()")));
        assertEq(
            IERC20Permit.permit.selector,
            bytes4(keccak256("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))
        );
        assertEq(IERC20Permit.nonces.selector, bytes4(keccak256("nonces(address)")));
        assertEq(IERC20Permit.DOMAIN_SEPARATOR.selector, bytes4(keccak256("DOMAIN_SEPARATOR()")));
    }
}

contract VaultV2BehaviorTest is Test {
    address internal constant DEAD_SHARES_RECIPIENT = 0x000000000000000000000000000000000000dEaD;

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
        uint256 seedAssets = _targetDeadAssets(collateral.decimals());
        VaultV2 vault = _createVault(true, true, seedAssets + 100);

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
        assertEq(vault.virtualShares(), 1);
        assertEq(vault.balanceOf(DEAD_SHARES_RECIPIENT), 1e9);
        assertEq(collateral.balanceOf(address(vault)), 1e9);
        _assertNoLegacyShareGetters(vault);
    }

    function test_InitializeStoresAssetAdjustedVirtualShares() public {
        collateral = new VaultV2SixDecimalToken();

        VaultV2 vault = _createVault(false, false, 0);

        assertEq(vault.virtualShares(), 1e12);
        assertEq(vault.decimals(), 18);
        assertEq(vault.balanceOf(DEAD_SHARES_RECIPIENT), 1e18);
        assertEq(collateral.balanceOf(address(vault)), 1e6);
        _assertNoLegacyShareGetters(vault);
    }

    function test_TotalSupplyIncludesAccruedFeeSharesBeforeMinting() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);
        uint256 rawSupply = vault.totalSupply();

        vm.warp(block.timestamp + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        (, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.getAccrueInterest();

        assertGt(performanceFeeShares + managementFeeShares, 0);
        assertEq(vault.totalSupply(), rawSupply + performanceFeeShares + managementFeeShares);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_AccrueInterestMintsPreviewedFeeSharesWithoutChangingVisibleSupply() public {
        VaultV2 vault = _createVault(false, false, 0);
        _deposit(vault, alice, 100 ether);

        vm.warp(block.timestamp + 30 days);
        collateral.transfer(address(vault), 100_000 ether);

        uint256 previewSupply = vault.totalSupply();
        (, uint256 previewPerformanceFeeShares, uint256 previewManagementFeeShares) = vault.getAccrueInterest();

        (uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterest();

        assertEq(performanceFeeShares, previewPerformanceFeeShares);
        assertEq(managementFeeShares, previewManagementFeeShares);
        assertEq(vault.balanceOf(address(this)), performanceFeeShares + managementFeeShares);
        assertEq(vault.totalSupply(), previewSupply);
        assertEq(vault.lastUpdate(), block.timestamp);
    }

    function _createVault(bool depositWhitelist, bool isDepositLimit, uint256 depositLimit)
        internal
        returns (VaultV2 vault)
    {
        bytes memory data = abi.encode(
            IVaultV2.InitParams({
                name: "Vault",
                symbol: "vTKN",
                asset: address(collateral),
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
        );
        collateral.approve(_predictVaultAddress(data), _targetDeadAssets(collateral.decimals()));

        address vaultAddress = vaultFactory.create(VAULT_V2_VERSION, address(this), data);

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

    function _predictVaultAddress(bytes memory data) internal view returns (address) {
        bytes memory initData = abi.encodeCall(IMigratableEntity.initialize, (VAULT_V2_VERSION, address(this), data));
        bytes memory initCode = abi.encodePacked(
            type(MigratableEntityProxy).creationCode,
            abi.encode(vaultFactory.implementation(VAULT_V2_VERSION), initData)
        );
        bytes32 salt = keccak256(abi.encode(vaultFactory.totalEntities(), VAULT_V2_VERSION, address(this), data));
        return Create2.computeAddress(salt, keccak256(initCode), address(vaultFactory));
    }

    function _targetDeadAssets(uint8 assetDecimals) internal pure returns (uint256) {
        uint256 decimalsOffset = assetDecimals >= 18 ? 0 : 18 - assetDecimals;
        uint256 virtualShares = 10 ** decimalsOffset;
        uint256 targetShares = _targetDeadShares(assetDecimals);
        return (targetShares + virtualShares - 1) / virtualShares;
    }

    function _targetDeadShares(uint8 assetDecimals) internal pure returns (uint256) {
        uint256 decimalsOffset = assetDecimals >= 18 ? 0 : 18 - assetDecimals;
        uint256 offsetTargetShares = 10 ** (6 + decimalsOffset);
        return offsetTargetShares > 1e9 ? offsetTargetShares : 1e9;
    }

    function _assertNoLegacyShareGetters(VaultV2 vault) internal view {
        _assertMissingGetter(address(vault), abi.encodeWithSignature("deadShares()"));
        _assertMissingGetter(address(vault), abi.encodeWithSignature("activeShares()"));
        _assertMissingGetter(
            address(vault), abi.encodeWithSignature("activeSharesAt(uint48,bytes)", uint48(block.timestamp), "")
        );
        _assertMissingGetter(address(vault), abi.encodeWithSignature("activeSharesOf(address)", alice));
        _assertMissingGetter(
            address(vault),
            abi.encodeWithSignature("activeSharesOfAt(address,uint48,bytes)", alice, uint48(block.timestamp), "")
        );
    }

    function _assertMissingGetter(address target, bytes memory data) internal view {
        (bool success,) = target.staticcall(data);
        assertFalse(success);
    }

    function _deposit(VaultV2 vault, address account, uint256 assets) internal {
        collateral.transfer(account, assets);

        vm.startPrank(account);
        collateral.approve(address(vault), assets);
        vault.deposit(assets, account);
        vm.stopPrank();
    }
}
