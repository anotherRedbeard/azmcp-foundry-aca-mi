#!/usr/bin/env bash

set -euo pipefail

for command in az jq npx; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azmcp-managed-dev}"
DEPLOYMENT_NAME="${AZURE_DEPLOYMENT_NAME:-managed-identity-foundation}"

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

TENANT_ID="$(deployment_output AZURE_TENANT_ID)"
MCP_IDENTIFIER_URI="$(deployment_output ENTRA_APP_IDENTIFIER_URI)"
MCP_URL="$(deployment_output MCP_API_URL)"
MCP_SERVICE_PRINCIPAL_ID="$(deployment_output ENTRA_APP_SERVICE_PRINCIPAL_ID)"
INSPECTOR_ROLE_ID="$(deployment_output ENTRA_APP_INSPECTOR_ROLE_ID)"
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
