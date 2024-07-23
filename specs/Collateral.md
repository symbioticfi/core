## Collateral

### General Overview

Any operator wishing to operate in a Proof of Stake (POS) system must have a stake. This stake must be locked in some manner, somewhere. There are solutions that make such a stake liquid, yet the original funds remain locked, and in exchange, depositors/delegators receive LST tokens. They can then operate with these LST tokens. The reasons for locking the original funds include the need for immediate slashing if an operator misbehaves. This requirement for instant action necessitates having the stake locked, a limitation imposed by the current design of POS systems.

Collateral introduces a new type of asset that allows stakeholders to hold onto their funds and earn yield from them without needing to lock these funds in direct manner or convert them to another type of asset. Collateral represents an asset but does not require physically holding or locking this asset. The securities backing the Collateral can be in various forms, such as a liquidity pool position, some real-world asset, or generally any type of asset. Depending on the implementation of Collateral, this securing asset can be held within the Collateral itself or elsewhere.

- Collateral token must support ERC-20 interface
- [**OPTIONAL**] Collateral token should be slashable i.e. native token or derivative that supports redeeming the underlying native token. _(Only if collateral is used in slashable vaults)_.
