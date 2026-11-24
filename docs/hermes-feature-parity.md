# Hermes → Tether feature inventory and implementation backlog

Baseline: 2026-09-16, installed Hermes 0.21.2, Tether source following commit 46496fa.
This is a feature-family inventory, not a claim that every provider, plugin, slash
command, or upstream release is supported. Extensions make an absolute fixed list
impossible. Installed CLI help, live API capabilities, and app source are the
authority for the current setup; current upstream docs may describe newer features.

## Evidence and status rules

- **Client**: implementation found in Tether; not automatically phone-verified.
- **Partial**: some client surface exists, with an important missing part.
- **Agent**: potentially usable through Hermes chat if tools/providers are configured;
  not a native mobile feature, and not claimed tested.
- **Gap**: no native implementation located.
- **Server**: operational functionality; needs an explicit authenticated management
  contract and appropriate authorization, not arbitrary command execution from UI.
- A feature is complete only after its intended phone workflow passes live tests.

Source anchors: `Tether/Services/HermesAPIClient.swift`, `Tether/App/AppModel.swift`,
`Tether/Views/ChatView.swift`, `Tether/Views/MiniAppsView.swift`,
`Tether/Services/ConnectionStore.swift`, and installed `hermes --help`.

## Conversation and execution

| Feature | Tether status | Remaining acceptance / implementation |
|---|---|---|
| Text chat and streaming | Client | Phone sends and receives a real guest model reply |
| Model/provider discovery and selection | Client | Verify selection on phone and provider failures |
| Reasoning controls | Gap | Discover supported controls; persist per run |
| Durable task submission/status/events | Client | Observe accepted run and terminal reconciliation |
| Idempotent retry | Client | Force-close/network ambiguity; prove one server run |
| Stop and steering | Client | Live stop/steer with truthful terminal state |
| Command approvals | Client | Recover pending approval and deny safely |
| Tool/subagent timeline | Client | Match server events; avoid implying child control |
| Local conversation history | Client | Preserve history across connection changes/restart |
| Server session list/search/import | Gap | Reconcile remote sessions, pagination and ownership |
| Server session rename/delete/fork | Gap | Explicit actions, confirmation, lineage preservation |
| Server session model locking | Gap | Respect remote lock in model picker |
| Context compression/cache/usage visibility | Partial | Backend automatic behavior; no complete diagnostics UI |
| Context file/folder/diff/URL references | Gap | Structured reference picker and scoped server resolution |
| Persistent goals | Agent / Gap | Goal status, progress and stop/resume controls |
| Delegation and parallel agents | Partial | Timeline exists; no dedicated child-task management |
| Mixture-of-Agents presets | Partial | May appear in model discovery; configuration absent |

## Tools, knowledge and integrations

| Feature | Tether status | Remaining acceptance / implementation |
|---|---|---|
| Tool/toolset discovery and selection | Gap | Read advertised catalog; enforce per-session selection |
| Tool search | Agent | Show selected tools and failures clearly |
| Terminal/code execution | Agent | No native authenticated terminal/file workspace |
| Files: read/write/patch/search | Agent | Scoped browser, previews and explicit destructive actions |
| Web search/extraction | Agent | Verify configured provider and render cited results |
| Browser automation | Agent | Progress/artifacts; live guest-only browser controls absent |
| Desktop computer use | Agent | Guest driver previously tested; mobile visual workflow absent |
| Skills browse/read/invoke | Gap | Installed server advertises skills API; add native catalog |
| Skills create/edit/install/sync/bundles/curation | Server / Gap | Versioned edits, install approval and provenance |
| Memory read/search/edit | Agent / Gap | Memory inspector/editor; live write API disabled |
| External memory providers / graph | Server / Gap | Provider-aware status; no blanket enablement |
| Personality and context files | Server / Gap | Scoped SOUL/USER/project-context editor |
| MCP discovery/OAuth/tool configuration | Server / Gap | Connection status and explicit credential/permission flow |
| Plugins/catalog/lifecycle hooks | Server / Gap | Install review, enable/disable, failure status |
| Credential vault / secret sources | Server / Gap | Never show raw secrets; dedicated authorization UX |
| Tool Gateway / external services | Server / Gap | Configuration/entitlements vary; no automatic paid setup |
| Project/workspace/worktree management | Server / Gap | Guest-scoped selection; do not expose host workspaces |
| Semantic diagnostics/LSP | Agent / Gap | Diagnostics presentation and server configuration |

## Media and deliverables

