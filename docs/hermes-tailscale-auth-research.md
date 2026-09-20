# Hermes Authentication over Tailscale

## Executive conclusions

Hermes exposes two materially different application surfaces, and they should not be treated as one protocol:

1. The **API Server** is the stable, application-facing surface. It uses a static `API_SERVER_KEY` as an HTTP bearer token and exposes OpenAI-compatible chat, Responses, Runs, sessions, SSE streaming, capabilities, skills, and toolsets. For a purpose-built iOS chat client, this is the simplest and least brittle interface.^1
2. The **Web Dashboard** is an administrative and interactive management surface. In remote mode it has a fail-closed authentication gate with username/password, Nous Portal OAuth, self-hosted OIDC, and plugin-defined providers. Its chat UI relies on authenticated REST plus short-lived, single-use WebSocket tickets.^2

Tailscale adds authenticated device connectivity, WireGuard encryption, network access policy, MagicDNS, and—when using Tailscale Serve—tailnet-only HTTPS. It does **not**, by itself, satisfy Hermes' application authentication gate. Stock Hermes does not consume Tailscale Serve's identity headers as a dashboard login provider. A request therefore normally passes two independent checks:

```text
iPhone identity/device ── Tailscale policy ──► Mac Studio
App credential          ── Hermes auth     ──► Hermes operation
```

For Tether, the recommended design is:

- Use the **Hermes API Server over Tailscale Serve** for chat and agent runs.
- Store a high-entropy `API_SERVER_KEY` in the iOS Keychain.
- Keep Hermes and the API Server bound to `127.0.0.1`; let Tailscale Serve terminate HTTPS and proxy to loopback.
- Restrict the Serve endpoint to the intended Tailscale user/devices with tailnet grants.
- Use the **Dashboard on a separate Serve HTTPS port** only for functionality that truly requires dashboard APIs or its PTY/WebSocket protocol.
- If dashboard access is required now, use Hermes Basic auth behind Tailscale. Tether already implements a one-time password bootstrap followed by Keychain-held access/refresh tokens and one-use WebSocket tickets.

This gives a small attack surface, avoids public exposure, avoids embedding an OAuth browser, and separates an app data plane from the host-owner dashboard control plane.

## 1. Security boundaries that must remain separate

Hermes has several things called “auth,” but they protect different boundaries:

| Boundary | What it protects | Mechanism relevant to Tether |
|---|---|---|
| Tailscale network | Which tailnet identity/device can reach the Mac Studio service | Device/user identity, WireGuard, grants/ACLs |
| Hermes API Server | Chat, Responses, Runs, sessions, skills/toolsets | `Authorization: Bearer $API_SERVER_KEY` |
| Hermes Dashboard | Host administration, settings, secrets, session management, PTY/WebSockets | Basic, Nous OAuth, self-hosted OIDC, custom dashboard providers |
| Hermes model backend | Hermes-to-model traffic, such as Hermes calling OMLX | Provider-specific key or local trust; not an iOS credential |
| Messaging gateway | Telegram/Discord/etc. users and pairing | Platform credentials and allowlists; not the dashboard/API Server gate |

This distinction matters because a Tailscale login authenticates the device to the tailnet, while Hermes credentials authorize the resulting HTTP request to exercise a powerful agent. Likewise, the OMLX credential belongs between Hermes and OMLX; it should never be sent to Tether.

## 2. Hermes Web Dashboard authentication

### 2.1 Loopback mode

The default dashboard binds to `127.0.0.1:9119`. In that mode the remote authentication gate is off. The local SPA uses a process/session token injected into the page and sends it through the legacy dashboard-token path. This mode is intended for a browser on the same host, not as an app authentication scheme.^2

Publishing a loopback dashboard through a reverse proxy changes the security decision when `dashboard.public_url` is non-loopback. Hermes deliberately enables the gate even though its listening socket remains on loopback. This prevents the locally injected SPA token from becoming a remote credential.^3

### 2.2 Fail-closed gated mode

The dashboard gate engages when either:

- Hermes binds to a host other than `127.0.0.1`, `::1`, or `localhost`; or
- `dashboard.public_url` / `HERMES_DASHBOARD_PUBLIC_URL` declares a non-loopback public origin.

