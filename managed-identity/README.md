# Managed-Identity Deployment

Use this variant when every user should receive the same Azure access. Azure RBAC is evaluated for the Azure MCP Container App's managed identity.

Do not combine this deployment with files, resources, connections, or core
deployment outputs from [`../user-passthrough`](../user-passthrough/).

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
- Azure CLI
- Node.js 20 or later
- Permission to configure Entra application registrations
- A GitHub Actions deployment application configured for OIDC
- `Contributor` and `User Access Administrator` on the target subscription

See [`../web-host/README.md`](../web-host/README.md) for the GitHub OIDC
federated-credential pattern.

## 1. Configure Entra applications

Create or reuse three single-tenant registrations.

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

### MCP protected API registration

Create a single-tenant registration for the managed-identity MCP endpoint:

1. Set its Application ID URI to `api://<mcp-app-client-id>`.
2. Set `requestedAccessTokenVersion` to `2`.
3. Add delegated scope `Mcp.Tools.ReadWrite`.
4. Add application role `Mcp.Tools.ReadWrite.All` with **Applications** as the
   allowed member type.
5. Add application role `Mcp.Inspector.Access` with **Users/Groups** as the
   allowed member type.
6. Ensure its enterprise application/service principal exists.

Record:

- Application/client ID
- Enterprise application object ID
- Application ID URI
- `Mcp.Tools.ReadWrite.All` role ID
- `Mcp.Inspector.Access` role ID

## 2. Configure the infrastructure workflow

Create the `managed-identity-infra-dev` GitHub Environment. Add these secrets:

| Secret | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | GitHub deployment application client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

Add these variables:

| Variable | Value |
| --- | --- |
| `APIM_PUBLISHER_NAME` | APIM publisher name |
| `APIM_PUBLISHER_EMAIL` | APIM publisher email |
| `SPA_CLIENT_ID` | SPA application client ID |
| `RESPONSES_API_CLIENT_ID` | Protected Responses API client ID |
| `MCP_APP_CLIENT_ID` | MCP protected API application/client ID |
| `MCP_APP_SERVICE_PRINCIPAL_ID` | MCP enterprise application object ID |
| `MCP_APP_IDENTIFIER_URI` | MCP Application ID URI |
| `MCP_TOOLS_APP_ROLE_ID` | `Mcp.Tools.ReadWrite.All` application role ID |
| `MCP_INSPECTOR_APP_ROLE_ID` | `Mcp.Inspector.Access` application role ID |
| `WEB_APP_ORIGIN` | Initial allowed origin, normally `http://localhost:3000` |

## 3. Set the Foundry agent name

The prompt agent is created manually, so its name is maintained directly in:

```text
infra/modules/policies/responses.xml
```

The default name is `MyMCPAgentDemo`. Either use that name when creating the agent or update the policy before deployment. The policy omits `version`, so Foundry uses the latest active agent version.

## 4. Deploy

Run **Deploy managed-identity infrastructure** from the repository's
**Actions** page.

The default stable deployment is:

```text
Resource group: rg-azmcp-managed-dev
Deployment: managed-identity-foundation
```

The workflow summary publishes the main endpoints and identifiers. To load
outputs for the manual commands below:

```bash
RESOURCE_GROUP="rg-azmcp-managed-dev"
DEPLOYMENT_NAME="managed-identity-foundation"

deployment_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs.$1.value" \
    --output tsv
}

AZURE_AI_PROJECT_ID="$(deployment_output AZURE_AI_PROJECT_ID)"
AZURE_AI_PROJECT_ENDPOINT="$(deployment_output AZURE_AI_PROJECT_ENDPOINT)"
AZURE_AI_GPT5_DEPLOYMENT_NAME="$(deployment_output AZURE_AI_GPT5_DEPLOYMENT_NAME)"
AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME="$(deployment_output AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME)"
MCP_API_URL="$(deployment_output MCP_API_URL)"
CONTAINER_APP_NAME="$(deployment_output CONTAINER_APP_NAME)"
FOUNDRY_PROJECT_PRINCIPAL_ID="$(deployment_output AZURE_AI_PROJECT_PRINCIPAL_ID)"
APIM_PRINCIPAL_ID="$(deployment_output APIM_PRINCIPAL_ID)"
MCP_SERVICE_PRINCIPAL_ID="$(deployment_output ENTRA_APP_SERVICE_PRINCIPAL_ID)"
MCP_TOOLS_ROLE_ID="$(deployment_output ENTRA_APP_ROLE_ID)"
MCP_IDENTIFIER_URI="$(deployment_output ENTRA_APP_IDENTIFIER_URI)"
```

