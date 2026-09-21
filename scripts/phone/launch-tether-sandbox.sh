#!/bin/zsh

set -euo pipefail

readonly DEVICE_ID="${TETHER_DEVICE_ID:-2CB86E93-55AB-5234-8F2C-D32353C7E792}"
readonly BUNDLE_ID="${TETHER_BUNDLE_ID:-app.tetherflow.ios}"
readonly API_URL="${TETHER_API_URL:-https://jarviss-virtual-machine.tail4a305f.ts.net}"
readonly TOKEN_FILE="${TETHER_TOKEN_FILE:-${HOME}/hermes_token}"

if [[ "${API_URL}" != https://*.ts.net ]]; then
  print -u2 "Refusing non-Tailscale or non-HTTPS API URL: ${API_URL}"
  exit 64
fi

if [[ ! -f "${TOKEN_FILE}" || ! -r "${TOKEN_FILE}" ]]; then
  print -u2 "Hermes token file is missing or unreadable: ${TOKEN_FILE}"
  exit 66
fi

token_mode="$(/usr/bin/stat -f '%OLp' "${TOKEN_FILE}")"
if (( (8#${token_mode} & 8#077) != 0 )); then
  print -u2 "Refusing token file accessible by group/others (mode ${token_mode})."
  exit 77
fi

work_dir="$(/usr/bin/mktemp -d /tmp/tether-phone-launch.XXXXXX)"
cleanup() {
  unset DEVICECTL_CHILD_TETHER_API_TOKEN
  /bin/rm -rf -- "${work_dir}"
}
trap cleanup EXIT INT TERM

device_json="${work_dir}/device.json"
/usr/bin/xcrun devicectl device info details \
  --device "${DEVICE_ID}" \
  --json-output "${device_json}" \
  --quiet

ddi_available="$(/usr/bin/plutil -extract result.deviceProperties.ddiServicesAvailable raw "${device_json}")"
developer_mode="$(/usr/bin/plutil -extract result.deviceProperties.developerModeStatus raw "${device_json}")"
tunnel_state="$(/usr/bin/plutil -extract result.connectionProperties.tunnelState raw "${device_json}")"

if [[ "${ddi_available}" != "true" || "${developer_mode}" != "enabled" || "${tunnel_state}" == "unavailable" ]]; then
  print -u2 "Phone is not ready: ddi=${ddi_available}, developerMode=${developer_mode}, tunnel=${tunnel_state}."
  print -u2 "Connect it to the Studio, unlock it, leave it on the Home Screen, and accept Trust if prompted."
  exit 69
fi

token="$(/usr/bin/tr -d '\r\n' < "${TOKEN_FILE}")"
if [[ -z "${token}" ]]; then
  print -u2 "Hermes token file is empty."
  exit 65
fi

export DEVICECTL_CHILD_TETHER_API_URL="${API_URL}"
export DEVICECTL_CHILD_TETHER_API_TOKEN="${token}"
unset token

/usr/bin/xcrun devicectl device process launch \
  --device "${DEVICE_ID}" \
  --terminate-existing \
  --activate \
  "${BUNDLE_ID}"

print "Tether launched on the paired phone with the sandbox profile bootstrap."
