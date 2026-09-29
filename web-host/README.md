# Deploy Optional Web Applications

The managed-identity and user-passthrough web applications are deployed
independently. Each workflow creates a dedicated resource group, Azure
Container Registry, Container Apps environment, and web Container App.

Run the matching core infrastructure workflow before its web workflow:

| Identity model | Core workflow | Optional web workflow |
| --- | --- | --- |
| Managed identity | **Deploy managed-identity infrastructure** | **Deploy managed-identity web app** |
| User passthrough | **Deploy user-passthrough infrastructure** | **Deploy user-passthrough web app** |

## GitHub OIDC

Create an Entra application for GitHub Actions and add one federated credential
for each GitHub Environment used by the workflows:

| Setting | Value |
| --- | --- |
| Organization | `<github-owner>` |
| Repository | `<github-repository>` |
| Entity type | Environment |
| Environment | Exact GitHub Environment name |

The deployment identity needs `Contributor` on the target subscription. The
managed-identity core workflow and both web workflows create role assignments
and therefore also need `User Access Administrator`.

The workflows do not create or modify Entra applications. Create the
variant-specific app registrations manually by following the selected
variant's README before running its infrastructure workflow.

## GitHub Environments

Create these environments:

```text
managed-identity-infra-dev
managed-identity-web-dev
user-passthrough-infra-dev
user-passthrough-web-dev
```

Add these variables to every environment:

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | GitHub deployment application client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

The web environments need no application-specific variables. They read the
tenant ID, SPA client ID, API scope, and APIM Responses URL from the stable core
deployment.

## Deploy a web application

Run the matching web workflow from the repository's **Actions** page. Its
default core resource group must match the resource group selected when the
core workflow ran.

Each web workflow:

1. Reads the matching stable core deployment outputs.
2. Creates a dedicated web-host resource group.
3. Builds one application image in ACR.
4. Deploys one Azure Container App.
5. Checks `/health`.
6. Publishes the application URL in the workflow summary.

Default web resource groups:

```text
rg-azmcp-managed-web-dev
rg-azmcp-passthrough-web-dev
```

## Configure the APIM subscription key

The web workflows intentionally deploy this placeholder:

```text
replace-before-use
```

After deployment, open the web Container App in the Azure portal:

1. Open **Settings > Secrets**.
2. Replace the value of `apim-subscription-key` with the matching APIM
   subscription key.
3. Create or restart the active revision so the application reads the new
   secret.

The web applications remain healthy with the placeholder, but agent requests
will receive an APIM authorization error until it is replaced.

## Configure the SPA redirect

Copy the application URL from the workflow summary. On the matching SPA
registration, add it under **Authentication > Single-page application**.

Do not add one variant's URL to the other variant's SPA registration.

## Cleanup

Delete only the selected web resource group. This does not remove the
corresponding Foundry, APIM, MCP, or Entra resources.
