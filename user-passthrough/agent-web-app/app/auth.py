import asyncio
import logging

import jwt
from fastapi import HTTPException, status
from jwt import PyJWKClient

from .config import Settings

logger = logging.getLogger(__name__)


class TokenValidator:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._issuer = (
            f"https://sts.windows.net/{settings.entra_tenant_id}/"
        )
        self._jwks = PyJWKClient(
            f"https://login.microsoftonline.com/"
            f"{settings.entra_tenant_id}/discovery/v2.0/keys"
        )

    async def validate(self, authorization: str | None) -> str:
        prefix = "Bearer "
        if not authorization or not authorization.startswith(prefix):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="A bearer access token is required.",
            )

        token = authorization[len(prefix) :]
        try:
            signing_key = await asyncio.to_thread(
                self._jwks.get_signing_key_from_jwt,
                token,
            )
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                issuer=self._issuer,
                audience=self._settings.foundry_api_audience,
            )
        except jwt.PyJWTError as error:
            logger.warning(
                "Access token validation failed: %s",
                type(error).__name__,
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="The access token is invalid or expired.",
            ) from error

        scope_claim = claims.get("scp")
        scopes = scope_claim.split() if isinstance(scope_claim, str) else []
        if self._settings.foundry_scope_name not in scopes:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="The required Foundry scope is missing.",
            )

        authorized_client = claims.get("appid")
        if authorized_client != self._settings.entra_spa_client_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="The token was not issued to this SPA.",
            )

        return authorization
