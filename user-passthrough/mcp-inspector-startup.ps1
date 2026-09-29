$ErrorActionPreference = "Stop"

foreach ($Command in @("az", "npx")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Command"
    }
}

$ResourceGroup = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } else { "rg-azmcp-passthrough-dev" }
$DeploymentName = if ($env:AZURE_DEPLOYMENT_NAME) { $env:AZURE_DEPLOYMENT_NAME } else { "user-passthrough-foundation" }

function Get-DeploymentOutput {
    param([Parameter(Mandatory = $true)][string]$Name)

    az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query "properties.outputs.$Name.value" `
        --output tsv
}

$McpAppId = Get-DeploymentOutput "ENTRA_APP_CLIENT_ID"
$McpScope = "api://$McpAppId/Mcp.Tools.ReadWrite"
$TenantId = Get-DeploymentOutput "AZURE_TENANT_ID"

az login `
    --tenant $TenantId `
    --scope $McpScope `
    --output none

$McpToken = az account get-access-token `
    --tenant $TenantId `
    --scope $McpScope `
    --query accessToken `
    --output tsv

$McpUrl = Get-DeploymentOutput "CONTAINER_APP_URL"
$ServerUrl = "$($McpUrl.TrimEnd('/'))/"

npx -y @modelcontextprotocol/inspector@2.6.0 `
    --server-url $ServerUrl `
    --transport http `
    --header "Authorization: Bearer $McpToken"