## 5. Assign the MCP application role

Assign `Mcp.Tools.ReadWrite.All` to both the Foundry project managed identity
and the APIM managed identity:

> [!IMPORTANT]
> Perform these assignments through the Microsoft Graph `az rest` endpoint
> shown below. The Entra portal's **Enterprise applications > Users and
> groups** picker supports users and groups, but it does not support selecting
> managed identities or other service principals for an application-role
> assignment.

```bash
assign_mcp_role() {
  local principal_id="$1"
  az rest \
    --method post \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/${MCP_SERVICE_PRINCIPAL_ID}/appRoleAssignedTo" \
    --body "{\"principalId\":\"${principal_id}\",\"resourceId\":\"${MCP_SERVICE_PRINCIPAL_ID}\",\"appRoleId\":\"${MCP_TOOLS_ROLE_ID}\"}"
}

assign_mcp_role "$FOUNDRY_PROJECT_PRINCIPAL_ID"
assign_mcp_role "$APIM_PRINCIPAL_ID"
```

These assignments are intentionally manual and are not created by the workflow.
Allow several minutes for them to propagate.

## 6. Create the Foundry agent

Before creating the agent, grant your signed-in user the **Foundry User** role on the deployed Foundry project:

```bash
az role assignment create \
  --assignee "$(az ad signed-in-user show --query id --output tsv)" \
  --role "Foundry User" \
  --scope "$AZURE_AI_PROJECT_ID"
```

Allow about five minutes for the role assignment to propagate before creating the agent. If Foundry still reports an authorization error, wait a few more minutes and retry.

Then, in the deployed Foundry project:

1. Create the agent using the name configured in `responses.xml`.
2. Use `AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME` for initial testing or `AZURE_AI_GPT5_DEPLOYMENT_NAME` for higher-quality testing.
3. Save and publish the agent.

## 7. Connect the agent to APIM MCP

1. Open the agent in Foundry.
2. Select **Add tool** -> **Custom** -> **Model Context Protocol**.
3. Use the `MCP_API_URL` output. Its path should end with:

   ```text
   /mcp/managed-identity/mcp
   ```

4. Select **Microsoft Entra** and **Project Managed Identity**.
5. Set the audience to `$MCP_IDENTIFIER_URI`.
6. Set `require_approval` to `always` so the sample web application prompts before MCP tool execution.
7. Save the connection and attach it directly to the agent.

Use `$MCP_API_URL`, not the Container App URL.

## 8. Test the agent

In the Foundry agent playground, submit:

```text
Use Azure Resource Graph to list up to five resource groups I can access.
Return the resource group name and location.
```

Approve the MCP tool call when prompted. Results are limited by the Container App managed identity's Azure RBAC assignments.

## 9. Run or deploy the web application

For local development, retrieve the APIM test subscription key and store it
only in the web application's `.env` file.

```bash
cd agent-web-app
cp .env.example .env
npm install
npm run dev
```

Open <http://localhost:3000>. See [`agent-web-app/README.md`](agent-web-app/README.md) for its required settings.

To deploy the optional hosted application, run **Deploy managed-identity web
app**. Follow [`../web-host/README.md`](../web-host/README.md) to replace the
placeholder APIM key and add the deployed SPA redirect URI.

## 10. Use MCP Inspector through APIM

To use MCP Inspector through APIM, first assign your user the **Azure MCP Inspector Access** role on the MCP enterprise application:

```bash
USER_OBJECT_ID="$(az ad signed-in-user show --query id --output tsv)"
MCP_SERVICE_PRINCIPAL_ID="$(deployment_output ENTRA_APP_SERVICE_PRINCIPAL_ID)"
INSPECTOR_ROLE_ID="$(deployment_output ENTRA_APP_INSPECTOR_ROLE_ID)"

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
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
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

Delete `rg-azmcp-managed-web-dev` first if the optional web application was
deployed, then delete `rg-azmcp-managed-dev`.
