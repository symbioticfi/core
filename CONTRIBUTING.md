# Contributing

- [Install](#install)
- [Pre-commit Hooks](#pre-commit-hooks)
- [Requirements for merge](#requirements-for-merge)
- [Branching](#branching)
  - [Main](#main)
  - [Audit](#audit)
- [Code Practices](#code-practices)
  - [Code Style](#code-style)
  - [Solidity Versioning](#solidity-versioning)
  - [Interfaces](#interfaces)
  - [NatSpec \& Comments](#natspec--comments)
- [Testing](#testing)
  - [Best Practices](#best-practices)
  - [IR Compilation](#ir-compilation)
  - [Gas Metering](#gas-metering)
- [Deployment](#deployment)
  - [Bytecode Hash](#bytecode-hash)
- [Dependency Management](#dependency-management)
- [Releases](#releases)

## Install

Follow these steps to set up your local environment for development:

- [Install foundry](https://book.getfoundry.sh/getting-started/installation)
- Install dependencies: `forge install`
- [Install pre-commit](https://pre-commit.com/#installation)
- Install pre commit hooks: `pre-commit install`

## Pre-commit Hooks

Follow the [installation steps](#install) to enable pre-commit hooks. To ensure consistency in our formatting `pre-commit` is used to check whether code was formatted properly and the documentation is up to date. Whenever a commit does not meet the checks implemented by pre-commit, the commit will fail and the pre-commit checks will modify the files to make the commits pass. Include these changes in your commit for the next commit attempt to succeed. On pull requests the CI checks whether all pre-commit hooks were run correctly.
This repo includes the following pre-commit hooks that are defined in the `.pre-commit-config.yaml`:

- `mixed-line-ending`: This hook ensures that all files have the same line endings (LF).
- `trailing-whitespace`: Strips trailing spaces from lines so that diffs remain clean and editors don't introduce noise.
- `end-of-file-fixer`: Ensures every file ends with a single newline and removes extra blank lines at the end of files.
- `check-merge-conflict`: Fails when Git merge conflict markers are present to avoid committing unresolved conflicts.
- `check-json`: Validates JSON files and fails fast on malformed syntax.
- `check-yaml`: Parses YAML files to verify they are syntactically valid.
- `sort-imports`: Normalises and sorts imports according to the rules mentioned in the [Code Style](#code-style) below.
- `sort-errors`: Sorts errors according to the rules mentioned in the [Code Style](#code-style) below.
- `format`: This hook uses `forge fmt` to format all Solidity files.
- `doc`: This hook uses `forge doc` to generate the Solidity documentation. Commit the generated files whenever the documentation changes.
- `prettier`: All remaining files are formatted using prettier.

## Requirements for merge

In order for a PR to be merged, it must pass the following requirements:

- All commits within the PR must be signed
- CI must pass (tests, linting, etc.)
- New features must be merged with associated tests
- Bug fixes must have a corresponding test that fails without the fix
- The PR must be approved by at least one maintainer

## Branching

This section outlines the branching strategy of this repo.

### Main

The main branch is supposed to reflect the deployed state on all networks, if not indicated otherwise inside the README. Only audited code should be merged into main. Сommits from dev branches should be merged into the main branch using a regular merge strategy. The commit messages should follow [the Conventional Commits specification](https://www.conventionalcommits.org/en/v1.0.0/).

### Audit

Before an audit, the code should be frozen on a branch dedicated to the audit with the naming convention `audit/<provider>`. Each fix in response to an audit finding should be developed as a separate commit. The commit message should look similar to `fix: <provider> - <issue title>`.

## Code Practices

### Code Style

The repo follows the official [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html). In addition to that, this repo also borrows the following rules from [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/GUIDELINES.md#solidity-conventions):

- Internal or private state variables or functions should have an underscore prefix.

  ```solidity
  contract TestContract {
      uint256 private _privateVar;
      uint256 internal _internalVar;
      function _testInternal() internal { ... }
      function _testPrivate() private { ... }
  }
  ```

- Naming collisions should be avoided using a single trailing underscore.

  ```solidity
  contract TestContract {
      uint256 public foo;

      constructor(uint256 foo_) {
        foo = foo_;
      }
  }
  ```

- Interface names should have a capital I prefix.

  ```solidity
  interface IERC777 {
  ```

- Contracts not intended to be used standalone should be marked abstract, so they are required to be inherited by other contracts.

  ```solidity
  abstract contract AccessControl is ..., {
  ```

- Unchecked arithmetic blocks should contain comments explaining why overflow is guaranteed not to happen or is permissible. If the reason is immediately apparent from the line above the unchecked block, the comment may be omitted.

Also, such exceptions/additions exist:

- Functions should be grouped according to their visibility and ordered:

  1. constructor

  2. external

  3. public

  4. internal

  5. private

  6. receive function (if exists)

  7. fallback function (if exists)

- Each contract should be virtually divided into sections by using such separators:

  1. /\* CONSTANTS \*/
  2. /\* IMMUTABLES \*/
  3. /\* STATE VARIABLES \*/
  4. /\* MODIFIERS \*/
  5. /\* CONSTRUCTOR \*/
  6. /\* EXTERNAL FUNCTIONS \*/
  7. /\* PUBLIC FUNCTIONS \*/
  8. /\* INTERNAL FUNCTIONS \*/
  9. /\* PRIVATE FUNCTIONS \*/
  10. /\* RECEIVE FUNCTION \*/
  11. /\* FALLBACK FUNCTION \*/

- Each interface should be virtually divided into sections by using such separators:

  1. /\* ERRORS \*/
  2. /\* STRUCTS \*/
  3. /\* EVENTS \*/
  4. /\* FUNCTIONS \*/

- Do not use external and private visibilities in most cases.

- Events should generally be emitted immediately after the state change that they
  represent, and should be named the same as the function's name. Some exceptions may be made for gas
  efficiency if the result doesn't affect the observable ordering of events.

  ```solidity
  function _burn(address who, uint256 value) internal {
      super._burn(who, value);
      emit Burn(who, value);
  }
  ```

- Custom errors should be used whenever possible. The naming should be concise and easy to read.

- Imports should be divided into separate groups and ordered alphabetically ascending inside each group:

  1. contracts

  2. libraries

  3. interfaces

  4. external files separately

  ```solidity
  import {NetworkManager} from "../base/NetworkManager.sol";
  import {OzEIP712} from "../base/OzEIP712.sol";
  import {PermissionManager} from "../base/PermissionManager.sol";

  import {Checkpoints} from "../../libraries/structs/Checkpoints.sol";
  import {KeyTags} from "../../libraries/utils/KeyTags.sol";

  import {ISettlement} from "../interfaces/modules/settlement/ISettlement.sol";
  import {ISigVerifier} from "../interfaces/modules/settlement/sig-verifiers/ISigVerifier.sol";

  import {StaticDelegateCallable} from "@symbioticfi/core/src/contracts/common/StaticDelegateCallable.sol";
  import {Subnetwork} from "@symbioticfi/core/src/contracts/libraries/Subnetwork.sol";

  import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
  ```

- In case of comparison with `msg.sender` or `tx.origin`, these keywords should be on the right side of the inequality.

  ```solidity
  modifier onlyOwner() internal {
      if (owner != msg.sender) {
        revert NotOwner();
      }
  }
  ```

- Errors should be ordered alphabetically ascending.

  ```solidity
  error InsufficientFunds();
  error NoAccess();
  error NotOwner();
  ```

### Solidity Versioning

Contracts that are meant to be deployed should have an explicit version set in the `pragma` statement.

```solidity
pragma solidity 0.8.X;
```

Abstract contracts, libraries and interfaces should use the caret (`^`) range operator to specify the version range to ensure better compatibility.

```solidity
pragma solidity ^0.X.0;
```

Libraries and abstract contracts using functionality introduced in newer versions of Solidity can use caret range operators with higher path versions (e.g., `^0.8.24` when using transient storage opcodes). For interfaces, it should be considered to use the greater than or equal to (`>=`) range operator to ensure better compatibility with future versions of Solidity.

### Interfaces

Every contract MUST implement its corresponding interface that includes all externally callable functions, errors and events.

### NatSpec & Comments

Interfaces should be the entry point for all contracts. When exploring a contract within the repository, the interface MUST contain all relevant information to understand the functionality of the contract in the form of NatSpec comments. This includes all externally callable functions, structs, errors and events. The NatSpec documentation MUST be added to the functions, structs, errors and events within the interface. This allows a reader to understand the functionality of a function before moving on to the implementation. The implementing functions MUST point to the NatSpec documentation in the interface using `@inheritdoc`. Internal and private functions shouldn't have NatSpec documentation except for `@dev` comments, whenever more context is needed. Additional comments within a function should only be used to give more context to more complex operations; otherwise, the code should be kept readable and self-explanatory. NatSpec comments in contracts should use a triple slash (`///`) to bring less noise to the implementation, while libraries and interfaces should use `/* */` wrappers.

The comments should respect the following rules:

- For read functions: `@notice Returns <...>`
- For write functions: `@notice <What it does, starts with verb>`
- For structs: `@notice <What it is>`
- For errors: `@notice Raised when <...>`
- For events: `@notice Emitted when <...>`

Each contract/library/interface should have a title comment that should follow such a structure:

1. `@title <Name>` (e.g., `Vault`)
2. `@notice Contract/Library/Interface for <...>.` - also, other variations are possible, e.g.:
   - `@notice Interface for the Vault contract.`
   - `@notice Base contract for <...>.`
   - `@notice Library-logic for <...>.`
3. `@dev <...>` (optional)

## Testing

The following testing practices should be followed when writing unit tests for new code. All functions, lines and branches should be tested to result in 100% testing coverage. Fuzz parameters and conditions whenever possible. Extremes should be tested in dedicated edge case and corner case tests. Invariants should be tested in dedicated invariant tests.

Differential testing should be used to compare assembly implementations with implementations in Solidity or testing alternative implementations against existing Solidity or non-Solidity code using ffi.

New features must be merged with associated tests. Bug fixes should have a corresponding test that fails without the bug fix.

### Best Practices

Best practices and naming conventions should be followed as outlined in the [Foundry Book](https://getfoundry.sh/forge/tests/overview).

### IR Compilation

All contracts and tests should be compilable without IR whenever possible.

### Gas Metering

Gas for function calls should be metered using the built-in `vm.snapshotGasLastCall` function in forge. To meter across multiple calls `vm.startSnapshotGas` and `vm.stopSnapshotGas` can be used. Tests that measure gas should be annotated with `/// forge-config: default.isolate = true` and not be fuzzed to ensure that the gas snapshot is accurate and consistent for CI verification. All external functions should have a gas snapshot test, and diverging paths within a function should have appropriate gas snapshot tests.
For more information on gas metering, see the [Forge cheatcodes reference](https://getfoundry.sh/reference/cheatcodes/gas-snapshots/#snapshotgas-cheatcodes).

### Bytecode Hash

Bytecode hash should be set to `none` in the `foundry.toml` file to ensure that the bytecode is consistent.

## Dependency Management

The preferred way to manage dependencies is using [`forge install`](https://book.getfoundry.sh/forge/dependencies). This ensures that your project uses the correct versions and structure for all external libraries. Also, `npm` and `soldeer` packages should be published to increase coverage of different use-cases.

## Releases

Every deployment and change made to contracts after deployment should be accompanied by a tag and release on GitHub.
