from functools import cached_property
from urllib.parse import urlsplit

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    port: int = Field(default=3000, ge=1, le=65535, alias="PORT")
    entra_tenant_id: str = Field(alias="ENTRA_TENANT_ID")
    entra_spa_client_id: str = Field(alias="ENTRA_SPA_CLIENT_ID")
    foundry_api_scope: str = Field(alias="FOUNDRY_API_SCOPE")
    apim_responses_url: str = Field(alias="APIM_RESPONSES_URL")
    apim_subscription_key: str = Field(alias="APIM_SUBSCRIPTION_KEY")

    @field_validator(
        "entra_tenant_id",
        "entra_spa_client_id",
        "foundry_api_scope",
        "apim_responses_url",
        "apim_subscription_key",
    )
    @classmethod
    def require_non_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be empty")
        return value

    @field_validator("foundry_api_scope")
    @classmethod
    def require_complete_scope(cls, value: str) -> str:
        audience, separator, scope_name = value.rpartition("/")
        if not separator or not audience or not scope_name:
            raise ValueError("FOUNDRY_API_SCOPE must be a complete delegated scope URI")
        return value

    @field_validator("apim_responses_url")
    @classmethod
    def require_https(cls, value: str) -> str:
        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError("APIM_RESPONSES_URL must be a complete HTTPS URL")
        return value

    @cached_property
    def foundry_scope_name(self) -> str:
        _, _, scope_name = self.foundry_api_scope.rpartition("/")
        return scope_name

    @cached_property
    def foundry_api_audience(self) -> str:
        audience, _, _ = self.foundry_api_scope.rpartition("/")
        return audience