| Feature | Tether status | Remaining acceptance / implementation |
|---|---|---|
| Image input / vision | Gap | Photo/file picker, supported payloads, size limits |
| General file input / document extraction | Gap | Verify upload contract; do not send unsupported file parts |
| Generated artifact download/preview/share | Gap | Authenticated download, MIME validation, safe preview |
| Image generation | Agent / Gap | Provider setup plus native result display/save |
| Transcription and speech synthesis | Gap | Live `audio_api` is false; capability-gated controls |
| Realtime voice | Gap | Live voice flags false; transport, interruptions and permissions |
| Wake-word interaction | Server / Gap | Not equivalent to unrestricted iOS background listening |
| Mini-app generation and isolated preview | Client | Tether-specific feature; verify physical-phone generation |
| Mini-app edit/recovery/rollback | Client | Close/reopen during build/edit; one artifact/revision |

## Automation and administration

| Feature | Tether status | Remaining acceptance / implementation |
|---|---|---|
| Cron schedules | Agent / Gap | List/create/pause/history with timezone-aware UI |
| Session heartbeats / recurring loops | Agent / Gap | Session-bound controls and truthful idle/active status |
| Kanban and worker lanes | Server / Gap | Board, assignment, lifecycle and multi-gateway ownership |
| Named bots/profiles/group coordination | Partial | Live Studio roster and canonical Bot Chat client; native phone gateway sign-in/control acceptance awaits valid dashboard credentials. Group coordination has no dedicated UI. |
| Webhooks / peer agent messaging | Server / Gap | Subscription management and explicit external-send consent |
| Messaging adapters and pairing | Server / Gap | Platform registry/status; separate account authorization |
| Batch/trajectory export/research workflows | Server / Gap | Submission/status/export contract needed |
| Gateway lifecycle / emergency pause | Server / Gap | Separate management permission; preserve active work |
| Config/default models/fallback/credential pools | Server / Gap | Live config-write API disabled; safe typed controls |
| Logs/readiness/monitoring/insights | Partial | Connection checks exist; operational console absent |
| Backup/restore/checkpoints | Server / Gap | Guest-only scope, progress, restore confirmations |
| Security audit/approval policy/egress/backends | Server | Deferred hardening; not implicitly authorized by parity |
| Update/migrate/uninstall/import | Server | Review destructive/admin actions; no host credential import |
| Themes/skins/mascots | Gap | Optional mobile equivalents; terminal appearance is not reusable UI |
| CLI/TUI/desktop/dashboard/ACP/library/proxy | Server | Alternate interfaces/integration modes, not phone screens |
| Multiple endpoints and origin-bound credentials | Client | Existing profiles preserved; verify migration on phone |
| Live feature availability | New client UI | Advanced connection details → Hermes feature availability |

Messaging/provider/plugin lists are dynamic. Show a server-discovered registry
rather than hardcoding a promise that every upstream adapter is configured.

## Live API limitations observed

The guest advertises durable runs, approval/steer/stop, session resources, model
options and skills. It reports config writes, jobs administration, memory writes,
audio and realtime voice disabled. Native UI cannot make a disabled API exist.
No flags, provider credentials, network policy, or admin permissions were changed
for this inventory. API-advertised support is not an end-to-end test result.

## Implementation sequence and definition of done

1. **Visibility:** ship live feature report and this inventory. Explicitly distinguish
   unavailable, unknown, missing UI, and implemented-but-unverified.
2. **Finish current phone acceptance:** real chat, model selection, approvals,
   steer/stop, mini-app generation/edit, force-close recovery and duplicate checks.
3. **Read-only workspace:** server sessions, skills, toolsets, run/artifact history.
   Add endpoint contract tests, pagination, auth-expiry and stale-origin tests.
4. **Interaction:** session fork/model lock, attachments, artifact preview, guest
   computer-use presentation. Verify media-specific formats before transmission.
5. **Knowledge and automation:** memory, skill editing, schedules, goals, bots and
   kanban. Requires actual supported endpoints and explicit write permissions.
6. **Administration and optional media:** configuration/MCP/plugins/providers,
   voice, backups and operations. Do not weaken protections or add paid services
   just to turn a status green; request missing authority when needed.

For every row: define a concrete phone action, add API/model/UI tests, check failure
states and credential isolation, then record physical-phone + guest evidence.
Do not replace missing functionality with a button that merely sends a vague prompt.
Do not label the full parity task complete until all requested applicable rows have
working implementations or a user-approved explicit exclusion.

## Upstream references

- [Hermes overview](https://hermes-agent.nousresearch.com/docs/)
- [Documentation index](https://hermes-agent.nousresearch.com/docs/llms.txt)
- [Application API](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server)
- Installed guest CLI help and live `/v1/capabilities`, checked 2026-09-16.
