# Legacy LLM Credential Cleanup

## Cause

Subscription authentication was removed, but the cleanup used only the renamed
`vote.aib.bzogak.llm.subscription` Keychain service. Earlier development builds
stored their tokens under `aib.Overline.llm.subscription`, leaving those entries
outside the deletion query.

## Scope

- Delete obsolete subscription credentials from both service names, restricted to known provider accounts.
- Keep the current and previous API-key services (`vote.aib.bzogak.llm` and `aib.Overline.llm`) unchanged.
- Keep unrelated Keychain accounts, provider/model selections, current API-key rejection state, and external-AI consent unchanged.
- Continue removing only the existing obsolete subscription preferences.
- Do not read or modify the library, reading records, or backup files.
- Keep cleanup repeatable at settings initialization; do not introduce a completion flag that could suppress retries after an unavailable Keychain.

Keychain access remains limited to the running app's entitlements. This migration
does not access another app's private Keychain group or transfer credentials
between different bundle IDs.

In particular, the former development target and the current App Store target use
different signing identities. Tokens left in the former app's private group are
not cleared by installing this release. Cleanup there would require a separately
authorized build signed for that original identity, or revocation through the
credential provider. No access-group entitlement, old app installation, or user's
existing data is changed as part of this fix.

## Verification

Run `bash Tests/LegacyCredentialCleanup/run.sh` from the repository root.
The tests compile the production settings source, inject in-memory deletion, and
use a temporary UserDefaults suite. They do not access the user's real Keychain.
Checks cover both subscription service names, preservation of API keys and other
settings, and repeated cleanup when obsolete entries are absent.

Before the service-name fix, the regression check reproduced the remaining
`aib.Overline.llm.subscription` entry. Real-device Keychain entitlement behavior
requires a separately signed device test; the isolated tests do not prove access
to credentials written by another bundle ID.

This correction is not included in the previously uploaded Version 1.0 / Build 4.
