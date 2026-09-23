# Deploy Both Web Applications

This deployment creates one resource group, Azure Container Registry, Log
Analytics workspace, and Azure Container Apps environment. It then builds and
deploys the two existing web applications as separate public Container Apps.

It reuses the existing APIM, Microsoft Foundry, and Entra resources. It does not
deploy either complete identity stack and does not use `azd`.

## 1. Create the GitHub OIDC credential

The deployment application is:

```text
spGithubActionsDemo
a448f016-1354-4b2c-b050-c6aa6d63d1ea
```

Create a federated credential for the GitHub Environment:

```bash
cat > federated-credential.json <<'JSON'
{
  "name": "github-azure-webapps-dev",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:anotherRedbeard/azmcp-foundry-aca-mi:environment:azure-webapps-dev",
  "description": "Deploy the dual web-host Container Apps environment",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
JSON

az ad app federated-credential create \
  --id a448f016-1354-4b2c-b050-c6aa6d63d1ea \
  --parameters @federated-credential.json

rm federated-credential.json
```

The service principal already requires these roles at subscription scope:

```text
Contributor
User Access Administrator
```

`User Access Administrator` is required because Bicep grants the Container Apps
pull identity `AcrPull` on the new registry.

## 2. Create the GitHub Environment

Create the environment:

```bash
gh api \
  --method PUT \
  repos/anotherRedbeard/azmcp-foundry-aca-mi/environments/azure-webapps-dev
```

Add deployment identity variables:

```bash
gh variable set AZURE_CLIENT_ID \
  --env azure-webapps-dev \
  --body a448f016-1354-4b2c-b050-c6aa6d63d1ea

gh variable set AZURE_TENANT_ID \
  --env azure-webapps-dev \
  --body 7f2ca508-a0fb-428b-b25e-cdfc4f5dc55b

gh variable set AZURE_SUBSCRIPTION_ID \
  --env azure-webapps-dev \
  --body 0272c02b-5a38-4b6b-86e6-dcc4ff2ff0e8
```

Add the managed-identity application variables:

```bash
gh variable set MANAGED_ENTRA_SPA_CLIENT_ID \
  --env azure-webapps-dev \
  --body "<managed-spa-client-id>"

gh variable set MANAGED_ENTRA_API_SCOPE \
  --env azure-webapps-dev \
  --body "api://<managed-responses-api-client-id>/access_as_user"

gh variable set MANAGED_APIM_RESPONSES_URL \
  --env azure-webapps-dev \
  --body "https://<managed-apim-name>.azure-api.net/agent/responses"
```

Add the user-passthrough application variables:

```bash
gh variable set PASSTHROUGH_ENTRA_SPA_CLIENT_ID \
  --env azure-webapps-dev \
  --body "<passthrough-spa-client-id>"

gh variable set PASSTHROUGH_FOUNDRY_API_SCOPE \
  --env azure-webapps-dev \
  --body "https://ai.azure.com/user_impersonation"

gh variable set PASSTHROUGH_APIM_RESPONSES_URL \
  --env azure-webapps-dev \
  --body "https://<passthrough-apim-name>.azure-api.net/agent/responses"
```

Add both APIM keys as environment secrets. Each command prompts for the value:

```bash
gh secret set MANAGED_APIM_SUBSCRIPTION_KEY --env azure-webapps-dev
gh secret set PASSTHROUGH_APIM_SUBSCRIPTION_KEY --env azure-webapps-dev
```

## 3. Run the workflow

Run it manually:

```bash
gh workflow run deploy-web-apps.yml --ref main
```

Watch the run:

```bash
gh run watch
```

The workflow runs only when manually dispatched.

The workflow:

1. signs in to Azure with OIDC;
2. validates and deploys the resource group and shared foundation with Bicep;
3. builds both images in ACR with immutable commit-SHA tags;
4. validates and deploys both Container Apps with Bicep;
5. verifies both `/health` endpoints; and
6. publishes both application URLs in the workflow summary.

## 4. Add SPA redirect URIs

Both clients use their current origin as the MSAL redirect URI. After the first
deployment, copy the two URLs from the workflow summary.

In the Azure portal, open each matching SPA application registration:

1. Select **Authentication**.
2. Under **Single-page application**, add that application's Container App URL.
3. Do not remove its existing local or deployed redirect URIs.
4. Save the application.

Use the managed URL only on the managed SPA registration and the passthrough URL
only on the passthrough SPA registration.

## Resources

The default names are:

```text
Resource group: rg-azmcp-webapps-dev
Container Apps environment: cae-azmcp-webapps-dev
Managed web app: ca-azmcp-managed-identity
Passthrough web app: ca-azmcp-user-passthrough
```

The registry name has a stable generated suffix because ACR names must be
globally unique.

Both apps use public HTTPS ingress, scale from zero to three replicas, and pull
images with a shared user-assigned identity that has only `AcrPull`.

## Cleanup

Delete only the shared web-host resource group:

```bash
az group delete \
  --name rg-azmcp-webapps-dev \
  --yes \
  --no-wait
```

This does not delete either existing APIM, Foundry, MCP, or Entra deployment.
