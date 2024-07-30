## Resolver

Symbiotic supports various modes of handling slashing incidents through the introduction of resolvers. Resolvers are contracts or entities that are able to veto slashing incidents forwarded from networks and can be shared across networks. Resolvers are determined through terms proposed by networks and accepted by vaults seeking to provide collateral backing to operators. A vault can allow multiple different (or no) resolvers to cover their entire collateral (e.g. 10% without resolver, 40% with a Resolver A, and 50% with Resolver B, both of which could e.g. be committees that cover a specific subset of networks). Additionally, decentralized dispute resolution frameworks such as UMA, Kleros, reality.eth, or others could be used as resolvers. It is also possible to require a quorum of resolvers to veto or pass a specific slashing incident providing additional security guarantees to participants in the Symbiotic protocol economy.

---

A resolver is an address that can veto a particular slashing request in the slasher module of the vault. It listens to the slashing requests and when it finds the request it has some time to veto the request or agree with the slashing. Note, that if a resolver does not veto the request, such a request will be considered approved for slashing by the resolver. Each slashing request has its own veto deadline defined by the vault.
