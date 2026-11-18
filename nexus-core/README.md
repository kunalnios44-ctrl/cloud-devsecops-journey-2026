# NORDIC NEXUS CORE

A practical, testable foundation for a cloud-security control plane, developed with a Denmark 🇩🇰, Finland 🇫🇮 and Sweden 🇸🇪 project focus.

## Current capability

- Deterministic Python policy evaluation for a small set of cloud-neutral security controls.
- JSON input/output suitable for CI integration.
- Unit tests for compliant, non-compliant and malformed input.
- GitHub Actions CI for linting and tests.

## Quick start

Requires Python 3.11+.

```bash
cd nexus-core
python -m venv .venv
source .venv/bin/activate
python -m pip install -e ".[dev]"
pytest
nexus-core evaluate examples/sample-inventory.json
```

On Windows, activate with `.venv\\Scripts\\activate`.

## Policy model

The initial evaluator checks whether resources declare encryption at rest, public exposure and owner metadata. It is an educational baseline, not a cloud scanner, compliance certification or substitute for provider-native security tooling.

## Output and exit codes

- `0`: evaluation completed and no failing findings.
- `1`: evaluation completed with one or more failing findings.
- `2`: invalid input or execution error.

## Roadmap

1. Add schema validation and versioned policy packs.
2. Add provider-specific inventory adapters (AWS and Azure).
3. Add signed, reproducible report artifacts.
4. Add threat-model documentation and integration tests.

No cloud resources are created by this project. Never commit credentials, tokens, state files or real customer inventories.
