# CI/CD Fundamentals

## What is CI/CD?

**Continuous Integration (CI)** and **Continuous Delivery/Deployment (CD)** are practices that automate the process of getting code changes from a developer's machine into production.

### Continuous Integration

CI is the practice of frequently merging code changes into a shared repository, where automated builds and tests verify each change. The goal is to catch problems early, when they're cheapest to fix.

A CI pipeline typically:
1. Runs on every pull request or push
2. Builds the application
3. Executes automated tests (unit, integration, end-to-end)
4. Performs static analysis and security scanning
5. Produces a deployable artifact (e.g., a container image)

### Continuous Delivery vs. Continuous Deployment

These terms are often used interchangeably but have a key difference:

- **Continuous Delivery** — every change that passes CI *can* be deployed to production, but a human approves the release
- **Continuous Deployment** — every change that passes CI *is* deployed to production automatically

This project uses **Continuous Delivery**: the CD pipeline deploys to a staging slot automatically, then pauses for human approval before swapping to production.

## How This Project Uses CI/CD

This project implements CI/CD through three GitHub Actions workflows:

| Workflow | Purpose | Trigger |
|----------|---------|---------|
| `ci.yml` | Test, scan, and build the container image | Pull requests, manual dispatch |
| `cd.yml` | Deploy to staging, approval gate, swap to production | After CI succeeds, manual dispatch |
| `terraform.yml` | Plan and apply infrastructure changes | PRs to `infrastructure/`, manual dispatch |

### CI Pipeline (`ci.yml`)

The CI pipeline has three sequential stages:

- **Test** — Runs pytest unit tests and Playwright end-to-end browser tests
- **Security Scan** — CodeQL static analysis (code scanning) and dependency review (supply chain security), both part of [GitHub Advanced Security](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security)
- **Build & Push** — Builds the Docker container and pushes it to Azure Container Registry

### CD Pipeline (`cd.yml`)

The CD pipeline picks up where CI left off:

- **Deploy to Staging** — Pushes the container to the App Service staging slot and waits for a health check
- **Swap to Production** — Pauses for approval via a [GitHub Environment protection rule](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment), then performs a zero-downtime slot swap

### Infrastructure Pipeline (`terraform.yml`)

Infrastructure changes follow a similar pattern:

- **On PR** — Runs `terraform plan` and posts the plan as a PR comment for review
- **On manual dispatch** — Runs `terraform apply` to provision or update Azure resources

## Key Concepts

### Deployment Slots (Blue/Green)

Azure App Service [deployment slots](https://learn.microsoft.com/en-us/azure/app-service/deploy-staging-slots) allow running two versions of the application side by side. The staging slot receives the new version, gets validated, and then swaps into production with zero downtime. If something goes wrong, the swap can be reversed.

### Approval Gates

GitHub [environment protection rules](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment#deployment-protection-rules) pause a workflow and require designated reviewers to approve before the job proceeds. This project uses an approval gate between the staging deployment and the production swap.

### Workload Identity Federation

Instead of storing Azure credentials as secrets, this project uses [Workload Identity Federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation) (OIDC). GitHub Actions presents a short-lived token that Azure trusts directly — no client secrets to rotate or leak.

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Advanced Security Overview](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security)
- [Azure App Service Deployment Best Practices](https://learn.microsoft.com/en-us/azure/app-service/deploy-best-practices)
- [Workload Identity Federation for GitHub Actions](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- [Terraform on Azure](https://learn.microsoft.com/en-us/azure/developer/terraform/)