If the gate is engaged and no session provider registers successfully, Hermes refuses to start. The old `--insecure` flag is now a deprecated no-op and cannot bypass this rule.^2

The public bootstrap routes include `/api/status`, `/api/auth/providers`, the login/callback routes, password login, and native token/refresh routes. Protected API requests receive a structured 401 rather than being blindly redirected through an OAuth flow.^4

### 2.3 Bundled Basic username/password provider

The Basic provider is designed for self-hosted, on-premises, LAN, or VPN deployments. It supports one configured username/password pair, not independent users, MFA, roles, or a user database. Hermes recommends it behind a trusted network or VPN rather than directly on the public internet.^2

Security properties in the current implementation include:

- Password hashing with scrypt; `password_hash` is preferred so plaintext is not stored.
- Constant-time username/password comparison and a dummy scrypt verification for unknown usernames.
- A generic 401 response for wrong username and wrong password.
- A process-local rate limit of ten password attempts per client IP per minute.
- Stateless HMAC-SHA256-signed access and refresh tokens.
- A default 12-hour access token and 30-day refresh token.^5

The token-signing secret must be configured explicitly. If omitted, Hermes generates a new secret at process start, invalidating every existing session after each restart. A strong, stable secret allows sessions to survive dashboard restarts.^5

Browser flow:

```text
POST /auth/password-login
  { provider: "basic", username, password }
       │
       ├─ Set-Cookie: hermes_session_at=<access token>
       ├─ Set-Cookie: hermes_session_rt=<refresh token>
       └─ Set-Cookie: hermes_session_provider=basic
```

Native clients can use the access token as `Authorization: Bearer ...` because the gated middleware verifies bearer access tokens through the same provider stack used for cookies.^4 The refresh token can be rotated with `POST /auth/native/refresh`.

One current caveat is important: the Basic tokens are stateless. In the source snapshot reviewed, `revoke_session` does not revoke an individual issued token server-side; clearing the client credential does not invalidate a stolen copy before expiry. Rotating the signing secret invalidates all Basic sessions. This makes Tailscale containment, Keychain storage, TLS, and a high-entropy password/signing secret important.^5

### 2.4 Nous Research OAuth provider

The bundled `nous` provider uses the Nous Portal. The dashboard must first be registered to obtain a client ID shaped like `agent:<instance-id>`, normally with `hermes dashboard register`. Browser login uses authorization code plus PKCE. Hermes constructs `/auth/callback` from the public URL, exchanges the upstream code, verifies the Portal JWT, and creates a Hermes dashboard session.^3

The currently documented browser contract has a 15-minute access token and no refresh token in its v1 flow, causing a browser to repeat login when the token expires. The native-app broker can instead provide app-held access/refresh token behavior when the upstream provider supports it.^3

This is Hermes' preferred provider for an internet-facing dashboard, but a Tailscale-only deployment does not need public-internet exposure and can reasonably use Basic auth.

### 2.5 Self-hosted OIDC provider

Hermes includes a generic OpenID Connect provider for Authentik, Keycloak, Zitadel, Authelia, Auth0, Okta, and other conforming issuers. It uses OIDC discovery, authorization code with PKCE, issuer/audience/signature validation, and JWKS key discovery. It requires HTTPS except for explicit loopback endpoints. The default scopes are `openid profile email`, and supported ID-token algorithms include RS256/384/512 and ES256/384/512; HS256 is deliberately excluded.^6

Required configuration is:

- `HERMES_DASHBOARD_OIDC_ISSUER`
- `HERMES_DASHBOARD_OIDC_CLIENT_ID`
- Optional `HERMES_DASHBOARD_OIDC_SCOPES`
- Optional client secret for an IDP configured as a confidential client

This is the integration point for Tailscale's `tsidp`, discussed below.

### 2.6 Custom dashboard providers

Hermes exposes a plugin extension point for additional password or redirect-based session providers. A provider can implement login start/completion, access-token verification, refresh, and revocation. Multiple providers may be registered and presented on the same login page.^3

There is also a separate service-to-service bearer extension: a provider can opt into `supports_token` and mark particular routes as token-authable. The bundled drain provider uses this for a narrow gateway-drain operation. It is not a generic static token that grants access to all dashboard routes and should not be confused with the native session bearer path.^2

