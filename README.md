# Nordic Cloud & DevSecOps Engineering Lab 🇩🇰 🇫🇮 🇸🇪

**Author:** Kunal Kashyap  
**Project focus:** Cloud infrastructure, Infrastructure as Code, platform security, containerisation and software supply-chain engineering for **Denmark 🇩🇰, Finland 🇫🇮 and Sweden 🇸🇪**.

This repository is a practical engineering portfolio focused on Nordic cloud and platform-engineering scenarios. It contains infrastructure definitions, security-oriented configuration and automation experiments. The objective is to make the implementation and its design decisions reviewable—not to claim that an unverified environment is already running in production.

> **Project status:** Active development. Code in this repository is not automatically evidence of a successful deployment, independent security audit, compliance certification or production readiness. Validation results will be documented as they are produced.

---

## 1. Project scope

The target-country scope is intentionally limited to:

- 🇩🇰 **Denmark**
- 🇫🇮 **Finland**
- 🇸🇪 **Sweden**

The current AWS network example uses **Stockholm (eu-north-1)**, which is an AWS region in Sweden. The Azure example currently specifies **North Europe**; that Azure region is in Ireland, so it is documented as a European Azure example—not as a Denmark, Finland or Sweden region. Country targeting and cloud-region availability are separate decisions and must be checked against each provider's current regional catalogue.

## 2. What is currently in the repository

| Engineering area | Current repository material |
|---|---|
| AWS infrastructure | Terraform VPC, public/private subnet, route-table, internet-gateway and security-group configuration. |
| Azure network security | Terraform hub-and-spoke layout, VNet peering, NSGs, Azure Firewall policy and workload routing. |
| Identity and secrets | Azure managed identity, Key Vault, RBAC assignment and private-endpoint configuration. |
| Container workloads | Dockerfile, Python application, Nginx configuration and deployment helper under docker-ha-cluster/. |
| Kubernetes | Workload manifest under kubernetes/. |
| GitOps | Argo CD Application manifest in argo-cd.yaml. |
| AWS storage security | S3 bucket policy example for transport security and encryption requirements. |
| Supply-chain security | SBOM generation helper under supply-chain/, using Syft and validating the generated JSON output. |
| Automation | Bash scripts and supporting operational modules. |

## 3. Architecture overview

These are separate infrastructure examples in one portfolio repository. The diagram does not imply that the environments are already connected or deployed.

```mermaid
flowchart TB
    REPO["GitHub source repository"] --> AWS["AWS Terraform example"]
    REPO --> AZ["Azure Terraform example"]
    REPO --> APP["Container and Kubernetes examples"]
    REPO --> SC["Software supply-chain automation"]

    subgraph NORDIC["Nordic project focus"]
      DK["🇩🇰 Denmark"]
      FI["🇫🇮 Finland"]
      SE["🇸🇪 Sweden"]
    end

    AWS --> STOCKHOLM["AWS Stockholm region<br/>eu-north-1"]
    STOCKHOLM --> VPC["VPC • public/private subnets<br/>route tables • security groups"]

    AZ --> AZEU["Azure North Europe example<br/>(Ireland — not a Nordic region)"]
    AZEU --> HUB["Hub VNet • firewall subnet"]
    HUB --> SPOKE["Spoke VNet • workload/private-endpoint subnets"]
    SPOKE --> KV["Key Vault private endpoint"]
    AZ --> LOG["Log Analytics diagnostics"]

    APP --> DOCKER["Docker • Nginx • Python"]
    APP --> K8S["Kubernetes manifest"]
    APP --> GITOPS["Argo CD application"]
    SC --> SBOM["SBOM generation and JSON validation"]
```

## 4. Repository layout

```text
.
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── argo-cd.yaml
├── aws-cloud-security/
│   └── s3-bucket-policy.json
├── azure-zero-trust/
│   └── main.tf
├── docker-ha-cluster/
│   ├── Dockerfile
│   ├── app.py
│   ├── deploy.sh
│   └── nginx.conf
├── kubernetes/
│   └── production-manifest.yaml
├── supply-chain/
│   └── sbom-scan.sh
├── bash-automation/
├── network-diagnostics/
├── runtime-security/
└── zero-trust-vpc/
```

