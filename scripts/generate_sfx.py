#!/usr/bin/env python3
"""Génère les effets sonores du jeu dans assets/audio/ (WAV mono 16 bits, 22 050 Hz).

Synthèse procédurale, sans dépendance ni asset externe. Graine fixe : relancer le script
redonne exactement les mêmes fichiers.

    python3 scripts/generate_sfx.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def envelope(t: float, duration: float, attack: float = 0.004, decay: float = 8.0) -> float:
    """Attaque brève puis décroissance exponentielle, nulle à la fin."""
    if t < attack:
        return t / attack
    fade_out = max(0.0, 1.0 - t / duration)
    return math.exp(-decay * (t - attack) / duration) * fade_out


def render(duration: float, sample) -> list[float]:
    count = int(RATE * duration)
    return [sample(i / RATE) for i in range(count)]


def noise(rng: random.Random) -> float:
    return rng.uniform(-1.0, 1.0)


def screw_tick(rng: random.Random) -> list[float]:
    """Cran de vis : clic métallique très court."""
    d = 0.035
    return render(d, lambda t: envelope(t, d, 0.001, 10.0) * (0.6 * math.sin(2 * math.pi * 2900 * t) + 0.4 * noise(rng)))


def pop(rng: random.Random) -> list[float]:
    """Pièce retirée : déclic qui descend en fréquence."""
    d = 0.11

    def sample(t: float) -> float:
        freq = 700 - 450 * (t / d)
        return envelope(t, d, 0.002, 5.0) * (0.85 * math.sin(2 * math.pi * freq * t) + 0.15 * noise(rng))

    return render(d, sample)


def creak(rng: random.Random) -> list[float]:
    """Pièce retenue qu'on force : grincement grave et irrégulier."""
    d = 0.16

    def sample(t: float) -> float:
        wobble = 1.0 + 0.5 * math.sin(2 * math.pi * 23 * t)
        saw = 2.0 * ((95 * wobble * t) % 1.0) - 1.0
        return envelope(t, d, 0.01, 3.0) * (0.55 * saw + 0.25 * noise(rng))

    return render(d, sample)


def crack(rng: random.Random) -> list[float]:
    """Casse : craquement bruité sur un choc sourd."""
    d = 0.32

    def sample(t: float) -> float:
        burst = noise(rng) * math.exp(-18 * t)
        thump = math.sin(2 * math.pi * 70 * t) * math.exp(-10 * t)
        return envelope(t, d, 0.001, 2.0) * (0.75 * burst + 0.6 * thump)

    return render(d, sample)


def sizzle(rng: random.Random) -> list[float]:
    """Chauffe de l'adhésif : souffle bref."""
    d = 0.09
    state = [0.0]

    def sample(t: float) -> float:
        state[0] = 0.6 * state[0] + 0.4 * noise(rng)
        return envelope(t, d, 0.01, 3.0) * 0.5 * (noise(rng) - state[0])

    return render(d, sample)


def click(rng: random.Random) -> list[float]:
    """Pièce remontée ou remplacée : clic net."""
    d = 0.05
    return render(d, lambda t: envelope(t, d, 0.001, 7.0) * math.sin(2 * math.pi * 1500 * t))


def success(rng: random.Random) -> list[float]:
    """Test final réussi : arpège montant."""
    notes = [523.25, 659.25, 783.99]
    step = 0.11
    d = step * len(notes) + 0.25

    def sample(t: float) -> float:
        value = 0.0
        for i, freq in enumerate(notes):
            local = t - i * step
            if local >= 0:
                value += envelope(local, d - i * step, 0.004, 4.0) * math.sin(2 * math.pi * freq * local)
        return 0.45 * value

    return render(d, sample)


def failure(rng: random.Random) -> list[float]:
    """Test final raté : deux notes graves bourdonnantes."""
    d = 0.42

    def sample(t: float) -> float:
        freq = 196.0 if t < 0.19 else 155.56
        local = t if t < 0.19 else t - 0.19
        square = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
        return 0.3 * envelope(local, 0.21, 0.005, 3.0) * square

    return render(d, sample)


SOUNDS = {
    "screw_tick": screw_tick,
    "pop": pop,
    "creak": creak,
    "crack": crack,
    "sizzle": sizzle,
    "click": click,
    "success": success,
    "failure": failure,
}


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = 0.9 / peak
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(frames)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for index, (name, generator) in enumerate(SOUNDS.items()):
        rng = random.Random(1000 + index)
        path = OUT / f"{name}.wav"
        write_wav(path, generator(rng))
        print(f"{path.relative_to(OUT.parent.parent)}  {path.stat().st_size} octets")


if __name__ == "__main__":
    main()
