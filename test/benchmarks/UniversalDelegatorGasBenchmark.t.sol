// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../src/contracts/vault/VaultV2Migrate.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";

abstract contract UniversalDelegatorGasBenchmarkBase is Test {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 7 days;
    uint256 internal constant SLOT_COUNT = 100;
    uint256 internal constant SLOT_SIZE = 100 ether;
    uint256 internal constant SLASH_AMOUNT = 1 ether;

    address internal owner = address(this);
    address internal network = address(0xBEEF0001);
    address internal middleware = address(0xBEEF0002);
    address internal burner = address(0xBEEF0003);

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    VaultConfigurator internal vaultConfigurator;
    MockRewards internal rewards;
    Token internal collateral;

    VaultV2 internal vault;
    UniversalDelegator internal delegator;
    UniversalSlasher internal slasher;

    bytes32 internal targetSubnetwork;
    address internal targetOperator;

    function setUp() public virtual {
        vm.warp(1000);

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        rewards = new MockRewards();
        collateral = new Token("Benchmark Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        _whitelistVaults();
        _whitelistDelegators();
        _whitelistSlashers();
        _createVault();
        _registerNetwork();
        _depositFullCapacity();
        _createSlots();

        vm.warp(block.timestamp + 1);
    }

    function _whitelistVaults() internal {
        vaultFactory.whitelist(
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(0),
                    address(rewards),
                    address(0),
                    vaultV2Migrate
                )
            )
        );
    }

    function _whitelistDelegators() internal {
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
    }

    function _whitelistSlashers() internal {
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
    }

    function _createVault() internal {
        IVaultV2.InitParams memory vaultParams = IVaultV2.InitParams({
            name: "Universal Delegator Benchmark",
            symbol: "UDB",
            collateral: address(collateral),
            burner: burner,
            epochDuration: EPOCH_DURATION,
            adapters: new address[](0),
            adaptersAllowDelay: EPOCH_DURATION + 1,
            depositWhitelist: false,
            depositorToWhitelist: owner,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: owner,
            depositWhitelistSetRoleHolder: owner,
            depositorWhitelistRoleHolder: owner,
            isDepositLimitSetRoleHolder: owner,
            depositLimitSetRoleHolder: owner,
            setAdapterLimitRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            allocateAdapterRoleHolder: owner,
            deallocateAdapterRoleHolder: owner
        });

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: owner,
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            removeSlotRoleHolder: owner,
            setWithdrawalBufferSizeRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });

        IUniversalSlasher.InitParams memory slasherParams =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 0, resolverSetDelay: EPOCH_DURATION + 1});

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(vaultParams),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(delegatorParams),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: abi.encode(slasherParams)
            })
        );

        vault = VaultV2(vault_);
        delegator = UniversalDelegator(delegator_);
        slasher = UniversalSlasher(slasher_);
    }

    function _registerNetwork() internal {
        targetSubnetwork = network.subnetwork(0);

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _depositFullCapacity() internal {
        uint256 amount = SLOT_COUNT * SLOT_SIZE;
        collateral.approve(address(vault), amount);
        vault.deposit(owner, amount);
    }

    function _createSlots() internal {
        for (uint256 i = 1; i <= SLOT_COUNT; ++i) {
            address operator = address(uint160(0xCAFE0000 + i));

            vm.prank(operator);
            operatorRegistry.registerOperator();

            vm.prank(operator);
            operatorVaultOptInService.optIn(address(vault));

            vm.prank(operator);
            operatorNetworkOptInService.optIn(network);

            uint32 slot = delegator.createSlot(targetSubnetwork, operator, uint128(SLOT_SIZE));
            assertEq(slot, uint32(i));

            if (i == SLOT_COUNT) {
                targetOperator = operator;
            }
        }
    }

    function _requestSlashUnmeasured() internal returns (uint256 slashIndex) {
        vm.prank(middleware);
        slashIndex = slasher.requestSlash(targetSubnetwork, targetOperator, SLASH_AMOUNT, 0, "");
    }

    function _executeSlashUnmeasured(uint256 slashIndex) internal {
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), SLASH_AMOUNT);
    }

    function _slashUnmeasured() internal {
        vm.prank(middleware);
        assertEq(slasher.slash(targetSubnetwork, targetOperator, SLASH_AMOUNT, 0, ""), SLASH_AMOUNT);
    }

    function _measureStake() internal returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        uint256 amount = delegator.stake(targetSubnetwork, targetOperator);
        gasUsed = gasBefore - gasleft();

        assertGt(amount, 0);
    }

    function _measureStakeForZero() internal returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        uint256 amount = delegator.stakeFor(targetSubnetwork, targetOperator, 0);
        gasUsed = gasBefore - gasleft();

        assertGt(amount, 0);
    }

    function _measureRequestSlash() internal returns (uint256 gasUsed) {
        vm.prank(middleware);
        uint256 gasBefore = gasleft();
        slasher.requestSlash(targetSubnetwork, targetOperator, SLASH_AMOUNT, 0, "");
        gasUsed = gasBefore - gasleft();
    }

    function _measureExecuteSlash(uint256 slashIndex) internal returns (uint256 gasUsed) {
        vm.prank(middleware);
        uint256 gasBefore = gasleft();
        uint256 slashedAmount = slasher.executeSlash(slashIndex, "");
        gasUsed = gasBefore - gasleft();

        assertEq(slashedAmount, SLASH_AMOUNT);
    }

    function _measureSlash() internal returns (uint256 gasUsed) {
        vm.prank(middleware);
        uint256 gasBefore = gasleft();
        uint256 slashedAmount = slasher.slash(targetSubnetwork, targetOperator, SLASH_AMOUNT, 0, "");
        gasUsed = gasBefore - gasleft();

        assertEq(slashedAmount, SLASH_AMOUNT);
    }

    function _logGas(string memory label, uint256 gasUsed) internal pure {
        console2.log(label, gasUsed);
    }
}