## 3. Dashboard session and transport protocol

### 3.1 Discovery

An app should begin with unauthenticated discovery:

```http
GET /api/status
GET /api/auth/providers
```

The useful fields are:

- `auth_required`
- `auth_providers`
- `auth_flows`, such as `cookie` and `native_pkce`
- provider metadata including `supports_password`

The app should not guess auth type from the URL or HTTP status alone.

### 3.2 Cookie sessions

The browser session uses HttpOnly cookies:

- `hermes_session_at`: access token, with Max-Age matching token lifetime
- `hermes_session_rt`: refresh token, when the provider issues one
- `hermes_session_provider`: non-secret routing hint
- `hermes_session_pkce`: temporary PKCE/CSRF state

On HTTPS at the root path, Hermes uses `__Host-` cookie-name hardening; behind a path prefix it uses `__Secure-`. Normal session cookies are `SameSite=Lax`. The cross-site PKCE cookie becomes `SameSite=None; Secure` over HTTPS.^7

### 3.3 Native bearer sessions

The gated middleware accepts a provider-issued access token on protected routes:

```http
Authorization: Bearer <access-token>
```

It verifies the token without server-side cookie refresh. The native client is responsible for refreshing through:

```http
POST /auth/native/refresh
Content-Type: application/json

{
  "refresh_token": "...",
  "provider": "basic"
}
```

Successful native token and refresh responses contain `access_token`, `refresh_token`, `token_type`, `expires_at`, `provider`, and `user_id`.^4

### 3.4 WebSocket authentication

The dashboard does not put the long-lived access token in a WebSocket URL. Instead, the app first makes an authenticated REST call:

```http
POST /api/auth/ws-ticket
Authorization: Bearer <access-token>
```

Hermes returns a random ticket with a 30-second TTL. The app immediately opens one WebSocket with `?ticket=<ticket>`. The ticket is consumed on first successful validation and cannot be reused. A reconnect must mint a fresh ticket.^8

This matters for Tether because `/api/ws` and `/api/pty` require separate fresh tickets. Reusing one ticket across both sockets or after a reconnect will fail by design.

## 4. Native OAuth and the iOS callback problem

Hermes implements an RFC 8252-style native broker:

1. The desktop app generates a PKCE verifier/challenge and starts a loopback HTTP listener.
2. It opens `/auth/native/authorize` in the system browser.
3. Hermes completes the upstream OAuth/OIDC login.
4. Hermes redirects to the app's loopback listener with a short-lived one-time gateway code.
5. The app redeems the code and verifier at `/auth/native/token` and stores the resulting bearer tokens in its OS keychain.^9

This is an excellent desktop design, but the current Hermes route validation accepts only literal `http://127.0.0.1:<port>/...` or `http://[::1]:<port>/...` native redirect URIs. It rejects `localhost`, custom schemes such as `hermeslink://`, and ordinary HTTPS universal-link callbacks.^4

Consequences for iOS:

- `ASWebAuthenticationSession` cannot complete the stock Hermes native flow through a Tether custom URL scheme.
- Opening the regular web login page in `ASWebAuthenticationSession` preserves browser cookies, but iOS deliberately does not hand those cookies to the app. Without a callback carrying a redeemable code, Tether cannot “take it from there.”
- A `WKWebView` can implement Hermes' legacy embedded-login fallback and retain a private cookie jar. This is viable for Basic auth but is inferior for OAuth: it loses the trusted system-browser experience and couples the app to cookie extraction/synchronization.
- A local HTTP listener on iOS could theoretically mimic the desktop loopback pattern, but app suspension, browser handoff, port lifetime, and App Store robustness make it a poor primary design.

The clean long-term fix is for Hermes' native broker to support pre-registered iOS redirect schemes or universal links, with exact redirect validation and PKCE retained. Until then, Basic password bootstrap or a static API Server key is more reliable.

## 5. Hermes API Server authentication

The API Server is distinct from port 9119. It defaults to `127.0.0.1:8642`, is enabled with `API_SERVER_ENABLED=true`, and always requires `API_SERVER_KEY`, including on loopback. Every protected request uses:

```http
Authorization: Bearer <API_SERVER_KEY>
```

It exposes the interfaces most useful to Tether:

