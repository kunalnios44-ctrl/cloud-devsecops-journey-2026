import json
import sys
from typing import Any, Dict, List

SENSITIVE_PORTS = {22, 3389, 5432, 3306}


def validate_plan_payload(data: Any) -> Dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("Terraform plan payload must be a JSON object")

    if "max_deletes" not in data or not isinstance(data["max_deletes"], int) or isinstance(data["max_deletes"], bool) or data["max_deletes"] < 0:
        raise ValueError("max_deletes must be a non-negative integer")

    changes = data.get("resource_changes")
    if not isinstance(changes, list):
        raise ValueError("resource_changes must be a list")

    for idx, item in enumerate(changes):
        if not isinstance(item, dict):
            raise ValueError(f"resource_changes[{idx}] must be an object")
        if not isinstance(item.get("address"), str) or not item["address"].strip():
            raise ValueError(f"resource_changes[{idx}].address must be a non-empty string")
        actions = item.get("actions")
        if not isinstance(actions, list) or not all(isinstance(a, str) for a in actions):
            raise ValueError(f"resource_changes[{idx}].actions must be a list of strings")
        after = item.get("after", {})
        if after is not None and not isinstance(after, dict):
            raise ValueError(f"resource_changes[{idx}].after must be an object or null")

    return data


def evaluate_terraform_plan(plan: Dict[str, Any]) -> List[str]:
    violations: List[str] = []
    delete_count = 0

    for item in plan["resource_changes"]:
        addr = item["address"]
        actions = item["actions"]
        after = item.get("after") or {}

        if "delete" in actions:
            delete_count += 1

        if after.get("public_access") is True:
            violations.append(f"Public access enabled on resource: {addr}")

        if after.get("encrypted") is False:
            violations.append(f"Encryption disabled on resource: {addr}")

        cidr = after.get("cidr_block")
        port = after.get("from_port")
        if cidr == "0.0.0.0/0" and port in SENSITIVE_PORTS:
            violations.append(f"Open world CIDR 0.0.0.0/0 on sensitive port {port}: {addr}")

    if delete_count > plan["max_deletes"]:
        violations.append(
            f"Blast radius exceeded: {delete_count} deletions requested (max allowed: {plan['max_deletes']})"
        )

    return violations


def main() -> int:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            raise ValueError("Empty input on stdin")
        if len(raw.encode("utf-8")) > 1048576:
            raise ValueError("Input exceeds 1 MiB limit")
        parsed = json.loads(raw)
        plan = validate_plan_payload(parsed)
    except Exception as exc:
        print(f"[INFRA_RUNTIME_ERROR] {exc}", file=sys.stderr)
        return 2

    violations = evaluate_terraform_plan(plan)
    if violations:
        for v in violations:
            print(f"[INFRA_VIOLATION] {v}", file=sys.stderr)
        return 1

    print(f"[INFRA_PASS] Terraform plan passed ({len(plan['resource_changes'])} resource changes evaluated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
  
