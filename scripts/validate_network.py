#!/usr/bin/env python3
import ipaddress
import json
import sys
q = json.load(sys.stdin)
valid = True
if q["enabled"] == "true":
    try:
        nets = [ipaddress.ip_network(q[k], strict=True) for k in ("vcn", "pods", "services")]
        valid = all(n.version == 4 for n in nets) and 16 <= nets[0].prefixlen <= 24
        valid = valid and not any(a.overlaps(b) for i, a in enumerate(nets) for b in nets[i+1:])
    except ValueError:
        valid = False
print(json.dumps({"valid": str(valid).lower()}))
