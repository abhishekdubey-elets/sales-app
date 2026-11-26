"""Operational helpers.

    python -m app.cli gen-secrets              # print fresh values for the secret env vars
    python -m app.cli webhook-urls [provider]  # static URLs to paste into the provider console
    python -m app.cli create-admin EMAIL "Full Name"   # prompts for a password
"""

import asyncio
import getpass
import secrets
import sys

import sqlalchemy as sa
from cryptography.fernet import Fernet

from app.core.config import settings


def gen_secrets() -> None:
    print(f"JWT_SECRET={secrets.token_urlsafe(48)}")
    print(f"BLIND_INDEX_KEY={secrets.token_urlsafe(48)}")
    print(f"WEBHOOK_SIGNING_SECRET={secrets.token_urlsafe(48)}")
    print(f"FIELD_ENCRYPTION_KEY={Fernet.generate_key().decode()}")
    print("# Keep FIELD_ENCRYPTION_KEY and BLIND_INDEX_KEY stable: changing them makes stored PII unreadable.")


def webhook_urls(provider: str | None) -> None:
    from app.api.v1.webhooks import provider_webhook_urls

    name = provider or settings.TELEPHONY_PROVIDER
    if not name:
        sys.exit("Pass a provider name or set TELEPHONY_PROVIDER")
    for label, url in provider_webhook_urls(name).items():
        print(f"{label:32} {url}")


async def create_admin(email: str, name: str) -> None:
    from app.core.database import SessionLocal
    from app.core.security import hash_password
    from app.models import RoleModel, User

    password = getpass.getpass("Password (min 8 chars): ")
    if len(password) < 8:
        sys.exit("Password too short")
    async with SessionLocal() as db:
        role = (await db.execute(sa.select(RoleModel).where(RoleModel.name == "admin"))).scalar_one_or_none()
        if role is None:
            sys.exit("Run `python -m app.seed` first to create roles")
        db.add(User(full_name=name, email=email.lower(), password_hash=hash_password(password), role_id=role.id))
        await db.commit()
    print(f"Created admin {email}")


if __name__ == "__main__":
    cmd, *rest = sys.argv[1:] or ["help"]
    if cmd == "gen-secrets":
        gen_secrets()
    elif cmd == "webhook-urls":
        webhook_urls(rest[0] if rest else None)
    elif cmd == "create-admin" and len(rest) == 2:
        asyncio.run(create_admin(rest[0], rest[1]))
    else:
        print(__doc__)
