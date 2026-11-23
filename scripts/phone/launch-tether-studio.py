#!/usr/bin/env python3
"""Verify Studio HTTPS and provision a debug Tether build without printing secrets.

Requires an installed Debug build. Reuses the matching API profile or adds Studio;
never replaces another connection. Reads the current Hermes key over existing SSH.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='CoreDevice or simulator UUID')
    parser.add_argument('--simulator', action='store_true')
    parser.add_argument('--host', default='souranils-mac-studio.tail4a305f.ts.net')
    parser.add_argument('--ssh-profile', default='jarvis')
    parser.add_argument('--url', default='https://souranils-mac-studio.tail4a305f.ts.net')
    parser.add_argument('--bundle', default='app.tetherflow.ios')
    args = parser.parse_args()
    url = urllib.parse.urlsplit(args.url)
    if url.scheme != 'https' or not (url.hostname or '').endswith('.ts.net') or url.username or url.password or url.query or url.fragment:
        parser.error('Use a credential-free Tailscale HTTPS endpoint.')
    source = """from pathlib import Path
for line in (Path.home()/'.hermes/.env').read_text().splitlines():
    if line.startswith('API_SERVER_KEY='):
        print(line.split('=',1)[1].strip().strip(chr(34)).strip(chr(39)))
        break
"""
    secret = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8',
        '-o', 'HostName='+args.host, args.ssh_profile, 'python3 -'], input=source,
        text=True, capture_output=True, check=True).stdout.strip()
    if not secret or '\n' in secret:
        raise RuntimeError('Studio did not return a single API credential.')
    # Do not forward the bearer credential through redirects.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    request = urllib.request.Request(args.url.rstrip('/')+'/v1/capabilities', headers={'Authorization': 'Bearer '+secret})
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=12) as response:
        capabilities = json.load(response)
    if capabilities.get('platform') != 'hermes-agent':
        raise RuntimeError('Endpoint is not Hermes.')
    env = os.environ.copy()
    prefix = 'SIMCTL_CHILD_' if args.simulator else 'DEVICECTL_CHILD_'
    env[prefix+'TETHER_API_URL'] = args.url
    env[prefix+'TETHER_API_TOKEN'] = secret
    env[prefix+'TETHER_CONNECTION_NAME'] = 'Studio'
    if args.simulator:
        command = ['xcrun', 'simctl', 'launch', '--terminate-running-process', args.device, args.bundle]
    else:
        command = ['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
                   '--terminate-existing', '--activate', args.bundle]
    subprocess.run(command, env=env, check=True)
    print('Studio HTTPS verified. Tether launched with its credential imported into Keychain.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Studio launch failed: '+str(error), file=sys.stderr)
        sys.exit(1)
