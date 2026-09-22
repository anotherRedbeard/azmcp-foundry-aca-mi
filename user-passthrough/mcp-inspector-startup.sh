MCP_APP_ID="$(azd env get-value ENTRA_APP_CLIENT_ID)"
MCP_SCOPE="api://${MCP_APP_ID}/Mcp.Tools.ReadWrite"
TENANT_ID="$(azd env get-value AZURE_TENANT_ID)"

az login \
  --tenant "$TENANT_ID" \
  --scope "$MCP_SCOPE"

MCP_TOKEN="$(
  az account get-access-token \
    --scope "$MCP_SCOPE" \
    --query accessToken \
    --output tsv
)"

MCP_URL="$(azd env get-value CONTAINER_APP_URL)"

npx -y @modelcontextprotocol/inspector@2.6.0 \
  --server-url "${MCP_URL%/}/" \
  --transport http \
  --header "Authorization: Bearer $MCP_TOKEN"
