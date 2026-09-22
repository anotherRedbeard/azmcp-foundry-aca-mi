const MAX_APPROVAL_RESPONSES = 20;

export class ResponseRequestValidationError extends Error {}

export function buildResponseRequest(body) {
  const input = body?.input;
  const previousResponseId = body?.previous_response_id;

  if (
    previousResponseId !== undefined &&
    (typeof previousResponseId !== "string" || previousResponseId.trim().length === 0)
  ) {
    throw new ResponseRequestValidationError(
      "previous_response_id must be a non-empty string.",
    );
  }

  if (typeof input === "string") {
    const message = input.trim();
    if (!message) {
      throw new ResponseRequestValidationError(
        "A non-empty input string is required.",
      );
    }

    return {
      input: message,
      ...(previousResponseId
        ? { previous_response_id: previousResponseId.trim() }
        : {}),
    };
  }

  if (!Array.isArray(input) || input.length === 0) {
    throw new ResponseRequestValidationError(
      "Input must be a non-empty message or MCP approval response array.",
    );
  }

  if (!previousResponseId) {
    throw new ResponseRequestValidationError(
      "previous_response_id is required for MCP approval responses.",
    );
  }

  if (input.length > MAX_APPROVAL_RESPONSES) {
    throw new ResponseRequestValidationError(
      `No more than ${MAX_APPROVAL_RESPONSES} MCP approval responses are allowed.`,
    );
  }

  const approvals = input.map((item) => {
    if (
      !item ||
      typeof item !== "object" ||
      Array.isArray(item) ||
      item.type !== "mcp_approval_response" ||
      typeof item.approval_request_id !== "string" ||
      item.approval_request_id.trim().length === 0 ||
      typeof item.approve !== "boolean"
    ) {
      throw new ResponseRequestValidationError(
        "Each approval must include type mcp_approval_response, a non-empty approval_request_id, and a Boolean approve value.",
      );
    }

    return {
      type: "mcp_approval_response",
      approval_request_id: item.approval_request_id.trim(),
      approve: item.approve,
    };
  });

  return {
    input: approvals,
    previous_response_id: previousResponseId.trim(),
  };
}
