import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, AsyncIterator

import httpx
import uvicorn
from azure.cosmos.exceptions import CosmosHttpResponseError
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from .auth import AuthenticatedPrincipal, TokenValidator
from .chat_history import (
    ChatHistoryStore,
    ConversationNotFoundError,
    CosmosChatHistoryStore,
    MemoryChatHistoryStore,
)
from .chat_models import (
    CreateConversationRequest,
    CreateMessageRequest,
    UpdateConversationRequest,
)
from .config import Settings
from .response_request import AgentRequest

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PUBLIC_DIRECTORY = Path(__file__).resolve().parent.parent / "public"


def create_app(
    settings: Settings | None = None,
    history_store: ChatHistoryStore | None = None,
    token_validator: TokenValidator | None = None,
) -> FastAPI:
    app_settings = settings or Settings()
    validator = token_validator or TokenValidator(app_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        transport = httpx.AsyncHTTPTransport(retries=1)
        async with httpx.AsyncClient(
            timeout=120.0,
            transport=transport,
        ) as client:
            app.state.http_client = client
            app.state.history_store = (
                history_store
                if history_store is not None
                else (
                    CosmosChatHistoryStore(app_settings)
                    if app_settings.chat_history_backend == "cosmos"
                    else MemoryChatHistoryStore()
                )
            )
            try:
                yield
            finally:
                if (
                    history_store is None
                    and app_settings.chat_history_backend == "cosmos"
                ):
                    await app.state.history_store.close()

    app = FastAPI(
        title="Foundry Agent Web App",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )

    async def authorize(
        authorization: Annotated[str | None, Header()] = None,
    ) -> AuthenticatedPrincipal:
        return await validator.validate(authorization)

    @app.middleware("http")
    async def add_security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline'; "
            "connect-src 'self' https://login.microsoftonline.com; "
            "frame-src https://login.microsoftonline.com; "
            "img-src 'self' data:; "
            "style-src 'self' 'unsafe-inline'; "
            "object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
        )
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "SAMEORIGIN"
        return response

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        _request: Request,
        _error: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "The request body is invalid."},
        )

    @app.exception_handler(HTTPException)
    async def handle_http_error(
        _request: Request,
        error: HTTPException,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=error.status_code,
            content={"error": error.detail},
            headers=error.headers,
        )

    @app.exception_handler(ConversationNotFoundError)
    async def handle_conversation_not_found(
        _request: Request,
        _error: ConversationNotFoundError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"error": "The conversation was not found."},
        )

    @app.exception_handler(CosmosHttpResponseError)
    async def handle_cosmos_error(
        _request: Request,
        error: CosmosHttpResponseError,
    ) -> JSONResponse:
        logger.error(
            "Cosmos DB request failed with status %s",
            error.status_code,
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"error": "Chat history storage is unavailable."},
        )

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/api/config")
    async def public_config() -> dict[str, str]:
        return {
            "tenantId": app_settings.entra_tenant_id,
            "spaClientId": app_settings.entra_spa_client_id,
            "apiScope": app_settings.foundry_api_scope,
        }

    @app.get("/api/conversations")
    async def list_conversations(
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> list[dict]:
        return await raw_request.app.state.history_store.list_conversations(
            principal.object_id,
        )

    @app.post("/api/conversations", status_code=status.HTTP_201_CREATED)
    async def create_conversation(
        conversation: CreateConversationRequest,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> dict:
        return await raw_request.app.state.history_store.create_conversation(
            principal.object_id,
            conversation.title,
        )

    @app.delete("/api/conversations")
    async def clear_history(
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> dict[str, int]:
        deleted = await raw_request.app.state.history_store.clear_history(
            principal.object_id,
        )
        return {"deleted": deleted}

    @app.get("/api/conversations/{conversation_id}")
    async def get_conversation(
        conversation_id: str,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> dict:
        return await raw_request.app.state.history_store.get_conversation(
            principal.object_id,
            conversation_id,
        )

    @app.patch("/api/conversations/{conversation_id}")
    async def update_conversation(
        conversation_id: str,
        update: UpdateConversationRequest,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> dict:
        return await raw_request.app.state.history_store.update_response_id(
            principal.object_id,
            conversation_id,
            update.previous_response_id,
        )

    @app.post(
        "/api/conversations/{conversation_id}/messages",
        status_code=status.HTTP_201_CREATED,
    )
    async def create_message(
        conversation_id: str,
        message: CreateMessageRequest,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> dict:
        return await raw_request.app.state.history_store.add_message(
            principal.object_id,
            conversation_id,
            message.role,
            message.content,
        )

    @app.delete(
        "/api/conversations/{conversation_id}",
        status_code=status.HTTP_204_NO_CONTENT,
    )
    async def delete_conversation(
        conversation_id: str,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> Response:
        await raw_request.app.state.history_store.delete_conversation(
            principal.object_id,
            conversation_id,
        )
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.post("/api/responses")
    async def proxy_response(
        request: AgentRequest,
        raw_request: Request,
        principal: Annotated[AuthenticatedPrincipal, Depends(authorize)],
    ) -> Response:
        request_body = {
            "input": (
                request.input
                if isinstance(request.input, str)
                else [item.model_dump() for item in request.input]
            )
        }
        if request.previous_response_id:
            request_body["previous_response_id"] = request.previous_response_id

        try:
            upstream = await raw_request.app.state.http_client.post(
                app_settings.apim_responses_url,
                headers={
                    "Authorization": principal.authorization,
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": (
                        app_settings.apim_subscription_key
                    ),
                },
                json=request_body,
            )
        except httpx.RequestError as error:
            logger.exception("APIM request failed")
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="The upstream APIM request could not be completed.",
            ) from error

        headers = {}
        content_type = upstream.headers.get("content-type")
        if content_type:
            headers["content-type"] = content_type

        return Response(
            content=upstream.content,
            status_code=upstream.status_code,
            headers=headers,
        )

    app.mount("/", StaticFiles(directory=PUBLIC_DIRECTORY, html=True), name="static")
    return app


app = create_app()


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=Settings().port,
        reload=False,
    )
