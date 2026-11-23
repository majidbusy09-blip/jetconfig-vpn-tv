# JET VPN TV — Prioritized Next Steps

1. Establish repeatable non-production validation: formatting, Flutter analysis, and a minimal test strategy.
2. Document connection/recovery state, server-selection rules, profile persistence, and update/install lifecycle from current source before changing them.
3. Extract and test pure logic only where behavior can be preserved and independently reviewed.
4. Maintain a manual TV checklist for connection and actual traffic, remote focus/navigation, sleep/resume, profile switching, and APK update.
5. Review the release workflow separately; it currently creates releases on pushes to `main`. Do not alter production release behavior without explicit approval.

Deferred: tunnel/server/authentication changes without a concrete issue; signing, package identity, release, tag, or deployment changes without explicit approval.