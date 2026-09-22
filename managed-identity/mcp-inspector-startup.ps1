$ErrorActionPreference = "Stop"

foreach ($Command in @("az", "azd", "npx")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Command"
    }
}

$TenantId = azd env get-value AZURE_TENANT_ID
$McpIdentifierUri = azd env get-value ENTRA_APP_IDENTIFIER_URI
$McpUrl = azd env get-value MCP_API_URL
$McpServicePrincipalId = azd env get-value ENTRA_APP_SERVICE_PRINCIPAL_ID
$InspectorRoleId = azd env get-value ENTRA_APP_INSPECTOR_ROLE_ID
$McpScope = "$McpIdentifierUri/Mcp.Tools.ReadWrite"
$ServerUrl = "$($McpUrl.TrimEnd('/'))/"

$UserObjectId = az ad signed-in-user show --query id --output tsv
$AssignmentCount = az rest `
    --method get `
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$McpServicePrincipalId/appRoleAssignedTo" `
    --query "length(value[?principalId=='$UserObjectId' && appRoleId=='$InspectorRoleId'])" `
    --output tsv

if ($AssignmentCount -ne "1") {
    throw "Your user is not assigned the Mcp.Inspector.Access role. Follow the MCP Inspector role-assignment step in README.md, wait about five minutes, and retry."
}

az login `
    --tenant $TenantId `
    --scope $McpScope `
    --output none

$McpToken = az account get-access-token `
    --tenant $TenantId `
    --scope $McpScope `
    --query accessToken `
    --output tsv

if ([string]::IsNullOrWhiteSpace($McpToken)) {
    throw "Azure CLI did not return an MCP access token."
}

$AuthorizationHeader = [string]::Concat(
    "Authorization",
    ": ",
    "Bearer",
    " ",
    $McpToken
)

npx -y @modelcontextprotocol/inspector@latest `
    --web `
    --server-url $ServerUrl `
    --transport http `
    --header $AuthorizationHeader
