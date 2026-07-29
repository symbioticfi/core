# Emergency Account and Adapter Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add recoverable emergency-freeze implementations and deployment scripts for Account and Adapter proxies.

**Architecture:** Each pause implementation inherits `MigratableEntity` so an existing factory can whitelist it, migrate a proxy into it, and later migrate the proxy to a recovery version. The pause implementation declares no Account/Adapter business API and has an unconditional reverting fallback, so every current or future business selector reverts. Each deployment script only deploys one implementation bound to the supplied existing factory.

**Tech Stack:** Solidity 0.8.28, Foundry (`forge`), existing `MigratableEntity` and `MigratablesFactory`.

## Global Constraints

- Use Foundry only; do not introduce Hardhat.
- Match the repository's pinned Solidity 0.8.28 compiler and existing import style.
- Do not modify production `Account`, `Adapter`, factory, or governance contracts.
- Do not whitelist implementations or migrate proxies in deployment scripts.
- Give both dummy contracts NatSpec stating that they are used for an emergency-freeze contracts proposal.
- Touch only new pause-contract, pause-script, focused-test, and plan files; preserve all unrelated worktree changes.

---

### Task 1: Specify freeze, recovery, and deployment behavior

**Files:**
- Create: `test/deploy/adapters/pause/PauseDeployments.t.sol`

**Interfaces:**
- Consumes: `MigratablesFactory(address owner)`, `MigratableEntity(address factory)`, `IAccount`, `IAdapter`.
- Produces: Behavioral requirements for `DeployAccountPauseScript.run(address) returns (address)` and `DeployAdapterPauseScript.run(address) returns (address)`.

- [ ] **Step 1: Write the failing behavioral tests**

Create a test that dynamically deploys the not-yet-existing script artifacts. Dynamic artifact loading lets the test compile before production files exist and fail at runtime because the required artifact is absent.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MigratableEntity} from "../../../../src/contracts/common/MigratableEntity.sol";
import {MigratablesFactory} from "../../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAdapter} from "../../../../src/interfaces/adapters/IAdapter.sol";
import {ICoWSwapConverter} from "../../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IConverter} from "../../../../src/interfaces/adapters/common/IConverter.sol";
import {IMigratableEntity} from "../../../../src/interfaces/common/IMigratableEntity.sol";
import {IMulticallable} from "../../../../src/interfaces/common/IMulticallable.sol";
import {IStaticDelegateCallable} from "../../../../src/interfaces/common/IStaticDelegateCallable.sol";

interface IDeployPauseScript {
    function run(address factory) external returns (address implementation);
}

interface INonces {
    function nonces(address owner) external view returns (uint256 nonce);
}

contract RecoveryImplementation is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}

    function active() public pure returns (bool) {
        return true;
    }
}

