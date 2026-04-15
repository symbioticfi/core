// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {StaticDelegateCallable} from "../../src/contracts/common/StaticDelegateCallable.sol";
import {
    BaseDelegatorHints,
    FullRestakeDelegatorHints,
    NetworkRestakeDelegatorHints,
    OperatorNetworkSpecificDelegatorHints,
    OperatorSpecificDelegatorHints
} from "../../src/contracts/hints/DelegatorHints.sol";
import {Hints} from "../../src/contracts/hints/Hints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";
import {BaseSlasherHints, SlasherHints, VetoSlasherHints} from "../../src/contracts/hints/SlasherHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {Checkpoints} from "../../src/contracts/libraries/Checkpoints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";

contract HintsHarness is Hints, StaticDelegateCallable {
    error CustomFailure();

    function guardedValueInternal() external view internalFunction returns (uint256) {
        return 123;
    }

    function revertEmptyInternal() external view internalFunction {
        assembly {
            revert(0, 0)
        }
    }

    function revertCustomInternal() external view internalFunction {
        revert CustomFailure();
    }

    function readGuardedValue(address target) external view returns (uint256) {
        return
            abi.decode(
                _selfStaticDelegateCall(target, abi.encodeCall(HintsHarness.guardedValueInternal, ())), (uint256)
            );
    }

    function bubbleEmpty(address target) external view returns (bytes memory) {
        return _selfStaticDelegateCall(target, abi.encodeCall(HintsHarness.revertEmptyInternal, ()));
    }

    function bubbleCustom(address target) external view returns (bytes memory) {
        return _selfStaticDelegateCall(target, abi.encodeCall(HintsHarness.revertCustomInternal, ()));
    }
}

contract OptInServiceHintsTarget is OptInServiceHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace208;

    function pushOptIn(address who, address where, uint48 timestamp, uint208 value) external {
        _isOptedIn[who][where].push(timestamp, value);
    }
}

contract VaultHintsTarget is VaultHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace256;

    function pushActiveStake(uint48 timestamp, uint256 value) external {
        _activeStake.push(timestamp, value);
    }

    function pushActiveShares(uint48 timestamp, uint256 value) external {
        _activeShares.push(timestamp, value);
    }

    function pushActiveSharesOf(address account, uint48 timestamp, uint256 value) external {
        _activeSharesOf[account].push(timestamp, value);
    }
}

contract NetworkRestakeDelegatorHintsTarget is NetworkRestakeDelegatorHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address baseDelegatorHints, address vaultHints)
        NetworkRestakeDelegatorHints(baseDelegatorHints, vaultHints)
    {}

    function TYPE() external pure returns (uint64) {
        return 0;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }

    function pushNetworkLimit(bytes32 subnetwork, uint48 timestamp, uint256 value) external {
        _networkLimit[subnetwork].push(timestamp, value);
    }

    function pushTotalOperatorNetworkShares(bytes32 subnetwork, uint48 timestamp, uint256 value) external {
        _totalOperatorNetworkShares[subnetwork].push(timestamp, value);
    }

    function pushOperatorNetworkShares(bytes32 subnetwork, address operator, uint48 timestamp, uint256 value) external {
        _operatorNetworkShares[subnetwork][operator].push(timestamp, value);
    }
}

contract FullRestakeDelegatorHintsTarget is FullRestakeDelegatorHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address baseDelegatorHints, address vaultHints)
        FullRestakeDelegatorHints(baseDelegatorHints, vaultHints)
    {}

    function TYPE() external pure returns (uint64) {
        return 1;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }

    function pushNetworkLimit(bytes32 subnetwork, uint48 timestamp, uint256 value) external {
        _networkLimit[subnetwork].push(timestamp, value);
    }

    function pushOperatorNetworkLimit(bytes32 subnetwork, address operator, uint48 timestamp, uint256 value) external {
        _operatorNetworkLimit[subnetwork][operator].push(timestamp, value);
    }
}

contract OperatorSpecificDelegatorHintsTarget is OperatorSpecificDelegatorHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address baseDelegatorHints, address vaultHints)
        OperatorSpecificDelegatorHints(baseDelegatorHints, vaultHints)
    {}

    function TYPE() external pure returns (uint64) {
        return 2;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }

    function pushNetworkLimit(bytes32 subnetwork, uint48 timestamp, uint256 value) external {
        _networkLimit[subnetwork].push(timestamp, value);
    }
}

