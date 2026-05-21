// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";

import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

import {Token} from "../../mocks/Token.sol";
import {MockAdapter} from "../../mocks/MockAdapter.sol";
import {MockFeeRegistry} from "../../mocks/MockFeeRegistry.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract VaultV2SolvencyHandler is Test {
    using Subnetwork for address;

    uint256 internal constant MAX_ACTION_AMOUNT = 1_000_000 ether;
    address internal constant BURNER = address(0xBEEF);

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
    UniversalDelegator public delegator;
    UniversalSlasher public slasher;
    MockAdapter public adapter;

    address public operator;
    address public primaryNetwork;
    address public primaryMiddleware;
    address public adapterNetwork;
    address public adapterMiddleware;
    bytes32 public primarySubnetwork;
    bytes32 public adapterSubnetwork;

    uint256 public totalDeposited;
    uint256 public totalDonated;
    uint256 public totalAdapterYield;
    uint256 public totalClaimed;

    bool public sawSuccessfulClaim;
    uint256 public lastClaimedAmount;
    uint256 public lastClaimPostClaimableBacking;
    uint256 public lastClaimPostUnclaimableReserve;
    uint256 public lastClaimPostVaultBalance;

    bool public sawSuccessfulSync;
    uint256 public lastSyncedAmount;
    uint256 public lastSyncPreTotalOwed;
    uint256 public lastSyncPostTotalOwed;
    uint256 public lastSyncPostVaultBalance;

    address[] internal depositors;
    mapping(address account => bool isKnownDepositor) internal knownDepositor;

    constructor() {
        _initialize();
    }

    function getDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function vaultBalance() public view returns (uint256) {
        return collateral.balanceOf(address(vault));
    }

    function adapterBalance() public view returns (uint256) {
        return collateral.balanceOf(address(adapter));
    }

    function burnerBalance() public view returns (uint256) {
        return collateral.balanceOf(BURNER);
    }

    function systemHoldings() public view returns (uint256) {
        return vaultBalance() + adapterBalance();
    }

    function trackedInflows() public view returns (uint256) {
        return totalDeposited + totalDonated + totalAdapterYield;
    }

    function trackedOutflows() public view returns (uint256) {
        return totalClaimed + burnerBalance();
    }

    function maxAllocatable() public view returns (uint256) {
        return vault.totalStake();
    }

    function adaptersOwe() public view returns (uint256) {
        return vault.adaptersOwe();
    }

    function claimableBacking() public view returns (uint256) {
        return vault.unclaimed();
    }

    function unclaimableReserve() public view returns (uint256) {
        return slasher.totalOwed();
    }

    function syncableOwedSlashCapacity() public view returns (uint256) {
        uint256 curTotalOwed = slasher.totalOwed();
        uint256 liquidBalance = vaultBalance();
        return curTotalOwed < liquidBalance ? curTotalOwed : liquidBalance;
    }

    function deposit(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _user(userSeed);
        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);

        deal(address(collateral), user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        try vault.deposit(user, amount) returns (uint256 depositedAmount, uint256) {
            totalDeposited += depositedAmount;
            _rememberDepositor(user);
        } catch {}
        vm.stopPrank();
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
        try vault.withdraw(user, amount) {} catch {}
    }

    function redeem(uint256 userSeed, uint256 shares, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _selectDepositor(userSeed);
        if (user == address(0)) {
            return;
        }

        uint256 activeShares = vault.activeSharesOf(user);
        if (activeShares == 0) {
            return;
        }

        shares = _bound(shares, 1, activeShares);

        vm.prank(user);
        try vault.redeem(user, shares) {} catch {}
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
        vm.prank(user);
        try vault.claim(user, index) returns (uint256 claimedAmount) {
            totalClaimed += claimedAmount;
            sawSuccessfulClaim = true;
            lastClaimedAmount = claimedAmount;
            lastClaimPostClaimableBacking = claimableBacking();
            lastClaimPostUnclaimableReserve = unclaimableReserve();
            lastClaimPostVaultBalance = vaultBalance();
        } catch {}
    }

    function donate(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        if (vault.totalStake() == 0) {
            return;
        }

        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);
        deal(address(collateral), address(rewards), amount);

        vm.startPrank(address(rewards));
        collateral.approve(address(vault), amount);
        try VaultV2(address(vault)).donate(amount) {
            totalDonated += amount;
        } catch {}
        vm.stopPrank();
    }

    function addAdapterYield(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);
        deal(address(collateral), address(adapter), adapterBalance() + amount);
        totalAdapterYield += amount;
    }


    function allocate(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        amount = _bound(amount, 1, MAX_ACTION_AMOUNT);

        vm.prank(address(adapter));
        try vault.allocateAdapter(address(adapter), amount) {} catch {}
    }

    function deallocate(uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint256 allocated = vault.adapterAllocated(address(adapter));
        if (allocated == 0) {
            return;
        }

        amount = _bound(amount, 1, allocated);

        vm.prank(address(adapter));
        try vault.deallocateAdapter(address(adapter), amount) {} catch {}
    }

    function setAdapterFailure(uint256 failSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        adapter.setShouldFail(failSeed % 2 == 0);
    }

    function slash(uint256 networkSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        bytes32 subnetwork = networkSeed % 2 == 0 ? primarySubnetwork : adapterSubnetwork;
        address middleware = networkSeed % 2 == 0 ? primaryMiddleware : adapterMiddleware;

        uint256 slashableStake = slasher.slashableStake(subnetwork, operator, 0, "");
        if (slashableStake == 0) {
            return;
        }

        amount = _bound(amount, 1, slashableStake);

        vm.prank(middleware);
        try slasher.slash(subnetwork, operator, amount, 0, "") {} catch {}
    }

    function syncOwedSlash(uint256 networkSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        bytes32 subnetwork = networkSeed % 2 == 0 ? primarySubnetwork : adapterSubnetwork;
        uint256 curOwed = slasher.owed(subnetwork, operator);
        if (curOwed == 0) {
            return;
        }

        uint256 preTotalOwed = slasher.totalOwed();

        try slasher.syncOwedSlash(subnetwork, operator) returns (uint256 slashedAmount) {
            sawSuccessfulSync = true;
            lastSyncedAmount = slashedAmount;
            lastSyncPreTotalOwed = preTotalOwed;
            lastSyncPostTotalOwed = slasher.totalOwed();
            lastSyncPostVaultBalance = vaultBalance();
        } catch {}
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
        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory),
                address(slasherFactory),
                address(feeRegistry),
                address(rewards),
                address(adapterRegistry)
            )
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(feeRegistry),
                    address(rewards),
                    address(adapterRegistry),
                    vaultV2Migrate
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
            burner: BURNER,
            epochDuration: 7 days,
            adapters: new address[](0),
            adaptersAllowDelay: 7 days + 1,
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
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(this),
            swapSlotsRoleHolder: address(this),
            removeSlotRoleHolder: address(this),
            setWithdrawalBufferSizeRoleHolder: address(this),
            withdrawalBufferSize: type(uint128).max
        });

        IUniversalSlasher.InitParams memory slasherParams =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 0, resolverSetDelay: 8 days});

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
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
        delegator = UniversalDelegator(delegator_);
        slasher = UniversalSlasher(slasher_);

        operator = makeAddr("invariant-operator");
        primaryNetwork = makeAddr("invariant-primary-network");
        primaryMiddleware = makeAddr("invariant-primary-middleware");
        adapterNetwork = makeAddr("invariant-adapter-network");
        adapterMiddleware = makeAddr("invariant-adapter-middleware");
        primarySubnetwork = primaryNetwork.subnetwork(0);
        adapterSubnetwork = adapterNetwork.subnetwork(0);

        vm.prank(operator);
        operatorRegistry.registerOperator();

        vm.startPrank(primaryNetwork);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(primaryMiddleware);
        vm.stopPrank();

        vm.startPrank(adapterNetwork);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(adapterMiddleware);
        vm.stopPrank();

        vm.prank(operator);
        operatorVaultOptInService.optIn(address(vault));
        vm.prank(operator);
        operatorNetworkOptInService.optIn(primaryNetwork);
        vm.prank(operator);
        operatorNetworkOptInService.optIn(adapterNetwork);

        address bootstrapDepositor = _user(0);
        uint256 bootstrapAmount = 200 ether;
        deal(address(collateral), bootstrapDepositor, bootstrapAmount);

        vm.startPrank(bootstrapDepositor);
        collateral.approve(address(vault), bootstrapAmount);
        (uint256 depositedAmount,) = vault.deposit(bootstrapDepositor, bootstrapAmount);
        vm.stopPrank();

        totalDeposited += depositedAmount;
        _rememberDepositor(bootstrapDepositor);

        uint128 slotSize = 100 ether;
        delegator.createSlot(primarySubnetwork, operator, slotSize);
        delegator.createSlot(adapterSubnetwork, operator, slotSize);

        adapter = new MockAdapter(address(vault), address(collateral));
        adapterRegistry.whitelistAdapter(address(adapter));
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);
        vm.warp(VaultV2(address(vault)).adapterAllowedAt(address(adapter)));
        VaultV2(address(vault)).setAdapterLimit(address(adapter), type(uint208).max);

        vm.prank(address(adapter));
        vault.allocateAdapter(address(adapter), slotSize);
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
        vm.warp(vm.getBlockTimestamp() + timeJump);
    }
}
