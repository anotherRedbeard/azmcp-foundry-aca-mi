# User-Passthrough/OBO Deployment

Use this variant when Azure RBAC must be evaluated for each signed-in user. The user's delegated identity flows through Foundry and APIM, and Azure MCP uses OAuth on-behalf-of (OBO) for downstream Azure access.

Do not combine this deployment with files, resources, connections, or `azd` environments from [`../managed-identity`](../managed-identity/).

## Architecture

```text
Browser -> Web app -> APIM -> Foundry agent -> APIM MCP server
   user token                                      user token
                                                       |
                                                       v
                                         Azure MCP Container App
                                                       |
                                                       v
                                           Azure access through OBO
```

The editable diagram is [`foundry-apim-mcp-user-passthrough.excalidraw`](foundry-apim-mcp-user-passthrough.excalidraw).

## Prerequisites

- Azure subscription access to deploy resources and create role assignments
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Azure CLI
- Python 3.11 or later
- Node.js 20 or later
- Permission to configure Entra applications, federated credentials, and tenant-wide delegated API consent

Sign in with accounts from the same tenant:

```bash
azd auth login
az login
azd auth login --check-status
az account show --query "{user:user.name, tenantId:tenantId, subscription:id}"
```

## 1. Configure Entra applications

### SPA registration

Create or reuse a single-tenant SPA registration:

1. Add the **Single-page application** platform.
2. Add `http://localhost:3000` as a redirect URI.
3. Add the **Azure Machine Learning Services** delegated `user_impersonation` permission.
4. Grant consent according to tenant policy.
5. Do not create a client secret.

Select **Azure Machine Learning Services** by name, then add its delegated
`user_impersonation` permission. No application or permission ID needs to be
copied into this repository.

### Foundry MCP OAuth client

Create a separate single-tenant confidential client:

1. Record its application/client ID.
2. Create a client secret and store it securely.
3. Do not add a redirect URI yet. Foundry provides it when the connection is created.

The secret belongs only in the Foundry connection. Do not commit it or add it to the web application.

## 2. Configure the deployment

Run all commands from this directory:

```bash
cd user-passthrough
azd show
```

`azd show` must report:

```text
azure-mcp-server-user-passthrough
```

Create the local environment file:

```bash
cp azd.env.example azd.env
```

PowerShell:

```powershell
Copy-Item azd.env.example azd.env
```

Replace every placeholder in `azd.env`:

```dotenv
AZURE_LOCATION="eastus2"
APIM_PUBLISHER_NAME="Contoso Publisher"
APIM_PUBLISHER_EMAIL="admin@example.com"
SPA_CLIENT_ID="<spa-client-id>"
API_CLIENT_ID="<foundry-mcp-oauth-client-id>"
WEB_APP_ORIGIN="http://localhost:3000"
```

`API_CLIENT_ID` is the Foundry MCP OAuth client ID. Do not put its secret in this file, and do not commit `azd.env`.

Create the `azd` environment and import the values:

```bash
azd env new user-passthrough-dev
azd env set --file azd.env
azd env get-values
```

## 3. Set the Foundry agent name

The prompt agent is created manually, so its name is maintained directly in:

```text
infra/modules/policies/responses.xml
```

The deployed agent name is `MyMcpPassthroughAgent`. The policy omits `version`, so Foundry uses the latest active agent version.

## 4. Deploy

```bash
azd up
```

The deployment declares these downstream delegated permissions on the MCP server application:

- Azure Resource Manager `user_impersonation`
- Azure Storage `user_impersonation`
- Azure Resource Manager MCP `MCP.Access`

It also ensures the first-party **ARM MCP Server** enterprise application exists in the tenant. Grant tenant-wide admin consent for all three permissions:

```bash
az ad app permission admin-consent --id "$(azd env get-value ENTRA_APP_CLIENT_ID)"
```

Inspect the outputs:

```bash
azd env get-values
```

The most important outputs are:

```text
APIM_GATEWAY_URL
APIM_TEST_SUBSCRIPTION_ID
RESPONSES_API_URL
MCP_API_URL
AZURE_AI_PROJECT_ID
AZURE_AI_PROJECT_ENDPOINT
AZURE_AI_GPT5_DEPLOYMENT_NAME
AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME
ENTRA_APP_CLIENT_ID
ENTRA_APP_IDENTIFIER_URI
ENTRA_APP_SCOPE_ID
ENTRA_APP_SCOPE_VALUE
CONTAINER_APP_NAME
APPLICATION_INSIGHTS_NAME
```

Do not grant Reader or data-plane roles to the OBO managed identity. Azure authorization must come from the signed-in user.

## 5. Create the Foundry agent

Before creating the agent, grant your signed-in user the **Foundry User** role on the deployed Foundry project:

```bash
az role assignment create \
  --assignee "$(az ad signed-in-user show --query id --output tsv)" \
  --role "Foundry User" \
  --scope "$(azd env get-value AZURE_AI_PROJECT_ID)"
```

Allow about five minutes for the role assignment to propagate before creating the agent. If Foundry still reports an authorization error, wait a few more minutes and retry.

Then, in the deployed Foundry project:

