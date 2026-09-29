# User-Passthrough/OBO Deployment

Use this variant when Azure RBAC must be evaluated for each signed-in user. The user's delegated identity flows through Foundry and APIM, and Azure MCP uses OAuth on-behalf-of (OBO) for downstream Azure access.

Do not combine this deployment with files, resources, connections, or core
deployment outputs from [`../managed-identity`](../managed-identity/).

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
- Azure CLI
- Python 3.11 or later
- Node.js 20 or later
- Permission to configure Entra applications, federated credentials, and tenant-wide delegated API consent
- A GitHub Actions deployment application configured for OIDC
- `Contributor` on the target subscription

See [`../web-host/README.md`](../web-host/README.md) for the GitHub OIDC
federated-credential pattern.

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

### MCP protected API registration

Create a single-tenant registration for the OBO MCP endpoint:

1. Set its Application ID URI to `api://<mcp-app-client-id>`.
2. Set `requestedAccessTokenVersion` to `2`.
3. Add delegated scope `Mcp.Tools.ReadWrite`.
4. Add these delegated API permissions:
   - Azure Service Management `user_impersonation`
   - Azure Storage `user_impersonation`
   - Azure Resource Manager MCP `MCP.Access`
5. Grant tenant-wide admin consent.
6. Ensure its enterprise application/service principal exists.

Record:

- Application/client ID
- Enterprise application object ID
- Application ID URI
- `Mcp.Tools.ReadWrite` delegated scope ID

## 2. Configure the infrastructure workflow

Create the `user-passthrough-infra-dev` GitHub Environment. Add these secrets:

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
| `API_CLIENT_ID` | Confidential Foundry MCP OAuth client ID |
| `MCP_APP_CLIENT_ID` | MCP protected API application/client ID |
| `MCP_APP_SERVICE_PRINCIPAL_ID` | MCP enterprise application object ID |
| `MCP_APP_IDENTIFIER_URI` | MCP Application ID URI |
| `MCP_APP_SCOPE_ID` | `Mcp.Tools.ReadWrite` delegated scope ID |
| `WEB_APP_ORIGIN` | Initial allowed origin, normally `http://localhost:3000` |

Do not add the confidential client's secret to GitHub. It is entered only when
the Foundry OAuth connection is created manually.

## 3. Set the Foundry agent name

The prompt agent is created manually, so its name is maintained directly in:

```text
infra/modules/policies/responses.xml
```

The deployed agent name is `MyMcpPassthroughAgent`. The policy omits `version`, so Foundry uses the latest active agent version.

## 4. Deploy

Run **Deploy user-passthrough infrastructure** from the repository's
**Actions** page.

The default stable deployment is:

```text
Resource group: rg-azmcp-passthrough-dev
Deployment: user-passthrough-foundation
```

The workflow summary publishes the main endpoints and identifiers. Load the
outputs needed for the remaining manual steps:

```bash
RESOURCE_GROUP="rg-azmcp-passthrough-dev"
DEPLOYMENT_NAME="user-passthrough-foundation"

deployment_output() {
  local name="${1:?Usage: deployment_output OUTPUT_NAME}"

  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query properties.outputs \
    --output json |
    jq -er --arg name "$name" \
      'to_entries
       | map(select((.key | ascii_downcase) == ($name | ascii_downcase)))
       | first
       | .value.value'
}

AZURE_TENANT_ID="$(deployment_output AZURE_TENANT_ID)"
ENTRA_APP_CLIENT_ID="$(deployment_output ENTRA_APP_CLIENT_ID)"
ENTRA_APP_SCOPE_ID="$(deployment_output ENTRA_APP_SCOPE_ID)"
MCP_API_URL="$(deployment_output MCP_API_URL)"
AZURE_AI_PROJECT_ID="$(deployment_output AZURE_AI_PROJECT_ID)"
AZURE_AI_PROJECT_ENDPOINT="$(deployment_output AZURE_AI_PROJECT_ENDPOINT)"
AZURE_AI_GPT5_DEPLOYMENT_NAME="$(deployment_output AZURE_AI_GPT5_DEPLOYMENT_NAME)"
AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME="$(deployment_output AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME)"
CONTAINER_APP_NAME="$(deployment_output CONTAINER_APP_NAME)"
OBO_MANAGED_IDENTITY_PRINCIPAL_ID="$(deployment_output CONTAINER_APP_PRINCIPAL_ID)"
```

The manually created MCP application must contain these downstream delegated
permissions:

- Azure Resource Manager `user_impersonation`
- Azure Storage `user_impersonation`
- Azure Resource Manager MCP `MCP.Access`

Grant tenant-wide admin consent for all three permissions:

```bash
az ad app permission admin-consent --id "$ENTRA_APP_CLIENT_ID"
```

Do not grant Reader or data-plane roles to the OBO managed identity. Azure authorization must come from the signed-in user.

## 5. Add the OBO federated credential

On the manually created MCP app registration, open **Certificates & secrets >
Federated credentials** and add:

| Setting | Value |
| --- | --- |
| Issuer | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Subject | `$OBO_MANAGED_IDENTITY_PRINCIPAL_ID` |
| Audience | `api://AzureADTokenExchange` |
| Name | `AzureMcpServerCredential` |

The subject is the managed identity's principal/object ID, not its client ID.
This step is intentionally manual because the managed identity is created by
the infrastructure workflow.

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

## 7. Create the OAuth MCP connection

Grant the confidential OAuth client the MCP application's delegated `Mcp.Tools.ReadWrite` permission:

```bash
az ad app permission add \
  --id "<foundry-mcp-oauth-client-id>" \
  --api "$ENTRA_APP_CLIENT_ID" \
  --api-permissions "$ENTRA_APP_SCOPE_ID=Scope"
```

In the Foundry project, create a remote MCP connection named
`AzureMcpApim2` with:

| Setting | Value |
| --- | --- |
| Target | `$MCP_API_URL` |
| Authentication | OAuth 2.0 |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Refresh URL | Same tenant v2 token endpoint |
| Client ID | Confidential Foundry MCP OAuth client ID |
| Client secret | Confidential client secret |
| Scopes | `openid offline_access api://<mcp-app-id>/Mcp.Tools.ReadWrite` |

Add Foundry's generated redirect URI to the confidential client registration,
complete the connection's OAuth consent flow, and attach the connection directly
to the agent's MCP tool.

Set `project_connection_id` to `AzureMcpApim2` and use `require_approval: always`. The sample web application renders each MCP tool request and sends an explicit approval or rejection before Foundry continues.

Do not use Project Managed Identity or Agent Identity for this connection.

## 8. Test the agent

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

## 9. Run or deploy the web application

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

To deploy the optional hosted application, run **Deploy user-passthrough web
app**. Follow [`../web-host/README.md`](../web-host/README.md) to replace the
placeholder APIM key and add the deployed SPA redirect URI.

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
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
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

Deploy this variant into a new resource group. After confirming OBO works,
review and remove only obsolete Reader or data-plane assignments belonging to
the old Container App identity:

```bash
az role assignment list \
  --assignee-object-id "<old-container-app-principal-id>" \
  --all \
  --include-inherited \
  --output table
```

Do not remove assignments used by other workloads.

## Clean up

Delete `rg-azmcp-passthrough-web-dev` first if the optional web application was
deployed, then delete `rg-azmcp-passthrough-dev`.
