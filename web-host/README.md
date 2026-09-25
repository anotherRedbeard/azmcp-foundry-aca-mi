# Deploy Both Web Applications

This manual GitHub Actions workflow creates a shared Azure Container Apps
environment and deploys both web front ends. It reuses your existing APIM,
Foundry, MCP, and Entra resources. It does not use `azd`.

## Prerequisites

- An Entra application for GitHub Actions
- `Contributor` and `User Access Administrator` on the target subscription
- Existing managed-identity and user-passthrough deployments

## 1. Configure GitHub OIDC

On the Entra application used by GitHub Actions, add a federated credential for
a GitHub Actions deployment environment:

| Setting | Value |
| --- | --- |
| Organization | `<github-owner>` |
| Repository | `<github-repository>` |
| Entity type | Environment |
| Environment | `<github-environment>` |
| Credential name | Any descriptive name |

The environment value must exactly match the GitHub Environment selected when
the workflow runs.

## 2. Configure the GitHub Environment

Create the GitHub Environment and add these variables:

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | `<github-deployment-client-id>` |
| `AZURE_TENANT_ID` | `<azure-tenant-id>` |
| `AZURE_SUBSCRIPTION_ID` | `<azure-subscription-id>` |
| `MANAGED_ENTRA_SPA_CLIENT_ID` | `<managed-spa-client-id>` |
| `MANAGED_ENTRA_API_SCOPE` | `api://<managed-responses-api-client-id>/access_as_user` |
| `MANAGED_APIM_RESPONSES_URL` | `https://<managed-apim-name>.azure-api.net/agent/responses` |
| `PASSTHROUGH_ENTRA_SPA_CLIENT_ID` | `<passthrough-spa-client-id>` |
| `PASSTHROUGH_FOUNDRY_API_SCOPE` | `https://ai.azure.com/user_impersonation` |
| `PASSTHROUGH_APIM_RESPONSES_URL` | `https://<passthrough-apim-name>.azure-api.net/agent/responses` |

Add these environment secrets:

| Secret | Value |
| --- | --- |
| `MANAGED_APIM_SUBSCRIPTION_KEY` | Managed-identity APIM subscription key |
| `PASSTHROUGH_APIM_SUBSCRIPTION_KEY` | User-passthrough APIM subscription key |

## 3. Deploy

Run **Deploy dual web apps** from the repository's **Actions** page.

The workflow inputs allow you to select:

- GitHub Environment
- Azure region
- Resource naming prefix
- Managed-identity Container App name
- User-passthrough Container App name

The workflow validates the Bicep templates, builds both images in ACR, deploys
both Container Apps, verifies their health endpoints, and publishes both URLs
in the run summary.

## 4. Configure SPA redirects

Copy both Container App URLs from the workflow summary. Add each URL under
**Authentication > Single-page application** on its matching SPA registration:

- Managed URL → managed-identity SPA
- User-passthrough URL → user-passthrough SPA

## Cleanup

Delete the resource group created by the workflow. With the default naming
prefix, its name is:

```text
rg-azmcp-webapps-dev
```

This deletes only the shared web-host resources.
