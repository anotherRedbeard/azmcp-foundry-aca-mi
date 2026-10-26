import os
import unittest
from datetime import datetime, timezone
from uuid import uuid4

os.environ.update(
    {
        "ENTRA_TENANT_ID": "tenant-id",
        "ENTRA_SPA_CLIENT_ID": "spa-client-id",
        "FOUNDRY_API_SCOPE": "https://ai.azure.com/user_impersonation",
        "APIM_RESPONSES_URL": "https://example.azure-api.net/responses",
        "APIM_SUBSCRIPTION_KEY": "subscription-key",
        "COSMOS_ENDPOINT": "https://example.documents.azure.com:443/",
    }
)

from fastapi.testclient import TestClient

from app.auth import AuthenticatedPrincipal
from app.chat_history import ConversationNotFoundError
from app.config import Settings
from app.main import create_app


class FakeTokenValidator:
    async def validate(
        self,
        authorization: str | None,
    ) -> AuthenticatedPrincipal:
        if authorization not in {"Bearer user-one", "Bearer user-two"}:
            raise AssertionError("Unexpected test authorization header")
        return AuthenticatedPrincipal(
            authorization=authorization,
            object_id=authorization.removeprefix("Bearer "),
        )


class InMemoryHistoryStore:
    def __init__(self) -> None:
        self.items: dict[str, dict[str, dict]] = {}

    async def list_conversations(self, user_id: str) -> list[dict]:
        return list(self.items.get(user_id, {}).values())

    async def create_conversation(self, user_id: str, title: str) -> dict:
        now = datetime.now(timezone.utc).isoformat()
        conversation = {
            "id": str(uuid4()),
            "title": title,
            "previousResponseId": None,
            "createdAt": now,
            "updatedAt": now,
        }
        self.items.setdefault(user_id, {})[conversation["id"]] = conversation
        return conversation

    async def get_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict:
        return {
            **self.items[user_id][conversation_id],
            "messages": [],
        }

    async def update_response_id(
        self,
        user_id: str,
        conversation_id: str,
        previous_response_id: str,
    ) -> dict:
        conversation = self.items[user_id][conversation_id]
        conversation["previousResponseId"] = previous_response_id
        return conversation

    async def rename_conversation(
        self,
        user_id: str,
        conversation_id: str,
        title: str,
    ) -> dict:
        try:
            conversation = self.items[user_id][conversation_id]
        except KeyError as error:
            raise ConversationNotFoundError(conversation_id) from error
        conversation["title"] = title
        conversation["updatedAt"] = datetime.now(timezone.utc).isoformat()
        return conversation

    async def add_message(
        self,
        user_id: str,
        conversation_id: str,
        role: str,
        content: str,
    ) -> dict:
        if conversation_id not in self.items.get(user_id, {}):
            raise AssertionError("Cross-user conversation access")
        return {
            "id": str(uuid4()),
            "role": role,
            "content": content,
            "createdAt": datetime.now(timezone.utc).isoformat(),
        }

    async def delete_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> None:
        del self.items[user_id][conversation_id]

    async def clear_history(self, user_id: str) -> int:
        deleted = len(self.items.get(user_id, {}))
        self.items[user_id] = {}
        return deleted


class ChatApiTests(unittest.TestCase):
    @staticmethod
    def auth_headers(user_id: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {user_id}"}

    def setUp(self) -> None:
        self.store = InMemoryHistoryStore()
        app = create_app(
            Settings(),
            history_store=self.store,
            token_validator=FakeTokenValidator(),  # type: ignore[arg-type]
        )
        self.client = TestClient(app)
        self.client.__enter__()

    def tearDown(self) -> None:
        self.client.__exit__(None, None, None)

    def test_conversations_are_isolated_by_validated_object_id(self) -> None:
        created = self.client.post(
            "/api/conversations",
            headers={"Authorization": "Bearer user-one"},
            json={"title": "User one's conversation"},
        )
        self.assertEqual(created.status_code, 201)

        user_one = self.client.get(
            "/api/conversations",
            headers={"Authorization": "Bearer user-one"},
        )
        user_two = self.client.get(
            "/api/conversations",
            headers={"Authorization": "Bearer user-two"},
        )

        self.assertEqual(len(user_one.json()), 1)
        self.assertEqual(user_two.json(), [])

    def test_clear_history_only_clears_authenticated_user(self) -> None:
        for token in ("user-one", "user-two"):
            response = self.client.post(
                "/api/conversations",
                headers={"Authorization": f"Bearer {token}"},
                json={"title": f"{token} conversation"},
            )
            self.assertEqual(response.status_code, 201)

        cleared = self.client.delete(
            "/api/conversations",
            headers={"Authorization": "Bearer user-one"},
        )

        self.assertEqual(cleared.status_code, 200)
        self.assertEqual(cleared.json(), {"deleted": 1})
        self.assertEqual(self.store.items["user-one"], {})
        self.assertEqual(len(self.store.items["user-two"]), 1)

    def test_rename_conversation_only_updates_authenticated_user(self) -> None:
        created = self.client.post(
            "/api/conversations",
            headers=self.auth_headers("user-one"),
            json={"title": "Original title"},
        ).json()

        renamed = self.client.patch(
            f"/api/conversations/{created['id']}",
            headers=self.auth_headers("user-one"),
            json={"title": "  Renamed chat  "},
        )

        self.assertEqual(renamed.status_code, 200)
        self.assertEqual(renamed.json()["title"], "Renamed chat")
        self.assertEqual(
            self.store.items["user-one"][created["id"]]["title"],
            "Renamed chat",
        )

        other_user = self.client.patch(
            f"/api/conversations/{created['id']}",
            headers=self.auth_headers("user-two"),
            json={"title": "Not allowed"},
        )
        self.assertEqual(other_user.status_code, 404)

    def test_rejects_invalid_conversation_updates(self) -> None:
        created = self.client.post(
            "/api/conversations",
            headers=self.auth_headers("user-one"),
            json={"title": "Conversation"},
        ).json()

        for body in (
            {},
            {"title": "   "},
            {"title": "Renamed", "previousResponseId": "response-1"},
        ):
            with self.subTest(body=body):
                response = self.client.patch(
                    f"/api/conversations/{created['id']}",
                    headers=self.auth_headers("user-one"),
                    json=body,
                )
                self.assertEqual(response.status_code, 400)

    def test_previous_response_id_update_remains_supported(self) -> None:
        created = self.client.post(
            "/api/conversations",
            headers=self.auth_headers("user-one"),
            json={"title": "Conversation"},
        ).json()

        updated = self.client.patch(
            f"/api/conversations/{created['id']}",
            headers=self.auth_headers("user-one"),
            json={"previousResponseId": "response-1"},
        )

        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["previousResponseId"], "response-1")

    def test_rejects_unknown_message_fields(self) -> None:
        created = self.client.post(
            "/api/conversations",
            headers={"Authorization": "Bearer user-one"},
            json={"title": "Conversation"},
        ).json()

        response = self.client.post(
            f"/api/conversations/{created['id']}/messages",
            headers={"Authorization": "Bearer user-one"},
            json={
                "role": "user",
                "content": "Hello",
                "userId": "user-two",
            },
        )

        self.assertEqual(response.status_code, 400)

    def test_web_shell_disables_browser_caching(self) -> None:
        for path in ("/", "/index.html", "/app.js", "/styles.css"):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(
                    response.headers["cache-control"],
                    "no-store, no-cache, must-revalidate",
                )


if __name__ == "__main__":
    unittest.main()
