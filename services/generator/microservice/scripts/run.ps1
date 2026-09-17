# Lance le microservice. Il n'écoute que sur 127.0.0.1 : seul le tunnel y accède.
$ErrorActionPreference = "Stop"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 5000
