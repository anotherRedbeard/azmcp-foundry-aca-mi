# Secure Foundry Agent and Azure MCP through API Management

This repository demonstrates an end-to-end Azure architecture in which an authenticated browser application calls a Microsoft Foundry agent through Azure API Management (APIM), and the agent calls Azure MCP Server through a second APIM gateway boundary.

The solution uses Microsoft Entra ID, delegated authorization, application roles, and managed identities. No client secrets are required.

## Attribution

This project was originally based on
[Azure-Samples/azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi)
at commit [`e35a1c3`](https://github.com/Azure-Samples/azmcp-foundry-aca-mi/commit/e35a1c32ecc804ecc514244dd7cd4e013371cb30).

This fork adds a browser SPA, APIM-mediated Foundry Responses API calls, a second
APIM boundary for Azure MCP, additional read-only Azure MCP namespaces, and
expanded identity, security, telemetry, and troubleshooting guidance.

## Architecture

```text
Browser SPA
  |  Entra delegated token
  v
FastAPI web host
  |  Entra delegated token + server-side APIM subscription key
  v
APIM: POST /responses
  |  APIM managed-identity token for https://ai.azure.com
  v
Microsoft Foundry Responses API
  |
  v
Foundry Agent
  |  Foundry project managed-identity token for the MCP application
  v
APIM: Azure MCP endpoint
  |  APIM managed-identity token for the MCP application
  v
Azure MCP Server on Azure Container Apps
  |  Container App managed identity + Azure RBAC
  v
Azure Resource Manager, Resource Graph, and Storage
```

The editable architecture diagram is available at [foundry-apim-mcp-architecture.excalidraw](foundry-apim-mcp-architecture.excalidraw).

### Identity and trust boundaries

| Call | Caller identity | Authorization |
|---|---|---|
| Browser → FastAPI | Signed-in user through the SPA registration | Delegated `access_as_user` scope validated by the web host |
| FastAPI → Agent APIM | Signed-in user token plus server-held APIM subscription key | APIM repeats JWT validation and applies product membership and quotas |
| Agent APIM → Foundry | APIM system-managed identity | Foundry project role, such as **Foundry User** |
| Foundry → MCP APIM | Foundry project managed identity | `Mcp.Tools.ReadWrite.All` application role exposed by the MCP Entra application |
| MCP APIM → Container App | APIM system-managed identity | `Mcp.Tools.ReadWrite.All` application role |
| Container App → Azure | Container App managed identity | Azure RBAC on the permitted resource scopes |

APIM terminates and validates each inbound credential, obtains a new token for its own managed identity, and replaces the `Authorization` header. It does not pass through or re-sign the original token.

## Repository components

### Azure MCP infrastructure

The Bicep deployment provisions:

- Azure Container Apps environment and Container App
- Azure MCP Server using Streamable HTTP
- System-managed identity for the Container App
- Entra application exposing `Mcp.Tools.ReadWrite.All`
- Application-role assignment for the Foundry project managed identity
- Azure RBAC assignments for the configured Storage account
- Optional Application Insights telemetry

Azure MCP Server runs with:

- `--mode all`
- `--read-only`
- `storage`, `subscription`, `group`, and `arm` namespaces

The `arm` namespace provides access to the hosted Azure Resource Manager MCP tools, including Azure Resource Graph queries.

### Web application

[`agent-web-app`](agent-web-app/) contains a production-style single-page application:

- MSAL Browser authorization-code flow with PKCE
- No browser or server-side client secret
- Same-origin browser calls to an authenticated FastAPI proxy
- Server-side APIM subscription-key injection
- Foundry Responses API multi-turn state using `previous_response_id`
- Static FastAPI host with `/api/config` and `/health`
- Docker support for Azure Container Apps or App Service

FastAPI validates the delegated token before proxying the request. APIM repeats authorization at the gateway boundary and applies product policy.

## Prerequisites

- Azure subscription with permissions to deploy resources and create role assignments
- Microsoft Foundry project with a prompt agent
- Existing Azure API Management instance with a system-managed identity
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Python 3.11 or later for the web host
- Node.js 20 or later to bundle the browser application
- Permission to create or configure Entra application registrations and application-role assignments

## Deploy Azure MCP Server

```bash
azd up
```

The deployment requests:

- `STORAGE_RESOURCE_ID` — Storage account used for the template's scoped RBAC assignments
- `FOUNDRY_PROJECT_RESOURCE_ID` — Foundry project whose managed identity receives the MCP application role

Inspect the selected environment and deployment outputs:

```bash
azd env get-values
```

Important outputs include:

```text
CONTAINER_APP_URL
ENTRA_APP_CLIENT_ID
ENTRA_APP_IDENTIFIER_URI
ENTRA_APP_OBJECT_ID
ENTRA_APP_ROLE_ID
ENTRA_APP_SERVICE_PRINCIPAL_ID
```

`azd` selects or creates the resource group before deploying the resource-group-scoped Bicep templates. The templates do not create the resource group directly.

## Configure the APIM agent gateway

Expose a narrow `POST /responses` operation rather than an unrestricted Foundry proxy.

The inbound policy should:

1. Handle CORS for the web application's origins.
2. Validate the delegated Entra token's tenant and API audience.
3. Require `scp=access_as_user`.
4. Require the SPA client ID in the `azp` claim.
5. Inject a fixed `agent_reference` so the caller cannot select another agent.
6. Authenticate to Foundry using APIM managed identity for `https://ai.azure.com`.
7. Forward to:

```text
https://<foundry-resource>.services.ai.azure.com/api/projects/<project>/openai/v1/responses
```

Grant the APIM managed identity the required role on the Foundry project.

The FastAPI proxy sends:

```http
Authorization: Bearer <delegated-user-token>
Ocp-Apim-Subscription-Key: <subscription-key>
Content-Type: application/json
```

The subscription key remains server-side and is never returned by `/api/config`. Keep Entra JWT validation enabled in both the web host and APIM.

## Configure the APIM MCP gateway

Create an APIM passthrough MCP API whose backend is `CONTAINER_APP_URL`.

The policy should:

1. Validate the Foundry project managed-identity token.
2. Require the MCP application audience.
3. Require the expected Foundry project `oid`.
4. Require `roles=Mcp.Tools.ReadWrite.All`.
5. Obtain an APIM managed-identity token for the MCP application.
6. Replace the backend `Authorization` header.
7. Preserve Streamable HTTP POST, GET/SSE, session, and protocol headers.

Assign `Mcp.Tools.ReadWrite.All` to the APIM managed identity on the MCP service principal. Managed-identity tokens are cached; a newly assigned application role might not appear until the cached token expires.

### Connect the Foundry agent to APIM MCP

Configure the agent's MCP tool to call APIM rather than the Container App directly:

1. Open the Foundry project and select the agent.
2. Select **Add tool** → **Custom** → **Model Context Protocol**.
3. Set the remote MCP endpoint to the APIM MCP URL:

   ```text
   https://<apim-name>.azure-api.net/azuremcpserver
   ```

4. Select **Microsoft Entra** and **Project Managed Identity**.
5. Set the audience to `ENTRA_APP_CLIENT_ID`, the application ID exposed by the MCP Entra registration.
6. Save the connection and associate it with the agent.

The Foundry project identity calls APIM. It should not use `CONTAINER_APP_URL` as the agent connection endpoint in this architecture.

### MCP body inspection and schema compatibility

MCP client messages are individual JSON-RPC POST bodies, while GET requests can establish long-lived SSE streams. Any policy that reads a request body must guard against GET requests and preserve the content:

```csharp
if (context.Request.Method != "POST" || context.Request.Body == null)
{
    return false;
}

var body = context.Request.Body.As<string>(preserveContent: true);
```

Foundry can reject ARM MCP `tools/list` schemas containing:

```json
"properties": { "result": true }
```

The current APIM compatibility workaround applies only to a successful JSON `tools/list` response and rewrites that property to:

```json
"properties": { "result": {} }
```

Do not apply `set-body` to `text/event-stream` responses.

### Tool-call telemetry

APIM can inspect JSON-RPC POST requests and trace `params.name` when `method` is `tools/call`. Log only the tool name and a correlation ID. Do not log:

- `Authorization` headers
- Access tokens
- APIM subscription keys
- Complete tool arguments or request bodies

## Run the web application

```bash
cd agent-web-app
cp .env.example .env
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
npm ci
npm run build
python -m app.main
```

Open <http://localhost:3000>. See the [web application README](agent-web-app/README.md) for Entra registration and deployment details.

## Validation

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
  --name azure-mcp-storage-server \
  --resource-group <resource-group> \
  --follow
```

APIM Application Insights telemetry should show both:

- `POST /azuremcpserver` for JSON-RPC messages
- `GET /azuremcpserver` when the MCP client opens an SSE stream

## Common errors

### `Object reference not set to an instance of an object`

An APIM policy attempted to read `context.Request.Body` on the MCP GET/SSE request. Check the method and ensure the body is non-null before parsing it.

### `The 'agent' property is deprecated`

Use `agent_reference` in the Foundry Responses API payload. This architecture injects it in APIM.

### Unexpected `iss` claim

Set the protected API registration manifest to issue v2 tokens:

```json
"requestedAccessTokenVersion": 2
```

APIM should validate the tenant-specific v2 issuer and the configured API audience.

### APIM returns `401` with `AzureApiManagementKey`

The API or product requires a subscription key. Attach a valid subscription and send its key in `Ocp-Apim-Subscription-Key`.

### MCP backend token has no `roles` claim

Assign `Mcp.Tools.ReadWrite.All` to the calling managed identity on the MCP enterprise application. If the assignment was just created, wait for the previously cached managed-identity token to expire.

### `ServiceManagementReference field is required`

Set `SERVICE_MANAGEMENT_REFERENCE` in the selected `azd` environment, then rerun `azd up`:

```bash
azd env set SERVICE_MANAGEMENT_REFERENCE <your-service-tree-guid>
```

## Clean up

```bash
azd down
```

This removes resources managed by the selected `azd` environment. Separately configured APIM APIs, policies, products, subscriptions, Entra registrations, and manually created role assignments must be removed separately if they are no longer needed.

## Infrastructure modules

- [`infra/main.bicep`](infra/main.bicep) — deployment orchestration and namespace allowlist
- [`infra/modules/aca-infrastructure.bicep`](infra/modules/aca-infrastructure.bicep) — Container App and Azure MCP startup arguments
- [`infra/modules/aca-role-assignment-resource-storage.bicep`](infra/modules/aca-role-assignment-resource-storage.bicep) — scoped Storage RBAC
- [`infra/modules/entra-app.bicep`](infra/modules/entra-app.bicep) — MCP Entra application and application role
- [`infra/modules/foundry-role-assignment-entraapp.bicep`](infra/modules/foundry-role-assignment-entraapp.bicep) — Foundry project application-role assignment
- [`infra/modules/application-insights.bicep`](infra/modules/application-insights.bicep) — optional telemetry
