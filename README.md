# Opinionated Azure Starter Project

A "Hello World" style project demonstrating Azure best practices for infrastructure-as-code, containerized applications, and CI/CD pipelines.

> **New here?** Start with the [docs](docs/README.md) for a walkthrough of CI/CD concepts, pipeline flows, and how authentication works.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Resource Group                         │
│                                                                     │
│  ┌──────────┐   ┌──────────────┐   ┌──────────┐   ┌─────────────┐ │
│  │  VNet     │   │ App Service  │   │  ACR      │   │ Key Vault   │ │
│  │  + Subnets│◄──│ (Container)  │──►│ (Public)  │   │ (Private)   │ │
│  └──────────┘   │  + Staging   │   └──────────┘   └─────────────┘ │
│                  └──────────────┘                                    │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Microsoft Foundry v2 (Private)                   │   │
│  │  AI Services Account → Project → Capability Hosts             │   │
│  │  CosmosDB · AI Search · Storage Account                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
├── infrastructure/           # Terraform IaC
│   ├── main.tf              # Root module
│   ├── variables.tf         # Parameterized config
│   ├── outputs.tf           # Key outputs
│   ├── providers.tf         # azurerm + azapi providers
│   ├── terraform.tfvars     # Default values
│   └── modules/
│       ├── networking/      # VNet, subnets, NSGs, private DNS
│       ├── acr/             # Azure Container Registry
│       ├── keyvault/        # Azure Key Vault
│       ├── appservice/      # App Service + staging slot
│       └── foundry/         # Microsoft Foundry v2 (AzAPI)
├── src/hello-world/         # Python Flask application
│   ├── app.py               # Flask app (port 8000)
│   ├── Dockerfile           # Python slim container image
│   ├── templates/           # HTML templates
│   ├── static/              # Static assets
│   └── tests/               # pytest + Playwright tests
└── .github/workflows/       # CI/CD pipelines
    ├── terraform.yml        # IaC: plan on PR, apply on dispatch
    ├── ci.yml               # Test → Security → Build & Push
    └── cd.yml               # Deploy to slot → Approval → Swap
```

## Prerequisites

### Azure Resources
1. An Azure subscription
2. A service principal with Contributor + User Access Administrator roles on the subscription

### Workload Identity Federation (OIDC)
Create federated credentials on your service principal for GitHub Actions. Two credentials are needed — one for branch-based workflows (CI, Terraform) and one for the `production` environment (CD approval gate):

```bash
# Create the app registration (if not already done)
az ad app create --display-name "github-actions-starter"

# Federated credential for branch-based workflows (CI, Terraform)
az ad app federated-credential create \
  --id <APP_OBJECT_ID> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<OWNER>/<REPO>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Federated credential for CD production environment (approval gate)
az ad app federated-credential create \
  --id <APP_OBJECT_ID> \
  --parameters '{
    "name": "github-production-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<OWNER>/<REPO>:environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

> **Why two credentials?** When a GitHub Actions job references an `environment`, the OIDC token's `sub` claim changes from `repo:<owner>/<repo>:ref:refs/heads/main` to `repo:<owner>/<repo>:environment:production`. Each claim pattern requires its own federated credential on the same app registration.

### GitHub Repository Secrets
Configure these secrets in your GitHub repository settings:

| Secret | Description |
|---|---|
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_CLIENT_ID` | Service principal (app registration) client ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |
| `ACR_NAME` | Azure Container Registry name (e.g., `acrhelloworld`) |
| `ACR_LOGIN_SERVER` | ACR login server (e.g., `acrhelloworld.azurecr.io`) |
| `APP_SERVICE_NAME` | App Service name (e.g., `app-helloworld`) |
| `RESOURCE_GROUP_NAME` | Resource group name (e.g., `rg-helloworld-development`) |

### GitHub Environment
Create a `production` environment in your repo settings (**Settings → Environments → New environment**) with **required reviewers** for the deployment approval gate. Repository-level secrets are inherited automatically — no need to duplicate them in the environment.

## Getting Started

### 1. Deploy Infrastructure

Set your Azure subscription ID as an environment variable (this avoids storing secrets in source control):

```bash
export TF_VAR_subscription_id="your-azure-subscription-id"
```

Then run Terraform:

```bash
cd infrastructure
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Or trigger the **Terraform** workflow via GitHub Actions.

### 2. Run the Application Locally

```bash
cd src/hello-world
pip install -r requirements-dev.txt
python app.py
# Visit http://localhost:8000
```

### 3. Run Tests

```bash
cd src/hello-world
pytest tests/test_app.py -v            # Unit tests
playwright install --with-deps chromium # First time only
pytest tests/test_e2e.py -v            # E2E tests
```

### 4. Build Container Locally

```bash
cd src/hello-world
docker build -t hello-world:local .
docker run -p 8000:8000 hello-world:local
```

## CI/CD Workflows

### Terraform (`terraform.yml`)
- **On PR** (changes to `infrastructure/`): runs `terraform plan` and posts the plan as a PR comment
- **On manual dispatch**: runs `terraform apply` with the selected action

### CI (`ci.yml`)
- **On PR** (changes to `src/hello-world/`): runs tests and security scans
- **On manual dispatch**: runs full pipeline including container build & push to ACR

### CD (`cd.yml`)
- **Triggered automatically** after CI succeeds, or via manual dispatch
- Deploys container to the **staging** deployment slot
- Waits for staging health check, then requires **approval** in the `production` environment before swapping slots

## Security Features

- **No local authentication** — all services use Managed Identity + RBAC
- **Private endpoints** — Key Vault and Foundry services are accessible only via VNet
- **ACR public access** — intentional exception to allow GitHub Actions to push without a private runner
- **CodeQL** — static analysis on every PR
- **SBOM scanning** — dependency vulnerability detection
- **Workload Identity Federation** — no secrets stored for Azure authentication in pipelines
- **Blue/green deployments** — zero-downtime releases via deployment slot swapping

## Configuration

Key variables in `infrastructure/variables.tf`:

| Variable | Default | Description |
|---|---|---|
| `location` | `westus3` | Azure region |
| `environment` | `development` | Environment tag |
| `project_name` | `helloworld` | Base name for resources |
| `vnet_address_space` | `10.0.0.0/16` | VNet CIDR |
| `subnet_appservice_prefix` | `10.0.1.0/24` | App Service subnet |
| `subnet_private_endpoints_prefix` | `10.0.2.0/24` | Private endpoints subnet |
| `subnet_foundry_prefix` | `10.0.3.0/24` | Foundry services subnet |
