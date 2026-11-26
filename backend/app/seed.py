"""Seed roles, settings, teams, users, sample leads and the Elets AI agent templates.

    python -m app.seed                   # idempotent base seed
    python -m app.seed --demo-activity   # also add 7 days of sample call history (provider = "demo-seed")

Sample lead numbers use the invalid +91 0… range so they can never ring a real phone.
Seeded users have no calling number; each salesperson sets theirs in Profile before dialing.
"""

import argparse
import asyncio
import random
from datetime import timedelta

import sqlalchemy as sa

from app.core.config import settings
from app.core.crypto import email_hash, phone_hash
from app.core.database import SessionLocal, utcnow
from app.core.permissions import DEFAULT_ROLE_PERMISSIONS, ROLE_DESCRIPTIONS, Role
from app.core.security import hash_password
from app.models import AIAgent, AICall, CallNote, CallTranscript, HumanCall, Lead, OrgSettings, RoleModel, Team, User
from app.models.enums import AnalysisStatus, CallDirection, CallOutcome, CallStatus, LeadStatus
from app.voice.prompts import AGENT_TEMPLATES

TEAMS = [("Corporate Sales", "Sales"), ("Events & Partnerships", "Events")]
USERS = [
    ("Aarav Mehta", "manager.sales@elets.local", Role.MANAGER, 0),
    ("Neha Kapoor", "manager.events@elets.local", Role.MANAGER, 1),
    ("Rohit Sharma", "rohit@elets.local", Role.EXECUTIVE, 0),
    ("Priya Nair", "priya@elets.local", Role.EXECUTIVE, 0),
    ("Karan Singh", "karan@elets.local", Role.EXECUTIVE, 1),
    ("Ananya Iyer", "ananya@elets.local", Role.EXECUTIVE, 1),
]
COMPANIES = [
    ("Sunrise International School", "Education", "Principal", "Pune"),
    ("Metro Health Hospitals", "Healthcare", "CIO", "Hyderabad"),
    ("Bharat Smart City Mission Office", "Government", "Director (IT)", "Bhopal"),
    ("Pinnacle Finance Ltd", "BFSI", "Head of Marketing", "Mumbai"),
    ("Greenfield University", "Education", "Registrar", "Chandigarh"),
    ("CloudNova Technologies", "Technology", "VP Partnerships", "Bengaluru"),
    ("Apex Diagnostics", "Healthcare", "Marketing Manager", "Chennai"),
    ("State e-Governance Society", "Government", "Joint Secretary", "Jaipur"),
    ("Lotus Public School", "Education", "Director", "Lucknow"),
    ("Vertex Insurance", "BFSI", "Brand Head", "Gurugram"),
    ("Orbit EdTech", "Education", "Founder", "Noida"),
    ("CarePlus Clinics", "Healthcare", "COO", "Kochi"),
]
FIRST = ["Asha", "Vikram", "Meera", "Sanjay", "Pooja", "Arjun", "Kavita", "Rahul", "Divya", "Manish", "Sneha", "Amit"]
LAST = ["Verma", "Rao", "Gupta", "Joshi", "Menon", "Reddy", "Bose", "Patel", "Das", "Khanna", "Pillai", "Saxena"]


async def seed_base() -> None:
    async with SessionLocal() as db:
        roles: dict[str, RoleModel] = {}
        for role, perms in DEFAULT_ROLE_PERMISSIONS.items():
            r = (await db.execute(sa.select(RoleModel).where(RoleModel.name == role.value))).scalar_one_or_none()
            if r is None:
                r = RoleModel(name=role.value, description=ROLE_DESCRIPTIONS[role], permissions=sorted(p.value for p in perms))
                db.add(r)
            else:
                r.permissions = sorted(p.value for p in perms)
            roles[role.value] = r
        if await db.get(OrgSettings, 1) is None:
            db.add(OrgSettings(id=1, timezone=settings.ORG_TIMEZONE))
        await db.flush()

        if (await db.execute(sa.select(User.id).where(User.email == settings.SEED_ADMIN_EMAIL))).scalar():
            await db.commit()
            print("Base data already present — roles refreshed.")
            return

        pw = hash_password(settings.SEED_DEFAULT_PASSWORD)
        teams = []
        for name, dept in TEAMS:
            t = Team(name=name, department=dept)
            db.add(t)
            teams.append(t)
        await db.flush()
        db.add(User(full_name="Elets Admin", email=settings.SEED_ADMIN_EMAIL, password_hash=pw,
                    role_id=roles["admin"].id))
        people: list[User] = []
        for full_name, email, role, team_idx in USERS:
            u = User(full_name=full_name, email=email, password_hash=pw, role_id=roles[role.value].id,
                     team_id=teams[team_idx].id)
            db.add(u)
            people.append(u)
        await db.flush()
        teams[0].manager_id, teams[1].manager_id = people[0].id, people[1].id
        executives = [u for u, spec in zip(people, USERS, strict=True) if spec[2] == Role.EXECUTIVE]

        for i in range(30):
            company, industry, designation, city = COMPANIES[i % len(COMPANIES)]
            name = f"{FIRST[i % len(FIRST)]} {LAST[(i * 7) % len(LAST)]}"
            phone = f"+9100000{i:05d}"
            email = f"{name.split()[0].lower()}.{i}@example.com"
            owner = executives[i % len(executives)] if i % 5 else None
            db.add(Lead(
                full_name=name, company_name=company if i < len(COMPANIES) else f"{company} ({i})", phone=phone,
                phone_hash=phone_hash(phone), email=email, email_hash=email_hash(email), designation=designation,
                industry=industry, location=city, source=random.choice(["Website", "Event", "Referral", "LinkedIn"]),
                priority=["high", "medium", "low"][i % 3], assigned_to_id=owner.id if owner else None,
                status=LeadStatus.ASSIGNED if owner else LeadStatus.NEW,
                remarks="Sample lead — replace with real data", created_by_id=None,
            ))
        for tpl in AGENT_TEMPLATES:
            db.add(AIAgent(**tpl))
        await db.commit()
        print(f"Seeded admin ({settings.SEED_ADMIN_EMAIL}), {len(USERS)} users, 30 sample leads, "
              f"{len(AGENT_TEMPLATES)} AI agents. Default password is SEED_DEFAULT_PASSWORD from .env.")


