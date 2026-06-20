#!/usr/bin/env bash
# Silero Local TTS setup for Alakeya (dev-only, personal use).
# Creates an isolated .venv/silero virtualenv with CPU PyTorch and soundfile.
# NOTE: Before commercial distribution verify Silero model license.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV="$PROJECT_ROOT/.venv/silero"

echo "=== Silero TTS setup ==="
echo "Project root: $PROJECT_ROOT"
echo "Virtualenv  : $VENV"
echo ""

# ── Find Python 3.9+ ─────────────────────────────────────
find_python() {
    for cmd in python3.12 python3.11 python3.10 python3.9 python3; do
        if command -v "$cmd" &>/dev/null; then
            local ver
            ver=$("$cmd" -c "import sys; print(sys.version_info >= (3,9))" 2>/dev/null)
            if [ "$ver" = "True" ]; then
                echo "$cmd"
                return 0
            fi
        fi
    done
    return 1
}

PYTHON=$(find_python || true)
if [ -z "$PYTHON" ]; then
    echo "ERROR: Python 3.9+ not found. Install via 'brew install python@3.11' or similar."
    exit 1
fi
echo "Python: $PYTHON ($($PYTHON --version 2>&1))"

# ── Create virtualenv ─────────────────────────────────────
if [ ! -d "$VENV" ]; then
    echo ""
    echo "Creating virtualenv at $VENV ..."
    "$PYTHON" -m venv "$VENV"
fi

PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

echo ""
echo "Upgrading pip ..."
"$PIP" install --upgrade pip --quiet

# ── Install CPU PyTorch ───────────────────────────────────
echo ""
echo "Installing torch (CPU) — this may take a few minutes on first run ..."
"$PIP" install torch --index-url https://download.pytorch.org/whl/cpu --quiet

# ── Install dependencies ──────────────────────────────────
echo "Installing soundfile, omegaconf, numpy<2 ..."
"$PIP" install soundfile omegaconf "numpy<2" --quiet

# ── Warm up / download Silero model ──────────────────────
echo ""
echo "Downloading Silero v4 Russian model (cached at ~/.cache/torch/hub after first run) ..."
WARMUP_WAV="$PROJECT_ROOT/.venv/silero_warmup_test.wav"
"$PY" "$SCRIPT_DIR/silero_tts.py" \
    --text "Привет, я Алакея." \
    --speaker xenia \
    --output "$WARMUP_WAV" \
    --sample-rate 24000 \
    --device cpu 2>&1 | grep -v "^$" || {
    echo ""
    echo "WARNING: Model warmup failed. Check error output above."
    echo "You can retry with: $PY $SCRIPT_DIR/silero_tts.py --text 'test' --speaker xenia --output /tmp/test.wav"
    exit 1
}

if [ -f "$WARMUP_WAV" ]; then
    echo ""
    echo "Model downloaded successfully."
    SIZE=$(wc -c < "$WARMUP_WAV" | tr -d ' ')
    echo "Test WAV: $WARMUP_WAV ($SIZE bytes)"
    rm -f "$WARMUP_WAV"
else
    echo ""
    echo "WARNING: Warmup WAV not found. Model may not have downloaded."
fi

echo ""
echo "=== Done ==="
echo "Silero Local TTS is ready. In Alakeya:"
echo "  Settings → Voice → Voice Provider → Silero Local TTS"
echo ""
echo "Python path used by Alakeya: $VENV/bin/python3"
