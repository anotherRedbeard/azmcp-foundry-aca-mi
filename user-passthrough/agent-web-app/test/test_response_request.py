import unittest

from pydantic import ValidationError

from app.response_request import AgentRequest


class AgentRequestTests(unittest.TestCase):
    def test_accepts_trimmed_text_input(self) -> None:
        request = AgentRequest(input="  list subscriptions  ")

        self.assertEqual(request.input, "list subscriptions")

    def test_accepts_approval_response_with_previous_id(self) -> None:
        request = AgentRequest(
            input=[
                {
                    "type": "mcp_approval_response",
                    "approval_request_id": " approval-1 ",
                    "approve": True,
                }
            ],
            previous_response_id=" response-1 ",
        )

        self.assertEqual(request.previous_response_id, "response-1")
        self.assertEqual(request.input[0].approval_request_id, "approval-1")

    def test_rejects_approval_response_without_previous_id(self) -> None:
        with self.assertRaises(ValidationError):
            AgentRequest(
                input=[
                    {
                        "type": "mcp_approval_response",
                        "approval_request_id": "approval-1",
                        "approve": True,
                    }
                ]
            )

    def test_rejects_unknown_approval_fields(self) -> None:
        with self.assertRaises(ValidationError):
            AgentRequest(
                input=[
                    {
                        "type": "mcp_approval_response",
                        "approval_request_id": "approval-1",
                        "approve": True,
                        "unexpected": "value",
                    }
                ],
                previous_response_id="response-1",
            )


if __name__ == "__main__":
    unittest.main()
