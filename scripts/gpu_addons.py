#!/usr/bin/env python3
"""Remove OKE-managed GPU components only; fail on API/auth/verification errors."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path
import shlex
import shutil

# Also supports import-based unit tests from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from orm_auth import uses_delegation

_orm_client = None

def orm_request(*args):
    import oci
    global _orm_client
    if _orm_client is None:
        from orm_auth import client
        _orm_client = client()
    cluster_id = os.environ["OKE_CLUSTER_ID"]
    try:
        if args[0] == "list-addons":
            response = oci.pagination.list_call_get_all_results(_orm_client.list_addons, cluster_id)
            return {"data": [{"name": x.name, "lifecycle-state": x.lifecycle_state} for x in response.data]}
        if args[0] == "disable-addon":
            name = args[args.index("--addon-name") + 1]
            response = _orm_client.disable_addon(cluster_id, name, True)
            work_id = response.headers.get("opc-work-request-id")
            if not work_id:
                raise RuntimeError("DisableAddon returned no work request ID")
            deadline = time.monotonic() + 1200
            while time.monotonic() < deadline:
                work = _orm_client.get_work_request(work_id).data
                if work.status == "SUCCEEDED":
                    return {}
                if work.status in ("FAILED", "CANCELED"):
                    raise RuntimeError("DisableAddon work request " + work.status + ": " + work_id)
                time.sleep(5)
            raise RuntimeError("Timed out waiting for DisableAddon: " + work_id)
        raise ValueError("Unsupported ORM add-on operation")
    except oci.exceptions.ServiceError as exc:
        # Keep authentication headers/tokens out of exceptions and job logs.
        raise RuntimeError(f"OKE API {exc.status} {exc.code}; request ID {exc.request_id}") from None


def ensure_orm_sdk(script_path=None):
    if not uses_delegation():
        return
    try:
        import oci
    except ImportError:
        # OCI CLI installations carry the SDK in their own Python environment.
        if os.environ.get("OKE_SDK_REEXEC"):
            raise RuntimeError("OCI Python SDK is unavailable in the runner")
        cli_path = shutil.which("oci")
        if not cli_path:
            raise RuntimeError("Install OCI CLI or the OCI Python SDK on the runner")
        first_line = Path(cli_path).read_text().splitlines()[0]
        interpreter = shlex.split(first_line[2:]) if first_line.startswith("#!") else []
        if not interpreter or not any("python" in x for x in interpreter):
            raise RuntimeError("Cannot find the OCI CLI Python interpreter")
        os.environ["OKE_SDK_REEXEC"] = "1"
        os.execvpe(interpreter[0], interpreter + [str(Path(script_path or __file__).resolve())] + sys.argv[1:], os.environ)


def is_gpu_addon(name):
    normalized = "".join(c for c in name.lower() if c.isalnum())
    return any(word in normalized for word in ("gpu", "nvidia", "dcgm", "nodefeaturediscovery"))


def cli(*args):
    if uses_delegation():
        return orm_request(*args)
    command = ["oci", "ce", "cluster", *args, "--cluster-id", os.environ["OKE_CLUSTER_ID"], "--output", "json"]
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "OCI CLI command failed")
    return json.loads(result.stdout) if result.stdout.strip() else {}


def addons():
    payload = cli("list-addons", "--all")["data"]
    items = payload if isinstance(payload, list) else payload["items"]
    # DELETED records can remain in the API. INACTIVE may retain resources and
    # must still be disabled with remove-existing-add-on=true.
    return [item for item in items if is_gpu_addon(item["name"]) and item.get("lifecycle-state") != "DELETED"]


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode not in ("check", "disable"):
        raise ValueError("Use check or disable")
    found = addons()
    if mode == "disable":
        for item in found:
            print("Removing OKE managed add-on:", item["name"], flush=True)
            cli("disable-addon", "--addon-name", item["name"], "--is-remove-existing-add-on", "true", "--force", "--wait-for-state", "SUCCEEDED", "--max-wait-seconds", "1200")
        for _ in range(24):
            found = addons()
            if not found:
                break
            time.sleep(5)
    if found:
        raise RuntimeError("GPU add-ons remain: " + ", ".join(a["name"] for a in found))
    print("PASS: OKE GPU plugin and operator (and related GPU add-ons) are absent.")


if __name__ == "__main__":
    try:
        ensure_orm_sdk()
        main()
    except (KeyError, ValueError, RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