- `POST /v1/chat/completions`, including SSE streaming
- `POST /v1/responses`, with server-side continuation
- Runs endpoints for long-running work, status, events, stop, steering, and approval
- Native session chat and SSE endpoints
- `/v1/capabilities`, `/v1/models`, `/v1/skills`, and `/v1/toolsets`

The key is a shared bearer secret. There is no user login, refresh token, MFA, or browser callback. Rotation is operational: generate a new key, update Hermes, and reprovision the app. Hermes warns that this key grants the full agent toolset, including terminal capabilities.^1

For a single-owner iOS app on a private tailnet, that simplicity is a strength. The Tailscale identity/grant restricts who can reach the endpoint; the API key remains defense in depth if a tailnet device or policy is compromised.

## 6. What Tailscale adds—and what it does not

### 6.1 Network and device authentication

Tailscale binds user identity to devices and cryptographically authenticates nodes using WireGuard keys. Tailnet policy can permit only a specific user, group, tagged device, protocol, or port. Modern Tailscale grants are deny-by-default and can also include device-posture requirements.^10

The iPhone must have the Tailscale app installed, signed into the same tailnet, and connected. Tailscale for iOS currently requires iOS 15 or later.^11

### 6.2 Tailscale Serve

Tailscale Serve can terminate HTTPS on a MagicDNS name such as:

```text
https://mac-studio.<tailnet>.ts.net
```

and proxy to an HTTP service bound only to `127.0.0.1`. The Tailscale daemon provisions the TLS certificate and keeps the service accessible only within the tailnet. `--bg` makes the Serve configuration persistent.^12

This is preferable to binding Hermes to `0.0.0.0` because LAN clients cannot bypass the Tailscale policy or TLS endpoint. Hermes itself remains reachable only from processes on the Mac Studio.

### 6.3 Identity headers

Serve injects headers including `Tailscale-User-Login`, `Tailscale-User-Name`, and `Tailscale-User-Profile-Pic` for tailnet user traffic, stripping inbound copies to prevent network clients from spoofing them. Tailscale recommends a loopback-only backend whenever those headers are trusted.^12

However, stock Hermes does not currently register a dashboard session provider that converts these headers into a Hermes session. Therefore:

- Tailscale identity headers do not suppress the Hermes login page.
- They do not satisfy `/api/auth/me`.
- They cannot mint a dashboard WebSocket ticket.
- A custom, security-reviewed Hermes provider or trusted-auth proxy would be required to make header identity the application login.

Tagged-node traffic also does not receive the user identity headers, which limits this pattern for machine-to-machine clients.^12

### 6.4 Tailscale `tsidp`

`tsidp` is an experimental OIDC/OAuth identity provider backed by Tailscale identity. An OIDC application redirects to `tsidp`; `tsidp` identifies the caller through Tailscale LocalAPI `whois` and returns standard ID/access tokens. Hermes' self-hosted OIDC provider is conceptually compatible with this.^13

This can produce a “Sign in with Tailscale” dashboard experience without another password prompt. It is not the simplest deployment:

- It requires tailnet Owner/Admin/Network-admin privileges.
- MagicDNS, HTTPS, and tailnet policy changes are required.
- The `tsidp` process needs durable state or restarts invalidate registrations and sessions.
- Tailscale labels it experimental and warns of breaking changes.
- Tether still faces the stock native callback restriction on iOS. A browser can log into the dashboard, but clean bearer-token handoff to the iOS app still needs Hermes callback support or an embedded cookie flow.^13

For this project, `tsidp` is a future SSO option rather than the immediate solution.

## 7. Deployment options

| Option | UX | Security | iOS complexity | Tether fit |
|---|---|---|---|---|
| API Server key + Tailscale Serve | Provision once; no repeated login | Strong for single-owner private tailnet; shared static secret | Low | **Best chat/data plane** |
| Dashboard Basic + Tailscale Serve | Enter password once; refresh automatically | Good behind tailnet; single shared identity | Medium | **Best current dashboard/PTY option** |
| Nous OAuth + Tailscale Serve | Familiar Portal login | Strong identity; short browser sessions | High until iOS callback supported | Future |
| Self-hosted OIDC + Tailscale Serve | Enterprise/SSO login | Strong if IDP configured correctly | High | Organizations already running an IDP |
| `tsidp` + Hermes OIDC | Near-zero-prompt Tailscale SSO | Promising, experimental | High; callback issue remains | Experimental |
| Trust Serve identity headers via custom provider | Seamless | Strong only with a loopback-only, carefully audited trust boundary | Very high/custom code | Not recommended initially |
| Direct LAN HTTP + Basic | Password login | No TLS; reachable on LAN | Low | Testing only |
| Tailscale Funnel | Public reachability | Expands exposure materially | Medium | Do not use for this private agent |

