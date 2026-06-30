// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Vault} from "../../../src/contracts/vault/Vault.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";

import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

import {Token} from "../../mocks/Token.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultHandler is Test {
    using Subnetwork for address;

    uint256 public totalDeposited;
    uint256 public totalClaimed;
    uint256 public totalSlashed;
    uint256 public totalWithdrawn;

    Vault public vault;
    FullRestakeDelegator public delegator;
    Slasher public slasher;
    Token public collateral;

    VaultConfigurator internal configurator;
    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;

    address internal network;
    address internal operator;
    bytes32 internal subnetwork;

    address[] public depositors;
    mapping(address account => uint256 withdrawalCount) internal withdrawalsCreated;
    mapping(address account => bool exists) internal isDepositor;
    mapping(address account => uint256 totalClaimed) public totalClaimedOf;
    mapping(address account => uint256 totalDeposited) public totalDepositOf;

    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 2 minutes, 1 days);
        vm.warp(vm.getBlockTimestamp() + timeJump);
        _;
    }

    constructor() {
        _initialize();
    }

    function activeStake() external view returns (uint256) {
        return vault.activeStake();
    }

    function getDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function vaultBalance() external view returns (uint256) {
        return collateral.balanceOf(address(vault));
    }

    function _initialize() internal {
        network = makeAddr("network");
        operator = makeAddr("operator");

        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        slasherFactory = new SlasherFactory(address(this));
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        // Metadata services are required by delegators/slashers but not used in invariants.
        new MetadataService(address(operatorRegistry));
        new MetadataService(address(networkRegistry));

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
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
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        configurator = new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        collateral = new Token("InvariantToken");

        vm.prank(network);
        networkRegistry.registerNetwork();

        vm.prank(operator);
        operatorRegistry.registerOperator();

        vm.prank(network);
        networkMiddlewareService.setMiddleware(address(this));

        (address vaultAddr, address delegatorAddr, address slasherAddr) = configurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(0),
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xBEEF),
                        epochDuration: 6 hours,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: address(this),
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0)
                    })
                ),
                delegatorIndex: 1, // FullRestakeDelegator
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(this), hook: address(0), hookSetRoleHolder: address(this)
                        }),
                        networkLimitSetRoleHolders: _asSingletonArray(address(this)),
                        operatorNetworkLimitSetRoleHolders: _asSingletonArray(address(this))
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        vault = Vault(vaultAddr);
        delegator = FullRestakeDelegator(delegatorAddr);
        slasher = Slasher(slasherAddr);

        subnetwork = network.subnetwork(0);

        _bootstrapLimitsAndOptIns();
    }

    function deposit(address depositor, uint256 amount, uint256 timeJumpSeed) external adjustTimestamp(timeJumpSeed) {
        depositor = _validAccount(depositor);

        amount = _bound(amount, 1 ether, 1_000_000 ether);

        deal(address(collateral), depositor, amount);

        vm.startPrank(depositor);
        collateral.approve(address(vault), amount);
        try vault.deposit(depositor, amount) returns (uint256 depositedAmount, uint256) {
            totalDeposited += depositedAmount;
            totalDepositOf[depositor] += depositedAmount;
            _rememberDepositor(depositor);
        } catch {}
        vm.stopPrank();
    }

    function withdraw(uint256 claimerSeed, uint256 amount, uint256 timeJumpSeed)
        external
        adjustTimestamp(timeJumpSeed)
    {
        address account = _selectDepositor(claimerSeed);
        if (account == address(0)) {
            return;
        }

        uint256 balance = vault.activeBalanceOf(account);
        if (balance == 0) {
            return;
        }

        amount = _bound(amount, 1, balance);

        vm.startPrank(account);
        vault.withdraw(account, amount);
        withdrawalsCreated[account] += 1;
        totalWithdrawn += amount;
        vm.stopPrank();
    }

    function redeem(uint256 claimerSeed, uint256 amount, uint256 timeJumpSeed) external adjustTimestamp(timeJumpSeed) {
        address account = _selectDepositor(claimerSeed);
        if (account == address(0)) {
            return;
        }

        uint256 shares = vault.activeSharesOf(account);
        if (shares == 0) {
            return;
        }

        amount = _bound(amount, 1, shares);

        vm.startPrank(account);
        (uint256 withdrawnAssets, uint256 mintedShares) = vault.redeem(account, amount);
        totalWithdrawn += withdrawnAssets;
        withdrawalsCreated[account] += 1;
        vm.stopPrank();
    }

    function claim(uint256 claimerSeed, uint256 indexSeed, uint256 timeJumpSeed)
        external
        adjustTimestamp(timeJumpSeed)
    {
        address account = _selectDepositor(claimerSeed);
        if (account == address(0)) {
            return;
        }

        uint256 created = withdrawalsCreated[account];
        if (created == 0) {
            return;
        }

        uint256 index = _bound(indexSeed, 0, created - 1);

        vm.startPrank(account);
        try vault.claim(account, index) returns (uint256 amount) {
            totalClaimed += amount;
            totalClaimedOf[account] += amount;
        } catch {}
        vm.stopPrank();
    }

    function claimBatch(uint256 claimerSeed, uint256 indexSeed, uint256 lengthSeed, uint256 timeJumpSeed)
        external
        adjustTimestamp(timeJumpSeed)
    {
        address account = _selectDepositor(claimerSeed);
        if (account == address(0)) {
            return;
        }

        uint256 created = withdrawalsCreated[account];
        if (created == 0) {
            return;
        }

        uint256 length = _bound(lengthSeed, 1, Math.min(created, 4));
        uint256[] memory epochs = new uint256[](length);
        uint256 start = _bound(indexSeed, 0, created - 1);
        for (uint256 i; i < length; ++i) {
            epochs[i] = (start + i) % created;
        }

        vm.startPrank(account);
        try vault.claimBatch(account, epochs) returns (uint256 amount) {
            totalClaimed += amount;
            totalClaimedOf[account] += amount;
        } catch {}
        vm.stopPrank();
    }

    function slash(uint256 amount, uint256 captureTimestampSeed, uint256 timeJumpSeed)
        external
        adjustTimestamp(timeJumpSeed)
    {
        // Reduce slashing frequency.
        if (captureTimestampSeed % 5 != 0) {
            return;
        }

        uint256 stake = vault.totalStake();
        if (stake == 0) {
            return;
        }

        uint48 captureTimestamp = uint48(vm.getBlockTimestamp()) - 1;
        amount = _bound(amount, 1, stake / 2);

        uint256 slashedAmount = slasher.slash(subnetwork, operator, amount, captureTimestamp, "");
        totalSlashed += slashedAmount;
    }

    function setDepositControls(
        address accountSeed,
        uint256 limitSeed,
        uint256 whitelistSeed,
        uint256 limitModeSeed,
        uint256 timeJumpSeed
    ) external adjustTimestamp(timeJumpSeed) {
        address account = _validAccount(accountSeed);

        try vault.setDepositWhitelist(whitelistSeed % 2 == 1) {} catch {}
        try vault.setDepositorWhitelistStatus(account, whitelistSeed % 3 != 0) {} catch {}
        try vault.setIsDepositLimit(limitModeSeed % 2 == 1) {} catch {}
        try vault.setDepositLimit(_bound(limitSeed, 0, totalDeposited + 1_000_000 ether)) {} catch {}
    }

    function setNetworkLimits(uint256 maxSeed, uint256 networkSeed, uint256 operatorSeed, uint256 timeJumpSeed)
        external
        adjustTimestamp(timeJumpSeed)
    {
        uint256 maxLimit = _bound(maxSeed, 0, type(uint256).max / 4);
        uint256 networkLimit = _bound(networkSeed, 0, maxLimit);
        uint256 operatorLimit = _bound(operatorSeed, 0, networkLimit);

        vm.prank(network);
        try delegator.setMaxNetworkLimit(0, maxLimit) {} catch {}
        try delegator.setNetworkLimit(subnetwork, networkLimit) {} catch {}
        try delegator.setOperatorNetworkLimit(subnetwork, operator, operatorLimit) {} catch {}
    }

    function _bootstrapLimitsAndOptIns() internal {
        uint256 limit = type(uint256).max / 4;

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, limit);

        // Allow delegator to stake entire vault balance to the single subnetwork/operator.
        delegator.setNetworkLimit(subnetwork, limit);
        delegator.setOperatorNetworkLimit(subnetwork, operator, limit);

        vm.prank(operator);
        operatorVaultOptInService.optIn(address(vault));

        vm.prank(operator);
        operatorNetworkOptInService.optIn(network);
    }

    function _selectDepositor(uint256 claimerSeed) internal view returns (address) {
        if (depositors.length == 0) {
            return address(0);
        }

        uint256 index = _bound(claimerSeed, 0, depositors.length - 1);
        return depositors[index];
    }

    function _rememberDepositor(address account) internal {
        if (isDepositor[account]) {
            return;
        }
        isDepositor[account] = true;
        depositors.push(account);
    }

    function _validAccount(address account) internal view returns (address) {
        if (account == address(0) || account == address(vault)) {
            return address(1);
        }
        return account;
    }

    function _asSingletonArray(address value) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = value;
    }
}