Some modules are still being developed. A directory or configuration file being present does not mean its implementation is complete.

## 5. Infrastructure design notes

### AWS — Stockholm, Sweden 🇸🇪

The root Terraform configuration includes an AWS provider alias for **Stockholm (eu-north-1)**. The Europe network example defines a VPC with public and private subnets across two availability zones, internet-gateway routing for public subnets, dedicated private route tables and a security group with HTTPS ingress.

The Terraform backend block is configured for an S3 remote state bucket with encryption and native state locking (use_lockfile = true). The backend bucket must exist and be secured before initialising with the remote backend. Never commit cloud credentials or Terraform state files to Git.

### Azure — North Europe (Ireland)

The azure-zero-trust/ configuration currently specifies Azure's North Europe region. It is a European example in this repository, not a claim that the deployment is hosted in Denmark, Finland or Sweden.

The current code includes:

- Hub and spoke virtual networks with peering.
- Separate management, workload, firewall and private-endpoint subnets.
- Network security groups and a user-defined route for workload egress through the hub firewall.
- Azure Firewall and a firewall policy rule collection.
- A user-assigned managed identity and Key Vault with RBAC, soft-delete retention and purge protection.
- A Key Vault private endpoint and private DNS zone links.
- Log Analytics workspace and diagnostic settings.

Provider compatibility, network rules, routing, regional service availability and dependencies must be validated before deployment.

## 6. Software supply-chain workflow

The supply-chain/sbom-scan.sh helper is intended to generate an SPDX JSON software bill of materials for a container image.

Example:

```bash
chmod +x supply-chain/sbom-scan.sh
./supply-chain/sbom-scan.sh alpine:3.20
```

Another image can be supplied as the script argument:

```bash
./supply-chain/sbom-scan.sh nginx:1.27-alpine
```

Review the script and generated report before using the output in a release or compliance process. An SBOM is an inventory artefact; it does not by itself prove that an image is secure.

## 7. Local validation

Validate each Terraform root separately. These commands initialise providers without configuring the remote state backend:

```bash
# Root AWS configuration
terraform init -backend=false
terraform fmt -check
terraform validate

# Azure configuration
terraform -chdir=azure-zero-trust init -backend=false
terraform -chdir=azure-zero-trust fmt -check
terraform -chdir=azure-zero-trust validate
```

Validation may require provider downloads and a compatible Terraform version. The root AWS configuration declares Terraform >= 1.11.0, < 2.0.0; the Azure module declares its own version and provider constraints.

Before any real deployment:

1. Review the Terraform plan and every proposed resource change.
2. Configure credentials outside the repository using the cloud provider's supported authentication method.
3. Create and secure the remote-state bucket before enabling the S3 backend.
4. Review network exposure, firewall rules, IAM/RBAC permissions, costs and regional availability.
5. Deploy only in an account and environment where you have permission.

This README does not claim a successful cloud deployment, uptime target, compliance certification or passing pipeline unless supporting evidence is committed.

## 8. Engineering principles

- **Least privilege:** scope identities and permissions to the resources that need them.
- **Private by design:** use private subnets and private endpoints where the architecture supports them.
- **Repeatability:** keep infrastructure and deployment configuration version-controlled.
- **Traceability:** produce reviewable configuration and software inventory artefacts.
- **Safe change management:** inspect plans, diffs and validation output before applying changes.
- **Honest status reporting:** distinguish code that exists, code that validates and infrastructure that has actually been deployed.

## 9. Next engineering direction

The next iterations will focus on modular Terraform, repeatable CI validation, security-control testing, operational documentation and region-aware design for Denmark 🇩🇰, Finland 🇫🇮 and Sweden 🇸🇪. Country-specific cloud placement will only be claimed when the chosen provider actually offers the required service in that region.

---

**Repository:** [cloud-devsecops-journey-2026](https://github.com/kunalnios44-ctrl/cloud-devsecops-journey-2026)  
**Source control:** GitHub  
**Status:** Work in progress
