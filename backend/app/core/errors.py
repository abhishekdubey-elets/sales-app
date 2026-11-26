from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppError(Exception):
    def __init__(self, status_code: int, code: str, detail: str, **extra: Any):
        super().__init__(detail)
        self.status_code = status_code
        self.code = code
        self.detail = detail
        self.extra = extra


def not_found(what: str = "Resource") -> AppError:
    return AppError(404, "not_found", f"{what} not found")


def forbidden(detail: str = "You do not have permission to perform this action") -> AppError:
    return AppError(403, "forbidden", detail)


def bad_request(detail: str, code: str = "bad_request", **extra: Any) -> AppError:
    return AppError(400, code, detail, **extra)


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        body = {"detail": exc.detail, "code": exc.code}
        body.update({k: (str(v) if not isinstance(v, (int, float, bool, list, dict, type(None))) else v)
                     for k, v in exc.extra.items()})
        return JSONResponse(status_code=exc.status_code, content=body)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {"loc": [str(p) for p in e.get("loc", [])], "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        first = errors[0]["msg"] if errors else "Invalid request"
        return JSONResponse(
            status_code=422,
            content={"detail": first, "code": "validation_error", "errors": errors},
        )
