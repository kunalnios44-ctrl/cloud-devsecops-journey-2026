#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/s3-bucket-policy.json"

BUCKET_NAME="${1:-}"

log() {
    printf '[INFO] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

validate_policy() {
    python3 - "$POLICY_FILE" "$BUCKET_NAME" <<'PY'
import json
import sys

source, bucket = sys.argv[1:]

with open(source, encoding="utf-8") as f:
    policy = json.load(f)

expected = {
    "DenyInsecureTransport",
    "DenyIncorrectExplicitEncryption",
    "DenyCustomerProvidedEncryption"
}

statements = policy.get("Statement", [])
found = {s.get("Sid") for s in statements}

assert found == expected, "Policy Sid verification failed"

for statement in statements:
    assert statement.get("Effect") == "Deny"
    assert statement.get("Principal") == "*"

    resources = statement["Resource"]
    resources = [resources] if isinstance(resources, str) else resources

    for resource in resources:
        assert "YOUR_BUCKET_NAME" in resource

        rendered = resource.replace(
            "YOUR_BUCKET_NAME", bucket
        )

        assert "YOUR_BUCKET_NAME" not in rendered
        assert f"arn:aws:s3:::{bucket}" in rendered

print("All three policy Sids verified.")
print("Policy rendering validation passed.")
PY
}

if [[ ! -f "$POLICY_FILE" ]]; then
    error "Policy file not found."
fi

command -v python3 >/dev/null 2>&1 ||
    error "Python 3 is required."

python3 -m json.tool "$POLICY_FILE" >/dev/null ||
    error "Invalid JSON policy."

if [[ "${1:-}" == "--validate-only" ]]; then
    BUCKET_NAME="audit-validation-test-bucket"
    validate_policy
    log "Static validation passed."
    exit 0
fi

if [[ -z "$BUCKET_NAME" ]]; then
    error "Usage: $0 <bucket-name>"
fi

if [[ ! "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
    error "Invalid S3 bucket name format."
fi

if [[ "$BUCKET_NAME" == *".."* ||
      "$BUCKET_NAME" == *".-"* ||
      "$BUCKET_NAME" == *"-."* ]]; then
    error "Invalid S3 bucket name."
fi

if [[ "$BUCKET_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "IP-address-style bucket names are not allowed."
fi

validate_policy

command -v aws >/dev/null 2>&1 ||
    error "AWS CLI is not installed."

aws sts get-caller-identity >/dev/null 2>&1 ||
    error "AWS credentials are unavailable."

log "Checking S3 bucket..."

aws s3api head-bucket --bucket "$BUCKET_NAME" ||
    error "Bucket does not exist or is inaccessible."

read -r -p "Apply security configuration to $BUCKET_NAME? (yes/no): " CONFIRM

[[ "$CONFIRM" == "yes" ]] ||
    error "Operation cancelled."

BACKUP_DIR="${HOME}/.aws-cloud-security-backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/${BUCKET_NAME}-${TIMESTAMP}-policy.json"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RAW_POLICY="$TMP_DIR/current-policy.json"
POLICY_ERROR="$TMP_DIR/policy-error.txt"

log "Backing up existing bucket policy..."

if aws s3api get-bucket-policy \
    --bucket "$BUCKET_NAME" \
    --output json > "$RAW_POLICY" 2> "$POLICY_ERROR"; then

    python3 - "$RAW_POLICY" "$BACKUP_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    response = json.load(f)

with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(response["Policy"])
PY

    log "Existing policy backed up: $BACKUP_FILE"

elif grep -q "NoSuchBucketPolicy" "$POLICY_ERROR"; then
    log "No existing bucket policy found."
else
    cat "$POLICY_ERROR" >&2
    error "Could not inspect existing policy. Aborting."
fi

RENDERED_POLICY="$TMP_DIR/rendered-policy.json"

python3 - "$POLICY_FILE" "$BUCKET_NAME" "$RENDERED_POLICY" <<'PY'
import json
import sys

source, bucket, destination = sys.argv[1:]

with open(source, encoding="utf-8") as f:
    policy = json.load(f)

for statement in policy["Statement"]:
    resources = statement["Resource"]

    if isinstance(resources, str):
        statement["Resource"] = resources.replace(
            "YOUR_BUCKET_NAME", bucket
        )
    else:
        statement["Resource"] = [
            item.replace("YOUR_BUCKET_NAME", bucket)
            for item in resources
        ]

with open(destination, "w", encoding="utf-8") as f:
    json.dump(policy, f, indent=2)
PY

log "Enabling public access block..."

aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

log "Enabling BucketOwnerEnforced ownership..."

aws s3api put-bucket-ownership-controls \
    --bucket "$BUCKET_NAME" \
    --ownership-controls \
    'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

log "Enabling versioning..."

aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

log "Configuring AES256 encryption..."

aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

log "Applying bucket policy..."

aws s3api put-bucket-policy \
    --bucket "$BUCKET_NAME" \
    --policy "file://$RENDERED_POLICY"

log "Verifying configuration..."

aws s3api get-public-access-block \
    --bucket "$BUCKET_NAME" > "$TMP_DIR/public.json"

aws s3api get-bucket-encryption \
    --bucket "$BUCKET_NAME" > "$TMP_DIR/encryption.json"

aws s3api get-bucket-versioning \
    --bucket "$BUCKET_NAME" > "$TMP_DIR/versioning.json"

aws s3api get-bucket-ownership-controls \
    --bucket "$BUCKET_NAME" > "$TMP_DIR/ownership.json"

aws s3api get-bucket-policy \
    --bucket "$BUCKET_NAME" > "$TMP_DIR/applied-policy.json"

python3 - "$TMP_DIR" "$BUCKET_NAME" <<'PY'
import json
import sys
from pathlib import Path

folder = Path(sys.argv[1])
bucket = sys.argv[2]

def load(name):
    with open(folder / name, encoding="utf-8") as f:
        return json.load(f)

public = load("public.json")["PublicAccessBlockConfiguration"]

for key in (
    "BlockPublicAcls",
    "IgnorePublicAcls",
    "BlockPublicPolicy",
    "RestrictPublicBuckets"
):
    assert public.get(key) is True, f"{key} verification failed"

encryption = load("encryption.json")
rules = encryption["ServerSideEncryptionConfiguration"]["Rules"]

assert any(
    rule.get("ApplyServerSideEncryptionByDefault", {}).get(
        "SSEAlgorithm"
    ) == "AES256"
    for rule in rules
), "AES256 verification failed"

assert load("versioning.json").get("Status") == "Enabled"

ownership = load("ownership.json")
assert any(
    rule.get("ObjectOwnership") == "BucketOwnerEnforced"
    for rule in ownership["OwnershipControls"]["Rules"]
)

applied = json.loads(load("applied-policy.json")["Policy"])

expected = {
    "DenyInsecureTransport",
    "DenyIncorrectExplicitEncryption",
    "DenyCustomerProvidedEncryption"
}

found = {s.get("Sid") for s in applied["Statement"]}
assert found == expected, "Applied policy Sid verification failed"

for statement in applied["Statement"]:
    resources = statement["Resource"]
    resources = [resources] if isinstance(resources, str) else resources

    assert all(
        f"arn:aws:s3:::{bucket}" in resource
        for resource in resources
    ), "Bucket ARN verification failed"

print("All AWS configuration checks passed.")
print("All three policy Sids verified.")
PY

log "SUCCESS: S3 security configuration verified."
log "Backup: $BACKUP_FILE"
