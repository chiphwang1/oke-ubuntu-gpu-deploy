#!/usr/bin/env python3
"""Download one generated key from an ORM Apply job without printing secrets."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def save_key(state, pool, destination):
    name = 'generated_worker_ssh_private_key' if pool == 'gpu' else 'generated_cpu_ssh_private_key'
    key = state.get('outputs', {}).get(name, {}).get('value')
    if not isinstance(key, str) or 'PRIVATE KEY-----' not in key:
        raise ValueError('This job has no generated private key for the selected pool')
    # Exclusive create rejects existing files and symlinks. Restrictive mode
    # applies at creation, before any private key content is written.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(key)
        if not key.endswith('\n'):
            stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job-id', required=True, help='Successful ORM Apply job OCID')
    parser.add_argument('--pool', choices=['gpu', 'cpu'], default='gpu')
    parser.add_argument('--output', required=True, help='New local private-key file (will not overwrite)')
    parser.add_argument('--region', required=True)
    parser.add_argument('--profile')
    parser.add_argument('--auth', choices=['api_key', 'security_token', 'instance_principal', 'resource_principal'])
    args = parser.parse_args()
    # OCI CLI writes the downloaded state into a private temporary directory.
    # The entire state is removed when extraction finishes or fails.
    with tempfile.TemporaryDirectory(prefix='oke-ssh-') as directory:
        state_path = Path(directory) / 'state.json'
        state_path.touch(mode=0o600)
        command = ['oci', 'resource-manager', 'job', 'get-job-tf-state', '--job-id', args.job_id, '--file', str(state_path), '--region', args.region]
        if args.profile:
            command += ['--profile', args.profile]
        if args.auth:
            command += ['--auth', args.auth]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError('Cannot download ORM job state. Check job OCID, region, authentication and permissions.')
        save_key(json.loads(state_path.read_text()), args.pool, Path(args.output).expanduser())
    print('Saved private key with owner-only permissions:', args.output)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError) as exc:
        raise SystemExit(str(exc)) from None
