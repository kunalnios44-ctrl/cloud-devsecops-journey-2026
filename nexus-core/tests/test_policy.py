import pytest

from nexus_core.policy import evaluate_inventory


def test_compliant_resource_passes_all_controls():
    findings = evaluate_inventory({"resources": [{
        "id": "db-1", "encryption_at_rest": True,
        "publicly_accessible": False, "owner": "team-a",
    }]})
    assert len(findings) == 3
    assert all(item.status == "pass" for item in findings)


def test_insecure_resource_fails_relevant_controls():
    findings = evaluate_inventory({"resources": [{
        "id": "bucket-1", "encryption_at_rest": False,
        "publicly_accessible": True, "owner": "team-a",
    }]})
    assert [item.status for item in findings] == ["fail", "fail", "pass"]


def test_rejects_duplicate_resource_ids():
    resource = {"id": "same", "encryption_at_rest": True, "publicly_accessible": False}
    with pytest.raises(ValueError, match="Duplicate"):
        evaluate_inventory({"resources": [resource, resource]})


def test_rejects_invalid_root():
    with pytest.raises(ValueError, match="root"):
        evaluate_inventory([])
