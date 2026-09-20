# Functional acceptance status — 2026-09-20

Scope: physical Tether iPhone → existing Tailscale → guest Hermes HTTPS → guest-local OpenAI subscription. Network hardening and oMLX are not acceptance work for this pass. Preserve existing services and profiles.

## Fresh evidence

- CoreDevice lists paired iPhone `2CB86E93-55AB-5234-8F2C-D32353C7E792` as `unavailable`. Physical-phone interaction and lifecycle acceptance cannot currently be performed.
- Current-source regression was rerun after the latest project changes: 39/39 Tether tests passed with zero failures or skips in `/tmp/tether-current-20260920.xcresult` on the iPhone 17 Pro simulator.
- A fresh physical-device Debug bundle is ready at `/tmp/tether-device-ready-20260920/Build/Products/Debug-iphoneos/Tether.app`. Strict/deep signature verification passes; it is arm64, bundle `app.tether.ios`, team `22BH2R3K7H`, signed September 20. Install it in place once CoreDevice reports the phone available; do not uninstall or reset app data.
- Guest SSH succeeds with the existing project key. Installed Hermes source is clean at commit `6c27a289c3f57839a97f5709edb089b202ee6d82`.
- The resolver-scoped repair from https://github.com/NousResearch/hermes-agent/pull/109496 was reviewed at PR head `a70e5d12fa`, including its stop/shutdown race follow-ups. Its 20 focused tests passed in an isolated checkout. The four commits applied cleanly to the exact installed base `6c27a289c3`; 96 focused and adjacent run-lifecycle tests passed on that compatibility checkout.
- The four reviewed commits are deployed in the guest checkout, now at `f079842525`. Rollback branch `backup/tether-pre-approval-fix-20260920` points to the prior revision. The launchd gateway recovered after one transient old-socket bind race and is again running; tailnet HTTPS health returns Hermes `0.21.2` `ok`.
- Live cancellation passed through the same authenticated API contract Tether uses: `run_f14643e0774443c2947270353c83c56b` transitioned `stopping` → `cancelled`, produced no output, and an identical idempotent replay returned that same run with `replayed:true`.
- Live approval denial passed for guest computer input: `run_51e04bf01a9c45c4a37189ee7a06adc8` transitioned through `waiting_for_approval`, exposed a request ID, accepted `deny` with HTTP 200, and completed reporting the denial without typing the marker.
- One-time approval routing is also live: subsequent constrained CUA runs accepted run-scoped `once` choices for `cua:focus_app`, `cua:key`, `cua:type`, `cua:click`, and `cua:bring_to_front`; an unlisted action was automatically denied by the acceptance harness. No session or permanent approval was granted.
- Guest `hermes computer-use doctor --json` reports overall `ok`, Accessibility granted, Screen Recording granted, AX reachable, and an active MCP session. The final visible CUA marker remains unverified because the guest console is currently at the `jarvis` password lock screen; while locked, TextEdit is absent from the accessibility surface. The user must unlock the guest before the harmless TextEdit marker test can complete.
- The preceding display-sleep verification read `displaysleep 0`; guest HTTPS health returned `ok`, Hermes `0.21.2`. This proves that setting and health at that observation, not completion of phone acceptance.

## Remaining acceptance

1. Reconnect/unlock the physical iPhone; verify its separate guest profile without replacing Studio profiles or exposing a token.
2. Demonstrate OpenAI-backed chat from that phone.
3. Create then edit a mini-app, closing Tether after admission for each operation. Confirm stable run IDs, exactly one artifact, and recovery on reopen. Existing simulator evidence is not a substitute.
4. Repeat the now-working approval/deny and cancellation paths from the physical phone UI. Backend API evidence is complete; phone UI evidence is not.
5. Unlock the guest GUI, then demonstrate phone-requested computer use affecting only the guest desktop and visibly verify the TextEdit marker.

The approval repair is deployed without changing `approvals.unattended_mode` (`deny`) and without creating standing action grants. The physical iPhone and guest GUI must both be unlocked to finish device-level acceptance.