## 8. Recommended Tether architecture

### 8.1 Primary application plane

```text
Tether on iPhone
  ├─ Tailscale tunnel and tailnet grant
  ├─ HTTPS to mac-studio.<tailnet>.ts.net
  ├─ Authorization: Bearer <API_SERVER_KEY from Keychain>
  └─ POST /v1/responses or /v1/runs
                 │
         Tailscale Serve :443
                 │
         http://127.0.0.1:8642
                 │
          Hermes API Server
                 │
          Hermes agent → OMLX
```

Use `/v1/responses` for ordinary multi-turn chat or `/v1/runs` when Tether needs reconnectable, long-running jobs and progress events. Give each app conversation a stable Hermes session or conversation identifier. Mini-app generation should use a strict application-level envelope that returns the complete isolated HTML plus metadata; treat generated HTML as untrusted and continue rendering it in a nonpersistent `WKWebView` with network-denying CSP.

### 8.2 Optional dashboard plane

Expose the dashboard on a second Serve HTTPS port and keep Hermes bound to loopback:

```text
https://mac-studio.<tailnet>.ts.net:8443
                 │
         Tailscale Serve :8443
                 │
         http://127.0.0.1:9119
                 │
      Hermes dashboard auth gate
```

Set `dashboard.public_url` to that exact HTTPS origin and configure Basic auth with a scrypt password hash plus a stable random signing secret. Hermes requires this provider even though the backend socket is loopback, because the public URL is remote.^3

Tether's dashboard flow should remain:

1. Read `/api/status` and `/api/auth/providers`.
2. If Basic is advertised and no valid Keychain session exists, POST username/password once.
3. Persist access token, refresh token, provider, expiry, and exact origin in Keychain.
4. Remove the bootstrap password after successful token capture.
5. Send the access token as Bearer for REST.
6. Refresh shortly before expiry with `/auth/native/refresh`.
7. Mint a separate one-use WebSocket ticket for every `/api/ws` and `/api/pty` connection and reconnect.
8. Delete tokens whenever the origin changes; never replay a credential to a different host.

The current Tether implementation already follows this pattern. It should be considered a dashboard compatibility transport, not the preferred general chat API.

## 9. Configuration blueprint

The Hermes process should continue running as the dedicated non-sudo user. Its own home contains Hermes configuration and credentials. OMLX continues under the current sudo-capable user and listens only where the Hermes process can reach it. No Hermes credential needs to grant the app access to OMLX directly.

### Hermes API Server

In the non-sudo Hermes user's protected environment/configuration:

```dotenv
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8642
API_SERVER_KEY=<at least 32 random bytes, generated securely>
```

Start/restart `hermes gateway`, then proxy loopback port 8642 with Tailscale Serve. Do not place the key in source code, `Info.plist`, screenshots, logs, or a QR code that remains stored in Photos. Provision it into Keychain once and redact it from diagnostics.

### Hermes Dashboard

Prefer `config.yaml` for non-secret structure and the non-sudo user's protected `.env` for secrets:

```yaml
dashboard:
  public_url: "https://mac-studio.<tailnet>.ts.net:8443"
  basic_auth:
    username: admin
    password_hash: "scrypt$..."
    secret: "<stable random signing secret>"
    session_ttl_seconds: 43200
```

Then run the dashboard on loopback:

```text
hermes dashboard --host 127.0.0.1 --port 9119 --no-open
```

The exact Tailscale Serve syntax should be confirmed against `tailscale serve --help` on the Mac Studio because the CLI has changed across releases. Current documentation supports `--https=<port>`, a loopback proxy target, and `--bg` persistence.^12

### Tailnet policy

