# Functional acceptance status

## Mac Studio Hermes verification — 2026-11-24

Current behavior supersedes the 2026-11-23 local bot catalog below. The app uses Hermes on the Mac Studio over Tailscale; no independent provider connectors or local model/agent execution were added. Generated mini-app HTML is a phone-rendered frontend.

- Hermes 0.23.3 is reachable at `https://souranils-mac-studio.tail4a305f.ts.net` (API) and port `9119` (gateway). The Mac’s Tailscale address is `100.86.238.64`. Existing Serve configuration was preserved.
- Gateway status reports the real profiles `default` and `chief-local`. The new Bots view uses those live profiles and the gateway’s canonical Bot Chat, replacing the phone-created Studio Assistant/Writer definitions. Legacy catalog code is removed; saved legacy files are preserved.
- Studio’s default model is oMLX `Inkling-2-Mini-oQ4e-mtp`. Models and provider choices continue to come from Hermes, including any subscription credentials managed there.
- The production app created a counter via the real Runs API (`run_5719ccc7c46441a7a868516a9e6ff2f5`). Its generated counter rendered in the app after the preview lifetime/layout fix. Loading and failure states now appear explicitly.
- An opt-in `LiveStudioTests` run passed against the real API using the production AppModel and preview controller: create a counter, click Increment, request an edit adding Reset, verify Reset, retain one artifact, and roll back to the original HTML. Artifact `CF62D5B1-D86E-4CB8-A69F-58352CBED737`; result `/private/tmp/tether-live-miniapp-acceptance.xcresult`. No network client was replaced in that test.
- Native gateway protocol was verified on the Studio through the official same-user gateway client over authorized Tailscale SSH. Reading `chief-local` returned its existing eight messages. A scratch default-profile session accepted a prompt and completed with `TETHER-GATEWAY-VERIFIED` using oMLX. Session `local-62c58dfa395a55d2c3a2c1f1e59b45cbf54846ea4742931ddb38fc2619d05ee4`, admission `cc1af2b738e94386a6cbca94c50117cb`. No profiles were created or existing Bot Chats modified by that probe.
- The phone client now uses native PKCE tokens, current canonical session fields, same-socket resume before prompt/control, exact approval generation, and saved submission identities for unconfirmed delivery.
- Provider setup now uses **Providers → Add provider → Hermes → Tailscale URL + API token**. New providers use Tailscale HTTPS, existing connections migrate to the Hermes provider kind without changing server identity, and bot gateway sign-in is available under the selected provider’s settings.
- Final regression suite: 46 tests passed, one opt-in live test skipped, zero failures in `/private/tmp/tether-providers-tests-passed.xcresult`. The separate opt-in real-Studio mini-app test above passed. Coverage includes PKCE challenge/code exchange, callback-state rejection, saved submission identity, real mounted SwiftUI/WebKit preview, and CSP enforcement.
- **Still unverified:** authenticated bot conversation/control from the phone client. Both supplied dashboard passwords were rejected with HTTP 401; the second also failed verification against the configured password hash. No passwords were changed and no session was manufactured. A correct Hermes dashboard login is required to complete this acceptance.
- Physical-iPhone installation and background lifecycle acceptance remain unverified this pass. Simulator mini-app execution and native Studio protocol probes do not establish physical-phone bot approval/cancellation acceptance.


## Historical API-backed local catalog — 2026-11-23 (superseded)

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
