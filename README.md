# Tether Flow for iPhone

Tether Flow is the native SwiftUI iPhone companion to [Tether Host for Mac](https://github.com/sladebot/Tether-Host). The host app creates and manages an isolated macOS guest, installs and verifies Hermes inside that guest, and produces a private connection for the phone. Tether Flow uses that connection for streaming agent chat and isolated HTML mini apps built by the agent.

The recommended connection is Hermes' application-facing API Server on port 8642, authenticated with `API_SERVER_KEY`. Tether stores the key in the iOS Keychain and binds it to the exact scheme, hostname, and port so it cannot silently follow an edited connection to another server.

Hermes Dashboard on port 9119 remains available as an advanced control-plane compatibility transport. For a gated Basic-auth dashboard, Tether exchanges the password once for signed access and refresh tokens, removes the password, stores the origin-bound tokens in Keychain, rotates them through `/auth/native/refresh`, and mints a fresh single-use ticket for each JSON-RPC and PTY WebSocket.

## How the two apps fit together

1. **Tether Host for Mac** creates or adopts a macOS VM, then runs the guest-only Tailscale and Hermes setup.
2. The guest keeps Hermes bound to `127.0.0.1:8642` and exposes it through tailnet-only Tailscale Serve HTTPS. Tailscale Funnel remains disabled.
3. Tether Host verifies the guest endpoint and presents its Tailscale URL and Hermes API token for the phone.
4. **Tether Flow** adds those values as a **Hermes API Server** connection, verifies `/v1/capabilities`, and stores the token in an origin-bound iOS Keychain record.
5. Accepted work continues as a durable Hermes run inside the guest. The phone can suspend or disconnect and reconcile the same run later without resubmitting it.

The VM is the agent-compute and computer-use boundary. Tether Flow never needs the physical Mac's Hermes credentials, model-provider credentials, VM files, or host administration access. A successful check in Tether Host does not replace the phone's own **Test Connection** check because the iPhone must independently reach the guest through the same tailnet.

Source is split by responsibility:

- This repository contains the iOS app, mobile Keychain handling, chat/run UI, and mini-app sandbox.
- [sladebot/Tether-Host](https://github.com/sladebot/Tether-Host) contains the macOS host app, VM lifecycle, guest installer, connection handoff, and host-side verification.

## Run the iOS app

1. Open `Tether.xcodeproj` in Xcode 26 or newer.
2. Select the `Tether` scheme and an iPhone running iOS 18 or newer. The app appears on the device as `Tether Flow`; its Xcode product is `Tether` with bundle identifier `app.tetherflow.ios`.
3. Build and run.
4. Complete guest setup in Tether Host for Mac and verify the connection there.
5. On the iPhone, join the same tailnet. Add a **Hermes API Server** connection with the verified Tailscale URL and Hermes token, then tap **Test Connection**.

For development-device bootstrap without hardcoding a secret, launch a Debug build with `TETHER_API_URL` and `TETHER_API_TOKEN` environment variables. Tether imports the token once into its origin-bound Keychain record; Release builds do not read this bootstrap environment.

## Manual Hermes setup

Tether Host is the recommended setup path. To connect Tether Flow to an existing Hermes installation without the host app, configure the application-facing API Server directly. A LAN URL such as `http://192.168.1.20:8642` works for development, but Tailscale Serve HTTPS is preferred.

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
