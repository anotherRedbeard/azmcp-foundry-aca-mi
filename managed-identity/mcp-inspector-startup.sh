#!/usr/bin/env bash

set -euo pipefail

for command in az azd npx; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

TENANT_ID="$(azd env get-value AZURE_TENANT_ID)"
MCP_IDENTIFIER_URI="$(azd env get-value ENTRA_APP_IDENTIFIER_URI)"
MCP_URL="$(azd env get-value MCP_API_URL)"
MCP_SERVICE_PRINCIPAL_ID="$(azd env get-value ENTRA_APP_SERVICE_PRINCIPAL_ID)"
INSPECTOR_ROLE_ID="$(azd env get-value ENTRA_APP_INSPECTOR_ROLE_ID)"
MCP_SCOPE="${MCP_IDENTIFIER_URI}/Mcp.Tools.ReadWrite"

USER_OBJECT_ID="$(az ad signed-in-user show --query id --output tsv)"
ASSIGNMENT_COUNT="$(
  az rest \
    --method get \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/${MCP_SERVICE_PRINCIPAL_ID}/appRoleAssignedTo" \
    --query "length(value[?principalId=='${USER_OBJECT_ID}' && appRoleId=='${INSPECTOR_ROLE_ID}'])" \
    --output tsv
)"

if [[ "$ASSIGNMENT_COUNT" != "1" ]]; then
  echo "Your user is not assigned the Mcp.Inspector.Access role." >&2
  echo "Follow the MCP Inspector role-assignment step in README.md, wait about five minutes, and retry." >&2
  exit 1
fi

az login \
  --tenant "$TENANT_ID" \
  --scope "$MCP_SCOPE" \
  --output none

MCP_TOKEN="$(
  az account get-access-token \
    --tenant "$TENANT_ID" \
    --scope "$MCP_SCOPE" \
    --query accessToken \
    --output tsv
)"

if [[ -z "$MCP_TOKEN" ]]; then
  echo "Azure CLI did not return an MCP access token." >&2
  exit 1
fi

AUTHORIZATION_HEADER="$(printf '%s: %s %s' Authorization Bearer "$MCP_TOKEN")"

exec npx -y @modelcontextprotocol/inspector@latest \
  --web \
  --server-url "${MCP_URL%/}/" \
  --transport http \
  --header "$AUTHORIZATION_HEADER"
