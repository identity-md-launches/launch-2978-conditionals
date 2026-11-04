# Conditionals (COND)

Conditionals is a fixed-supply ERC-20. The entire **1,000,000,000 COND** is minted once to the
immediate deployer in its constructor. It uses the vendored OpenZeppelin Contracts v5.1.0 ERC-20
implementation without overriding transfers, approvals, or decimals.

| Deployment parameter | Value |
| --- | --- |
| Solidity contract / source | `Conditionals` / `src/Conditionals.sol` |
| Token name | `Conditionals` |
| Symbol | `COND` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | Zero |
| Initial recipient | `msg.sender`, the immediate deploying address |
| Intended launch chain | Ethereum, chain ID 1 |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer / metadata | Enabled, 200 runs / `bytecode_hash = "none"` |
| Application contracts | None |

## Behavior and assumptions

The brief specifies no additional transfer conditions, so transfers are ordinary ERC-20 transfers:
the recipient receives exactly the amount debited from the sender. There are no fees, taxes,
rebases, burns, restrictions on trading, or dependencies on external contracts, time, or oracles.
There is no owner, minter, pause, blacklist, seizure, upgrade, initializer, or recovery function.
Supply cannot increase or decrease after construction. The inherited mint/burn helpers are internal
and have no post-construction entry point in this contract.

Transfers and approvals return `true` on success and revert with OpenZeppelin ERC-6093 custom errors
on failure. Zero-value transfers are allowed and emit `Transfer`; zero recipient and spender
addresses are rejected. Self-transfers leave balances unchanged but still require sufficient funds.
`transferFrom` requires the caller's allowance, including for the deployer, and consumes finite
allowances. A maximum `uint256` approval is unlimited and is not consumed. Failed transfers revert
all changes, including allowance consumption.

`approve` replaces the current allowance and emits `Approval`. Successful `transferFrom` emits
`Transfer` but, following OpenZeppelin v5, does not emit a separate `Approval` when consuming an
allowance. Integrators should query `allowance` rather than reconstruct it only from events.

## Build and test

Foundry and Solidity 0.8.26 are the toolchain prerequisites. All Solidity dependencies and their
licenses are ordinary files in `lib/`; no package installation, Git submodules, RPC, wallet, or
network access is needed once the compiler is available. `dependencies.lock.json` records upstream
tags, commits, archive hashes, and the SHA-256 of every vendored file.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xc9d8fc811631f4994fde692671ff34c5e253048ebe2885c5df68af1c20e9ebed forge test
forge fmt --check
```

Tests do not read or modify environment variables. The seed above configures Foundry itself;
tests also work without it. Fuzz tests run 1,000 cases each. Stateful invariants run 128 sequences
of 64 actions, comparing balances and allowances against an independent accounting model after
transfers, approvals, delegated transfers, and failed overdrafts. Each test has its own setup.

The suite checks metadata, constructor mint and event, direct and CREATE2 factory deployment,
exact transfers, full-balance and zero/self transfers, allowance replacement/revocation/exhaustion,
infinite approvals, failed-call atomicity, unauthorized spending, absent privileged entry points,
and forbidden runtime opcodes. Local factory/distributor/pool fixtures exercise token movements
for distribution, claims, purchases, and sales. They do not execute Uniswap swaps or liquidity math.
The supplied protected integration tests depend on external launch infrastructure and resolved
manifest inputs; they are inputs to the independent verifier, not included in this project.

## Deployment and operational responsibilities

Use the creation bytecode for `src/Conditionals.sol:Conditionals`, with no appended constructor
arguments and no linked libraries. `forge build` writes the ABI and bytecode to
`out/Conditionals.sol/Conditionals.json`. The constructor makes no external calls and needs no
initialization transaction. A factory deployment gives **all** supply to the factory, not the
transaction origin or the caller that instructed the factory. Direct deployment gives all supply
to that direct deployer. The deployment mechanism must be able to distribute what it receives.

The launch operator is responsible for the separate manifest, factory deployment, distribution,
pool setup, and source verification. The token performs none of that distribution itself.
For the specified launch, the factory forwards 10% to the launch distributor, seeds the pool with
80%, and forwards the remaining 10% to the requester's specified recipient. These are launch
operations, not token constructor allocations. They must leave supply and transfer amounts intact.
No deployment transaction is sent by this repository, and no signer or owner configuration is needed.

After launch there are no settings, privileged keys, maintenance calls, or token administrator.
The operator should verify the deployed metadata, total supply, constructor mint recipient/event,
runtime bytecode, and exact launch distributions, then publish the verified source and address.
Holders manage their own custody and approvals. Approvals should be limited to amounts required;
when replacing a nonzero allowance, revoke it and confirm before granting a new amount to reduce
the ERC-20 allowance replacement race. Tokens sent to an address that cannot return them, including
the token contract itself, cannot be recovered by an administrator. Ordinary ETH sends revert.

## Review scope

The implementation keeps all token accounting inside OpenZeppelin's ERC-20 and exposes no external
callbacks, arbitrary calls, delegate calls, or upgrade mechanism. Local verification consists of
Foundry build, unit/fuzz/invariant tests, formatting, and source review. Slither and Mythril were not
run. Passing tests are not an independent security audit; the launch's independent review and
deployment checks remain the operator's responsibility.

## Dependencies

- [OpenZeppelin Contracts v5.1.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0):
  the five Solidity files required by ERC-20, plus its MIT license.
- [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7):
  Solidity test helpers and MIT/Apache-2.0 licenses; used only by tests.
