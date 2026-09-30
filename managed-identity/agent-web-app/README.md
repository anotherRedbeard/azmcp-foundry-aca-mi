# Foundry Agent Web App

An authenticated single-page chat application that invokes a Microsoft Foundry prompt agent through Azure API Management.

Use this guide after completing steps 1-8 in the
[managed-identity deployment guide](../README.md). The core infrastructure
workflow deploys the APIM Responses API and policy. Do not create or configure
another APIM API for the web application.

## Before you start

Confirm that:

- The managed-identity infrastructure workflow completed successfully.
- The Foundry agent is published and connected to the APIM MCP endpoint.
- You can invoke the agent successfully from the Foundry playground.
- You can retrieve the APIM test subscription key for local testing.

## Deployed request flow (reference)

> [!NOTE]
> This section explains the deployed authentication flow. It is not an
> additional configuration procedure.

```text
Browser SPA
  |  delegated Entra token
  v
Express web host
  |  delegated Entra token + server-side APIM subscription key
  v
APIM POST /responses
  |  APIM managed identity
  v
Microsoft Foundry Responses API
  |
  v
Foundry Agent
  |  Foundry project managed identity
  v
APIM MCP endpoint
  |  APIM managed identity
  v
Azure MCP Server
```

The browser uses authorization code with PKCE and calls the same-origin `/api/responses` endpoint. Express validates the delegated token, adds the server-held APIM subscription key, and forwards the request to APIM.

The signed-in user's token authorizes both the Express proxy and the APIM Responses operation. APIM injects a fixed `agent_reference`, replaces the user credential with its managed-identity token, and forwards the request to Foundry. The user token never reaches Foundry.

When the agent returns an `mcp_approval_request`, the UI displays the MCP
server, tool name, and arguments. The user must approve or reject every pending
call before the app continues the response with validated
`mcp_approval_response` items. The completed core setup configures the agent's
MCP tool with `require_approval: always`.

No client secret is required. The core deployment guide and workflow establish
the Entra registrations, delegated scope, APIM `POST /responses` operation,
CORS policy, token validation, managed-identity authentication, and fixed
`agent_reference`. The SPA stores the latest response ID in memory for
multi-turn conversations and clears it when **New chat** is selected.

### Subscription key

When the APIM API or product requires a subscription, the SPA sends:

```http
Ocp-Apim-Subscription-Key: <key>
```

The key is stored only in the server environment and is added by Express when forwarding to APIM. It is not returned through `/api/config` or included in the browser bundle. Entra JWT validation remains the authorization boundary.

## 1. Configure the local application

On macOS or Linux:

```bash
cd managed-identity/agent-web-app
cp .env.example .env
```

On Windows PowerShell:

```powershell
Set-Location managed-identity/agent-web-app
Copy-Item .env.example .env
```

Read the required values from the stable core deployment:

```bash
outputs="$(az deployment group show \
  --resource-group rg-azmcp-managed-dev \
  --name managed-identity-foundation \
  --query properties.outputs \
  --output json)"

jq -r '
  def output($name):
    to_entries
    | map(select((.key | ascii_downcase) == ($name | ascii_downcase)))
    | first
    | .value.value;

  "ENTRA_TENANT_ID=\(output("AZURE_TENANT_ID"))",
  "ENTRA_SPA_CLIENT_ID=\(output("SPA_CLIENT_ID"))",
  "ENTRA_API_SCOPE=\(output("ENTRA_API_SCOPE"))",
  "APIM_RESPONSES_URL=\(output("RESPONSES_API_URL"))"
' <<< "$outputs"
```

Copy those values into `.env`.

| Variable | Purpose |
|---|---|
| `ENTRA_TENANT_ID` | `AZURE_TENANT_ID` deployment output |
| `ENTRA_SPA_CLIENT_ID` | `SPA_CLIENT_ID` deployment output |
| `ENTRA_API_SCOPE` | `ENTRA_API_SCOPE` deployment output |
| `APIM_RESPONSES_URL` | `RESPONSES_API_URL` deployment output |
| `APIM_SUBSCRIPTION_KEY` | Primary key for the APIM test subscription |
| `PORT` | Express port; defaults to `3000` |
| `NODE_ENV` | Express runtime environment |

Retrieve the subscription key from **API Management > Subscriptions** in the
Azure portal. Select the test subscription created by the infrastructure
deployment and copy its primary key. Store the key only in `.env`.

Only `ENTRA_TENANT_ID`, `ENTRA_SPA_CLIENT_ID`, and `ENTRA_API_SCOPE` are delivered to the SPA by `/api/config`. The APIM URL and subscription key remain server-side.

## 2. Run locally

### macOS and Linux

```bash
npm install
npm run dev
```

### Windows PowerShell

```powershell
npm install
npm run dev
```

Open <http://localhost:3000>.

The UI provides:

- Compact pinned header
- Independently scrolling message pane
- Automatic scrolling to the newest message
- Multi-line composer with Enter-to-send
- New-chat and sign-out controls

## 3. Validate

```bash
npm run check
docker build .
```

## 4. Deploy to Azure

1. Follow the [web-host deployment guide](../../web-host/README.md) to
   configure the `managed-identity-web-dev` GitHub Environment and GitHub OIDC.
2. Run **Deploy managed-identity web app** from the repository's **Actions**
   page.
3. Copy the application URL from the workflow summary.
4. In the deployed Container App, replace the `apim-subscription-key` secret's
   `replace-before-use` value with the APIM test subscription key, then restart
   or create a revision.
5. Add the application URL to the SPA registration under **Authentication >
   Single-page application**.
6. Open the application URL and sign in.

The web workflow deploys only this application to its own Azure Container Apps
environment and resource group.

## Troubleshooting

### No Express request logs for an agent error

Inspect the Express logs, the browser request to `/api/responses`, and APIM Application Insights telemetry.

The server logs only responses that require MCP approval. Each log includes the Foundry response ID and the pending approval request ID, server, tool, and arguments.

### `401 AzureApiManagementKey`

Set `APIM_SUBSCRIPTION_KEY` to a valid subscription key attached to a product containing the Responses API.

### Unexpected issuer

Set `"requestedAccessTokenVersion": 2` on the protected API registration and confirm APIM validates the tenant-specific v2 issuer.

### Deprecated `agent` property

The Foundry Responses API requires `agent_reference`. The APIM policy should inject it rather than accepting an agent name from the browser.
