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
