"""G.711 µ-law ⇄ 16-bit PCM conversion (pure Python; no audioop, which is gone in Python 3.13)."""

import array
import sys

_BIAS = 0x84
_CLIP = 32635


def _ulaw_to_linear(u: int) -> int:
    u = ~u & 0xFF
    sign = u & 0x80
    exponent = (u >> 4) & 0x07
    mantissa = u & 0x0F
    sample = ((mantissa << 3) + _BIAS) << exponent
    sample -= _BIAS
    return -sample if sign else sample


_DECODE = array.array("h", (_ulaw_to_linear(i) for i in range(256)))


def _linear_to_ulaw(sample: int) -> int:
    sign = 0x80 if sample < 0 else 0
    if sample < 0:
        sample = -sample
    sample = min(sample, _CLIP) + _BIAS
    exponent = 7
    mask = 0x4000
    while exponent > 0 and not (sample & mask):
        exponent -= 1
        mask >>= 1
    mantissa = (sample >> (exponent + 3)) & 0x0F
    return ~(sign | (exponent << 4) | mantissa) & 0xFF


_ENCODE = bytes(_linear_to_ulaw(s - 32768) for s in range(65536))


def ulaw_to_pcm16(data: bytes) -> bytes:
    out = array.array("h", (_DECODE[b] for b in data))
    if sys.byteorder == "big":
        out.byteswap()
    return out.tobytes()


def pcm16_to_ulaw(data: bytes) -> bytes:
    samples = array.array("h")
    samples.frombytes(data[: len(data) - (len(data) % 2)])
    if sys.byteorder == "big":
        samples.byteswap()
    return bytes(_ENCODE[s + 32768] for s in samples)


def convert(data: bytes, src: str, dst: str) -> bytes:
    if src == dst:
        return data
    if src == "mulaw" and dst == "linear16":
        return ulaw_to_pcm16(data)
    if src == "linear16" and dst == "mulaw":
        return pcm16_to_ulaw(data)
    raise ValueError(f"unsupported conversion {src} → {dst}")
