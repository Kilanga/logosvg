# Installation du microservice sous Windows (PowerShell).
# A lancer depuis le dossier microservice :  .\scripts\install.ps1
$ErrorActionPreference = "Stop"

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    $key = .\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(32))"
    (Get-Content ".env") -replace "API_KEY=change-moi", "API_KEY=$key" | Set-Content ".env"
    Write-Host "Fichier .env cree. Cle API a reporter dans le .env de l'application Rails (GENERATOR_API_KEY et API_KEY) :"
    Write-Host $key
}