contract UniversalDelegatorGasBeforeBenchmarkTest is UniversalDelegatorGasBenchmarkBase {
    function test_benchmarkStake_beforeSlashing_100thSlot() public {
        _logGas("stake() before slashing", _measureStake());
    }

    function test_benchmarkStakeForZero_beforeSlashing_100thSlot() public {
        _logGas("stakeFor(0) before slashing", _measureStakeForZero());
    }

    function test_benchmarkRequestSlash_beforeSlashing_100thSlot() public {
        _logGas("requestSlash() before slashing", _measureRequestSlash());
    }

    function test_benchmarkSlash_beforeSlashing_100thSlot() public {
        _logGas("slash() before slashing", _measureSlash());
    }
}

contract UniversalDelegatorGasExecuteBeforeBenchmarkTest is UniversalDelegatorGasBenchmarkBase {
    uint256 internal slashIndex;

    function setUp() public override {
        super.setUp();
        slashIndex = _requestSlashUnmeasured();
    }

    function test_benchmarkExecuteSlash_beforeSlashing_100thSlot() public {
        _logGas("executeSlash() before slashing", _measureExecuteSlash(slashIndex));
    }
}

contract UniversalDelegatorGasAfterBenchmarkTest is UniversalDelegatorGasBenchmarkBase {
    function setUp() public override {
        super.setUp();
        _slashUnmeasured();

        assertEq(delegator.stake(targetSubnetwork, targetOperator), SLOT_SIZE - SLASH_AMOUNT);
        assertEq(delegator.stakeFor(targetSubnetwork, targetOperator, 0), SLOT_SIZE - SLASH_AMOUNT);
    }

    function test_benchmarkStake_afterSlashing_100thSlot() public {
        _logGas("stake() after slashing", _measureStake());
    }

    function test_benchmarkStakeForZero_afterSlashing_100thSlot() public {
        _logGas("stakeFor(0) after slashing", _measureStakeForZero());
    }

    function test_benchmarkRequestSlash_afterSlashing_100thSlot() public {
        _logGas("requestSlash() after slashing", _measureRequestSlash());
    }

    function test_benchmarkSlash_afterSlashing_100thSlot() public {
        _logGas("slash() after slashing", _measureSlash());
    }
}

contract UniversalDelegatorGasExecuteAfterBenchmarkTest is UniversalDelegatorGasBenchmarkBase {
    uint256 internal slashIndex;

    function setUp() public override {
        super.setUp();
        _slashUnmeasured();
        slashIndex = _requestSlashUnmeasured();

        assertEq(delegator.stake(targetSubnetwork, targetOperator), SLOT_SIZE - SLASH_AMOUNT);
        assertEq(delegator.stakeFor(targetSubnetwork, targetOperator, 0), SLOT_SIZE - SLASH_AMOUNT);
    }

    function test_benchmarkExecuteSlash_afterSlashing_100thSlot() public {
        _logGas("executeSlash() after slashing", _measureExecuteSlash(slashIndex));
    }
}
