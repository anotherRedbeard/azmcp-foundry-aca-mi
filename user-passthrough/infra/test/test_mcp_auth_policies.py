import json
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


POLICIES = Path(__file__).resolve().parents[1] / "modules" / "policies"
RESOURCE_URL = "https://gateway.example.net/mcp/user-passthrough/mcp"
METADATA_URL = (
    "https://gateway.example.net/.well-known/oauth-protected-resource"
    "/mcp/user-passthrough/mcp"
)
SCOPE_URI = f"{RESOURCE_URL}/Mcp.Tools.ReadWrite"
TENANT_ID = "11111111-1111-4111-8111-111111111111"
MCP_CLIENT_ID = "22222222-2222-4222-8222-222222222222"
FOUNDRY_CLIENT_ID = "33333333-3333-4333-8333-333333333333"
CHATGPT_CLIENT_ID = "44444444-4444-4444-8444-444444444444"


def render_policy(name, chatgpt_client_id=""):
    replacements = {
        "__RESOURCE_URL__": RESOURCE_URL,
        "__METADATA_URL__": METADATA_URL,
        "__SCOPE_URI__": SCOPE_URI,
        "__TENANT_ID__": TENANT_ID,
        "__MCP_CLIENT_ID__": MCP_CLIENT_ID,
        "__API_CLIENT_ID__": FOUNDRY_CLIENT_ID,
        "__CHATGPT_CLIENT_CLAIM__": (
            f"<value>{chatgpt_client_id.lower()}</value>"
            if chatgpt_client_id
            else ""
        ),
    }
    text = (POLICIES / name).read_text()
    for marker, value in replacements.items():
        text = text.replace(marker, value)
    if re.search(r"__[A-Z_]+__", text):
        raise AssertionError("Unresolved policy template marker")
    return ET.fromstring(text)


class McpAuthPolicyTests(unittest.TestCase):
    def test_metadata_is_public_and_describes_the_resource(self):
        policy = render_policy("mcp-metadata.xml")
        inbound = policy.find("inbound")
        self.assertEqual(inbound[0].tag, "return-response")
        response = inbound[0]
        self.assertEqual(response.find("set-status").get("code"), "200")
        self.assertEqual(
            response.find("set-header[@name='Content-Type']/value").text,
            "application/json",
        )
        document = json.loads(response.find("set-body").text)
        self.assertEqual(document["resource"], RESOURCE_URL)
        self.assertEqual(document["scopes_supported"], [SCOPE_URI])
        self.assertEqual(
            document["authorization_servers"],
            [f"https://login.microsoftonline.com/{TENANT_ID}/v2.0"],
        )
        self.assertEqual(document["bearer_methods_supported"], ["header"])
        self.assertIsNone(inbound.find("validate-jwt"))
        self.assertIsNone(inbound.find("base"))

    def test_authentication_failure_challenges_only_the_mcp_validator(self):
        policy = render_policy("mcp.xml")
        jwt = policy.find("inbound/validate-jwt")
        when = policy.find("on-error/choose/when")
        self.assertEqual(
            when.get("condition"),
            f'@(context.LastError.PolicyId == "{jwt.get("id")}")',
        )
        response = when.find("return-response")
        self.assertEqual(response.find("set-status").get("code"), "401")
        self.assertEqual(
            response.find("set-header[@name='WWW-Authenticate']/value").text,
            f'Bearer resource_metadata="{METADATA_URL}", scope="{SCOPE_URI}"',
        )
        self.assertEqual(policy.find("on-error")[-1].tag, "base")

    def test_scope_failure_returns_a_separate_forbidden_challenge(self):
        policy = render_policy("mcp.xml")
        when = policy.find("inbound/choose/when")
        response = when.find("return-response")
        self.assertEqual(response.find("set-status").get("code"), "403")
        self.assertEqual(
            response.find("set-header[@name='WWW-Authenticate']/value").text,
            f'Bearer error="insufficient_scope", resource_metadata="{METADATA_URL}", '
            f'scope="{SCOPE_URI}"',
        )
        self.assertIn('jwt.Claims.ContainsKey("scp")', when.get("condition"))
        self.assertIn(
            """value.Split(' ').Contains("Mcp.Tools.ReadWrite")""",
            when.get("condition"),
        )
        self.assertEqual(
            policy.find("inbound/validate-jwt").get("output-token-variable-name"),
            "mcpJwt",
        )

    def test_chatgpt_is_opt_in_and_does_not_replace_foundry(self):
        for additional, expected in [
            ("", [FOUNDRY_CLIENT_ID]),
            (CHATGPT_CLIENT_ID, [FOUNDRY_CLIENT_ID, CHATGPT_CLIENT_ID]),
        ]:
            with self.subTest(additional_client=additional):
                policy = render_policy("mcp.xml", additional)
                claim = policy.find(
                    "inbound/validate-jwt/required-claims/claim[@name='azp']"
                )
                self.assertEqual(claim.get("match"), "any")
                self.assertEqual([value.text for value in claim], expected)

    def test_authentication_and_delegated_backend_forwarding_are_preserved(self):
        policy = render_policy("mcp.xml")
        jwt = policy.find("inbound/validate-jwt")
        self.assertEqual(jwt.get("require-expiration-time"), "true")
        self.assertEqual(jwt.get("require-scheme"), "Bearer")
        self.assertNotEqual(jwt.get("require-signed-tokens"), "false")
        self.assertEqual(
            jwt.find("openid-config").get("url"),
            f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/"
            ".well-known/openid-configuration",
        )
        self.assertEqual(
            [value.text for value in jwt.findall("audiences/audience")],
            [f"api://{MCP_CLIENT_ID}", MCP_CLIENT_ID],
        )
        self.assertIsNone(policy.find(".//set-header[@name='Authorization']"))
        self.assertIsNone(policy.find(".//authentication-managed-identity"))
        self.assertEqual(
            policy.find("inbound/set-backend-service").get("backend-id"),
            "azure-mcp",
        )


if __name__ == "__main__":
    unittest.main()
