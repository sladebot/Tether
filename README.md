# HermesLink

HermesLink is a native SwiftUI harness for a self-hosted [Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server). It has two primary surfaces: streaming agent chat and isolated HTML mini apps built by the agent. It connects directly over your local network or through Tailscale.

The recommended connection is Hermes' application-facing API Server on port 8642, authenticated with `API_SERVER_KEY`. HermesLink stores the key in the iOS Keychain and binds it to the exact scheme, hostname, and port so it cannot silently follow an edited connection to another server.

Hermes Dashboard on port 9119 remains available as an advanced control-plane compatibility transport. For a gated Basic-auth dashboard, HermesLink exchanges the password once for signed access and refresh tokens, removes the password, stores the origin-bound tokens in Keychain, rotates them through `/auth/native/refresh`, and mints a fresh single-use ticket for each JSON-RPC and PTY WebSocket.

## Run

1. Open `HermesLink.xcodeproj` in Xcode 26 or newer.
2. Select the `HermesLink` scheme and an iPhone running iOS 18 or newer.
3. Build and run.
4. Add a **Hermes API Server** connection such as `http://192.168.1.20:8642` for LAN, or preferably an HTTPS Tailscale Serve URL such as `https://my-mac.tailnet-name.ts.net`.

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

Use the resulting `https://<machine>.<tailnet>.ts.net` origin in HermesLink. Keep Tailscale Funnel disabled and narrow the tailnet grant to the intended identity/device and HTTPS port.

If dashboard-only behavior is required, expose it separately rather than mixing it with the application API:

```sh
tailscale serve --bg --https=8443 http://127.0.0.1:9119
```

Set Hermes `dashboard.public_url` to that exact `https://...:8443` origin and enable Basic, Nous OAuth, or self-hosted OIDC. Basic is the simplest provider for a private tailnet.

## Included

- Multiple named LAN or Tailscale connection profiles
- Origin-bound API keys and dashboard sessions stored in Keychain (never `UserDefaults`)
- Hermes API Server verification through `/v1/capabilities`, with an older-server fallback to `/v1/models`
- Authenticated model discovery through `/v1/models`
- Automatic discovery of the model name advertised by each Hermes gateway
- Streaming chat through `/v1/chat/completions`
- Durable chat history stored separately for every connection profile
- A Mini Apps library with agent-driven generation, preview, and deletion
- One directory and a fresh non-persistent WebKit environment per mini app
- A restrictive Content Security Policy that blocks network, iframe, object, and form access
- Local-network privacy description and Bonjour service declaration
- Unit tests for endpoint normalization and SSE parsing

Chat history is stored locally per connection and the current conversation is sent with every request, matching Hermes' stateless Chat Completions endpoint.