contract PauseDeploymentsTest is Test {
    string internal constant ACCOUNT_SCRIPT =
        "script/deploy/adapters/pause/DeployAccountPause.s.sol:DeployAccountPauseScript";
    string internal constant ADAPTER_SCRIPT =
        "script/deploy/adapters/pause/DeployAdapterPause.s.sol:DeployAdapterPauseScript";

    bytes4 internal constant ACCOUNT_INVALID_FACTORY =
        bytes4(keccak256("DeployAccountPauseScript__InvalidFactory()"));
    bytes4 internal constant ADAPTER_INVALID_FACTORY =
        bytes4(keccak256("DeployAdapterPauseScript__InvalidFactory()"));

    function test_AccountPauseDeploymentUsesFactory() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));

        address implementation = _runScript(ACCOUNT_SCRIPT, address(factory));

        assertEq(IMigratableEntity(implementation).FACTORY(), address(factory));
    }

    function test_AdapterPauseDeploymentUsesFactory() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));

        address implementation = _runScript(ADAPTER_SCRIPT, address(factory));

        assertEq(IMigratableEntity(implementation).FACTORY(), address(factory));
    }

    function test_AccountPauseRejectsZeroFactory() public {
        address script = vm.deployCode(ACCOUNT_SCRIPT);

        vm.expectRevert(ACCOUNT_INVALID_FACTORY);
        IDeployPauseScript(script).run(address(0));
    }

    function test_AdapterPauseRejectsZeroFactory() public {
        address script = vm.deployCode(ADAPTER_SCRIPT);

        vm.expectRevert(ADAPTER_INVALID_FACTORY);
        IDeployPauseScript(script).run(address(0));
    }

    function test_AccountPauseFreezesBusinessCallsAndCanRecover() public {
        (MigratablesFactory factory, address entity) = _createEntity();
        address pauseImplementation = _runScript(ACCOUNT_SCRIPT, address(factory));
        factory.whitelist(pauseImplementation);

        factory.migrate(entity, 2, "");

        _assertAccountBusinessCallsRevert(entity);
        _assertArbitrarySelectorReverts(entity);
        _assertCanRecover(factory, entity);
    }

    function test_AdapterPauseFreezesBusinessCallsAndCanRecover() public {
        (MigratablesFactory factory, address entity) = _createEntity();
        address pauseImplementation = _runScript(ADAPTER_SCRIPT, address(factory));
        factory.whitelist(pauseImplementation);

        factory.migrate(entity, 2, "");

        _assertAdapterBusinessCallsRevert(entity);
        _assertArbitrarySelectorReverts(entity);
        _assertCanRecover(factory, entity);
    }

    function _createEntity() internal returns (MigratablesFactory factory, address entity) {
        factory = new MigratablesFactory(address(this));
        factory.whitelist(address(new RecoveryImplementation(address(factory))));
        entity = factory.create(1, address(this), "");
    }

    function _runScript(string memory artifact, address factory) internal returns (address implementation) {
        address script = vm.deployCode(artifact);
        implementation = IDeployPauseScript(script).run(factory);
    }

    function _assertArbitrarySelectorReverts(address entity) internal {
        _assertCallReverts(entity, abi.encodeWithSignature("futureBusinessFunction(uint256)", 1));
    }

    function _assertAccountBusinessCallsRevert(address entity) internal {
        _assertCallReverts(entity, abi.encodeCall(IAccount.TOKEN_TO_REDEEM, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.ORACLE, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.adapter, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.vault, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.totalAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAccount.sync, ()));

        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.COW_SWAP_SETTLEMENT, ()));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.COW_SWAP_VAULT_RELAYER, ()));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.executableAt, (0, bytes32(0))));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.converters, (0)));
        _assertCallReverts(entity, abi.encodeCall(IConverter.convert, (address(1), 1, address(2), "")));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.prepareConvert, (address(1), 1, address(2), "")));

        address[] memory converters = new address[](0);
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.setConverters, (converters)));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.invalidateConvert, ("")));
        _assertCallReverts(entity, abi.encodeCall(ICoWSwapConverter.invalidateConverts, (address(1))));
        _assertCallReverts(entity, abi.encodeCall(INonces.nonces, (address(this))));

        bytes[] memory calls = new bytes[](0);
        _assertCallReverts(entity, abi.encodeCall(IMulticallable.multicall, (calls)));
    }

    function _assertAdapterBusinessCallsRevert(address entity) internal {
        _assertCallReverts(entity, abi.encodeCall(IAdapter.vault, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.allocatable, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.totalAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.freeAssets, ()));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.allocate, (1)));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.deallocate, (1)));
        _assertCallReverts(entity, abi.encodeCall(IAdapter.requestDeallocate, (1)));

        bytes[] memory calls = new bytes[](0);
        _assertCallReverts(entity, abi.encodeCall(IMulticallable.multicall, (calls)));
        _assertCallReverts(entity, abi.encodeCall(IStaticDelegateCallable.staticDelegateCall, (address(1), "")));
    }

    function _assertCallReverts(address entity, bytes memory data) internal {
        (bool success, bytes memory returnData) = entity.call(data);
        assertFalse(success);
        assertEq(returnData.length, 0);
    }

    function _assertCanRecover(MigratablesFactory factory, address entity) internal {
        factory.whitelist(address(new RecoveryImplementation(address(factory))));
        factory.migrate(entity, 3, "");

        assertTrue(RecoveryImplementation(entity).active());
        assertEq(IMigratableEntity(entity).version(), 3);
    }
}
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
forge test --match-path test/deploy/adapters/pause/PauseDeployments.t.sol \
  --match-test test_AccountPauseDeploymentUsesFactory -vvv
```

Expected: FAIL at `vm.deployCode` because `DeployAccountPauseScript` does not exist.

### Task 2: Implement pause contracts and deploy scripts

**Files:**
- Create: `script/deploy/adapters/pause/contracts/AccountPause.sol`
- Create: `script/deploy/adapters/pause/contracts/AdapterPause.sol`
- Create: `script/deploy/adapters/pause/DeployAccountPause.s.sol`
- Create: `script/deploy/adapters/pause/DeployAdapterPause.s.sol`
- Test: `test/deploy/adapters/pause/PauseDeployments.t.sol`

**Interfaces:**
- Consumes: Target factory address supplied to each constructor and `run(address factory)`.
- Produces: `AccountPause(address factory)`, `AdapterPause(address factory)`, and two `run(address)` deployment entry points.

- [ ] **Step 1: Add the minimal Account pause implementation**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MigratableEntity} from "../../../../../src/contracts/common/MigratableEntity.sol";

/// @title AccountPause
/// @notice Dummy Account implementation used for an emergency-freeze contracts proposal.
/// @dev Account business calls unconditionally revert while migration functionality remains available for recovery.
contract AccountPause is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}

    fallback() external payable {
        revert();
    }
}
```

