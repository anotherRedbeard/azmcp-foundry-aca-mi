# Deploy Both Web Applications

This manual GitHub Actions workflow creates a shared Azure Container Apps
environment and deploys both web front ends. It reuses your existing APIM,
Foundry, MCP, and Entra resources. It does not use `azd`.

## Prerequisites

- Azure CLI and GitHub CLI
- An Entra application for GitHub Actions
- `Contributor` and `User Access Administrator` on the target subscription
- Existing managed-identity and user-passthrough deployments

Set these values:

```bash
GITHUB_REPOSITORY="<owner>/<repository>"
GITHUB_ENVIRONMENT="azure-webapps-dev"
DEPLOYMENT_CLIENT_ID="<github-deployment-client-id>"
AZURE_TENANT_ID="<azure-tenant-id>"
AZURE_SUBSCRIPTION_ID="<azure-subscription-id>"
```

Find the current tenant and subscription:

```bash
az account show --query "{tenantId:tenantId, subscriptionId:id}" --output table
```

## 1. Configure GitHub OIDC

Create a federated credential on the deployment application:

```bash
jq -n \
  --arg name "github-${GITHUB_ENVIRONMENT}" \
  --arg subject "repo:${GITHUB_REPOSITORY}:environment:${GITHUB_ENVIRONMENT}" \
  '{
    name: $name,
    issuer: "https://token.actions.githubusercontent.com",
    subject: $subject,
    audiences: ["api://AzureADTokenExchange"]
  }' > federated-credential.json

az ad app federated-credential create \
  --id "$DEPLOYMENT_CLIENT_ID" \
  --parameters @federated-credential.json

rm federated-credential.json
```

## 2. Configure the GitHub Environment

```bash
gh api --method PUT \
  "repos/${GITHUB_REPOSITORY}/environments/${GITHUB_ENVIRONMENT}"

gh variable set AZURE_CLIENT_ID \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "$DEPLOYMENT_CLIENT_ID"

gh variable set AZURE_TENANT_ID \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "$AZURE_TENANT_ID"

gh variable set AZURE_SUBSCRIPTION_ID \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "$AZURE_SUBSCRIPTION_ID"
```

Add the managed-identity settings:

```bash
gh variable set MANAGED_ENTRA_SPA_CLIENT_ID \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "<managed-spa-client-id>"

gh variable set MANAGED_ENTRA_API_SCOPE \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "api://<managed-responses-api-client-id>/access_as_user"

gh variable set MANAGED_APIM_RESPONSES_URL \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "https://<managed-apim-name>.azure-api.net/agent/responses"
```

Add the user-passthrough settings:

```bash
gh variable set PASSTHROUGH_ENTRA_SPA_CLIENT_ID \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "<passthrough-spa-client-id>"

gh variable set PASSTHROUGH_FOUNDRY_API_SCOPE \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "https://ai.azure.com/user_impersonation"

gh variable set PASSTHROUGH_APIM_RESPONSES_URL \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT" \
  --body "https://<passthrough-apim-name>.azure-api.net/agent/responses"
```

Add both APIM subscription keys when prompted:

```bash
gh secret set MANAGED_APIM_SUBSCRIPTION_KEY \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT"

gh secret set PASSTHROUGH_APIM_SUBSCRIPTION_KEY \
  --repo "$GITHUB_REPOSITORY" --env "$GITHUB_ENVIRONMENT"
```

## 3. Deploy

Run the manual workflow:

```bash
gh workflow run deploy-web-apps.yml \
  --repo "$GITHUB_REPOSITORY" \
  --ref main \
  --field github_environment="$GITHUB_ENVIRONMENT"

gh run watch --repo "$GITHUB_REPOSITORY"
```

The workflow form also allows you to change the Azure region, naming prefix,
and both Container App names.

## 4. Configure SPA redirects

Copy both Container App URLs from the workflow summary. Add each URL under
**Authentication > Single-page application** on its matching SPA registration:

- Managed URL → managed-identity SPA
- User-passthrough URL → user-passthrough SPA

## Cleanup

```bash
NAMING_PREFIX="azmcp-webapps-dev"

az group delete --name "rg-${NAMING_PREFIX}" --yes --no-wait
```

This deletes only the shared web-host resources.
