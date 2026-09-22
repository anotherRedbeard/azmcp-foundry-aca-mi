import assert from "node:assert/strict";
import test from "node:test";
import {
  buildResponseRequest,
  ResponseRequestValidationError,
} from "../src/response-request.js";

test("builds a trimmed message request", () => {
  assert.deepEqual(buildResponseRequest({ input: "  list storage accounts  " }), {
    input: "list storage accounts",
  });
});

test("builds a sanitized MCP approval continuation", () => {
  assert.deepEqual(
    buildResponseRequest({
      previous_response_id: " response-1 ",
      input: [
        {
          type: "mcp_approval_response",
          approval_request_id: " approval-1 ",
          approve: true,
          ignored: "value",
        },
        {
          type: "mcp_approval_response",
          approval_request_id: "approval-2",
          approve: false,
        },
      ],
    }),
    {
      previous_response_id: "response-1",
      input: [
        {
          type: "mcp_approval_response",
          approval_request_id: "approval-1",
          approve: true,
        },
        {
          type: "mcp_approval_response",
          approval_request_id: "approval-2",
          approve: false,
        },
      ],
    },
  );
});

test("requires a previous response for MCP approvals", () => {
  assert.throws(
    () =>
      buildResponseRequest({
        input: [
          {
            type: "mcp_approval_response",
            approval_request_id: "approval-1",
            approve: true,
          },
        ],
      }),
    ResponseRequestValidationError,
  );
});

test("rejects arbitrary structured input", () => {
  assert.throws(
    () =>
      buildResponseRequest({
        previous_response_id: "response-1",
        input: [{ type: "function_call_output", output: "untrusted" }],
      }),
    ResponseRequestValidationError,
  );
});