- [ ] **Step 2: Add the minimal Adapter pause implementation**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MigratableEntity} from "../../../../../src/contracts/common/MigratableEntity.sol";

/// @title AdapterPause
/// @notice Dummy Adapter implementation used for an emergency-freeze contracts proposal.
/// @dev Adapter business calls unconditionally revert while migration functionality remains available for recovery.
contract AdapterPause is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}

    fallback() external payable {
        revert();
    }
}
```

- [ ] **Step 3: Add the Account deployment script**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {AccountPause} from "./contracts/AccountPause.sol";

contract DeployAccountPauseScript is Script {
    error DeployAccountPauseScript__InvalidFactory();

    function run(address factory) public returns (address implementation) {
        if (factory == address(0)) {
            revert DeployAccountPauseScript__InvalidFactory();
        }

        vm.startBroadcast();
        implementation = address(new AccountPause(factory));
        vm.stopBroadcast();

        assert(AccountPause(payable(implementation)).FACTORY() == factory);
        console2.log("Deployed AccountPause:", implementation);
    }
}
```

- [ ] **Step 4: Add the Adapter deployment script**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {AdapterPause} from "./contracts/AdapterPause.sol";

contract DeployAdapterPauseScript is Script {
    error DeployAdapterPauseScript__InvalidFactory();

    function run(address factory) public returns (address implementation) {
        if (factory == address(0)) {
            revert DeployAdapterPauseScript__InvalidFactory();
        }

        vm.startBroadcast();
        implementation = address(new AdapterPause(factory));
        vm.stopBroadcast();

        assert(AdapterPause(payable(implementation)).FACTORY() == factory);
        console2.log("Deployed AdapterPause:", implementation);
    }
}
```

- [ ] **Step 5: Make the focused test compile the new script artifacts**

Add these imports to `PauseDeployments.t.sol`. They intentionally come after the RED run because the script files do not exist before implementation.

```solidity
import {DeployAccountPauseScript} from "../../../../script/deploy/adapters/pause/DeployAccountPause.s.sol";
import {DeployAdapterPauseScript} from "../../../../script/deploy/adapters/pause/DeployAdapterPause.s.sol";
```

- [ ] **Step 6: Run formatting**

Run:

```bash
forge fmt \
  script/deploy/adapters/pause/contracts/AccountPause.sol \
  script/deploy/adapters/pause/contracts/AdapterPause.sol \
  script/deploy/adapters/pause/DeployAccountPause.s.sol \
  script/deploy/adapters/pause/DeployAdapterPause.s.sol \
  test/deploy/adapters/pause/PauseDeployments.t.sol
```

- [ ] **Step 7: Run the focused test to verify GREEN**

Run:

```bash
forge test --match-path test/deploy/adapters/pause/PauseDeployments.t.sol -vvv
```

Expected: six tests pass with zero failures.

- [ ] **Step 8: Commit the isolated implementation**

```bash
git add \
  docs/superpowers/plans/2026-07-28-emergency-account-adapter-freeze.md \
  script/deploy/adapters/pause/contracts/AccountPause.sol \
  script/deploy/adapters/pause/contracts/AdapterPause.sol \
  script/deploy/adapters/pause/DeployAccountPause.s.sol \
  script/deploy/adapters/pause/DeployAdapterPause.s.sol \
  test/deploy/adapters/pause/PauseDeployments.t.sol
git commit -m "feat: add emergency account and adapter freeze implementations"
```

### Task 3: Verify the completed change

**Files:**
- Inspect: all files created by Tasks 1 and 2.

**Interfaces:**
- Consumes: Completed pause implementations, scripts, and focused tests.
- Produces: Fresh compile, test, formatting, and diff evidence.

- [ ] **Step 1: Run focused freeze tests**

```bash
forge test --match-path test/deploy/adapters/pause/PauseDeployments.t.sol -vvv
```

Expected: six tests pass, zero fail.

- [ ] **Step 2: Run migration regression tests**

```bash
forge test --match-path test/common/MigratablesFactory.t.sol
```

Expected: ten tests pass, zero fail.

- [ ] **Step 3: Run the full Foundry suite**

```bash
forge test
```

Expected: all non-fork tests pass. Any environment-dependent fork failures must be reported separately and must not be represented as passing.

- [ ] **Step 4: Check formatting and patch cleanliness**

```bash
forge fmt --check
git diff --check HEAD^ -- \
  docs/superpowers/plans/2026-07-28-emergency-account-adapter-freeze.md \
  script/deploy/adapters/pause \
  test/deploy/adapters/pause
git status --short
```

Expected: formatting and diff checks exit zero; status contains only the user's pre-existing unrelated modifications.
