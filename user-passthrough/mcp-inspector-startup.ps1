$McpAppId = azd env get-value ENTRA_APP_CLIENT_ID
$McpScope = "api://$McpAppId/Mcp.Tools.ReadWrite"
$TenantId = azd env get-value AZURE_TENANT_ID

az login `
  --tenant $TenantId `
  --scope $McpScope

$McpToken = az account get-access-token `
  --scope $McpScope `
  --query accessToken `
  --output tsv

$McpUrl = azd env get-value CONTAINER_APP_URL
$ServerUrl = "$($McpUrl.TrimEnd('/'))/"

npx -y @modelcontextprotocol/inspector@2.6.0 `
  --server-url $ServerUrl `
  --transport http `
  --header "Authorization: ******"
