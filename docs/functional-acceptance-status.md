# Functional acceptance status

## Bot Mode and Studio verification — 2026-11-23

- Native Home, Chat, Bots, and Library navigation compiles with simulator signing enabled.
- All 50 tests passed in `/private/tmp/tether-bots-final-tests.xcresult`. Coverage includes independent provider/model routing, frozen queued settings, sequential work per bot, recovery without resubmission, cancellation retry, exact approval targeting, missing-connection recovery, provider failure explanations, and the mini-app CSP comment bypass regression in WebKit.
- Studio Hermes 0.23.3 was verified through `https://souranils-mac-studio.tail4a305f.ts.net` with its current API key. The active Tailscale Mac app already serves HTTPS to loopback port 8642. The old SSH address and `~/hermes_token` handoff were stale; the new launch helper reads the current key over existing authorized SSH without printing it.
- In a dedicated simulator, Studio Assistant was configured with `openai-codex` / `gpt-6.1-sol`, and Studio Writer independently selected `anthropic` / `claude-sonnet-4-6`. The OpenAI task completed and its result appeared in the native task view.
- A second OpenAI task, `run_e7056f294f12469fa495350440de297a`, was accepted while the simulator app was active. Tether was terminated with its local checkpoint still `running`. A separate HTTPS status request observed server completion while the app was terminated. Reopening Tether without bootstrap variables recovered one saved task under the same run ID with 2,146 output characters; the result was visible in the native Home feed and task view.
- The Anthropic task was accepted but failed with a server explanation that the model service could not be reached and required sign-in or a different model. Model discovery advertising an authenticated provider is not proof that its inference credential works. Tether now preserves failed-run output so this explanation is visible.
- Current Bot Mode is API-backed and local to Tether. It uses separate API sessions for conversational context; it does not import Desktop Bot Chats or provision isolated Hermes profiles. Recurring routines, proactive feeds, goal tracking, and APNs completion notifications are not implemented. Queued tasks require the app to run until Hermes accepts them.
- This pass did not install on or validate a physical iPhone. Live UI approval/denial and cancellation against the Studio remain device acceptance work; those paths have automated client coverage.

## Earlier physical-phone acceptance — 2026-09-20

Scope: physical Tether iPhone → existing Tailscale → guest Hermes HTTPS → guest-local OpenAI subscription. Network hardening and oMLX are not acceptance work for this pass. Preserve existing services and profiles.

## Fresh evidence

- CoreDevice lists paired iPhone `2CB86E93-55AB-5234-8F2C-D32353C7E792` as `unavailable`. Physical-phone interaction and lifecycle acceptance cannot currently be performed.
- Current-source regression was rerun after the latest project changes: 39/39 Tether tests passed with zero failures or skips in `/tmp/tether-current-20260920.xcresult` on the iPhone 17 Pro simulator.
- The renamed current Tether source compiles for generic arm64 iOS into `/tmp/tether-device-ready-20260920/Build/Products/Debug-iphoneos/Tether.app`, bundle `app.tether.ios`, team `22BH2R3K7H`. Final signing is pending because command-line access to the valid Apple Development private key returned `errSecInternalComponent` while the login keychain disallowed interaction. Unlock the login keychain, rerun the prepared build, then install it in place once CoreDevice reports the phone available; do not uninstall or reset app data.
- Guest SSH succeeds with the existing project key. Installed Hermes source is clean at commit `6c27a289c3f57839a97f5709edb089b202ee6d82`.
- The resolver-scoped repair from https://github.com/NousResearch/hermes-agent/pull/109496 was reviewed at PR head `a70e5d12fa`, including its stop/shutdown race follow-ups. Its 20 focused tests passed in an isolated checkout. The four commits applied cleanly to the exact installed base `6c27a289c3`; 96 focused and adjacent run-lifecycle tests passed on that compatibility checkout.
- The four reviewed commits are deployed in the guest checkout, now at `f079842525`. Rollback branch `backup/tether-pre-approval-fix-20260920` points to the prior revision. The launchd gateway recovered after one transient old-socket bind race and is again running; tailnet HTTPS health returns Hermes `0.21.2` `ok`.
- Live cancellation passed through the same authenticated API contract Tether uses: `run_f14643e0774443c2947270353c83c56b` transitioned `stopping` → `cancelled`, produced no output, and an identical idempotent replay returned that same run with `replayed:true`.
- Live approval denial passed for guest computer input: `run_51e04bf01a9c45c4a37189ee7a06adc8` transitioned through `waiting_for_approval`, exposed a request ID, accepted `deny` with HTTP 200, and completed reporting the denial without typing the marker.
- One-time approval routing is also live: subsequent constrained CUA runs accepted run-scoped `once` choices for `cua:focus_app`, `cua:key`, `cua:type`, `cua:click`, and `cua:bring_to_front`; an unlisted action was automatically denied by the acceptance harness. No session or permanent approval was granted.
- Guest `hermes computer-use doctor --json` reports overall `ok`, Accessibility granted, Screen Recording granted, AX reachable, and an active MCP session. After the guest was unlocked, authenticated API run `run_4885f3d9292740948cd640997857e29a` transitioned `running` → `waiting_for_approval` → `running` → `waiting_for_approval` → `running` → `completed`. Two exact, run-scoped `cua:type:background` requests were approved once; no session or permanent grant was created. The guest TextEdit window visibly contained the legacy acceptance marker, completing guest-only CUA backend acceptance.
- The preceding display-sleep verification read `displaysleep 0`; guest HTTPS health returned `ok`, Hermes `0.21.2`. This proves that setting and health at that observation, not completion of phone acceptance.

## Remaining acceptance

1. Unlock the host login keychain for code signing, then reconnect/unlock the physical iPhone; sign and install the current Tether build in place and verify its separate guest profile without replacing Studio profiles or exposing a token.
2. Demonstrate OpenAI-backed chat from that phone.
3. Create then edit a mini-app, closing Tether after admission for each operation. Confirm stable run IDs, exactly one artifact, and recovery on reopen. Existing simulator evidence is not a substitute.
4. Repeat the now-working approval/deny and cancellation paths from the physical phone UI. Backend API evidence is complete; phone UI evidence is not.
5. Trigger the already-proven guest-only computer-use path from the physical phone UI and confirm the approval presentation there. Backend execution and visible guest isolation evidence are complete; phone UI evidence is not.

The approval repair is deployed without changing `approvals.unattended_mode` (`deny`) and without creating standing action grants. The guest GUI acceptance is complete. The physical iPhone must become available to CoreDevice to finish device-level acceptance.