1. Create the agent using the name configured in `responses.xml`.
2. Use `AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME` for initial testing or `AZURE_AI_GPT5_DEPLOYMENT_NAME` for higher-quality testing.
3. Save and publish the agent.

## 6. Create the OAuth MCP connection

Grant the confidential OAuth client the MCP application's delegated `Mcp.Tools.ReadWrite` permission:

```bash
az ad app permission add \
  --id "<foundry-mcp-oauth-client-id>" \
  --api "$(azd env get-value ENTRA_APP_CLIENT_ID)" \
  --api-permissions "$(azd env get-value ENTRA_APP_SCOPE_ID)=Scope"
```

Create the Foundry remote-tool connection:

```bash
azd ai connection create AzureMcpApim2 \
  --kind remote-tool \
  --target "$(azd env get-value MCP_API_URL)" \
  --auth-type oauth2 \
  --authorization-url "https://login.microsoftonline.com/$(azd env get-value AZURE_TENANT_ID)/oauth2/v2.0/authorize" \
  --token-url "https://login.microsoftonline.com/$(azd env get-value AZURE_TENANT_ID)/oauth2/v2.0/token" \
  --refresh-url "https://login.microsoftonline.com/$(azd env get-value AZURE_TENANT_ID)/oauth2/v2.0/token" \
  --client-id "$(azd env get-value API_CLIENT_ID)" \
  --client-secret "<store-securely-and-do-not-commit>" \
  --scopes "openid offline_access api://$(azd env get-value ENTRA_APP_CLIENT_ID)/Mcp.Tools.ReadWrite" \
  --project-endpoint "$(azd env get-value AZURE_AI_PROJECT_ENDPOINT)"
```

Add Foundry's required redirect URI to the confidential client registration, complete the connection's OAuth consent flow, and attach the connection directly to the agent's MCP tool.

Set `project_connection_id` to `AzureMcpApim2` and use `require_approval: always`. The sample web application renders each MCP tool request and sends an explicit approval or rejection before Foundry continues.

Do not use Project Managed Identity or Agent Identity for this connection.

## 7. Test the agent

In the Foundry agent playground, submit:

```text
Use Azure Resource Graph to list up to five resource groups I can access.
Return the resource group name and location.
```

Complete OAuth consent using the same account that invoked the agent. Results must match that user's Azure RBAC permissions.

The user needs:

- A Foundry project role that permits agent invocation
- Consent for Foundry `user_impersonation`
- Consent for `Mcp.Tools.ReadWrite`
- Azure RBAC for the resources being queried

## 8. Run the web application

Retrieve the APIM test subscription key through an authorized workflow and store it only in the web application's `.env` file.

macOS and Linux:

```bash
cd agent-web-app
cp .env.example .env
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
npm ci
npm run build
python -m app.main
```

If `python3` resolves to the removed root-level `agent-web-app/.venv`, reset the old environment before creating this one:

```bash
deactivate 2>/dev/null || true
unset VIRTUAL_ENV
hash -r
```

PowerShell:

```powershell
cd agent-web-app
Copy-Item .env.example .env
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
npm ci
npm run build
python -m app.main
```

Open <http://localhost:3000>. See [`agent-web-app/README.md`](agent-web-app/README.md) for its required settings.

## Verify and troubleshoot

Validate the web application:

```bash
cd agent-web-app
npm run check
python -m compileall app
docker build .
```

Inspect Container App logs:

```bash
az containerapp logs show \
  --name "$(azd env get-value CONTAINER_APP_NAME)" \
  --resource-group <resource-group> \
  --follow
```

Application Insights should contain `POST` and `GET` requests for `/mcp/user-passthrough/mcp`. APIM uses 100% sampling, information verbosity, and up to 8 KB of frontend and backend request and response body capture. Authentication headers are excluded.

| Error | Check |
|---|---|
| `The 'agent' property is deprecated` | Send `agent_reference`; the APIM policy injects it automatically. |
| Agent name/version not found | Confirm the published agent name exactly matches `responses.xml`. Do not add a version. |
| Unexpected Foundry token claims | Confirm the v1 token has `aud=https://ai.azure.com`, `scp=user_impersonation`, and the expected SPA ID in `appid`. |
| APIM returns `401` with `AzureApiManagementKey` | Send a valid key in `Ocp-Apim-Subscription-Key`. |
| MCP token has no delegated scope | Confirm the OAuth connection requests `api://<mcp-app-id>/Mcp.Tools.ReadWrite`. |
| MCP calls work initially, then APIM reports `TokenExpired` | Recreate the custom OAuth connection with `offline_access` and set the refresh URL to the tenant v2 token endpoint. Reauthorize the user after recreating the connection. |
| Users see the wrong Azure resources | Confirm both APIM gateways preserve the bearer token, Azure MCP uses `UseOnBehalfOf`, and no legacy Reader assignment remains on the MCP identities. |

## Upgrading an older managed-identity deployment

Deploy this variant into a new `azd` environment. After confirming OBO works, review and remove only the obsolete Reader or data-plane assignments belonging to the old Container App identity:

```bash
az role assignment list \
  --assignee-object-id "<old-container-app-principal-id>" \
  --all \
  --include-inherited \
  --output table
```

Do not remove assignments used by other workloads.

## Clean up

```bash
azd down
```
