"""Prompt assembly for live AI calls and post-call analysis, plus the Elets agent templates."""

from app.models import AIAgent, Lead
from app.voice.languages import language
from app.voice.llm.base import ToolSpec

CALL_TOOLS: list[ToolSpec] = [
    ToolSpec(
        name="transfer_to_human",
        description="Use when the prospect asks to speak with a person, or a configured hand-off condition is met.",
        parameters={"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"],
                    "additionalProperties": False},
    ),
    ToolSpec(
        name="schedule_meeting",
        description="Record that the prospect agreed to a meeting or call-back with an Elets sales executive.",
        parameters={
            "type": "object",
            "properties": {
                "preferred_time": {"type": "string", "description": "The prospect's preferred time, in their words"},
                "preferred_datetime_iso": {
                    "type": ["string", "null"],
                    "description": "ISO-8601 local date-time if the prospect gave a concrete time, else null",
                },
                "notes": {"type": "string"},
            },
            "required": ["preferred_time", "preferred_datetime_iso", "notes"],
            "additionalProperties": False,
        },
    ),
    ToolSpec(
        name="record_opt_out",
        description="Use when the prospect asks not to be called again. Ends the call after a short confirmation.",
        parameters={"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"],
                    "additionalProperties": False},
    ),
    ToolSpec(
        name="end_call",
        description="End the call after you have said goodbye, or if the person is not the right contact "
                    "or the line is unusable.",
        parameters={"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"],
                    "additionalProperties": False},
    ),
]


def opening_line(agent: AIAgent, lead: Lead | None, ai_disclosure: str, recording_notice: str | None) -> str:
    """Fixed, non-LLM opening so the AI disclosure (and recording notice) is always said first."""
    parts = [ai_disclosure.strip()]
    if recording_notice:
        parts.append(recording_notice.strip())
    greeting = (agent.greeting or "").strip()
    if greeting:
        name = lead.full_name.split()[0] if lead and lead.full_name else ""
        parts.append(greeting.replace("{first_name}", name).replace("{company}", (lead.company_name or "") if lead else ""))
    return " ".join(p for p in parts if p)


def live_system_prompt(agent: AIAgent, lead: Lead | None, opening: str) -> str:
    lang = language(agent.language)
    who = "the prospect"
    if lead:
        who = lead.full_name
        if lead.designation:
            who += f", {lead.designation}"
        if lead.company_name:
            who += f" at {lead.company_name}"
    lang_rule = f"Speak only in {lang.name}."
    if agent.language == "hi-IN":
        lang_rule += " Use natural, conversational Hindi; common English business terms are fine."

    sections = [
        f"You are {agent.name}, an AI voice assistant on a live phone call on behalf of Elets Technomedia.",
        agent.personality or "",
        "## This call",
        f"- You are speaking with {who}.",
        f"- {lang_rule}",
        f'- You have already opened the call by saying: "{opening}" Continue naturally from there.',
    ]
    if agent.objectives:
        sections.append("## Objectives\n" + "\n".join(f"- {o}" for o in agent.objectives))
    if agent.knowledge_base:
        sections.append("## Knowledge base (the only facts you may state about Elets offerings)\n"
                        + agent.knowledge_base.strip())
    handoff = ["The prospect asks to speak with a person."] + list(agent.handoff_conditions or [])
    sections.append("## Hand off to a human salesperson (transfer_to_human) when\n"
                    + "\n".join(f"- {h}" for h in handoff))
    sections.append("## Instructions from the Elets team\n" + agent.system_prompt.strip())
    sections.append(
        "## How to talk on the phone\n"
        "- You are an AI assistant. If asked, say so plainly; never claim to be human.\n"
        "- This is spoken audio: reply in one to three short sentences, with no lists, markdown, emojis or URLs.\n"
        "- Ask one question at a time and give the prospect room to talk.\n"
        "- Only state prices, dates, packages or commitments that appear in the knowledge base. Otherwise offer to "
        "have the sales team confirm.\n"
        "- If they ask not to be called again, use record_opt_out. When the conversation is done, say a brief "
        "goodbye and use end_call.\n"
        "- Never ask for payment details, passwords or government ID numbers."
    )
    return "\n\n".join(s for s in sections if s)


ANALYSIS_SYSTEM_PROMPT = (
    "You analyse phone conversations between an Elets Technomedia AI calling assistant and a prospect, and "
    "produce structured notes for the human sales team. Base every field strictly on what was said in the "
    "transcript; use null where something was not discussed rather than guessing. The qualification score "
    "(0-100) reflects fit, interest, authority and timing as evidenced in the call."
)


