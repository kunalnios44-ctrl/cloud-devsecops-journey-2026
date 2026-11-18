"""Small deterministic policy engine for normalized cloud inventory records."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class Finding:
    resource_id: str
    control_id: str
    severity: str
    status: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


def evaluate_inventory(document: dict[str, Any]) -> list[Finding]:
    """Evaluate normalized resources without making network or cloud API calls."""
    if not isinstance(document, dict):
        raise TypeError("Inventory root must be a JSON object")
    resources = document.get("resources")
    if not isinstance(resources, list):
        raise TypeError("'resources' must be a list")

    findings: list[Finding] = []
    seen_ids: set[str] = set()
    for index, resource in enumerate(resources):
        if not isinstance(resource, dict):
            raise TypeError(f"Resource at index {index} must be an object")
        resource_id = resource.get("id")
        if not isinstance(resource_id, str):
            raise TypeError(f"Resource at index {index} requires a string 'id'")
        if not resource_id.strip():
            raise ValueError(f"Resource at index {index} requires a non-empty 'id'")
        if resource_id in seen_ids:
            raise ValueError(f"Duplicate resource id: {resource_id}")
        seen_ids.add(resource_id)

        encrypted = resource.get("encryption_at_rest")
        public = resource.get("publicly_accessible")
        owner = resource.get("owner")
        if not isinstance(encrypted, bool) or not isinstance(public, bool):
            raise TypeError(
                f"Resource '{resource_id}' requires boolean "
                "encryption_at_rest and publicly_accessible"
            )

        findings.append(Finding(
            resource_id, "NEXUS-ENC-001", "high",
            "pass" if encrypted else "fail",
            "Encryption at rest is enabled." if encrypted else "Encryption at rest is not enabled.",
        ))
        findings.append(Finding(
            resource_id, "NEXUS-NET-001", "high",
            "pass" if not public else "fail",
            "Resource is not publicly accessible." if not public else "Resource is publicly accessible; review exposure.",
        ))
        has_owner = isinstance(owner, str) and bool(owner.strip())
        findings.append(Finding(
            resource_id, "NEXUS-GOV-001", "low",
            "pass" if has_owner else "fail",
            "Owner metadata is present." if has_owner else "Owner metadata is missing.",
        ))
    return findings
