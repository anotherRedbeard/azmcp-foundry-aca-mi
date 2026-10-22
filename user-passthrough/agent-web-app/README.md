# Foundry Agent Web App

An authenticated single-page chat application that invokes a Microsoft Foundry prompt agent through Azure API Management.

Use this guide after completing steps 1-8 in the
[user-passthrough deployment guide](../README.md). The core infrastructure
workflow deploys the APIM Responses API and policy. Do not create or configure
another APIM API for the web application.

## Before you start

Confirm that:

- The user-passthrough infrastructure workflow completed successfully.
- The Foundry agent is published and connected to the OAuth MCP connection.
- You can invoke the agent successfully from the Foundry playground.
- Every user testing the web application has the project-scoped **Foundry
  User** role.
- You can retrieve the APIM test subscription key for local testing.

## Deployed request flow (reference)

> [!NOTE]
> This section explains the deployed authentication flow. It is not an
> additional configuration procedure.

```text
Browser SPA
  |  delegated Foundry token
  v
FastAPI web host
  |  delegated Foundry token + server-side APIM subscription key
  v
APIM POST /responses
  |  same delegated Foundry token
  v
Microsoft Foundry Responses API
  |
  v
Foundry Agent
  |  Direct MCP tool using a Foundry OAuth2 identity-passthrough connection
  v
APIM MCP endpoint
  |  delegated MCP token
  v
Azure MCP Server
  |  OBO exchange
  v
Azure APIs using the MCP-authorizing user's RBAC
```

The browser uses authorization code with PKCE to request the Microsoft Foundry `user_impersonation` scope and calls the same-origin `/api/responses` endpoint. FastAPI validates the delegated Foundry token, adds the server-held APIM subscription key, and forwards the token unchanged to APIM.

APIM validates the same delegated token, injects a fixed `agent_reference`, and
relays the token to Foundry. The agent's direct MCP tool references an OAuth2
identity-passthrough project connection, which obtains a delegated token for
the private MCP application. Azure MCP exchanges that token on behalf of the
user who authorizes the MCP connection. Azure RBAC is therefore evaluated for
that user rather than a shared Container App identity.

The SPA and FastAPI host require no client secret. The separate confidential
OAuth client used by the Foundry project connection stores its credential in
Foundry, not in this web application.

The first MCP tool call can return an OAuth consent link. The UI opens that link in a new tab and continues the pending response after the user confirms authorization. Use the same account for the SPA and MCP consent flow when exact end-to-end identity continuity is required.

The completed core setup configures the direct MCP tool with
`require_approval: always`. The UI displays each `mcp_approval_request`,
including the server, tool, and arguments, and sends an explicit approval or
rejection before Foundry continues the response.

The completed core setup also configures the Foundry custom OAuth connection
with `offline_access` and the tenant v2 token endpoint for both its token URL
and refresh URL. Without the refresh URL, the MCP access token expires and APIM
rejects later tool calls.

The SPA registration, delegated Foundry permission, APIM `POST /responses`
operation, CORS policy, token validation, bearer-token forwarding, and fixed
`agent_reference` are established by the core deployment guide and workflow.
The deployed application stores conversation metadata, messages, and the
latest Foundry response ID in Azure Cosmos DB for NoSQL. After sign-in, the UI
automatically opens the most recently updated conversation. Users can select a
different saved conversation, delete one conversation, or clear all of their
history.

Cosmos data is partitioned by the validated Entra `oid` claim. FastAPI derives
that value from the access token and never accepts a user ID from the browser.
The Container App uses its system-assigned managed identity for Cosmos data
access. The existing user-assigned identity remains dedicated to ACR image
pulls.

### Subscription key

When the APIM API or product requires a subscription, the SPA sends:

```http
Ocp-Apim-Subscription-Key: <key>
```

The key is stored only in the server environment and is added by FastAPI when forwarding to APIM. It is not returned through `/api/config` or included in the browser bundle. The delegated Foundry token remains the authorization boundary.

## 1. Configure the local application

On macOS or Linux:

```bash
cd user-passthrough/agent-web-app
cp .env.example .env
```

On Windows PowerShell:

```powershell
Set-Location user-passthrough/agent-web-app
Copy-Item .env.example .env
```

Read the required values from the stable core deployment:

```bash
outputs="$(az deployment group show \
  --resource-group rg-azmcp-passthrough-dev \
  --name user-passthrough-foundation \
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
  "FOUNDRY_API_SCOPE=\(output("FOUNDRY_API_SCOPE"))",
  "APIM_RESPONSES_URL=\(output("RESPONSES_API_URL"))"
' <<< "$outputs"
```

Copy those values into `.env`.

| Variable | Purpose |
|---|---|
| `ENTRA_TENANT_ID` | `AZURE_TENANT_ID` deployment output |
| `ENTRA_SPA_CLIENT_ID` | `SPA_CLIENT_ID` deployment output |
| `FOUNDRY_API_SCOPE` | `FOUNDRY_API_SCOPE` deployment output |
| `APIM_RESPONSES_URL` | `RESPONSES_API_URL` deployment output |
| `APIM_SUBSCRIPTION_KEY` | Primary key for the APIM test subscription |
| `CHAT_HISTORY_BACKEND` | `memory` for the local walkthrough; Azure sets `cosmos` |
| `PORT` | FastAPI port; defaults to `3000` |

