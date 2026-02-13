# Symbiotic Core Mirror AGENTS

## Stack decisions (non-negotiable)

- Smart contracts: Solidity + Foundry (forge/cast/anvil). Do NOT use Hardhat.
- UI: Vite + TypeScript + viem/wagmi + Privy + daisyUI. Do NOT use Next.js.
- Web3 libs: Do NOT use ethers. Use viem and wagmi.
- Auth/wallet: Use Privy (not WalletConnect, not RainbowKit).
- JS package manager: pnpm (not npm).

Build/lint/test:

- `forge build`
- `forge test`
- Single test: `forge test --match-test <TestName>` or `forge test --match-path test/<File>.t.sol`
- Format: `forge fmt`
- UI (Vite): `pnpm --prefix ui run dev|build|lint|preview`

Architecture/structure:

- Solidity contracts live in `src/`; tests in `test/`; scripts in `script/` and `script/actions/`.
- Core domains: Collateral, Vaults, Operators, Resolvers, Networks (see README).
- Foundry config in `foundry.toml`; artifacts in `out/`; libraries under `lib/` (openzeppelin, forge-std, solady).
- Frontend sandbox lives in `ui/` (React + Vite), separate from contracts.

Code style:

- Use `forge fmt` defaults (4-space indent, 120 line length, double quotes, no import sorting).
- Prefer explicit types and descriptive names; avoid mixed-case lints already excluded by config.
- Keep Solidity files in ASCII unless the file already uses Unicode.
- Error handling: use `require`/`revert` with clear reason strings; favor custom errors when present in patterns.
