# Managed-Identity Deployment

Use this variant when every user should receive the same Azure access. Azure RBAC is evaluated for the Azure MCP Container App's managed identity.

Do not combine this deployment with files, resources, connections, or `azd` environments from [`../user-passthrough`](../user-passthrough/).

## Architecture

```text
Browser -> Web app -> APIM -> Foundry agent -> APIM MCP server
                                                    |
                                                    v
                                      Azure MCP Container App
                                                    |
                                                    v
                               Azure access through managed identity
```

The editable diagram is [`foundry-apim-mcp-managed-identity.excalidraw`](foundry-apim-mcp-managed-identity.excalidraw).

## Prerequisites

- Azure subscription access to deploy resources and create role assignments
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Azure CLI
- Node.js 20 or later
- Permission to configure Entra application registrations

Sign in with accounts from the same tenant:

```bash
azd auth login
az login
azd auth login --check-status
az account show --query "{user:user.name, tenantId:tenantId, subscription:id}"
```

## 1. Configure Entra applications

Create or reuse two single-tenant registrations.

### SPA registration

1. Add the **Single-page application** platform.
2. Add `http://localhost:3000` as a redirect URI.
3. Do not create a client secret.

### Responses API registration

1. Expose an API using `api://<responses-api-client-id>`.
2. Add the delegated scope `access_as_user`.
3. Add that permission to the SPA registration.
4. Set `requestedAccessTokenVersion` to `2` in the manifest.
5. Do not create a client secret.

Record both application/client IDs.

## 2. Configure the deployment

Run all commands from this directory:

```bash
cd managed-identity
azd show
```

`azd show` must report:

```text
azure-mcp-server-managed-identity
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
SPA_CLIENT_ID="00000000-0000-0000-0000-000000000000"
RESPONSES_API_CLIENT_ID="00000000-0000-0000-0000-000000000000"
WEB_APP_ORIGIN="http://localhost:3000"
```

Do not commit `azd.env`.

Create the `azd` environment and import the values:

```bash
azd env new managed-identity-dev
azd env set --file azd.env
azd env get-values
```

## 3. Set the Foundry agent name

The prompt agent is created manually, so its name is maintained directly in:

```text
infra/modules/policies/responses.xml
```

The default name is `MyMCPAgentDemo`. Either use that name when creating the agent or update the policy before deployment. The policy omits `version`, so Foundry uses the latest active agent version.

## 4. Deploy

```bash
azd up
```

After deployment, inspect the outputs:

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
ENTRA_APP_IDENTIFIER_URI
ENTRA_APP_INSPECTOR_ROLE_ID
ENTRA_APP_SERVICE_PRINCIPAL_ID
CONTAINER_APP_NAME
APPLICATION_INSIGHTS_NAME
```

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

## 6. Connect the agent to APIM MCP

1. Open the agent in Foundry.
2. Select **Add tool** -> **Custom** -> **Model Context Protocol**.
3. Use the `MCP_API_URL` output. Its path should end with:

   ```text
   /mcp/managed-identity/mcp
   ```

4. Select **Microsoft Entra** and **Project Managed Identity**.
5. Set the audience to the `ENTRA_APP_IDENTIFIER_URI` output.
6. Set `require_approval` to `always` so the sample web application prompts before MCP tool execution.
7. Save the connection and attach it directly to the agent.

Use `MCP_API_URL`, not `CONTAINER_APP_URL`.

## 7. Test the agent

In the Foundry agent playground, submit:

```text
Use Azure Resource Graph to list up to five resource groups I can access.
Return the resource group name and location.
```

Approve the MCP tool call when prompted. Results are limited by the Container App managed identity's Azure RBAC assignments.

## 8. Run the web application

Retrieve the APIM test subscription key through an authorized workflow and store it only in the web application's `.env` file.

```bash
cd agent-web-app
cp .env.example .env
npm install
npm run dev
```

Open <http://localhost:3000>. See [`agent-web-app/README.md`](agent-web-app/README.md) for its required settings.

## 9. Use MCP Inspector through APIM

To use MCP Inspector through APIM, first assign your user the **Azure MCP Inspector Access** role on the MCP enterprise application:

```bash
USER_OBJECT_ID="$(az ad signed-in-user show --query id --output tsv)"
MCP_SERVICE_PRINCIPAL_ID="$(azd env get-value ENTRA_APP_SERVICE_PRINCIPAL_ID)"
INSPECTOR_ROLE_ID="$(azd env get-value ENTRA_APP_INSPECTOR_ROLE_ID)"

az rest \
  --method post \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/${MCP_SERVICE_PRINCIPAL_ID}/appRoleAssignedTo" \
  --body "{\"principalId\":\"${USER_OBJECT_ID}\",\"resourceId\":\"${MCP_SERVICE_PRINCIPAL_ID}\",\"appRoleId\":\"${INSPECTOR_ROLE_ID}\"}"
```

Allow about five minutes for the assignment to propagate. Then launch MCP Inspector from the `managed-identity/` directory:

```bash
./mcp-inspector-startup.sh
```

PowerShell:

```powershell
.\mcp-inspector-startup.ps1
```

The scripts connect to `MCP_API_URL` using your delegated `Mcp.Tools.ReadWrite` token. APIM permits either the Foundry project managed identity or a user assigned the `Mcp.Inspector.Access` role, then authenticates to the managed-identity MCP backend.

## Verify and troubleshoot

Validate the web application:

```bash
cd agent-web-app
npm run check
docker build .
```

Inspect Container App logs:

```bash
az containerapp logs show \
  --name "$(azd env get-value CONTAINER_APP_NAME)" \
  --resource-group <resource-group> \
  --follow
```

Application Insights should contain `POST` and `GET` requests for `/mcp/managed-identity/mcp`. APIM uses 100% sampling, information verbosity, and up to 8 KB of frontend and backend request and response body capture. Authentication headers are excluded.

| Error | Check |
|---|---|
| `The 'agent' property is deprecated` | Send `agent_reference`; the APIM policy injects it automatically. |
| Agent name/version not found | Confirm the published agent name exactly matches `responses.xml`. Do not add a version. |
| Unexpected `iss` claim | Confirm the Responses API registration uses `requestedAccessTokenVersion: 2`. |
| APIM returns `401` with `AzureApiManagementKey` | Send a valid key in `Ocp-Apim-Subscription-Key`. |
| APIM returns `403 MCP caller is not authorized` | Assign the user `Azure MCP Inspector Access`, wait about five minutes, and rerun the Inspector script to obtain a new token. |
| MCP token has no `roles` claim | Confirm both Foundry project and APIM managed identities have `Mcp.Tools.ReadWrite.All`; allow time for token-cache expiration after assignment. |

## Clean up

```bash
azd down
```
