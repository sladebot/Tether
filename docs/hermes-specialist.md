# Hermes specialist: Agenty integration reference

Verified September 12, 2026. This document is the working reference for the Hermes specialist subagent. Prefer the running server's capability response over assumptions based on dashboard features or upstream documentation. Recheck after Hermes upgrades.

## Evidence and live deployment

Read-only probes against `http://127.0.0.1:8642` returned Hermes **0.21.0**, successful health/readiness, and authenticated capabilities. `/v1/capabilities` returned **401 without authentication** and succeeded with the token loaded into an environment variable from `~/hermes_token`. No token contents were printed or committed.

The configured Tailscale hostname `souranils-mac-studio.tail4a305f.ts.net` failed DNS resolution from this Mac during this audit. That is a connectivity finding, not an API-token failure. The loopback server remained healthy. Phone connectivity and the final Tailscale repair require separate verification.

The dedicated Hermes account's source directory was inaccessible under its filesystem permissions. This audit did not bypass that isolation or modify backend settings. Implementation details below reference public upstream source; they are not a claim that the installed checkout matches upstream byte for byte.

## Live capability map

These rows come directly from authenticated discovery on this installation. “Advertised” means the endpoint/feature was discovered, not that a mutating operation was executed.

| Capability | API | Installation |
|---|---|---|
| Submit long-running work | `POST /v1/runs` | Advertised |
| Recover result and status | `GET /v1/runs/{id}` | Advertised |
| Agent progress | `GET /v1/runs/{id}/events` | Advertised SSE |
| Stop / steer / approvals | `POST /v1/runs/{id}/stop`, `/steer`, `/approval` | All advertised |
| Duplicate-safe admission | `Idempotency-Key` | Durable; retention 86,400 seconds |
| Models | `GET /v1/models`, `GET /api/model/options` | Rich options verified |
| Sessions | `GET/POST /api/sessions`; `GET/PATCH/DELETE /api/sessions/{id}` | Advertised |
| History and branches | `GET /api/sessions/{id}/messages`; `POST .../fork` | Advertised |
| Session model lock | `POST /api/sessions/{id}/model` | Advertised; payload not tested |
| Session turns | `POST /api/sessions/{id}/chat`, `/chat/stream` | Advertised |
| Tool and skill discovery | `GET /v1/toolsets`, `/v1/skills` | Advertised |
| OpenAI-compatible entry points | `POST /v1/chat/completions`, `/v1/responses` | Advertised with streaming |
| Browser controller | Registration and WebSocket endpoints | Feature disabled |
| Audio / realtime voice | — | Explicitly false |
| Memory write / configuration write | — | Explicitly false |
| Scheduled jobs administration | — | `jobs_admin: false`; do not expose based on upstream docs alone |

The runtime reports `server_agent`, server-side tool execution, and no split runtime. Agenty talks to Hermes; Hermes owns model credentials and performs tools on its host. An app connection does not provide a separate sandbox for terminal tools.

## Async contract and important limits

Upstream run handlers maintain execution independently of the SSE connection. Disconnect cleanup removes transport state, so a later events request may return 404 while status polling still works. Poll status after reconnect and use final `output` as authoritative. `waiting_for_approval` includes an `approval` event with command, choices and request ID. A restarted gateway marks orphaned durable work `interrupted`; durability of admission does not mean execution resumes after a server crash. Steering accepts `{"input":"guidance"}` while running and rejects incompatible states with 409. It is not safe to retry steering automatically after an ambiguous transport failure. [Run handlers](https://github.com/NousResearch/hermes-agent/blob/main/gateway/platforms/api_server_runs.py)

Run creation should persist its exact body and unguessable idempotency key before transmission. Identical retries reuse the original run; a changed body conflicts. Retention is bounded. Never change model/history while retrying the same key. [Idempotency storage](https://github.com/NousResearch/hermes-agent/blob/main/gateway/platforms/api_server_run_idempotency.py)

Recommended Agenty lifecycle:

1. Persist job ID, origin/profile, complete request, key, and submission time.
2. Submit; persist accepted run ID before reporting server execution.
3. Show the build in the library so its form can close immediately.
4. On app launch or network recovery, poll known run IDs; retry uncertain submissions with the exact saved key/body.
5. Surface approval from status, not exclusively from stream events. Send only a server-offered choice and the exact request ID when available.
6. Atomically save validated HTML under the job's stable artifact ID before marking completed.
7. Treat server interruption, expiration, authentication failure and temporary network loss as distinct states. Never silently restart a missing job with a fresh key.

These are app design recommendations. They do not claim unlimited iOS background execution or an APNs completion service. A job cannot run on Hermes until submission reaches the server.

## Models, sessions and delegation

The live model inventory showed authenticated Nous (52), Anthropic (11), OpenAI Codex subscription (8), Mixture of Agents (1), OpenCode Free (7), and `custom:omlx` (9). Counts are a snapshot, not a guarantee every model call succeeds. Use provider slug plus model ID; keep model credentials on Hermes.

Upstream documents richer options, per-request model/provider selection, and request-scoped reasoning settings. Session overrides can take precedence. It also distinguishes detached delegation using server session history from requests supplying their own history; late child results can be read through session messages. Subagent lifecycle events are available, but detailed child tool events are intentionally excluded. [API guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/api-server.md)

At audit time Agenty's `createRun` sends `conversation_history`. Before enabling detached child-result UX, decide deliberately whether to adopt authoritative server history and reconcile `/api/sessions/{id}/messages`. Do not promise late child results will appear in a client-owned history snapshot automatically.

## Auth and Tailscale operation

Retain the existing architecture documented in [the authentication research](hermes-tailscale-auth-research.md): Hermes under the non-sudo account; loopback API Server; Tailscale Serve HTTPS; origin-bound bearer credential in Keychain. Tailscale supplies network access; the API Server separately verifies the bearer key. Dashboard authentication is a different surface and is unnecessary for these advertised application APIs.

Connection diagnostics should distinguish hostname lookup, route/VPN availability, TLS, HTTP 401, and backend readiness. A successful public health request alone does not validate the credential. Never follow credential-bearing requests to another origin, silently downgrade to LAN HTTP, or send the Hermes key into mini-app HTML. Do not rotate the key to address a DNS failure.

## Mini apps and next integrations

No dedicated mini-app generation API appears in the live discovery response. HTML generation is an Agenty workflow built on agent runs. Validation, storage, preview isolation and the library remain Agenty responsibilities; generated HTML is untrusted.

Highest-value next integrations are approval recovery, steering, server conversation history/forking, and a read-only skills/toolsets browser. Model reasoning controls should follow capability discovery. Scheduled jobs, voice, memory editing and browser control need additional verified support rather than UI promises.

## Service additions from this audit

`HermesAPIClient.steerRun(_:input:)` validates server acknowledgement and surfaces conflicts. `RunStatus.approval` decodes the recoverable pending approval. `HermesRunEvent.requestID` and optional `resolveApproval(..., requestID:)` support precise approval resolution. Focused tests cover steering success/conflict and approval recovery without SSE. The main agent integrates and runs the full build/test pass.
