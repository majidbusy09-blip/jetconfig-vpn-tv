# JET VPN TV — Prioritized Next Steps

1. Use the new read-only PR validation workflow to establish a green baseline for source analysis and an ARM64 debug APK; investigate any existing analyzer/build failures before changing app behavior.
2. Document the connection/recovery state, server-selection rules, profile persistence, and update/install lifecycle from current source before changing them.
3. Extract and test pure logic only where behavior can be preserved and independently reviewed.
4. Maintain a manual TV checklist for connection and actual traffic, remote focus/navigation, sleep/resume, profile switching, and APK update.
5. Review the release workflow separately; it currently creates releases on pushes to `main`. Do not alter production release behavior without explicit approval.

Deferred: tunnel/server/authentication changes without a concrete issue; signing, package identity, release, tag, or deployment changes without explicit approval.
