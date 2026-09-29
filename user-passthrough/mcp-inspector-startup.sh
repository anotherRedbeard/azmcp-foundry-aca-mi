#!/usr/bin/env bash

set -euo pipefail

for command in az jq npx; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-azmcp-passthrough-dev}"
DEPLOYMENT_NAME="${AZURE_DEPLOYMENT_NAME:-user-passthrough-foundation}"

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

MCP_APP_ID="$(deployment_output ENTRA_APP_CLIENT_ID)"
MCP_SCOPE="api://${MCP_APP_ID}/Mcp.Tools.ReadWrite"
TENANT_ID="$(deployment_output AZURE_TENANT_ID)"

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

MCP_URL="$(deployment_output CONTAINER_APP_URL)"

npx -y @modelcontextprotocol/inspector@2.6.0 \
  --server-url "${MCP_URL%/}/" \
  --transport http \
  --header "Authorization: Bearer $MCP_TOKEN"
