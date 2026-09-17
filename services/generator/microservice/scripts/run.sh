#!/usr/bin/env sh
# Équivalent macOS/Linux de run.ps1.
set -e
python3 -m uvicorn app.main:app --host 127.0.0.1 --port 5000