async def seed_demo_activity() -> None:
    """Historical sample calls so dashboards have something to show. Clearly tagged provider='demo-seed'."""
    async with SessionLocal() as db:
        if (await db.execute(sa.select(HumanCall.id).where(HumanCall.provider == "demo-seed").limit(1))).scalar():
            print("Demo activity already present.")
            return
        leads = (await db.execute(sa.select(Lead).where(Lead.assigned_to_id.is_not(None)))).scalars().unique().all()
        agent = (await db.execute(sa.select(AIAgent).limit(1))).scalars().first()
        rnd = random.Random(42)
        now = utcnow()
        for day in range(7):
            for lead in leads:
                if rnd.random() < 0.45:
                    continue
                started = now - timedelta(days=day, hours=rnd.randint(0, 6), minutes=rnd.randint(0, 59))
                status = rnd.choices([CallStatus.COMPLETED, CallStatus.NOT_ANSWERED, CallStatus.BUSY,
                                      CallStatus.FAILED], [60, 25, 10, 5])[0]
                talk = rnd.randint(40, 900) if status == CallStatus.COMPLETED else 0
                outcome = rnd.choice(list(CallOutcome)) if status == CallStatus.COMPLETED else None
                sp = lead.assigned_to
                call = HumanCall(
                    direction=CallDirection.OUTBOUND, lead_id=lead.id, lead_name=lead.full_name,
                    phone_number=lead.phone, phone_hash=lead.phone_hash, salesperson_id=sp.id,
                    salesperson_name=sp.full_name, team_id=sp.team_id, provider="demo-seed",
                    provider_call_id=f"demo-{rnd.getrandbits(48):x}", status=status, started_at=started,
                    answered_at=started + timedelta(seconds=12) if talk else None,
                    ended_at=started + timedelta(seconds=talk + 20), duration_seconds=talk + 20, talk_seconds=talk,
                    outcome=outcome.value if outcome else None,
                )
                db.add(call)
                if outcome:
                    await db.flush()
                    db.add(CallNote(human_call_id=call.id, author_id=sp.id, author_name=sp.full_name,
                                    body="Sample note (demo data)."))
        if agent:
            for lead in leads[:6]:
                started = now - timedelta(days=rnd.randint(0, 6), hours=rnd.randint(0, 5))
                interest = rnd.choice(["high", "medium", "low"])
                ai = AICall(
                    agent_id=agent.id, lead_id=lead.id, lead_name=lead.full_name, phone_number=lead.phone,
                    phone_hash=lead.phone_hash, provider="demo-seed", provider_call_id=f"demo-ai-{rnd.getrandbits(40):x}",
                    status=CallStatus.COMPLETED, started_at=started, answered_at=started + timedelta(seconds=8),
                    ended_at=started + timedelta(seconds=150), duration_seconds=150, interest_level=interest,
                    qualification_score={"high": 82, "medium": 61, "low": 28}[interest],
                    summary="Sample data: demo AI call used to preview the AI call screens.",
                    analysis_status=AnalysisStatus.DONE,
                    intelligence={
                        "summary": "Sample data: demo AI call used to preview the AI call screens.",
                        "customer_requirements": ["(sample) wants event sponsorship options"],
                        "interest_level": interest, "budget_information": None, "decision_maker_information": None,
                        "next_action": "(sample) share the event brochure", "followup_recommendation": None,
                        "followup_date": None, "qualification_score": {"high": 82, "medium": 61, "low": 28}[interest],
                        "sentiment": "neutral", "lead_status_suggestion": "contacted",
                    },
                )
                db.add(ai)
                await db.flush()
                db.add(CallTranscript(ai_call_id=ai.id, language="en-IN", full_text="(sample transcript)", segments=[
                    {"speaker": "agent", "text": "Hello, this is an AI assistant calling on behalf of Elets "
                                                 "Technomedia. (sample)", "offset_ms": 0},
                    {"speaker": "customer", "text": "(sample reply)", "offset_ms": 6000},
                ]))
        await db.commit()
        print("Added 7 days of demo call history (provider = demo-seed).")


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--demo-activity", action="store_true")
    args = parser.parse_args()
    await seed_base()
    if args.demo_activity:
        await seed_demo_activity()


if __name__ == "__main__":
    asyncio.run(main())