contract OperatorNetworkSpecificDelegatorHintsTarget is OperatorNetworkSpecificDelegatorHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace256;

    constructor(address baseDelegatorHints, address vaultHints)
        OperatorNetworkSpecificDelegatorHints(baseDelegatorHints, vaultHints)
    {}

    function TYPE() external pure returns (uint64) {
        return 3;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }

    function pushMaxNetworkLimit(bytes32 subnetwork, uint48 timestamp, uint256 value) external {
        _maxNetworkLimit[subnetwork].push(timestamp, value);
    }
}

contract VaultStorageTarget {
    address public delegator;

    constructor(address delegator_) {
        delegator = delegator_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }
}

contract VetoSlasherHintsTarget is VetoSlasherHints, StaticDelegateCallable {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;

    constructor(address baseSlasherHints) VetoSlasherHints(baseSlasherHints) {}

    function setVault(address vault_) external {
        vault = vault_;
    }

    function pushCumulativeSlash(bytes32 subnetwork, address operator, uint48 timestamp, uint256 value) external {
        _cumulativeSlash[subnetwork][operator].push(timestamp, value);
    }

    function pushResolver(bytes32 subnetwork, uint48 timestamp, address resolver) external {
        _resolver[subnetwork].push(timestamp, uint208(uint160(resolver)));
    }

    function pushSlashRequest(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        uint48 vetoDeadline,
        bool completed
    ) external {
        slashRequests.push(
            IVetoSlasher.SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                captureTimestamp: captureTimestamp,
                vetoDeadline: vetoDeadline,
                completed: completed
            })
        );
    }
}

