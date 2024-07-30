## Collateral

Collateral is a concept introduced by Symbiotic that brings capital efficiency and scale by enabling assets used to secure Symbiotic networks to be held outside of the Symbiotic protocol itself - e.g. in DeFi positions on networks other than Ethereum itself.

Symbiotic achieves this by separating the ability to slash assets from the underlying asset itself, similar to how liquid staking tokens create tokenized representations of underlying staked positions. Technically, collateral positions in Symbiotic are ERC-20 tokens with extended functionality to handle slashing incidents if applicable. In other words, if the collateral token aims to support slashing, it should be possible to create a `Burner` responsible for proper burning of the asset.

For example, if asset is ETH LST it can be used as a collateral if it's possible to create `Burner` contract that withdraw ETH from beaconchain and burn it, if asset is native e.g. governance token it also can be used as collateral since burner might be implemented as "black-hole" contract or address.

Symbiotic allows collateral tokens to be deposited into vaults, which delegate collateral to operators across Symbiotic networks. Vaults define acceptable collateral and it's `Burner` _(if vault supports slashing)_ and networks need to accept these and other vault terms such as slashing limits to receive rewards _(these processes are described in detail in Vault section)_.

---

We do not specify the exact implementation of the Collateral, however, it must satisfy all the following requirement:

- Collateral token must support ERC-20 interface
- [**OPTIONAL**] Collateral token should be slashable i.e. native token or derivative that supports redeeming the underlying native token. _(Only if collateral is used in slashable vaults)_.
