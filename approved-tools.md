# Approved Azure MCP Tools

Use this seven-tool allowlist for the focused Azure operations report profile
in [agent-system-instructions.md](agent-system-instructions.md). Select only
these exact command names in the Foundry MCP tool-selection panel, save the
agent, and test in a new conversation.

| Tool name | Purpose |
| --- | --- |
| `subscription_list` | Discover subscriptions accessible to the connected identity. |
| `arm_validate_query` | Validate directly authored Resource Graph queries before execution. |
| `arm_execute_query` | Execute validated Resource Graph queries for inventory and configuration reports. |
| `arm_get_resource` | Read targeted resource configuration. |
| `arm_query_costs` | Retrieve Cost Management data. |
| `monitor_metrics_query` | Retrieve metrics for individual resources, including storage usage and VM CPU. |
| `advisor_recommendation_list` | Retrieve Advisor recommendations for savings investigations. |

## Copyable configuration

The Foundry configuration field is `allowed_tools`, not `approved_tools`.
Apply this fragment to the existing MCP tool entry, preserving its connection,
authentication, and other settings:

```json
{
  "allowed_tools": {
    "tool_names": [
      "subscription_list",
      "arm_validate_query",
      "arm_execute_query",
      "arm_get_resource",
      "arm_query_costs",
      "monitor_metrics_query",
      "advisor_recommendation_list"
    ]
  }
}
```

This is a fragment, not a complete agent definition. Omitting `allowed_tools`
or setting it to `[]` allows all tools exposed by the server; it does not
disable tool access.

## Scope and safeguards

The allowlist filters tools available to the agent. It does not change the
server's namespaces, grant Azure permissions, switch identities, or configure
tool-call approvals. Retain the read-only instructions and server enforcement.

Resource Graph query generation is intentionally excluded: the agent authors
queries directly and validates them before execution. `monitor_metrics_batchquery`
is also excluded because its separate endpoint fails delegated OBO authentication
in this user-passthrough deployment. The approved per-resource metrics tool still
requires an explicit subscription and the resource's full inventory ID.

For managed-identity deployments, keep that variant's connection and identity
separate and adapt the authentication-specific instructions before reuse.

Reference: [Microsoft Foundry MCP tools documentation](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).