contract HintsTest is Test {
    address internal constant ACCOUNT = address(0xA11CE);
    address internal constant OPERATOR = address(0xB0B);
    address internal constant NETWORK = address(0xCAFE);
    uint96 internal constant IDENTIFIER = 7;
    uint48 internal constant CHECKPOINT_TIMESTAMP = 10;
    uint48 internal constant QUERY_TIMESTAMP = 20;

    bytes32 internal _subnetwork;

    HintsHarness internal _hintsReader;
    HintsHarness internal _hintsTarget;
    OptInServiceHints internal _optInReader;
    OptInServiceHintsTarget internal _operatorVaultOptInTarget;
    OptInServiceHintsTarget internal _operatorNetworkOptInTarget;
    VaultHints internal _vaultReader;
    VaultHintsTarget internal _vaultTarget;
    BaseDelegatorHints internal _baseDelegatorReader;
    NetworkRestakeDelegatorHintsTarget internal _networkDelegatorTarget;
    FullRestakeDelegatorHintsTarget internal _fullDelegatorTarget;
    OperatorSpecificDelegatorHintsTarget internal _operatorSpecificDelegatorTarget;
    OperatorNetworkSpecificDelegatorHintsTarget internal _operatorNetworkSpecificDelegatorTarget;
    BaseSlasherHints internal _baseSlasherReader;
    SlasherHints internal _slasherReader;
    VetoSlasherHints internal _vetoReader;
    VetoSlasherHintsTarget internal _vetoSlasherTarget;
    VaultStorageTarget internal _vaultStorageTarget;

    function setUp() public {
        _subnetwork = Subnetwork.subnetwork(NETWORK, IDENTIFIER);

        _hintsReader = new HintsHarness();
        _hintsTarget = new HintsHarness();

        _optInReader = new OptInServiceHints();
        _operatorVaultOptInTarget = new OptInServiceHintsTarget();
        _operatorNetworkOptInTarget = new OptInServiceHintsTarget();

        _vaultReader = new VaultHints();
        _vaultTarget = new VaultHintsTarget();
        _vaultTarget.pushActiveStake(CHECKPOINT_TIMESTAMP, 1000);
        _vaultTarget.pushActiveShares(CHECKPOINT_TIMESTAMP, 100);
        _vaultTarget.pushActiveSharesOf(ACCOUNT, CHECKPOINT_TIMESTAMP, 50);

        _operatorVaultOptInTarget.pushOptIn(OPERATOR, address(_vaultTarget), CHECKPOINT_TIMESTAMP, 1);
        _operatorNetworkOptInTarget.pushOptIn(OPERATOR, NETWORK, CHECKPOINT_TIMESTAMP, 1);

        _baseDelegatorReader = new BaseDelegatorHints(
            address(_optInReader),
            address(_vaultReader),
            address(_operatorVaultOptInTarget),
            address(_operatorNetworkOptInTarget)
        );

        _networkDelegatorTarget =
            new NetworkRestakeDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        _networkDelegatorTarget.setVault(address(_vaultTarget));
        _networkDelegatorTarget.pushNetworkLimit(_subnetwork, CHECKPOINT_TIMESTAMP, 700);
        _networkDelegatorTarget.pushTotalOperatorNetworkShares(_subnetwork, CHECKPOINT_TIMESTAMP, 40);
        _networkDelegatorTarget.pushOperatorNetworkShares(_subnetwork, OPERATOR, CHECKPOINT_TIMESTAMP, 30);

        _fullDelegatorTarget = new FullRestakeDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        _fullDelegatorTarget.setVault(address(_vaultTarget));
        _fullDelegatorTarget.pushNetworkLimit(_subnetwork, CHECKPOINT_TIMESTAMP, 600);
        _fullDelegatorTarget.pushOperatorNetworkLimit(_subnetwork, OPERATOR, CHECKPOINT_TIMESTAMP, 250);

        _operatorSpecificDelegatorTarget =
            new OperatorSpecificDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        _operatorSpecificDelegatorTarget.setVault(address(_vaultTarget));
        _operatorSpecificDelegatorTarget.pushNetworkLimit(_subnetwork, CHECKPOINT_TIMESTAMP, 500);

        _operatorNetworkSpecificDelegatorTarget =
            new OperatorNetworkSpecificDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        _operatorNetworkSpecificDelegatorTarget.setVault(address(_vaultTarget));
        _operatorNetworkSpecificDelegatorTarget.pushMaxNetworkLimit(_subnetwork, CHECKPOINT_TIMESTAMP, 450);

        _baseSlasherReader = new BaseSlasherHints(address(_baseDelegatorReader));
        _slasherReader = SlasherHints(_baseSlasherReader.SLASHER_HINTS());
        _vetoReader = VetoSlasherHints(_baseSlasherReader.VETO_SLASHER_HINTS());

        _vetoSlasherTarget = new VetoSlasherHintsTarget(address(_baseSlasherReader));
        _vetoSlasherTarget.pushCumulativeSlash(_subnetwork, OPERATOR, CHECKPOINT_TIMESTAMP, 77);
        _vetoSlasherTarget.pushResolver(_subnetwork, CHECKPOINT_TIMESTAMP, address(0x1111));
        _vetoSlasherTarget.pushResolver(_subnetwork, 90, address(0x2222));
        _vetoSlasherTarget.pushSlashRequest(_subnetwork, OPERATOR, 33, QUERY_TIMESTAMP, 120, false);

        _vaultStorageTarget = new VaultStorageTarget(address(_networkDelegatorTarget));
        _vetoSlasherTarget.setVault(address(_vaultStorageTarget));
    }

    function test_hints_selfStaticDelegateCallCoversSuccessAndReverts() public {
        vm.expectRevert(Hints.ExternalCall.selector);
        _hintsTarget.guardedValueInternal();

        vm.expectRevert(Hints.ExternalCall.selector);
        _operatorVaultOptInTarget.optInHintInternal(OPERATOR, address(_vaultTarget), QUERY_TIMESTAMP);

        assertEq(_hintsReader.readGuardedValue(address(_hintsTarget)), 123);

        vm.expectRevert();
        _hintsReader.bubbleEmpty(address(_hintsTarget));

        vm.expectRevert(HintsHarness.CustomFailure.selector);
        _hintsReader.bubbleCustom(address(_hintsTarget));
    }

    function test_subnetworkHelpersRoundTrip() public view {
        assertEq(Subnetwork.network(_subnetwork), NETWORK);
        assertEq(Subnetwork.identifier(_subnetwork), IDENTIFIER);
    }

    function test_optInServiceHintReturnsEncodedCheckpoint() public view {
        assertEq(
            _optInReader.optInHint(
                address(_operatorVaultOptInTarget), OPERATOR, address(_vaultTarget), QUERY_TIMESTAMP
            ),
            abi.encode(uint32(0))
        );
        assertEq(
            _optInReader.optInHint(address(_operatorNetworkOptInTarget), OPERATOR, NETWORK, QUERY_TIMESTAMP),
            abi.encode(uint32(0))
        );
    }

    function test_vaultHintsReturnEncodedCheckpoints() public view {
        assertEq(_vaultReader.activeStakeHint(address(_vaultTarget), QUERY_TIMESTAMP), abi.encode(uint32(0)));
        assertEq(_vaultReader.activeSharesHint(address(_vaultTarget), QUERY_TIMESTAMP), abi.encode(uint32(0)));
        assertEq(
            _vaultReader.activeSharesOfHint(address(_vaultTarget), ACCOUNT, QUERY_TIMESTAMP), abi.encode(uint32(0))
        );

        IVault.ActiveBalanceOfHints memory activeBalanceHints = abi.decode(
            _vaultReader.activeBalanceOfHints(address(_vaultTarget), ACCOUNT, QUERY_TIMESTAMP),
            (IVault.ActiveBalanceOfHints)
        );
        assertEq(activeBalanceHints.activeSharesOfHint, abi.encode(uint32(0)));
        assertEq(activeBalanceHints.activeStakeHint, abi.encode(uint32(0)));
        assertEq(activeBalanceHints.activeSharesHint, abi.encode(uint32(0)));
    }

    function test_baseDelegatorDispatchesNetworkRestakeHints() public view {
        INetworkRestakeDelegator.StakeHints memory hints = abi.decode(
            _baseDelegatorReader.stakeHints(address(_networkDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            (INetworkRestakeDelegator.StakeHints)
        );
        IBaseDelegator.StakeBaseHints memory baseHints = abi.decode(hints.baseHints, (IBaseDelegator.StakeBaseHints));

        assertEq(baseHints.operatorVaultOptInHint, abi.encode(uint32(0)));
        assertEq(baseHints.operatorNetworkOptInHint, abi.encode(uint32(0)));
        assertEq(hints.activeStakeHint, abi.encode(uint32(0)));
        assertEq(hints.networkLimitHint, abi.encode(uint32(0)));
        assertEq(hints.operatorNetworkSharesHint, abi.encode(uint32(0)));
        assertEq(hints.totalOperatorNetworkSharesHint, abi.encode(uint32(0)));
    }

    function test_baseDelegatorDispatchesFullRestakeHints() public view {
        IFullRestakeDelegator.StakeHints memory hints = abi.decode(
            _baseDelegatorReader.stakeHints(address(_fullDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            (IFullRestakeDelegator.StakeHints)
        );
        IBaseDelegator.StakeBaseHints memory baseHints = abi.decode(hints.baseHints, (IBaseDelegator.StakeBaseHints));

        assertEq(baseHints.operatorVaultOptInHint, abi.encode(uint32(0)));
        assertEq(baseHints.operatorNetworkOptInHint, abi.encode(uint32(0)));
        assertEq(hints.activeStakeHint, abi.encode(uint32(0)));
        assertEq(hints.networkLimitHint, abi.encode(uint32(0)));
        assertEq(hints.operatorNetworkLimitHint, abi.encode(uint32(0)));
    }

    function test_baseDelegatorDispatchesOperatorSpecificHints() public view {
        IOperatorSpecificDelegator.StakeHints memory hints = abi.decode(
            _baseDelegatorReader.stakeHints(
                address(_operatorSpecificDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP
            ),
            (IOperatorSpecificDelegator.StakeHints)
        );
        IBaseDelegator.StakeBaseHints memory baseHints = abi.decode(hints.baseHints, (IBaseDelegator.StakeBaseHints));

        assertEq(baseHints.operatorVaultOptInHint, abi.encode(uint32(0)));
        assertEq(baseHints.operatorNetworkOptInHint, abi.encode(uint32(0)));
        assertEq(hints.activeStakeHint, abi.encode(uint32(0)));
        assertEq(hints.networkLimitHint, abi.encode(uint32(0)));
    }

    function test_baseDelegatorDispatchesOperatorNetworkSpecificHints() public view {
        IOperatorNetworkSpecificDelegator.StakeHints memory hints = abi.decode(
            _baseDelegatorReader.stakeHints(
                address(_operatorNetworkSpecificDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP
            ),
            (IOperatorNetworkSpecificDelegator.StakeHints)
        );
        IBaseDelegator.StakeBaseHints memory baseHints = abi.decode(hints.baseHints, (IBaseDelegator.StakeBaseHints));

        assertEq(baseHints.operatorVaultOptInHint, abi.encode(uint32(0)));
        assertEq(baseHints.operatorNetworkOptInHint, abi.encode(uint32(0)));
        assertEq(hints.activeStakeHint, abi.encode(uint32(0)));
        assertEq(hints.maxNetworkLimitHint, abi.encode(uint32(0)));
    }

    function test_directDelegatorHintReadersAndLateBranchEvaluation() public {
        NetworkRestakeDelegatorHints networkReader =
            NetworkRestakeDelegatorHints(_baseDelegatorReader.NETWORK_RESTAKE_DELEGATOR_HINTS());
        FullRestakeDelegatorHints fullReader =
            FullRestakeDelegatorHints(_baseDelegatorReader.FULL_RESTAKE_DELEGATOR_HINTS());
        OperatorSpecificDelegatorHints operatorSpecificReader =
            OperatorSpecificDelegatorHints(_baseDelegatorReader.OPERATOR_SPECIFIC_DELEGATOR_HINTS());
        OperatorNetworkSpecificDelegatorHints operatorNetworkSpecificReader =
            OperatorNetworkSpecificDelegatorHints(_baseDelegatorReader.OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS());

        assertEq(
            networkReader.networkLimitHint(address(_networkDelegatorTarget), _subnetwork, QUERY_TIMESTAMP),
            abi.encode(uint32(0))
        );
        assertEq(
            networkReader.operatorNetworkSharesHint(
                address(_networkDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP
            ),
            abi.encode(uint32(0))
        );
        assertEq(
            networkReader.totalOperatorNetworkSharesHint(
                address(_networkDelegatorTarget), _subnetwork, QUERY_TIMESTAMP
            ),
            abi.encode(uint32(0))
        );
        assertEq(
            fullReader.networkLimitHint(address(_fullDelegatorTarget), _subnetwork, QUERY_TIMESTAMP),
            abi.encode(uint32(0))
        );
        assertEq(
            fullReader.operatorNetworkLimitHint(address(_fullDelegatorTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            abi.encode(uint32(0))
        );
        assertEq(
            operatorSpecificReader.networkLimitHint(
                address(_operatorSpecificDelegatorTarget), _subnetwork, QUERY_TIMESTAMP
            ),
            abi.encode(uint32(0))
        );
        assertEq(
            operatorNetworkSpecificReader.maxNetworkLimitHint(
                address(_operatorNetworkSpecificDelegatorTarget), _subnetwork, QUERY_TIMESTAMP
            ),
            abi.encode(uint32(0))
        );

        bytes32 sparseSubnetwork = Subnetwork.subnetwork(address(0xDEAD), IDENTIFIER);
        VaultHintsTarget sparseVault = new VaultHintsTarget();

        NetworkRestakeDelegatorHintsTarget sparseNetworkTarget =
            new NetworkRestakeDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        sparseNetworkTarget.setVault(address(sparseVault));
        sparseNetworkTarget.pushOperatorNetworkShares(sparseSubnetwork, OPERATOR, CHECKPOINT_TIMESTAMP, 9);
        sparseNetworkTarget.pushTotalOperatorNetworkShares(sparseSubnetwork, CHECKPOINT_TIMESTAMP, 11);

        INetworkRestakeDelegator.StakeHints memory sparseNetworkHints = abi.decode(
            networkReader.stakeHints(address(sparseNetworkTarget), sparseSubnetwork, OPERATOR, QUERY_TIMESTAMP),
            (INetworkRestakeDelegator.StakeHints)
        );
        assertEq(sparseNetworkHints.baseHints, "");
        assertEq(sparseNetworkHints.activeStakeHint, "");
        assertEq(sparseNetworkHints.networkLimitHint, "");
        assertEq(sparseNetworkHints.operatorNetworkSharesHint, abi.encode(uint32(0)));
        assertEq(sparseNetworkHints.totalOperatorNetworkSharesHint, abi.encode(uint32(0)));

        FullRestakeDelegatorHintsTarget sparseFullTarget =
            new FullRestakeDelegatorHintsTarget(address(_baseDelegatorReader), address(_vaultReader));
        sparseFullTarget.setVault(address(sparseVault));
        sparseFullTarget.pushOperatorNetworkLimit(sparseSubnetwork, OPERATOR, CHECKPOINT_TIMESTAMP, 13);

        IFullRestakeDelegator.StakeHints memory sparseFullHints = abi.decode(
            fullReader.stakeHints(address(sparseFullTarget), sparseSubnetwork, OPERATOR, QUERY_TIMESTAMP),
            (IFullRestakeDelegator.StakeHints)
        );
        assertEq(sparseFullHints.baseHints, "");
        assertEq(sparseFullHints.activeStakeHint, "");
        assertEq(sparseFullHints.networkLimitHint, "");
        assertEq(sparseFullHints.operatorNetworkLimitHint, abi.encode(uint32(0)));
    }

    function test_slasherHintsWrapSlashableStakeHints() public view {
        IBaseSlasher.SlashableStakeHints memory slashableStakeHints = abi.decode(
            _baseSlasherReader.slashableStakeHints(address(_vetoSlasherTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            (IBaseSlasher.SlashableStakeHints)
        );
        ISlasher.SlashHints memory slashHints = abi.decode(
            _slasherReader.slashHints(address(_vetoSlasherTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            (ISlasher.SlashHints)
        );

        assertEq(slashableStakeHints.cumulativeSlashFromHint, abi.encode(uint32(0)));
        assertGt(slashableStakeHints.stakeHints.length, 0);
        assertEq(
            slashHints.slashableStakeHints,
            _baseSlasherReader.slashableStakeHints(address(_vetoSlasherTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP)
        );
    }

    function test_directSlasherHintReadersReturnEncodedCheckpoints() public view {
        assertEq(
            _baseSlasherReader.cumulativeSlashHint(address(_vetoSlasherTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            abi.encode(uint32(0))
        );
        assertEq(
            _vetoReader.resolverHint(address(_vetoSlasherTarget), _subnetwork, QUERY_TIMESTAMP), abi.encode(uint32(0))
        );
    }

    function test_vetoSlasherHintBuildersReturnEncodedCheckpoints() public {
        vm.warp(100);

        IVetoSlasher.RequestSlashHints memory requestSlashHints = abi.decode(
            _vetoReader.requestSlashHints(address(_vetoSlasherTarget), _subnetwork, OPERATOR, QUERY_TIMESTAMP),
            (IVetoSlasher.RequestSlashHints)
        );
        IVetoSlasher.ExecuteSlashHints memory executeSlashHints =
            abi.decode(_vetoReader.executeSlashHints(address(_vetoSlasherTarget), 0), (IVetoSlasher.ExecuteSlashHints));
        IVetoSlasher.VetoSlashHints memory vetoSlashHints =
            abi.decode(_vetoReader.vetoSlashHints(address(_vetoSlasherTarget), 0), (IVetoSlasher.VetoSlashHints));
        IVetoSlasher.SetResolverHints memory setResolverHints = abi.decode(
            _vetoReader.setResolverHints(address(_vetoSlasherTarget), _subnetwork, QUERY_TIMESTAMP),
            (IVetoSlasher.SetResolverHints)
        );

        assertGt(requestSlashHints.slashableStakeHints.length, 0);
        assertEq(executeSlashHints.captureResolverHint, abi.encode(uint32(0)));
        assertEq(executeSlashHints.currentResolverHint, abi.encode(uint32(1)));
        assertGt(executeSlashHints.slashableStakeHints.length, 0);
        assertEq(vetoSlashHints.captureResolverHint, abi.encode(uint32(0)));
        assertEq(vetoSlashHints.currentResolverHint, abi.encode(uint32(1)));
        assertEq(setResolverHints.resolverHint, abi.encode(uint32(0)));
    }
}
