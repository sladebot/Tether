# Tether Flow for iPhone

Native iPhone chat, Hermes bots, and mini apps connected to your Mac Studio over Tailscale. All agent and model execution happens in Hermes on that Mac, including its local oMLX model and any providers configured in Hermes. There are no independent OpenAI or Claude account connectors and no phone-created bot catalog.

## Providers

Open **Providers → Add provider → Hermes**, enter your Tailscale URL and API token, then save. Hermes is the only connector currently available. Each saved provider has its own server identity and conversations; models offered inside Hermes are still discovered from that server.

The current Mac Studio exposes two Hermes services on its private tailnet:

| Purpose | Endpoint | Authentication |
| --- | --- | --- |
| Chat and mini-app generation | `https://souranils-mac-studio.tail4a305f.ts.net` | Hermes API key |
| Configured bots and their conversations | `https://souranils-mac-studio.tail4a305f.ts.net:9119` | Hermes dashboard account |

These are services on the same Mac Studio. The iPhone must be connected to the same tailnet. The API key is saved in origin-bound iOS Keychain storage. Bot sign-in exchanges the dashboard username/password through Hermes’ native PKCE flow and saves native access/refresh tokens in Keychain.

## Using the app

- **Home:** connection details and shortcuts to chat, Hermes bots, and mini apps.
- **Agent:** native conversations with models discovered from Hermes, tool progress, approvals, steering, and stop controls.
- **Bots:** the real profiles reported by the Studio’s Hermes gateway. Sign in to open their existing Bot Chat conversations, change a profile’s model, or create a real profile on the Studio. Model changes affect that Hermes profile. Each profile can use a different provider/model configured on the server.
- **Activity:** search past conversations and return to work in progress.
- **Spaces:** create an HTML mini app using the Hermes default or a selected server model, preview it, request edits, and roll back a version. Edits retain the originating connection and model.

Tap the half-filled circle in Agent to choose White, Black, or System. [Explore the agent and Spaces walkthrough](screenshots/workflow.html).

The bot roster can show names from Hermes’ public status endpoint before sign-in. This does not grant access to conversations or model settings. Tether does not replace a failed gateway request with sample bots or invented history. Earlier builds’ phone-created bot definitions are no longer used; their on-disk files are left untouched.

Accepted work runs on the Mac after the phone disconnects. Reopening a bot reads its server-owned conversation, current activity, and approval prompts. Unconfirmed message delivery is saved before submission; an explicit retry uses the original submission identity. Mini-app builds preserve their run ID and duplicate-protection window across reconnection. Failed builds retain the server’s explanation instead of reporting success.

Mini-app HTML executes in an isolated, nonpersistent WebKit preview on the iPhone; this is the frontend, not a local model or agent. Network access, frames, objects, forms, and file navigation are blocked. Generated HTML is saved on the phone for preview. No recurring routines or APNs completion notifications are implemented.

## Build and connect

1. Open `Tether.xcodeproj` in Xcode 26 or newer and select the `Tether` scheme.
2. Build for an iPhone running iOS 18 or newer. The bundle identifier is `app.tetherflow.ios`.
3. Join the same tailnet on the iPhone.
4. Open **Providers → Add provider → Hermes**, enter the Studio’s Tailscale HTTPS URL and current API token, then test and save.
5. In **Providers → Provider settings → Bot access**, sign in using the Mac Studio’s Hermes dashboard credentials. The API key and dashboard password serve different purposes.

For Debug builds, `TETHER_API_URL` and `TETHER_API_TOKEN` import an API connection into Keychain without replacing existing profiles. Release builds ignore these launch variables. `scripts/phone/launch-tether-studio.py` can fetch the current Studio key over existing authorized SSH and launch an installed build without printing the key.

### Use a local model through Hermes

Configure the model on the machine running Hermes. For an OpenAI-compatible local server such as Ollama or oMLX, set the Hermes profile’s model configuration to your server’s URL and an installed model ID:

```yaml
model:
  provider: custom
  base_url: http://127.0.0.1:11434/v1
  default: your-installed-model-id
```

If the inference server requires authentication, configure its key in Hermes. In Tether, connect to the **Hermes API Server** using the Hermes token, then leave **Hermes default** selected in the composer. Tap the model name to choose an alternative that Hermes advertises. Loopback in the example is relative to Hermes. When Hermes runs inside a VM, use an inference address reachable from that VM.

For a Hermes gateway serving multiple profiles, save each bot as a named connection using its profile URL, such as `https://your-gateway.ts.net/p/planner`. Each connection has its own conversation history and credential record.

## Verification

Run the regression suite with:

```sh
xcodebuild test -project Tether.xcodeproj -scheme Tether \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`LiveStudioTests` is opt-in and uses the production API client against a real Studio. Set `TETHER_LIVE_ACCEPTANCE=1`, `TETHER_LIVE_API_URL`, and `TETHER_LIVE_API_TOKEN` in the test runner environment. Keep credentials out of source control and command-line arguments. The live test creates and edits a small counter through Hermes, verifies its JavaScript in the production WebKit preview, and checks rollback.

See [functional acceptance status](docs/functional-acceptance-status.md) for current live evidence and remaining phone/authentication checks, [feature inventory](docs/hermes-feature-parity.md), and [authentication design](docs/hermes-tailscale-auth-research.md). [Tether Host for Mac](https://github.com/sladebot/Tether-Host) remains a separate optional deployment project; this app can connect directly to an existing Studio Hermes installation.
