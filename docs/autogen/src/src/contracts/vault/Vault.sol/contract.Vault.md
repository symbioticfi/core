# Vault
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/vault/Vault.sol)

**Inherits:**
[VaultStorage](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/vault/VaultStorage.sol/abstract.VaultStorage.md), [MigratableEntity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/MigratableEntity.sol/abstract.MigratableEntity.md), AccessControlUpgradeable, [IVault](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/vault/IVault.sol/interface.IVault.md)


## Functions
### constructor


```solidity
constructor(address delegatorFactory, address slasherFactory, address vaultFactory)
    VaultStorage(delegatorFactory, slasherFactory)
    MigratableEntity(vaultFactory);
```

### isInitialized

Check if the vault is fully initialized (a delegator and a slasher are set).


```solidity
function isInitialized() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the vault is fully initialized|


### totalStake

Get a total amount of the collateral that can be slashed.


```solidity
function totalStake() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of the slashable collateral|


### activeBalanceOfAt

Get an active balance for a particular account at a given timestamp using hints.


```solidity
function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata hints) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the active balance for|
|`timestamp`|`uint48`|time point to get the active balance for the account at|
|`hints`|`bytes`|hints for checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|active balance for the account at the timestamp|


### activeBalanceOf

Get an active balance for a particular account.


```solidity
function activeBalanceOf(address account) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the active balance for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|active balance for the account|


### withdrawalsOf

Get withdrawals for a particular account at a given epoch (zero if claimed).


```solidity
function withdrawalsOf(uint256 epoch, address account) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epoch`|`uint256`|epoch to get the withdrawals for the account at|
|`account`|`address`|account to get the withdrawals for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|withdrawals for the account at the epoch|


### slashableBalanceOf

Get a total amount of the collateral that can be slashed for a given account.


```solidity
function slashableBalanceOf(address account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the slashable collateral for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of the account's slashable collateral|


### deposit

Deposit collateral into the vault.


```solidity
function deposit(address onBehalfOf, uint256 amount)
    public
    virtual
    nonReentrant
    returns (uint256 depositedAmount, uint256 mintedShares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`onBehalfOf`|`address`|account the deposit is made on behalf of|
|`amount`|`uint256`|amount of the collateral to deposit|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`depositedAmount`|`uint256`|real amount of the collateral deposited|
|`mintedShares`|`uint256`|amount of the active shares minted|


### withdraw

Withdraw collateral from the vault (it will be claimable after the next epoch).


```solidity
function withdraw(address claimer, uint256 amount)
    external
    nonReentrant
    returns (uint256 burnedShares, uint256 mintedShares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`claimer`|`address`|account that needs to claim the withdrawal|
|`amount`|`uint256`|amount of the collateral to withdraw|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`burnedShares`|`uint256`|amount of the active shares burned|
|`mintedShares`|`uint256`|amount of the epoch withdrawal shares minted|


### redeem

Redeem collateral from the vault (it will be claimable after the next epoch).


```solidity
function redeem(address claimer, uint256 shares)
    external
    nonReentrant
    returns (uint256 withdrawnAssets, uint256 mintedShares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`claimer`|`address`|account that needs to claim the withdrawal|
|`shares`|`uint256`|amount of the active shares to redeem|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`withdrawnAssets`|`uint256`|amount of the collateral withdrawn|
|`mintedShares`|`uint256`|amount of the epoch withdrawal shares minted|


### claim

Claim collateral from the vault.


```solidity
function claim(address recipient, uint256 epoch) external nonReentrant returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|account that receives the collateral|
|`epoch`|`uint256`|epoch to claim the collateral for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|amount of the collateral claimed|


### claimBatch

Claim collateral from the vault for multiple epochs.


```solidity
function claimBatch(address recipient, uint256[] calldata epochs) external nonReentrant returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|account that receives the collateral|
|`epochs`|`uint256[]`|epochs to claim the collateral for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|amount of the collateral claimed|


### onSlash

Slash callback for burning collateral.

Only the slasher can call this function.


```solidity
function onSlash(uint256 amount, uint48 captureTimestamp) external nonReentrant returns (uint256 slashedAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|amount to slash|
|`captureTimestamp`|`uint48`|time point when the stake was captured|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`slashedAmount`|`uint256`|real amount of the collateral slashed|


### setDepositWhitelist

Enable/disable deposit whitelist.

Only a DEPOSIT_WHITELIST_SET_ROLE holder can call this function.


```solidity
function setDepositWhitelist(bool status) external nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`bool`|if enabling deposit whitelist|


### setDepositorWhitelistStatus

Set a depositor whitelist status.

Only a DEPOSITOR_WHITELIST_ROLE holder can call this function.


```solidity
function setDepositorWhitelistStatus(address account, bool status)
    external
    nonReentrant
    onlyRole(DEPOSITOR_WHITELIST_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account for which the whitelist status is set|
|`status`|`bool`|if whitelisting the account|


### setIsDepositLimit

Enable/disable deposit limit.

Only a IS_DEPOSIT_LIMIT_SET_ROLE holder can call this function.


```solidity
function setIsDepositLimit(bool status) external nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`bool`|if enabling deposit limit|


### setDepositLimit

Set a deposit limit.

Only a DEPOSIT_LIMIT_SET_ROLE holder can call this function.


```solidity
function setDepositLimit(uint256 limit) external nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|deposit limit (maximum amount of the collateral that can be in the vault simultaneously)|


### setDelegator


```solidity
function setDelegator(address delegator_) external nonReentrant;
```

### setSlasher


```solidity
function setSlasher(address slasher_) external nonReentrant;
```

### _withdraw


```solidity
function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
    internal
    virtual
    returns (uint256 mintedShares);
```

### _claim


```solidity
function _claim(uint256 epoch) internal returns (uint256 amount);
```

### _initialize


```solidity
function _initialize(uint64, address, bytes memory data) internal virtual override;
```

### _migrate


```solidity
function _migrate(
    uint64,
    /* oldVersion */
    uint64,
    /* newVersion */
    bytes calldata /* data */
)
    internal
    override;
```

