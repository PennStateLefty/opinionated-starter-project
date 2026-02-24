# Pipeline Flow

This document walks through how a code change moves from a developer's pull request all the way to production. Each section covers one phase of the journey.

## End-to-End Overview

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant GH as GitHub
    participant CI as CI Workflow
    participant CD as CD Workflow
    participant ACR as Azure Container Registry
    participant Staging as App Service (Staging)
    participant Prod as App Service (Production)

    Dev->>GH: Open Pull Request
    GH->>CI: Trigger CI pipeline
    CI->>CI: Run tests (unit + E2E)
    CI->>CI: Security scan (CodeQL + dependency review)
    CI->>ACR: Build & push container image
    CI-->>GH: Report status ✅

    GH->>CD: Trigger CD pipeline
    CD->>Staging: Deploy container to staging slot
    CD->>Staging: Health check (poll /health)
    Staging-->>CD: 200 OK

    CD-->>GH: Request approval
    actor Reviewer as Reviewer
    Reviewer->>GH: Approve deployment
    GH->>CD: Resume pipeline

    CD->>Prod: Swap staging → production
    CD->>Prod: Verify production health
    Prod-->>CD: 200 OK
    CD-->>GH: Deployment complete ✅
```

## Phase 1: Continuous Integration

When a developer opens a pull request that touches `src/hello-world/` or the CI workflow itself, the CI pipeline runs automatically.

### Test Stage

```mermaid
sequenceDiagram
    participant Runner as GitHub Runner
    participant Pytest as pytest
    participant Flask as Flask App
    participant Browser as Playwright Browser

    Runner->>Runner: Checkout code
    Runner->>Runner: Setup Python 3.12
    Runner->>Runner: pip install requirements-dev.txt

    Runner->>Pytest: Run unit tests (test_app.py)
    Pytest-->>Runner: Results

    Runner->>Runner: Install Playwright + Chromium
    Runner->>Flask: Start Flask subprocess
    Runner->>Pytest: Run E2E tests (test_e2e.py)
    Pytest->>Browser: Launch headless Chromium
    Browser->>Flask: GET http://localhost:8000
    Flask-->>Browser: HTML response
    Browser-->>Pytest: Assert page content
    Pytest-->>Runner: Results
```

### Security Stage

Runs only after tests pass. Uses GitHub Advanced Security features.

```mermaid
sequenceDiagram
    participant Runner as GitHub Runner
    participant CodeQL as CodeQL Engine
    participant DepReview as Dependency Review

    Runner->>Runner: Checkout code
    Runner->>CodeQL: Initialize (Python)
    Runner->>CodeQL: Autobuild
    Runner->>CodeQL: Analyze
    CodeQL-->>Runner: Upload SARIF results to Code Scanning

    Runner->>DepReview: Review dependency changes
    DepReview->>DepReview: Check for high-severity vulnerabilities
    DepReview-->>Runner: Pass / Fail
```

### Build Stage

Runs only on manual dispatch or merged PRs. Produces the container image.

```mermaid
sequenceDiagram
    participant Runner as GitHub Runner
    participant Azure as Azure (OIDC)
    participant ACR as Container Registry

    Runner->>Azure: Login via Workload Identity Federation
    Azure-->>Runner: Access token
    Runner->>ACR: az acr login
    Runner->>Runner: docker build (python:3.12-slim)
    Runner->>ACR: docker push :sha
    Runner->>ACR: docker push :latest
    Runner-->>Runner: Output image tag = commit SHA
```

## Phase 2: Continuous Delivery

The CD pipeline triggers automatically when CI completes successfully, or can be triggered manually with a specific image tag.

### Deploy to Staging

```mermaid
sequenceDiagram
    participant Runner as GitHub Runner
    participant Azure as Azure (OIDC)
    participant AppSvc as App Service
    participant Staging as Staging Slot

    Runner->>Azure: Login via Workload Identity Federation
    Runner->>Runner: Determine image tag (SHA or manual input)
    Runner->>AppSvc: az webapp config container set --slot staging
    AppSvc->>Staging: Pull image from ACR

    loop Health check (up to 30 attempts)
        Runner->>Staging: GET /health
        alt Healthy
            Staging-->>Runner: 200 OK
        else Not ready
            Staging-->>Runner: non-200
            Runner->>Runner: Wait 10 seconds
        end
    end
```

### Approval Gate & Production Swap

```mermaid
sequenceDiagram
    actor Reviewer as Reviewer
    participant GH as GitHub
    participant Runner as GitHub Runner
    participant Azure as Azure (OIDC)
    participant AppSvc as App Service

    Runner-->>GH: Job references 'production' environment
    GH-->>GH: Pause — waiting for approval
    GH->>Reviewer: Notification: deployment pending review

    Reviewer->>GH: Approve

    GH->>Runner: Resume swap-production job
    Runner->>Azure: Login via Workload Identity Federation
    Note right of Runner: Uses environment:production<br/>federated credential
    Runner->>AppSvc: az webapp deployment slot swap --slot staging
    AppSvc->>AppSvc: Swap staging ↔ production (zero downtime)

    Runner->>AppSvc: GET /health (production)
    AppSvc-->>Runner: 200 OK ✅
```

## Phase 3: Infrastructure (Terraform)

Infrastructure changes follow a separate workflow, triggered by changes to the `infrastructure/` directory.

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant GH as GitHub
    participant Runner as GitHub Runner
    participant Azure as Azure (OIDC)
    participant ARM as Azure Resource Manager

    Dev->>GH: Open PR (infrastructure/ changes)
    GH->>Runner: Trigger Terraform workflow

    Runner->>Azure: Login via Workload Identity Federation
    Runner->>Runner: terraform init
    Runner->>Runner: terraform validate
    Runner->>ARM: terraform plan
    ARM-->>Runner: Execution plan

    Runner->>GH: Post plan as PR comment

    Note over Dev,GH: Developer reviews plan in PR

    Dev->>GH: Manual dispatch (action: apply)
    GH->>Runner: Trigger Terraform workflow
    Runner->>Azure: Login
    Runner->>ARM: terraform apply
    ARM-->>Runner: Resources provisioned ✅
```
