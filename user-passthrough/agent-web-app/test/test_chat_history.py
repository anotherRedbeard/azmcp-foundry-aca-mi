import asyncio
import unittest

from app.chat_history import (
    ConversationNotFoundError,
    MemoryChatHistoryStore,
)


class MemoryChatHistoryStoreTests(unittest.TestCase):
    def test_crud_and_user_isolation(self) -> None:
        asyncio.run(self._test_crud_and_user_isolation())

    async def _test_crud_and_user_isolation(self) -> None:
        store = MemoryChatHistoryStore()
        conversation = await store.create_conversation(
            "user-one",
            "First conversation",
        )
        await store.add_message(
            "user-one",
            conversation["id"],
            "user",
            "Hello",
        )
        await store.update_response_id(
            "user-one",
            conversation["id"],
            "response-1",
        )

        loaded = await store.get_conversation(
            "user-one",
            conversation["id"],
        )
        self.assertEqual(loaded["previousResponseId"], "response-1")
        self.assertEqual(loaded["messages"][0]["content"], "Hello")
        self.assertEqual(await store.list_conversations("user-two"), [])

        with self.assertRaises(ConversationNotFoundError):
            await store.get_conversation(
                "user-two",
                conversation["id"],
            )

    def test_delete_one_and_clear_all(self) -> None:
        asyncio.run(self._test_delete_one_and_clear_all())

    async def _test_delete_one_and_clear_all(self) -> None:
        store = MemoryChatHistoryStore()
        first = await store.create_conversation("user-one", "First")
        second = await store.create_conversation("user-one", "Second")
        await store.add_message(
            "user-one",
            second["id"],
            "assistant",
            "Saved response",
        )

        await store.delete_conversation("user-one", first["id"])
        remaining = await store.list_conversations("user-one")
        self.assertEqual([item["id"] for item in remaining], [second["id"]])

        deleted = await store.clear_history("user-one")
        self.assertEqual(deleted, 2)
        self.assertEqual(await store.list_conversations("user-one"), [])


if __name__ == "__main__":
    unittest.main()
