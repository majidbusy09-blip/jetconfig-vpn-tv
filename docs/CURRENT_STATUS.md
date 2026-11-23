# JET VPN TV — Current Status

- Snapshot: 2026-11-23; inspected `main` SHA `73577bdadc1fb2b1a894d877120bc3372ae19d67`.
- Active documentation/engineering PR: [#1](https://github.com/majidbusy09-blip/jetconfig-vpn-tv/pull/1), draft and unmerged.
- PR head at this status update: `333f2125aaf23ccde511c7dd11c624a20345d747`.
- Version: `1.0.14+114`.
- Main source: `lib/main.dart`; Android project is generated in CI.
- SHA-256 client support (Phases A/B) is implemented on the PR branch. Legacy manifests remain compatible but unverified.
- Backend panel source was located in the user-provided archive and a separate SHA-256 patch bundle was prepared.
- Backend patch local verification: 11 helper checks + 5 manifest checks + 4 panel integration checks; PHP syntax checks passed.
- No staging host was available. The owner waived the staging-access task to proceed; no live backend or physical-TV result is claimed.
- PR validation for the prior head completed successfully: [run #45131117262](https://github.com/majidbusy09-blip/jetconfig-vpn-tv/actions/runs/45131117262).
- No source, version, signing, production manifest, or workflow changes are included in this documentation update.
- No Release, Deploy, or production workflow was run.