def analysis_input(agent: AIAgent, lead: Lead | None, transcript_text: str, call_date: str) -> str:
    lead_line = "Unknown prospect"
    if lead:
        lead_line = ", ".join(x for x in [lead.full_name, lead.designation, lead.company_name, lead.industry] if x)
    objectives = "; ".join(agent.objectives or []) or "General outreach"
    return (
        f"Call date: {call_date}\nAgent: {agent.name}\nAgent objectives: {objectives}\nProspect: {lead_line}\n\n"
        f"Transcript:\n{transcript_text}"
    )


_KB_PLACEHOLDER = (
    "Elets Technomedia is a media, technology and events company that runs conferences, summits, awards and "
    "publications across sectors such as government, education, healthcare and BFSI.\n"
    "[Add your current event calendar here: event names, cities, dates, audience profile, sponsorship and "
    "speaking packages, media/advertising options and who to contact. The agent will only state facts listed here.]"
)

AGENT_TEMPLATES: list[dict] = [
    {
        "name": "Elets Outreach Agent",
        "description": "Introduces Elets Technomedia to prospective companies and identifies business opportunities.",
        "personality": "Warm, professional and concise. Curious about the prospect's business; never pushy.",
        "language": "en-IN",
        "voice_id": None,
        "speaking_speed": 1.0,
        "system_prompt": (
            "Introduce Elets Technomedia and its events, conferences and media opportunities. Learn what the "
            "prospect's organisation does, whether they participate in industry events or advertise, and who handles "
            "partnerships. If there is a fit, offer a meeting with an Elets sales executive."
        ),
        "knowledge_base": _KB_PLACEHOLDER,
        "objectives": [
            "Confirm you are speaking with the right person for partnerships or marketing",
            "Briefly explain Elets events, conferences and media opportunities",
            "Identify a potential business opportunity (sponsorship, speaking, advertising, participation)",
            "Offer a meeting with an Elets sales executive when there is interest",
        ],
        "greeting": "Am I speaking with {first_name}? I'm calling to briefly introduce Elets' events and media "
                    "platforms — do you have a minute?",
        "max_call_duration_seconds": 300,
        "retry_rules": {"max_attempts": 3, "retry_delay_minutes": 180, "retry_on": ["busy", "not_answered"]},
        "handoff_conditions": ["The prospect wants pricing or a proposal", "The prospect is ready to commit"],
        "recording_enabled": True,
    },
    {
        "name": "Elets Lead Qualification Agent",
        "description": "Calls existing leads, understands requirements, qualifies them and books meetings.",
        "personality": "Consultative and attentive. Asks crisp qualifying questions and listens.",
        "language": "en-IN",
        "voice_id": None,
        "speaking_speed": 1.0,
        "system_prompt": (
            "This lead has previously shown interest in Elets. Understand their requirements, timeline, budget range "
            "and decision-making process. Identify whether they are a qualified prospect and, if so, schedule a "
            "meeting with their Elets sales executive."
        ),
        "knowledge_base": _KB_PLACEHOLDER,
        "objectives": [
            "Understand the prospect's requirements and goals",
            "Ask about timeline, budget range and who makes the decision",
            "Gauge interest level honestly",
            "Schedule a meeting with a sales executive for qualified prospects",
        ],
        "greeting": "Am I speaking with {first_name}? I'm following up on your interest in Elets — is now a good "
                    "time for a quick chat?",
        "max_call_duration_seconds": 420,
        "retry_rules": {"max_attempts": 3, "retry_delay_minutes": 240, "retry_on": ["busy", "not_answered"]},
        "handoff_conditions": ["The prospect has detailed commercial questions", "The prospect is a senior decision "
                                                                                 "maker ready to proceed"],
        "recording_enabled": True,
    },
    {
        "name": "Elets Event Invitation Agent",
        "description": "Invites potential attendees to upcoming Elets conferences and checks participation interest.",
        "personality": "Friendly, upbeat and respectful of the person's time.",
        "language": "en-IN",
        "voice_id": None,
        "speaking_speed": 1.0,
        "system_prompt": (
            "Invite the person to the upcoming Elets conference described in the knowledge base. Share the key event "
            "details, check whether they would like to attend, and note any questions for the events team."
        ),
        "knowledge_base": _KB_PLACEHOLDER,
        "objectives": [
            "Introduce the upcoming Elets conference",
            "Share date, city and audience details from the knowledge base",
            "Check participation interest",
            "Note questions or registration help needed",
        ],
        "greeting": "Hi {first_name}, I'm calling with an invitation to an upcoming Elets conference — do you have a "
                    "moment?",
        "max_call_duration_seconds": 240,
        "retry_rules": {"max_attempts": 2, "retry_delay_minutes": 240, "retry_on": ["busy", "not_answered"]},
        "handoff_conditions": ["The person wants to sponsor or speak at the event"],
        "recording_enabled": True,
    },
]
