# VaultTokenized
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/contracts/vault/VaultTokenized.sol)

**Inherits:**
[Vault](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/vault/Vault.sol/contract.Vault.md), ERC20Upgradeable, [IVaultTokenized](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/vault/IVaultTokenized.sol/interface.IVaultTokenized.md)


## Functions
### constructor


```solidity
constructor(address delegatorFactory, address slasherFactory, address vaultFactory)
    Vault(delegatorFactory, slasherFactory, vaultFactory);
```

### decimals

Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).
Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.
NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}.


```solidity
function decimals() public view override returns (uint8);
```

### totalSupply

See {IERC20-totalSupply}.


```solidity
function totalSupply() public view override returns (uint256);
```

### balanceOf

See {IERC20-balanceOf}.


```solidity
function balanceOf(address account) public view override returns (uint256);
```

### deposit

Deposit collateral into the vault.


```solidity
function deposit(address onBehalfOf, uint256 amount)
    public
    override(Vault, IVault)
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


### _withdraw


```solidity
function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
    internal
    override
    returns (uint256 mintedShares);
```

### _update

Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
(or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
this function.
Emits a {Transfer} event.


```solidity
function _update(address from, address to, uint256 value) internal override;
```

### _initialize


```solidity
function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override;
```

