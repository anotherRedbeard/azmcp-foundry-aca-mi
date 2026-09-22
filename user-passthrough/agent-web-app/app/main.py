import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, AsyncIterator

import httpx
import uvicorn
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from .auth import TokenValidator
from .config import Settings
from .response_request import AgentRequest

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PUBLIC_DIRECTORY = Path(__file__).resolve().parent.parent / "public"


def create_app(settings: Settings | None = None) -> FastAPI:
    app_settings = settings or Settings()
    token_validator = TokenValidator(app_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        async with httpx.AsyncClient(timeout=120.0) as client:
            app.state.http_client = client
            yield

    app = FastAPI(
        title="Foundry Agent Web App",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )

    async def authorize(
        authorization: Annotated[str | None, Header()] = None,
    ) -> str:
        return await token_validator.validate(authorization)

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

    @app.post("/api/responses")
    async def proxy_response(
        request: AgentRequest,
        raw_request: Request,
        authorization: Annotated[str, Depends(authorize)],
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
                    "Authorization": authorization,
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": (
                        app_settings.apim_subscription_key
                    ),
                },
                json=request_body,
            )
        except httpx.RequestError as error:
            logger.error("APIM request failed: %s", type(error).__name__)
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
