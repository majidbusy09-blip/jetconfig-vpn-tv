# JET VPN TV — Prioritized Next Steps

1. Use the new read-only PR validation workflow to establish a green baseline for source analysis and an ARM64 debug APK; investigate any existing analyzer/build failures before changing app behavior.
2. Document the connection/recovery state, server-selection rules, profile persistence, and update/install lifecycle from current source before changing them. Initial profile and update-manifest logic has been extracted without changing credential storage or download/install behavior.
3. Pure-logic regression tests now cover connection-state parsing, server ping ranking, profile persistence serialization/parsing, and update-manifest validation. Keep these tests independent of platform plugins, network, and filesystem side effects.
4. Next automated coverage candidate: pending-update metadata consistency and file-integrity decision logic, extracted from filesystem operations only after mapping all existing compatibility cases. Maintain a manual TV checklist for connection and actual traffic, remote focus/navigation, sleep/resume, profile switching, and APK update.
5. Review the release workflow separately; it currently creates releases on pushes to `main`. Do not alter production release behavior without explicit approval.

Deferred: tunnel/server/authentication changes without a concrete issue; signing, package identity, release, tag, or deployment changes without explicit approval.
