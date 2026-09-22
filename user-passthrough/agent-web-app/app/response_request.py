from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

MAX_APPROVAL_RESPONSES = 20


class McpApprovalResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["mcp_approval_response"]
    approval_request_id: str = Field(min_length=1)
    approve: bool

    @field_validator("approval_request_id")
    @classmethod
    def strip_approval_request_id(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("approval_request_id must not be empty")
        return stripped


class AgentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str | list[McpApprovalResponse]
    previous_response_id: str | None = None

    @field_validator("previous_response_id")
    @classmethod
    def strip_previous_response_id(cls, value: str | None) -> str | None:
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            raise ValueError("previous_response_id must not be empty")
        return stripped

    @model_validator(mode="after")
    def validate_input(self) -> "AgentRequest":
        if isinstance(self.input, str):
            self.input = self.input.strip()
            if not self.input:
                raise ValueError("input must not be empty")
            return self

        if not self.input:
            raise ValueError("at least one MCP approval response is required")
        if len(self.input) > MAX_APPROVAL_RESPONSES:
            raise ValueError(
                f"no more than {MAX_APPROVAL_RESPONSES} approval responses are allowed"
            )
        if not self.previous_response_id:
            raise ValueError(
                "previous_response_id is required for MCP approval responses"
            )
        return self
