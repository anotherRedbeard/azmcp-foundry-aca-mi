import asyncio
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException

from app.auth import TokenValidator
from app.config import Settings


def create_settings() -> Settings:
    return Settings(
        PORT=3000,
        ENTRA_TENANT_ID="tenant-id",
        ENTRA_SPA_CLIENT_ID="spa-client-id",
        FOUNDRY_API_SCOPE="https://ai.azure.com/user_impersonation",
        APIM_RESPONSES_URL="https://example.azure-api.net/responses",
        APIM_SUBSCRIPTION_KEY="subscription-key",
        COSMOS_ENDPOINT="https://example.documents.azure.com:443/",
    )


class TokenValidatorTests(unittest.TestCase):
    def test_returns_validated_object_id_and_authorization(self) -> None:
        validator = TokenValidator(create_settings())
        validator._jwks.get_signing_key_from_jwt = lambda _token: (  # type: ignore[method-assign]
            SimpleNamespace(key="key")
        )

        with patch(
            "app.auth.jwt.decode",
            return_value={
                "scp": "user_impersonation",
                "appid": "spa-client-id",
                "oid": "user-object-id",
            },
        ):
            principal = asyncio.run(validator.validate("Bearer token"))

        self.assertEqual(principal.authorization, "Bearer token")
        self.assertEqual(principal.object_id, "user-object-id")

    def test_rejects_token_without_object_id(self) -> None:
        validator = TokenValidator(create_settings())
        validator._jwks.get_signing_key_from_jwt = lambda _token: (  # type: ignore[method-assign]
            SimpleNamespace(key="key")
        )

        with patch(
            "app.auth.jwt.decode",
            return_value={
                "scp": "user_impersonation",
                "appid": "spa-client-id",
            },
        ):
            with self.assertRaises(HTTPException) as context:
                asyncio.run(validator.validate("Bearer token"))

        self.assertEqual(context.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