Retrieve the subscription key from **API Management > Subscriptions** in the
Azure portal. Select the test subscription created by the infrastructure
deployment and copy its primary key. Store the key only in `.env`.

Only `ENTRA_TENANT_ID`, `ENTRA_SPA_CLIENT_ID`, and `FOUNDRY_API_SCOPE` are delivered to the SPA by `/api/config`. The APIM URL and subscription key remain server-side.

The default local `memory` backend keeps conversations across browser refreshes
while FastAPI is running and clears them when the process stops. To test the
real Cosmos backend locally:

1. Set `CHAT_HISTORY_BACKEND=cosmos`.
2. Set `COSMOS_ENDPOINT`, `COSMOS_DATABASE_NAME`, and
   `COSMOS_CONTAINER_NAME`.
3. Run `az login`.
4. Grant your signed-in developer identity **Cosmos DB Built-in Data
   Contributor** on the chat-history container.

Do not use account keys or connection strings. The deployed account disables
local/key authentication.

## 2. Run locally

### macOS and Linux

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
npm ci
npm run build
python -m app.main
```

If `python3` resolves to a different or deleted virtual environment, run `deactivate`, clear `VIRTUAL_ENV`, and run `hash -r`, or open a new terminal before creating `.venv`.

### Windows PowerShell

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
npm ci
npm run build
python -m app.main
```

If PowerShell blocks the activation script, allow locally created scripts for
the current user, then activate the environment again:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\.venv\Scripts\Activate.ps1
```

After activation, verify that the intended interpreter is selected:

```powershell
Get-Command python
```

Its path should end in `.venv\Scripts\python.exe`. To run without activating
the environment, use:

```powershell
.\.venv\Scripts\python.exe -m app.main
```

Open <http://localhost:3000>.

Node.js is used only to bundle MSAL Browser and the SPA JavaScript. The application server and APIM proxy run in Python.

For client-side development, run `npm run dev:client` in a second terminal while FastAPI is running.

The UI provides:

- Compact pinned header
- Independently scrolling message pane
- Automatic scrolling to the newest message
- Multi-line composer with Enter-to-send
- Automatic restore of the latest saved conversation
- Saved-conversation selection
- New-chat, delete-chat, clear-history, and sign-out controls

## 3. Validate

```bash
npm run check
python -m compileall app
python -m unittest discover -s test -v
```

Optionally confirm that the production container image builds:

```bash
docker build .
```

## 4. Deploy to Azure

Create the `user-passthrough-web-dev` GitHub Environment and add these secrets:

| Secret | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | GitHub deployment application client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

Add a federated credential to the GitHub deployment application with:

| Setting | Value |
| --- | --- |
| Organization | GitHub repository owner |
| Repository | This repository |
| Entity type | Environment |
| Environment | `user-passthrough-web-dev` |

The deployment identity needs `Contributor` and `User Access Administrator` on
the target subscription.

1. Run **Deploy user-passthrough web app** from the repository's **Actions**
   page.
2. Copy the resource group, Container App name, and application URL from the
   workflow summary.
3. In the Azure portal, open the deployed Container App.
4. Open **Security > Secrets** and select `apim-subscription-key`.
5. Replace `replace-before-use` with the APIM test subscription's primary key,
   then save the secret.
6. Open **Application > Revisions and replicas**, select the active revision,
   and restart it so the application loads the new secret value.
7. In Microsoft Entra ID, open the SPA app registration and go to
   **Authentication > Single-page application**. Add the exact Container App
   application URL copied from the workflow summary as a redirect URI. Do not
   add it under the **Web** platform.
8. Open the application URL and sign in.

The web workflow also deploys a serverless Cosmos DB for NoSQL account,
database, and `/userId`-partitioned container in the web resource group. It
disables key authentication, enables a system-assigned identity on the
Container App, and grants that identity **Cosmos DB Built-in Data
Contributor** only on the chat-history container. Chat records remain until
the user deletes one conversation or clears all history.

Serverless Cosmos DB has no provisioned-throughput floor. Storage and request
units are usage-based; a private endpoint is not included in this public POC
deployment.

## Troubleshooting

### No FastAPI request logs for an agent error

Inspect the FastAPI logs, the browser request to `/api/responses`, and APIM Application Insights telemetry.

### `401 AzureApiManagementKey`

Set `APIM_SUBSCRIPTION_KEY` to a valid subscription key attached to a product containing the Responses API.

### `Chat history storage is unavailable`

For Azure, confirm that the Container App has a system-assigned identity, that
the identity has **Cosmos DB Built-in Data Contributor** on the deployed
chat-history container, and that `CHAT_HISTORY_BACKEND=cosmos` plus the three
`COSMOS_*` settings are present.

For local Cosmos testing, confirm that `az account show` succeeds and your
signed-in identity has the same Cosmos data-plane role. Use
`CHAT_HISTORY_BACKEND=memory` when Cosmos persistence is not needed locally.

### Unexpected issuer or audience

Foundry currently issues a v1-format delegated token with:

```text
iss=https://sts.windows.net/<tenant-id>/
aud=https://ai.azure.com
scp=user_impersonation
```

Validate those claims and require the SPA client ID in `appid`.

### Deprecated `agent` property

The Foundry Responses API requires `agent_reference`. The APIM policy should inject it rather than accepting an agent name from the browser.
