#!/usr/bin/env python3
"""Attach/detach only this stack's shared security list; preserve existing lists."""
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from orm_auth import uses_delegation
from gpu_addons import ensure_orm_sdk


def desired_lists(subnet, list_id, vcn_id, action):
    if subnet['vcn-id'] != vcn_id:
        raise RuntimeError('Selected subnet does not belong to the expected VCN')
    current = list(subnet['security-list-ids'])
    if action == 'detach':
        result = [item for item in current if item != list_id]
        if not result:
            raise RuntimeError('Refusing to detach the only subnet security list')
        return result
    if list_id in current:
        return current
    if len(current) >= 5:
        raise RuntimeError('Subnet already has five security lists; free one association before applying')
    return current + [list_id]


class Network:
    def __init__(self):
        self.client = None
        if uses_delegation():
            from orm_auth import client
            self.client = client('core')

    @staticmethod
    def cli(*args):
        p = subprocess.run(['oci', 'network', 'subnet', *args, '--output', 'json'], capture_output=True, text=True)
        if p.returncode:
            raise RuntimeError('OCI subnet command failed; check network permissions and concurrent subnet updates')
        return json.loads(p.stdout)

    def get(self, subnet_id):
        if self.client:
            r = self.client.get_subnet(subnet_id)
            return {'vcn-id': r.data.vcn_id, 'security-list-ids': r.data.security_list_ids}, r.headers.get('etag')
        r = self.cli('get', '--subnet-id', subnet_id)
        return r['data'], r.get('etag')

    def update(self, subnet_id, list_ids, etag):
        if not etag:
            raise RuntimeError('Subnet response has no ETag; refusing an unguarded update')
        if self.client:
            import oci
            self.client.update_subnet(subnet_id, oci.core.models.UpdateSubnetDetails(security_list_ids=list_ids), if_match=etag)
        else:
            self.cli('update', '--subnet-id', subnet_id, '--security-list-ids', json.dumps(list_ids), '--if-match', etag, '--force')


def reconcile(network, subnet_ids, list_id, vcn_id, action):
    # Preflight every selected subnet before making any change.
    selected = sorted(set(filter(None, subnet_ids)))
    for subnet_id in selected:
        subnet, _ = network.get(subnet_id)
        desired_lists(subnet, list_id, vcn_id, action)
    for subnet_id in selected:
        subnet, etag = network.get(subnet_id)
        desired = desired_lists(subnet, list_id, vcn_id, action)
        if desired != subnet['security-list-ids']:
            network.update(subnet_id, desired, etag)
        actual, _ = network.get(subnet_id)
        if (list_id in actual['security-list-ids']) != (action == 'attach'):
            raise RuntimeError('Subnet security-list association verification failed')
    print(f'Verified {action} on {len(selected)} selected subnets.')


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'attach'
    if action not in ('attach', 'detach'):
        raise ValueError('Use attach or detach')
    reconcile(Network(), json.loads(os.environ['SUBNET_IDS']), os.environ['SECURITY_LIST_ID'], os.environ['VCN_ID'], action)


if __name__ == '__main__':
    try:
        ensure_orm_sdk(__file__)
        main()
    except Exception as exc:
        # Never dump authentication headers or tokens from SDK responses.
        if hasattr(exc, 'status') and hasattr(exc, 'code'):
            print(f'OCI subnet API {exc.status} {exc.code}', file=sys.stderr)
        elif isinstance(exc, (KeyError, ValueError, RuntimeError, OSError)):
            print(str(exc), file=sys.stderr)
        else:
            print('Subnet association operation failed', file=sys.stderr)
        sys.exit(1)
