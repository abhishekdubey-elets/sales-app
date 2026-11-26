from functools import lru_cache
from typing import Literal

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_SECRET_MARKER = "change-me-dev-only"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    APP_NAME: str = "Elets SalesCall AI"
    ENVIRONMENT: Literal["development", "staging", "production", "test"] = "development"
    API_PUBLIC_BASE_URL: str = "http://localhost:8000"
    DATABASE_URL: str = "postgresql+asyncpg://elets:elets@localhost:5432/elets_salescall"
    CORS_ORIGINS: list[str] = ["http://localhost:8080", "http://localhost:3000"]
    ORG_TIMEZONE: str = "Asia/Kolkata"
    RUN_WORKERS: bool = True
    WORKER_TICK_SECONDS: int = 10

    JWT_SECRET: str = "change-me-dev-only-jwt-secret"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_MINUTES: int = 15
    REFRESH_TOKEN_DAYS: int = 30
    FIELD_ENCRYPTION_KEY: str = ""
    BLIND_INDEX_KEY: str = "change-me-dev-only-blind-index-key"
    WEBHOOK_SIGNING_SECRET: str = "change-me-dev-only-webhook-secret"
    SIGNED_URL_TTL_SECONDS: int = 300
    DEFAULT_COUNTRY_CODE: str = "91"

    TELEPHONY_PROVIDER: Literal["", "exotel", "twilio", "plivo", "knowlarity"] = ""
    TELEPHONY_CALLER_ID: str = ""
    CALL_TIME_LIMIT_SECONDS: int = 3600
    CALL_LOCK_TTL_MINUTES: int = 90

    EXOTEL_API_KEY: str = ""
    EXOTEL_API_TOKEN: str = ""
    EXOTEL_ACCOUNT_SID: str = ""
    EXOTEL_SUBDOMAIN: str = "api.exotel.com"
    EXOTEL_AI_APP_ID: str = ""

    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""

    PLIVO_AUTH_ID: str = ""
    PLIVO_AUTH_TOKEN: str = ""

    KNOWLARITY_API_KEY: str = ""
    KNOWLARITY_AUTH_TOKEN: str = ""
    KNOWLARITY_K_NUMBER: str = ""
    KNOWLARITY_BASE_URL: str = "https://kpi.knowlarity.com/Basic/v1/account"

    LLM_PROVIDER: Literal["anthropic", ""] = "anthropic"
    ANTHROPIC_API_KEY: str = ""
    LLM_MODEL: str = "claude-opus-5-5"
    LLM_REALTIME_EFFORT: Literal["low", "medium", "high", "xhigh", "max"] = "low"
    LLM_ANALYSIS_EFFORT: Literal["low", "medium", "high", "xhigh", "max"] = "medium"

    STT_PROVIDER: Literal["deepgram", ""] = "deepgram"
    DEEPGRAM_API_KEY: str = ""
    DEEPGRAM_MODEL: str = "nova-2"

    TTS_PROVIDER: Literal["elevenlabs", ""] = "elevenlabs"
    ELEVENLABS_API_KEY: str = ""
    ELEVENLABS_MODEL: str = "eleven_flash_v2_5"
    ELEVENLABS_DEFAULT_VOICE_ID: str = ""

    FCM_PROJECT_ID: str = ""
    FCM_SERVICE_ACCOUNT_FILE: str = ""

    SEED_ADMIN_EMAIL: str = "admin@elets.local"
    SEED_DEFAULT_PASSWORD: str = "Elets@12345"

    MAX_IMPORT_ROWS: int = 10000
    MAX_UPLOAD_BYTES: int = 5 * 1024 * 1024

    @field_validator("API_PUBLIC_BASE_URL")
    @classmethod
    def _strip_slash(cls, v: str) -> str:
        return v.rstrip("/")

    @model_validator(mode="after")
    def _no_dev_secrets_in_prod(self) -> "Settings":
        if self.ENVIRONMENT in ("staging", "production"):
            for name in ("JWT_SECRET", "BLIND_INDEX_KEY", "WEBHOOK_SIGNING_SECRET"):
                if DEV_SECRET_MARKER in getattr(self, name):
                    raise ValueError(f"{name} must be set to a real secret in {self.ENVIRONMENT}")
            if not self.FIELD_ENCRYPTION_KEY:
                raise ValueError(f"FIELD_ENCRYPTION_KEY is required in {self.ENVIRONMENT}")
            if not self.API_PUBLIC_BASE_URL.startswith("https://"):
                raise ValueError("API_PUBLIC_BASE_URL must be https in staging/production")
        return self

    @property
    def public_ws_base_url(self) -> str:
        url = self.API_PUBLIC_BASE_URL
        if url.startswith("https://"):
            return "wss://" + url[len("https://"):]
        if url.startswith("http://"):
            return "ws://" + url[len("http://"):]
        return url


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
