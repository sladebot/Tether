# Physical-phone sandbox launch

`launch-tether-sandbox.sh` securely bootstraps the already-installed Debug build
to the guest Hermes API. It preserves application data and never uninstalls the
app. The token is read from `~/hermes_token`, required to be private, supplied
through devicectl's child environment, and never printed or placed in command
arguments.

The script refuses to launch when CoreDevice services, Developer Mode, or the
device tunnel are unavailable. Connect and unlock the phone before retrying:

```sh
./scripts/phone/launch-tether-sandbox.sh
```

Optional overrides are `TETHER_DEVICE_ID`, `TETHER_BUNDLE_ID`,
`TETHER_API_URL`, and `TETHER_TOKEN_FILE`. The URL must remain HTTPS on a
`.ts.net` hostname. Release builds intentionally ignore Debug bootstrap
environment variables.

## Studio launch

`launch-tether-studio.py` verifies the Studio's existing Tailscale HTTPS API and launches an installed Debug build. It retrieves the current API key from the Hermes account through an already-authorized SSH connection, then supplies it only through the child environment. The app imports it into its origin-bound Keychain record. The script refuses HTTP and cross-origin redirects and does not print the credential.

```sh
python3 scripts/phone/launch-tether-studio.py --device <CoreDevice-UUID> --host <trusted-Studio-SSH-host>
```

For a booted simulator, add `--simulator` and use its simulator UUID. `--host` controls SSH only; `--url` controls the phone's HTTPS API endpoint. Both default to the Studio's Tailscale hostname. If SSH trusts the Studio under an IP or alias instead, pass that trusted address with `--host`. Build with normal simulator signing enabled so the app can use Keychain. No provider key is copied to the phone; the one imported credential is the Hermes API key.
