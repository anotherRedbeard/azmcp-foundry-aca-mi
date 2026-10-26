import logging
from datetime import datetime, timezone
from typing import Any, Protocol
from uuid import uuid4

from azure.cosmos.aio import CosmosClient
from azure.cosmos.exceptions import (
    CosmosHttpResponseError,
    CosmosResourceNotFoundError,
)
from azure.identity.aio import DefaultAzureCredential, ManagedIdentityCredential

from .config import Settings

logger = logging.getLogger(__name__)


class ConversationNotFoundError(LookupError):
    pass


class ChatHistoryStore(Protocol):
    async def list_conversations(self, user_id: str) -> list[dict[str, Any]]: ...

    async def get_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict[str, Any]: ...

    async def create_conversation(
        self,
        user_id: str,
        title: str,
    ) -> dict[str, Any]: ...

    async def update_response_id(
        self,
        user_id: str,
        conversation_id: str,
        previous_response_id: str,
    ) -> dict[str, Any]: ...

    async def rename_conversation(
        self,
        user_id: str,
        conversation_id: str,
        title: str,
    ) -> dict[str, Any]: ...

    async def add_message(
        self,
        user_id: str,
        conversation_id: str,
        role: str,
        content: str,
    ) -> dict[str, Any]: ...

    async def delete_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> None: ...

    async def clear_history(self, user_id: str) -> int: ...


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class MemoryChatHistoryStore:
    def __init__(self) -> None:
        self._conversations: dict[str, dict[str, dict[str, Any]]] = {}
        self._messages: dict[str, dict[str, list[dict[str, Any]]]] = {}

    async def list_conversations(self, user_id: str) -> list[dict[str, Any]]:
        conversations = list(
            self._conversations.get(user_id, {}).values(),
        )
        conversations.sort(
            key=lambda item: item["updatedAt"],
            reverse=True,
        )
        return [dict(item) for item in conversations]

    async def get_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict[str, Any]:
        conversation = self._get_conversation(user_id, conversation_id)
        return {
            **conversation,
            "messages": [
                dict(item)
                for item in self._messages.get(user_id, {}).get(
                    conversation_id,
                    [],
                )
            ],
        }

    async def create_conversation(
        self,
        user_id: str,
        title: str,
    ) -> dict[str, Any]:
        now = utc_now()
        conversation = {
            "id": str(uuid4()),
            "title": title,
            "previousResponseId": None,
            "createdAt": now,
            "updatedAt": now,
        }
        self._conversations.setdefault(user_id, {})[
            conversation["id"]
        ] = conversation
        self._messages.setdefault(user_id, {})[conversation["id"]] = []
        return dict(conversation)

    async def update_response_id(
        self,
        user_id: str,
        conversation_id: str,
        previous_response_id: str,
    ) -> dict[str, Any]:
        conversation = self._get_conversation(user_id, conversation_id)
        conversation["previousResponseId"] = previous_response_id
        conversation["updatedAt"] = utc_now()
        return dict(conversation)

    async def rename_conversation(
        self,
        user_id: str,
        conversation_id: str,
        title: str,
    ) -> dict[str, Any]:
        conversation = self._get_conversation(user_id, conversation_id)
        conversation["title"] = title
        conversation["updatedAt"] = utc_now()
        return dict(conversation)

    async def add_message(
        self,
        user_id: str,
        conversation_id: str,
        role: str,
        content: str,
    ) -> dict[str, Any]:
        conversation = self._get_conversation(user_id, conversation_id)
        now = utc_now()
        message = {
            "id": str(uuid4()),
            "role": role,
            "content": content,
            "createdAt": now,
        }
        self._messages[user_id][conversation_id].append(message)
        conversation["updatedAt"] = now
        return dict(message)

    async def delete_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> None:
        self._get_conversation(user_id, conversation_id)
        del self._conversations[user_id][conversation_id]
        del self._messages[user_id][conversation_id]

    async def clear_history(self, user_id: str) -> int:
        conversation_count = len(self._conversations.get(user_id, {}))
        message_count = sum(
            len(messages)
            for messages in self._messages.get(user_id, {}).values()
        )
        self._conversations[user_id] = {}
        self._messages[user_id] = {}
        return conversation_count + message_count

    def _get_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict[str, Any]:
        try:
            return self._conversations[user_id][conversation_id]
        except KeyError as error:
            raise ConversationNotFoundError(conversation_id) from error


