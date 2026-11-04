# Conditionals test coverage

The existing metadata, deployment, mint-event, ERC-20, administrative-entry-point,
and launch-transfer tests remain in place. `ConditionalsProperties.t.sol` adds
10 boundary examples and 7 fuzz properties. `Conditionals.invariant.t.sol`
extends the existing ledger model with targeted failure paths and full-balance
transfers after every generated sequence.

The five discovery passes from the supplied Pashov reference were applied to
`src/Conditionals.sol` and its vendored ERC-20 implementation. The supplied Trail
of Bits reference informed input bounds, explicit examples, and failure review.
These tests use the real token through its public interface; they do not replace
its accounting, mint extra balances, or change its storage with cheatcodes.

| Discovery pass | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor fixes supply at `10^27` (`src/Conditionals.sol:10-14`); all tracked balances must sum to that supply. | Existing constructor checks and the invariant ledger, including zero-address and unexpected-recipient balances. |
| State transitions | Transfers affect only sender/recipient; approval replacement affects one owner/spender pair; failed calls preserve both balances and allowances (`ERC20.sol:104-153,280-312`). | All 16 actor allowance pairs checked after every action, replacement/revocation examples, and isolated balance/allowance failures. |
| Round trips | Ordinary transfers have no fees or conversions (`ERC20.sol:183-211`), so returning the same amount restores balances and splitting an amount does not change its result. | Direct and delegated round trips, split-versus-single transfer property; delegated round trips still consume finite approvals. |
| Adversarial inputs | A spender cannot exceed cumulative authorization or the owner's balance, including self-transfers; holders can move their full balances (`ERC20.sol:166-211,301-312`). | Repeated-spend exhaustion, finite/infinite rollback, maximum values, and full-balance exit after each random sequence. |
| Token-specific boundaries | Only maximum `uint256` represents unlimited approval; zero-value transfers remain valid; zero recipients/spenders are rejected (`ERC20.sol:166-174,280-312`). | Zero/one/full-supply examples, maximum-minus-one approval, zero-address failures, and finite/infinite zero-value delegated transfers. |

The invariant handler targets eleven actions across four actors. General approvals
retain the full `uint256` input range. Dedicated actions choose zero, one, the
current balance, maximum-minus-one, and maximum approvals. Positive delegated
spends select a funded actor so they cannot silently turn into zero-value calls.
Balance-failure actions first grant sufficient allowance; allowance-failure
actions use an affordable amount. Each rejection checks the exact custom error,
then the invariant checks the entire ledger against unchanged expected state.
Known-invalid calls are caught inside the handler, while unexpected handler
reverts fail the campaign.

Run counts are inline in the added/extended suites: 1,000 cases per new fuzz
property, and 256 invariant sequences of 64 calls. Bounds generate valid test
domains without discarded assumptions. Tests use only the dependencies already
vendored in the repository and require no network, fork, credentials, or launch
configuration. The existing launch fixture covers token movements; actual
Uniswap execution belongs to the separately supplied protected integration checks.

Local validation passed: 50 tests, zero failures or skips, including 16,384
invariant actions with all eleven selectors exercised. No implementation defect
was reproduced. Commands, keeping generated artifacts in disposable scratch:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xc9d8fc811631f4994fde692671ff34c5e253048ebe2885c5df68af1c20e9ebed forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```
