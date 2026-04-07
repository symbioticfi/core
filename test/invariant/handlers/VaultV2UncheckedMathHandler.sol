// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";
import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../../mocks/Token.sol";
import {MockFeeRegistry} from "../../mocks/MockFeeRegistry.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract VaultV2UncheckedMathHandler is Test {
    uint256 internal constant MAX_ACTION_AMOUNT = 1_000_000 ether;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    VaultConfigurator internal vaultConfigurator;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;

    Token public collateral;
    MockFeeRegistry internal feeRegistry;
    MockRewards public rewards;
    AdapterRegistry internal adapterRegistry;
    IVaultV2 public vault;

    uint256 public totalDeposited;
    uint256 public totalDonated;
    uint256 public totalClaimed;
    uint256 public totalSlashed;

    address[] internal depositors;
    mapping(address account => bool isKnownDepositor) internal knownDepositor;
    mapping(address account => uint256 totalDeposited) public totalDepositedOf;
    mapping(address account => uint256 totalClaimed) public totalClaimedOf;

    constructor() {
        _initialize();
    }

    function getDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function vaultBalance() external view returns (uint256) {
        return collateral.balanceOf(address(vault));
    }

    function deposit(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _user(userSeed);
        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);

        deal(address(collateral), user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        (uint256 depositedAmount,) = vault.deposit(user, amount);
        vm.stopPrank();

        totalDeposited += depositedAmount;
        totalDepositedOf[user] += depositedAmount;
        _rememberDepositor(user);
    }

    function withdraw(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _selectDepositor(userSeed);
        if (user == address(0)) {
            return;
        }

        uint256 balance = vault.activeBalanceOf(user);
        if (balance == 0) {
            return;
        }

        amount = _bound(amount, 1, balance);

        vm.prank(user);
        vault.withdraw(user, amount);
    }

    function claim(uint256 userSeed, uint256 indexSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _selectDepositor(userSeed);
        if (user == address(0)) {
            return;
        }

        uint256 created = vault.withdrawalsOfLength(user);
        if (created == 0) {
            return;
        }

        uint256 index = _bound(indexSeed, 0, created - 1);
        if (vault.isWithdrawalsClaimed(index, user)) {
            return;
        }
        if (block.timestamp < vault.withdrawalUnlockAt(index, user)) {
            return;
        }

        uint256 amount = vault.withdrawalsOf(index, user);
        if (amount == 0) {
            return;
        }

        vm.prank(user);
        uint256 claimedAmount = vault.claim(user, index);

        totalClaimed += claimedAmount;
        totalClaimedOf[user] += claimedAmount;
    }

    function donate(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        if (vault.activeStake() + vault.activeWithdrawals() == 0) {
            return;
        }

        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);
        deal(address(collateral), address(rewards), amount);

        vm.startPrank(address(rewards));
        collateral.approve(address(vault), amount);
        VaultV2(address(vault)).donate(amount);
        vm.stopPrank();

        totalDonated += amount;
    }

    function slash(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint256 slashableStake = vault.totalStake();
        if (slashableStake == 0) {
            return;
        }

        amount = _bound(amount, 1, slashableStake);

        vm.prank(vault.slasher());
        (uint256 slashedAmount,) = VaultV2(address(vault)).onSlash(amount, false);

        totalSlashed += slashedAmount;
    }

    function _initialize() internal {
        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        slasherFactory = new SlasherFactory(address(this));
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        feeRegistry = new MockFeeRegistry();
        rewards = new MockRewards();
        adapterRegistry = new AdapterRegistry(address(this));
        collateral = new Token("InvariantToken");

        vaultFactory.whitelist(
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(feeRegistry),
                    address(rewards),
                    address(adapterRegistry)
                )
            )
        );

        delegatorFactory.whitelist(
            address(
                new NetworkRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new FullRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorNetworkSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new UniversalDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes(),
                    address(networkMiddlewareService)
                )
            )
        );

        slasherFactory.whitelist(
            address(
                new Slasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new VetoSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new UniversalSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );

        IVaultV2.InitParams memory vaultParams = IVaultV2.InitParams({
            name: "Invariant Vault",
            symbol: "IVLT",
            collateral: address(collateral),
            burner: address(0xBEEF),
            epochDuration: 7 days,
            depositWhitelist: false,
            depositorToWhitelist: address(0xBEEF),
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: address(this),
            depositWhitelistSetRoleHolder: address(this),
            depositorWhitelistRoleHolder: address(this),
            isDepositLimitSetRoleHolder: address(this),
            depositLimitSetRoleHolder: address(this),
            setAdapterLimitRoleHolder: address(this),
            swapAdaptersRoleHolder: address(this),
            allocateAdapterRoleHolder: address(this),
            deallocateAdapterRoleHolder: address(this)
        });

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: address(this),
            hook: address(0),
            hookSetRoleHolder: address(this),
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(this),
            swapSlotsRoleHolder: address(this),
            removeSlotRoleHolder: address(this),
            setWithdrawalBufferSizeRoleHolder: address(this),
            withdrawalBufferSize: type(uint128).max
        });

        IUniversalSlasher.InitParams memory slasherParams =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 1 days, resolverSetDelay: 21 days});

        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(0),
                vaultParams: abi.encode(vaultParams),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(delegatorParams),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: abi.encode(slasherParams)
            })
        );

        vault = IVaultV2(vault_);
    }

    function _rememberDepositor(address user) internal {
        if (knownDepositor[user]) {
            return;
        }
        knownDepositor[user] = true;
        depositors.push(user);
    }

    function _selectDepositor(uint256 seed) internal view returns (address) {
        if (depositors.length == 0) {
            return address(0);
        }
        return depositors[_bound(seed, 0, depositors.length - 1)];
    }

    function _user(uint256 seed) internal pure returns (address user) {
        user = address(uint160(seed + 100));
        if (user == address(0)) {
            user = address(100);
        }
    }

    function _warp(uint256 timeJumpSeed) internal {
        uint256 timeJump = _bound(timeJumpSeed, 1 hours, 14 days);
        vm.warp(block.timestamp + timeJump);
    }
}