class CosmosChatHistoryStore:
    def __init__(self, settings: Settings) -> None:
        self._credential = (
            ManagedIdentityCredential()
            if settings.azure_hosted
            else DefaultAzureCredential(
                exclude_managed_identity_credential=True,
            )
        )
        self._client = CosmosClient(
            settings.cosmos_endpoint or "",
            credential=self._credential,
        )
        database = self._client.get_database_client(
            settings.cosmos_database_name,
        )
        self._container = database.get_container_client(
            settings.cosmos_container_name,
        )

    async def close(self) -> None:
        await self._client.close()
        await self._credential.close()

    async def list_conversations(self, user_id: str) -> list[dict[str, Any]]:
        items = [
            item
            async for item in self._container.query_items(
                query=(
                    "SELECT * FROM c "
                    "WHERE c.userId = @userId "
                    "AND c.documentType = 'conversation'"
                ),
                parameters=[
                    {"name": "@userId", "value": user_id},
                ],
                partition_key=user_id,
            )
        ]
        items.sort(key=lambda item: item["updatedAt"], reverse=True)
        return [self._conversation_summary(item) for item in items]

    async def get_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict[str, Any]:
        conversation = await self._read_conversation(
            user_id,
            conversation_id,
        )
        messages = [
            item
            async for item in self._container.query_items(
                query=(
                    "SELECT * FROM c "
                    "WHERE c.userId = @userId "
                    "AND c.documentType = 'message' "
                    "AND c.conversationId = @conversationId"
                ),
                parameters=[
                    {"name": "@userId", "value": user_id},
                    {
                        "name": "@conversationId",
                        "value": conversation_id,
                    },
                ],
                partition_key=user_id,
            )
        ]
        messages.sort(key=lambda item: item["createdAt"])
        result = self._conversation_summary(conversation)
        result["messages"] = [self._message_response(item) for item in messages]
        return result

    async def create_conversation(
        self,
        user_id: str,
        title: str,
    ) -> dict[str, Any]:
        now = utc_now()
        item = {
            "id": str(uuid4()),
            "documentType": "conversation",
            "userId": user_id,
            "title": title,
            "previousResponseId": None,
            "createdAt": now,
            "updatedAt": now,
        }
        created = await self._container.create_item(item)
        return self._conversation_summary(created)

    async def update_response_id(
        self,
        user_id: str,
        conversation_id: str,
        previous_response_id: str,
    ) -> dict[str, Any]:
        await self._read_conversation(user_id, conversation_id)
        updated = await self._container.patch_item(
            item=conversation_id,
            partition_key=user_id,
            patch_operations=[
                {
                    "op": "replace",
                    "path": "/previousResponseId",
                    "value": previous_response_id,
                },
                {
                    "op": "replace",
                    "path": "/updatedAt",
                    "value": utc_now(),
                },
            ],
        )
        return self._conversation_summary(updated)

    async def rename_conversation(
        self,
        user_id: str,
        conversation_id: str,
        title: str,
    ) -> dict[str, Any]:
        await self._read_conversation(user_id, conversation_id)
        updated = await self._container.patch_item(
            item=conversation_id,
            partition_key=user_id,
            patch_operations=[
                {
                    "op": "replace",
                    "path": "/title",
                    "value": title,
                },
                {
                    "op": "replace",
                    "path": "/updatedAt",
                    "value": utc_now(),
                },
            ],
        )
        return self._conversation_summary(updated)

    async def add_message(
        self,
        user_id: str,
        conversation_id: str,
        role: str,
        content: str,
    ) -> dict[str, Any]:
        await self._read_conversation(user_id, conversation_id)
        now = utc_now()
        item = {
            "id": str(uuid4()),
            "documentType": "message",
            "userId": user_id,
            "conversationId": conversation_id,
            "role": role,
            "content": content,
            "createdAt": now,
        }
        created = await self._container.create_item(item)
        await self._container.patch_item(
            item=conversation_id,
            partition_key=user_id,
            patch_operations=[
                {
                    "op": "replace",
                    "path": "/updatedAt",
                    "value": now,
                },
            ],
        )
        return self._message_response(created)

    async def delete_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> None:
        await self._read_conversation(user_id, conversation_id)
        message_ids = [
            item["id"]
            async for item in self._container.query_items(
                query=(
                    "SELECT c.id FROM c "
                    "WHERE c.userId = @userId "
                    "AND c.documentType = 'message' "
                    "AND c.conversationId = @conversationId"
                ),
                parameters=[
                    {"name": "@userId", "value": user_id},
                    {
                        "name": "@conversationId",
                        "value": conversation_id,
                    },
                ],
                partition_key=user_id,
            )
        ]
        for message_id in message_ids:
            await self._container.delete_item(
                item=message_id,
                partition_key=user_id,
            )
        await self._container.delete_item(
            item=conversation_id,
            partition_key=user_id,
        )

    async def clear_history(self, user_id: str) -> int:
        item_ids = [
            item["id"]
            async for item in self._container.query_items(
                query="SELECT c.id FROM c WHERE c.userId = @userId",
                parameters=[
                    {"name": "@userId", "value": user_id},
                ],
                partition_key=user_id,
            )
        ]
        for item_id in item_ids:
            await self._container.delete_item(
                item=item_id,
                partition_key=user_id,
            )
        return len(item_ids)

    async def _read_conversation(
        self,
        user_id: str,
        conversation_id: str,
    ) -> dict[str, Any]:
        try:
            item = await self._container.read_item(
                item=conversation_id,
                partition_key=user_id,
            )
        except CosmosResourceNotFoundError as error:
            raise ConversationNotFoundError(conversation_id) from error
        if item.get("documentType") != "conversation":
            raise ConversationNotFoundError(conversation_id)
        return item

    @staticmethod
    def _conversation_summary(item: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": item["id"],
            "title": item["title"],
            "previousResponseId": item.get("previousResponseId"),
            "createdAt": item["createdAt"],
            "updatedAt": item["updatedAt"],
        }

    @staticmethod
    def _message_response(item: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": item["id"],
            "role": item["role"],
            "content": item["content"],
            "createdAt": item["createdAt"],
        }


__all__ = [
    "ChatHistoryStore",
    "ConversationNotFoundError",
    "CosmosChatHistoryStore",
    "CosmosHttpResponseError",
    "MemoryChatHistoryStore",
]
