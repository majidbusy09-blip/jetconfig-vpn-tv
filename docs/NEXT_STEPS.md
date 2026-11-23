# JET VPN TV — Prioritized Next Steps

1. Keep the read-only PR validation workflow green for source analysis, tests, and a non-release ARM64 debug APK.
2. Review the client SHA-256 implementation and expand deterministic regression tests only where a concrete coverage gap exists.
3. Preserve the backend handoff record in `docs/TV_UPDATE_BACKEND_SHA256_PATCH.md`; the separate patch bundle is prepared and locally validated, but is not deployed.
4. Since staging access was waived by the owner, continue with offline verification and documentation. Do not represent the waived stage as a live server or device test.
5. When staging access becomes available, apply the backend patch only to a staging copy, then run the server-to-client and physical-TV verification matrix in `docs/TV_UPDATE_HASH_ROLLOUT_CHECKLIST.md`.
6. Maintain a manual TV checklist for real traffic, remote focus/navigation, sleep/resume, profile switching, and APK update/install.

Deferred: tunnel/server/authentication changes without a concrete issue; signing, package identity, version, release, tag, production manifest, or deployment changes without explicit approval.