Use a narrow grant permitting only the intended identity/device to the Serve HTTPS port(s). Do not leave the default allow-all tailnet policy merely because the service also has an application key. Tailscale grants can restrict destination, TCP port, user/group, and device posture.^10

## 10. Verification checklist

Network layer:

- Hermes and API Server listen only on `127.0.0.1`.
- Direct LAN requests to ports 9119/8642 fail.
- The Tailscale HTTPS hostname works from the iPhone with Tailscale connected.
- The same hostname is unreachable when Tailscale is disconnected.
- Tailnet policy denies an unauthorized tailnet identity/device.
- Funnel is off.

API Server:

- `/health` responds through Serve.
- Protected endpoints return 401 without the API key and succeed with it.
- Chat SSE survives normal network changes and reconnect logic does not duplicate a run.
- Key rotation causes the old app credential to fail.

Dashboard:

- `/api/status` reports `auth_required: true` and the expected provider.
- `/api/auth/me` rejects no credential and accepts the issued bearer token.
- Restarting Hermes does not invalidate Basic sessions when the stable signing secret is unchanged.
- Expired access tokens refresh through `/auth/native/refresh`.
- Every WebSocket uses a newly minted ticket; ticket replay fails.
- Changing the saved base URL clears origin-bound tokens.

iOS storage and UI:

- All API/dashboard credentials use Keychain with device-only accessibility.
- Secrets never enter UserDefaults, SwiftData, logs, crash reports, mini-app HTML, or screenshots.
- Authentication errors distinguish unreachable service, Tailscale disconnected, 401/expired session, and unsupported provider.
- Mini-app webviews cannot read app credentials and have no shared persistent cookie/data store.

## 11. Decision

For the current Mac Studio + iPhone + private tailnet setup, the strongest practical choice is not full browser SSO. It is **Tailscale Serve plus two narrowly separated Hermes credentials**:

- `API_SERVER_KEY` for the Tether chat/agent API.
- Dashboard Basic access/refresh tokens only if Tether must use dashboard-only functions.

This avoids exposing Hermes on the LAN, keeps the non-sudo sandbox intact, gives HTTPS without managing certificates, and gives the app a protocol designed for native API consumers. `tsidp` becomes attractive after Hermes supports an iOS-compatible registered callback or if Tether intentionally adopts a cookie-based embedded login flow.

## Sources

1. Nous Research, [Hermes Agent API Server](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/api-server.md), accessed September 2026.
2. Nous Research, [Hermes Web Dashboard: authentication and remote setup](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md), accessed September 2026.
3. Nous Research, [Hermes Web Dashboard: public URL, reverse proxy, OAuth, and Tailscale Serve](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md#public-url-override), accessed September 2026.
4. Nous Research, [Dashboard authentication routes and middleware](https://github.com/NousResearch/hermes-agent/tree/main/hermes_cli/dashboard_auth), accessed September 2026.
5. Nous Research, [Basic dashboard authentication provider](https://github.com/NousResearch/hermes-agent/blob/main/plugins/dashboard_auth/basic/__init__.py), accessed September 2026.
6. Nous Research, [Self-hosted OIDC dashboard provider](https://github.com/NousResearch/hermes-agent/blob/main/plugins/dashboard_auth/self_hosted/__init__.py), accessed September 2026.
7. Nous Research, [Dashboard authentication cookie implementation](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/dashboard_auth/cookies.py), accessed September 2026.
8. Nous Research, [Dashboard WebSocket ticket implementation](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/dashboard_auth/ws_tickets.py), accessed September 2026.
9. Nous Research, [Desktop Native Sign-In (RFC 8252)](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/desktop-native-signin.md), accessed September 2026.
10. Tailscale, [Grants](https://tailscale.com/docs/features/access-control/grants) and [grant examples](https://tailscale.com/docs/reference/examples/grants), validated 2026.
11. Tailscale, [Tailscale for iOS](https://tailscale.com/download/ios), accessed September 2026.
12. Tailscale, [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) and [Serve CLI reference](https://tailscale.com/docs/reference/tailscale-cli/serve), validated 2026.
13. Tailscale, [`tsidp`](https://tailscale.com/docs/features/tsidp) and [`tsidp` configuration](https://tailscale.com/docs/reference/tsidp-configuration), validated March 2026.
