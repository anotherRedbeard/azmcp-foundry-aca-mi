# Foundry Agent Web App

An authenticated single-page chat application that invokes a Microsoft Foundry prompt agent through Azure API Management.

## Request flow

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

Configure the direct MCP tool with `require_approval: always`. The UI displays each `mcp_approval_request`, including the server, tool, and arguments, and sends an explicit approval or rejection before Foundry continues the response.

The Foundry custom OAuth connection must include `offline_access` and use the tenant v2 token endpoint for both its token URL and refresh URL. Without the refresh URL, the MCP access token expires and APIM rejects later tool calls.

## SPA registration

1. Create a single-tenant registration such as `Foundry Agent SPA`.
2. Add the **Single-page application** platform.
3. Add `http://localhost:3000` as a redirect URI.
4. Add the **Azure Machine Learning Services** delegated `user_impersonation` permission.
5. Grant consent if tenant policy requires it.
6. Do not create a client secret.

Select **Azure Machine Learning Services** by name and add its delegated
`user_impersonation` permission. No application or permission ID needs to be
copied into this repository.

For Azure deployment, add the deployed HTTPS origin as another SPA redirect URI.

## APIM Responses operation

Configure a `POST /responses` operation that:

1. Allows the web application's origins through CORS.
2. Validates the tenant-specific token issuer and `aud=https://ai.azure.com`.
3. Requires `scp=user_impersonation`.
4. Requires the SPA application ID in the v1 token's `appid` claim.
5. Injects the fixed Foundry `agent_reference`.
6. Preserves the inbound `Authorization` header instead of replacing it with an APIM managed-identity token.
7. Forwards the request to:

```text
https://<foundry-resource>.services.ai.azure.com/api/projects/<project>/openai/v1/responses
```

Each signed-in user needs the required Foundry project RBAC role.

The SPA request body contains:

```json
{
  "input": "User message",
  "previous_response_id": "optional-response-id"
}
```

APIM supplies the agent reference. The SPA stores the latest response ID in memory for multi-turn conversations and clears it when **New chat** is selected.

## Subscription key

When the APIM API or product requires a subscription, the SPA sends:

```http
Ocp-Apim-Subscription-Key: <key>
```

The key is stored only in the server environment and is added by FastAPI when forwarding to APIM. It is not returned through `/api/config` or included in the browser bundle. The delegated Foundry token remains the authorization boundary.

## Configuration

On macOS or Linux:

```bash
cp .env.example .env
```

On Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

| Variable | Purpose |
|---|---|
| `ENTRA_TENANT_ID` | Microsoft Entra tenant ID |
| `ENTRA_SPA_CLIENT_ID` | SPA registration client ID |
| `FOUNDRY_API_SCOPE` | Foundry delegated scope; use `https://ai.azure.com/user_impersonation` |
| `APIM_RESPONSES_URL` | Complete APIM URL for `POST /responses` |
| `APIM_SUBSCRIPTION_KEY` | Server-side APIM product subscription key; never exposed through public runtime configuration |
| `PORT` | FastAPI port; defaults to `3000` |

Only `ENTRA_TENANT_ID`, `ENTRA_SPA_CLIENT_ID`, and `FOUNDRY_API_SCOPE` are delivered to the SPA by `/api/config`. The APIM URL and subscription key remain server-side.

## Run locally

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
- New-chat and sign-out controls

## Validate

```bash
npm run check
python -m compileall app
docker build .
```

## Deploy to Azure

The included Dockerfile can run on Azure Container Apps, App Service, or another container host.

1. Configure the environment variables as application settings.
2. Add the deployed HTTPS origin to the SPA registration's redirect URIs.
3. Add that origin to the APIM CORS policy.
4. Configure the health probe to call `/health`.
5. Ensure the host can make outbound HTTPS calls to Microsoft Entra endpoints.

The web host is stateless and can run with multiple replicas.

For Azure Container Apps, build and deploy the included Dockerfile. For Azure App Service, either deploy the same container or use a Python source deployment with this startup command:

```text
python -m app.main
```

Run `npm ci && npm run build` before a non-container source deployment so `public/app.js` exists.

If your environment requires a Python package proxy, pass it without storing credentials in the Dockerfile:

```bash
docker build --build-arg PIP_INDEX_URL=https://<package-proxy>/pypi/simple/ .
```

## Troubleshooting

### No FastAPI request logs for an agent error

Inspect the FastAPI logs, the browser request to `/api/responses`, and APIM Application Insights telemetry.

### `401 AzureApiManagementKey`

Set `APIM_SUBSCRIPTION_KEY` to a valid subscription key attached to a product containing the Responses API.

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
