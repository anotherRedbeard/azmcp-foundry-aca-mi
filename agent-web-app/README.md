# Foundry Agent Web App

An authenticated single-page chat application that invokes a Microsoft Foundry prompt agent through Azure API Management.

## Request flow

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

No client secret is required.

## Entra application registrations

Use separate SPA and protected API registrations.

### Protected API registration

1. Create a single-tenant registration such as `Foundry Agent API`.
2. Under **Expose an API**, accept `api://<API-client-id>`.
3. Add an enabled delegated scope named `access_as_user`.
4. Permit user or admin consent according to tenant policy.
5. Do not add a redirect URI or client credential.
6. Set this manifest property:

```json
"requestedAccessTokenVersion": 2
```

Record the complete scope:

```text
api://<API-client-id>/access_as_user
```

### SPA registration

1. Create a single-tenant registration such as `Foundry Agent SPA`.
2. Add the **Single-page application** platform.
3. Add `http://localhost:3000` as a redirect URI.
4. Add the protected API's delegated `access_as_user` permission.
5. Grant consent if tenant policy requires it.
6. Do not create a client secret.

For Azure deployment, add the deployed HTTPS origin as another SPA redirect URI.

## APIM Responses operation

Configure a `POST /responses` operation that:

1. Allows the web application's origins through CORS.
2. Validates the token tenant and protected API audience.
3. Requires `scp=access_as_user`.
4. Requires the SPA application ID in `azp`.
5. Injects the fixed Foundry `agent_reference`.
6. Authenticates to Foundry with APIM managed identity for `https://ai.azure.com`.
7. Forwards to:

```text
https://<foundry-resource>.services.ai.azure.com/api/projects/<project>/openai/v1/responses
```

Grant the APIM managed identity the required Foundry project role.

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

The key is stored only in the server environment and is added by Express when forwarding to APIM. It is not returned through `/api/config` or included in the browser bundle. Entra JWT validation remains the authorization boundary.

## Configuration

```bash
cp .env.example .env
```

| Variable | Purpose |
|---|---|
| `ENTRA_TENANT_ID` | Microsoft Entra tenant ID |
| `ENTRA_SPA_CLIENT_ID` | SPA registration client ID |
| `ENTRA_API_SCOPE` | Complete delegated scope, such as `api://<API-client-id>/access_as_user` |
| `APIM_RESPONSES_URL` | Complete APIM URL for `POST /responses` |
| `APIM_SUBSCRIPTION_KEY` | Server-side APIM product subscription key; never exposed through public runtime configuration |
| `PORT` | Express port; defaults to `3000` |
| `NODE_ENV` | Express runtime environment |

Only `ENTRA_TENANT_ID`, `ENTRA_SPA_CLIENT_ID`, and `ENTRA_API_SCOPE` are delivered to the SPA by `/api/config`. The APIM URL and subscription key remain server-side.

## Run locally

```bash
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

## Validate

```bash
npm run check
docker build .
```

## Deploy to Azure

The included Dockerfile can run on Azure Container Apps, App Service, or another container host.

1. Configure the environment variables as application settings.
2. Add the deployed HTTPS origin to the SPA registration's redirect URIs.
3. Add that origin to the APIM CORS policy.
4. Configure the health probe to call `/health`.
5. Ensure the host can make outbound HTTPS calls to Microsoft Entra endpoints.

The web host is stateless and can run with multiple replicas. For a non-container source deployment, run `npm run build` before `npm start`.

## Troubleshooting

### No Express request logs for an agent error

Inspect the Express logs, the browser request to `/api/responses`, and APIM Application Insights telemetry.

### `401 AzureApiManagementKey`

Set `APIM_SUBSCRIPTION_KEY` to a valid subscription key attached to a product containing the Responses API.

### Unexpected issuer

Set `"requestedAccessTokenVersion": 2` on the protected API registration and confirm APIM validates the tenant-specific v2 issuer.

### Deprecated `agent` property

The Foundry Responses API requires `agent_reference`. The APIM policy should inject it rather than accepting an agent name from the browser.
