from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CreateConversationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)

    @field_validator("title")
    @classmethod
    def trim_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("title must not be empty")
        return value


class UpdateConversationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    previous_response_id: str = Field(
        alias="previousResponseId",
        min_length=1,
        max_length=200,
    )

    @field_validator("previous_response_id")
    @classmethod
    def trim_response_id(cls, value: str) -> str:
        return value.strip()


class CreateMessageRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=32000)

    @field_validator("content")
    @classmethod
    def require_content(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("content must not be empty")
        return value
