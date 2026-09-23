# Azure MCP Foundry Identity Variants

This repository contains two independent implementations for connecting a Microsoft Foundry prompt agent to Azure MCP. Choose the identity model that matches your authorization requirements, then follow that variant's README.

This root README is an overview only. Run deployment commands from the selected variant directory, not from the repository root.

## Choose a deployment

| Identity model | Azure authorization identity | Deployment guide | Architecture diagram |
|---|---|---|---|
| Managed identity | Shared Azure MCP Container App managed identity | [`managed-identity/README.md`](managed-identity/README.md) | [`managed-identity/foundry-apim-mcp-managed-identity.excalidraw`](managed-identity/foundry-apim-mcp-managed-identity.excalidraw) |
| Delegated authentication / identity passthrough | Signed-in user through OAuth identity passthrough and OBO | [`user-passthrough/README.md`](user-passthrough/README.md) | [`user-passthrough/foundry-apim-mcp-user-passthrough.excalidraw`](user-passthrough/foundry-apim-mcp-user-passthrough.excalidraw) |

Choose **managed identity** when all users should receive the same Azure access. Azure RBAC is evaluated for the Container App managed identity.

Choose **delegated authentication** when Azure RBAC must be evaluated independently for each signed-in user.

The linked variant README is the authoritative source for that deployment's prerequisites, Entra configuration, infrastructure deployment, direct MCP tool setup, manual testing, web application setup, troubleshooting, and cleanup.

Quick links:

- [Deploy the managed-identity variant](managed-identity/README.md)
- [Deploy the user-passthrough/OBO variant](user-passthrough/README.md)
- [Deploy both web applications with GitHub Actions](web-host/README.md)
- [Configure MCP Inspector through managed-identity APIM](managed-identity/README.md#9-use-mcp-inspector-through-apim)

## Keep the variants isolated

Azure MCP selects its downstream authentication strategy when the server process starts:

- Managed identity uses `UseHostingEnvironmentIdentity`.
- Delegated authentication uses `UseOnBehalfOf`.

Do not combine or share the variants':

- Azure MCP Container Apps or ingress URLs
- Entra applications or OAuth connections
- APIM policies or MCP servers
- Foundry projects, agents, or MCP connections
- `azd` environments or deployment outputs
- Web application configuration

The optional [dual web-host deployment](web-host/README.md) places only the two
web front ends in one shared Container Apps environment. Their APIM, Foundry,
MCP runtime, Entra configuration, and application settings remain separate.

Pointing one variant at the other variant's MCP endpoint creates a hybrid identity flow and invalidates the authorization model.

## Shared infrastructure shape

Each variant independently deploys:

- Azure MCP Server on Azure Container Apps
- API Management Basic v2
- A Microsoft Foundry account and project
- `gpt-5-mini` and `gpt-5`
- A narrow APIM Responses API
- A variant-specific APIM passthrough MCP server
- Identity configuration and role assignments for that flow

The prompt agent and its direct MCP tool are configured after infrastructure provisioning. Neither deployment uses a Foundry toolbox.

## Repository layout

```text
managed-identity/
  README.md
  azure.yaml
  infra/
  agent-web-app/
  foundry-apim-mcp-managed-identity.excalidraw

user-passthrough/
  README.md
  azure.yaml
  infra/
  agent-web-app/
  foundry-apim-mcp-user-passthrough.excalidraw

web-host/
  README.md
  infra/

.github/workflows/
  deploy-web-apps.yml
```

Deployment and testing commands belong only in the corresponding variant README. Web-host implementation details belong in that variant's `agent-web-app/README.md`.

## Attribution

This project was originally based on [Azure-Samples/azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi) at commit [`e35a1c3`](https://github.com/Azure-Samples/azmcp-foundry-aca-mi/commit/e35a1c32ecc804ecc514244dd7cd4e013371cb30).
