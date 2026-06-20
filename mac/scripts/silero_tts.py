#!/usr/bin/env python3
"""
Silero TTS sidecar for Alakeya.
Generates Russian speech via Silero v4 model and writes a WAV file.

Usage:
    python3 silero_tts.py --text "Привет мир" --speaker xenia --output /tmp/out.wav

NOTE: For personal/dev use. Before commercial distribution, verify Silero license.
"""

import argparse
import sys
import os
import re


def parse_args():
    p = argparse.ArgumentParser(description="Silero Russian TTS")
    p.add_argument("--text",        required=True,  help="Text to synthesise")
    p.add_argument("--speaker",     default="xenia", help="Speaker name (xenia/aidar/baya/kseniya/eugene)")
    p.add_argument("--output",      required=True,  help="Output WAV path")
    p.add_argument("--sample-rate", type=int, default=48000, help="Sample rate (8000/24000/48000)")
    p.add_argument("--device",      default="cpu",  help="Torch device (cpu/cuda/mps)")
    return p.parse_args()


def normalize_text(text: str) -> str:
    """Minimal normalization before sending to Silero."""
    # Replace URLs
    text = re.sub(r"https?://\S+", "ссылка", text)
    # Replace currency symbols
    text = text.replace("₽", " рублей").replace("$", " долларов").replace("€", " евро")
    # Strip markdown
    text = re.sub(r"\*\*([^*\n]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*\n]+)\*", r"\1", text)
    text = re.sub(r"^#+\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"^[-*•]\s+", "", text, flags=re.MULTILINE)
    # Strip raw JSON/DOM markers
    bad = ["CURRENT_PAGE:", "ACTION_RESULT:", '"elements":', '"scrollY":']
    for marker in bad:
        if marker in text:
            return "Готово."
    # Truncate
    return text.strip()[:700]


def main():
    args = parse_args()

    text = normalize_text(args.text)
    if not text:
        print("Empty text after normalization, skipping.", file=sys.stderr)
        sys.exit(0)

    valid_sample_rates = [8000, 24000, 48000]
    sample_rate = args.sample_rate if args.sample_rate in valid_sample_rates else 48000

    try:
        import torch
    except ImportError:
        print("ERROR: torch not found. Run scripts/setup_silero_tts.sh first.", file=sys.stderr)
        sys.exit(1)

    try:
        import soundfile as sf
    except ImportError:
        print("ERROR: soundfile not found. Run scripts/setup_silero_tts.sh first.", file=sys.stderr)
        sys.exit(1)

    device = torch.device(args.device)
    print(f"[Silero] Loading model (device={args.device}) ...", file=sys.stderr)

    # Suppress torch.hub verbose output
    import warnings
    warnings.filterwarnings("ignore")

    try:
        model, _ = torch.hub.load(
            repo_or_dir="snakers4/silero-models",
            model="silero_tts",
            language="ru",
            speaker="v4_ru",
            verbose=False,
        )
        model.to(device)
    except Exception as e:
        print(f"ERROR: Failed to load Silero model: {e}", file=sys.stderr)
        sys.exit(2)

    valid_speakers = model.speakers if hasattr(model, "speakers") else \
        ["aidar", "baya", "kseniya", "xenia", "eugene"]
    speaker = args.speaker if args.speaker in valid_speakers else "xenia"

    print(f"[Silero] Synthesising: speaker={speaker} rate={sample_rate} chars={len(text)}", file=sys.stderr)

    try:
        audio = model.apply_tts(text=text, speaker=speaker, sample_rate=sample_rate)
    except Exception as e:
        print(f"ERROR: Silero synthesis failed: {e}", file=sys.stderr)
        sys.exit(3)

    try:
        sf.write(args.output, audio.numpy(), sample_rate)
        print(f"[Silero] Saved: {args.output}", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: Failed to write WAV: {e}", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()
