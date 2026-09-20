# Tether

Tether is a native SwiftUI harness for a self-hosted [Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server). It has two primary surfaces: streaming agent chat and isolated HTML mini apps built by the agent. It connects directly over your local network or through Tailscale.

The recommended connection is Hermes' application-facing API Server on port 8642, authenticated with `API_SERVER_KEY`. Tether stores the key in the iOS Keychain and binds it to the exact scheme, hostname, and port so it cannot silently follow an edited connection to another server.

Hermes Dashboard on port 9119 remains available as an advanced control-plane compatibility transport. For a gated Basic-auth dashboard, Tether exchanges the password once for signed access and refresh tokens, removes the password, stores the origin-bound tokens in Keychain, rotates them through `/auth/native/refresh`, and mints a fresh single-use ticket for each JSON-RPC and PTY WebSocket.

## Run

1. Open `Tether.xcodeproj` in Xcode 26 or newer.
2. Select the `Tether` scheme and an iPhone running iOS 18 or newer. The app appears on the device as `Tether Flow`; its Xcode product is `Tether` with bundle identifier `app.tether.ios`.

For development-device bootstrap without hardcoding a secret, launch a Debug build with `TETHER_API_URL` and `TETHER_API_TOKEN` environment variables. Tether imports the token once into its origin-bound Keychain record; Release builds do not read this bootstrap environment.
3. Build and run.
4. Add a **Hermes API Server** connection such as `http://192.168.1.20:8642` for LAN, or preferably an HTTPS Tailscale Serve URL such as `https://my-mac.tailnet-name.ts.net`.

## Tether Host for macOS

The shared `Tether Host` scheme builds the first read-only macOS companion
milestone. It enumerates UTM through `utmctl`, displays exact VM UUIDs and
duplicate-name warnings, and keeps isolation unknown until fresh evidence from
an accepted source exists. Management controls remain disabled in this build;
it does not change the VM, firewall, Tailscale, or credentials.

Core safety contracts and tests are in `TetherHost/`. Run them with:

```sh
cd TetherHost
swift test
```

See `docs/tether-host-architecture.md` for the threat model and phased release
gates, and `docs/tether-host-distribution.md` for the Developer ID/notarization
pipeline scaffold.

On the Hermes host, enable the API server. For Tailscale Serve, keep it bound to loopback:

```dotenv
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8642
API_SERVER_KEY=replace-with-a-strong-key
```

Then run `hermes gateway` and expose only the loopback listener through Tailscale Serve:

```sh
tailscale serve --bg --https=443 http://127.0.0.1:8642
```

Use the resulting `https://<machine>.<tailnet>.ts.net` origin in Tether. Keep Tailscale Funnel disabled and narrow the tailnet grant to the intended identity/device and HTTPS port.

If dashboard-only behavior is required, expose it separately rather than mixing it with the application API:

```sh
tailscale serve --bg --https=8443 http://127.0.0.1:9119
```

Set Hermes `dashboard.public_url` to that exact `https://...:8443` origin and enable Basic, Nous OAuth, or self-hosted OIDC. Basic is the simplest provider for a private tailnet.

## Included

- Multiple named LAN or Tailscale connection profiles
- Origin-bound API keys and dashboard sessions stored in Keychain (never `UserDefaults`)
- Hermes API Server verification through `/v1/capabilities`, requiring durable run support (older incompatible servers are rejected)
- Live server feature availability under connection details, separating advertised capabilities from native app coverage
- Rich model/provider discovery through `/api/model/options`, with searchable per-conversation model selection
- Resumable server-side chat through `/v1/runs`, including durable idempotency keys and Hermes session continuity
- Automatic recovery after force-close, suspension, or network loss without duplicate run submission
- Short iOS background execution grace plus continued server-side execution while Tether is suspended
- Multiple locally persisted conversations per connection, available from the conversation drawer
- Collapsible tool and sub-agent progress timelines, stop control, and native approval actions
- A Mini Apps library with agent-driven generation, preview, and deletion
- One directory and a fresh non-persistent WebKit environment per mini app
- A restrictive Content Security Policy that blocks network, iframe, object, and form access
- Local-network privacy description and Bonjour service declaration
- Unit tests for endpoint normalization, authentication, model discovery, idempotent run submission, and SSE event parsing

Hermes continues an accepted `/v1/runs` task on the server when iOS suspends or terminates Tether. The app persists its run ID and reconciles the authoritative result when it can run again. iOS does not permit arbitrary apps to hold a network stream indefinitely in the background; this server-side handoff is what makes long-running work reliable.

## Hermes feature parity

See [the feature inventory and implementation backlog](docs/hermes-feature-parity.md)
for current coverage, missing mobile workflows, server-only administration, and
the acceptance criteria. Tether does not yet implement every Hermes feature.
