"""Language registry. Add a language here (and to schemas.ai.Language) to support it end to end."""

from dataclasses import dataclass


@dataclass(frozen=True)
class LanguageSpec:
    code: str          # our code, e.g. "hi-IN"
    name: str
    stt_code: str      # Deepgram language parameter
    tts_code: str      # ElevenLabs language_code (ISO 639-1)
    closing_line: str
    handoff_line: str
    opt_out_line: str
    timeout_line: str
    still_there_line: str
    error_line: str


LANGUAGES: dict[str, LanguageSpec] = {
    "en-IN": LanguageSpec(
        code="en-IN", name="English (India)", stt_code="en-IN", tts_code="en",
        closing_line="Thank you for your time. Have a great day!",
        handoff_line="Sure, I'll have one of our team members get in touch with you shortly. Thank you!",
        opt_out_line="Understood. We won't call you again. Have a good day.",
        timeout_line="I'm sorry, we're out of time for this call. Our team will follow up with you. Thank you!",
        still_there_line="Are you still there?",
        error_line="I'm sorry, I'm having a technical problem. Someone from our team will call you back. Thank you.",
    ),
    "hi-IN": LanguageSpec(
        code="hi-IN", name="Hindi", stt_code="hi", tts_code="hi",
        closing_line="आपके समय के लिए धन्यवाद। आपका दिन शुभ हो!",
        handoff_line="ज़रूर, हमारी टीम का एक सदस्य जल्द ही आपसे संपर्क करेगा। धन्यवाद!",
        opt_out_line="समझ गया। हम आपको दोबारा कॉल नहीं करेंगे। धन्यवाद।",
        timeout_line="माफ़ कीजिए, इस कॉल का समय समाप्त हो गया है। हमारी टीम आपसे संपर्क करेगी। धन्यवाद!",
        still_there_line="क्या आप लाइन पर हैं?",
        error_line="माफ़ कीजिए, तकनीकी समस्या आ रही है। हमारी टीम आपको वापस कॉल करेगी। धन्यवाद।",
    ),
}


def language(code: str) -> LanguageSpec:
    return LANGUAGES.get(code, LANGUAGES["en-IN"])
