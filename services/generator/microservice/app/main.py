"""API du service de génération et de vectorisation."""
import asyncio
import logging
import re
from contextlib import asynccontextmanager
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import settings
from .jobs import Job, JobManager, new_seed
from .prompt_filter import PromptFilter, clean_prompt
from .security import RateLimiter, require_api_key

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

JOB_ID = re.compile(r"^[a-f0-9]{32}$")
FILES = {"design.svg": "image/svg+xml", "source.png": "image/png"}

prompt_filter = PromptFilter(settings.blocklist_file)
rate_limiter = RateLimiter(settings.rate_limit_count, settings.rate_limit_window)
manager: Optional[JobManager] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global manager
    if not settings.api_key or settings.api_key == "change-moi":
        raise RuntimeError("Définissez une vraie valeur pour API_KEY dans le fichier .env.")
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    manager = JobManager(prompt_filter)
    tasks = [asyncio.create_task(manager.worker()), asyncio.create_task(manager.cleanup_loop())]
    logging.getLogger(__name__).info("Service prêt (mode %s)", settings.generator_mode)
    yield
    for task in tasks:
        task.cancel()


app = FastAPI(title="T-shirt IA — génération vectorielle", lifespan=lifespan, docs_url=None, redoc_url=None)


class GenerateRequest(BaseModel):
    prompt: str = Field(min_length=3, max_length=300)
    style: Literal["logo", "illustration", "mascotte", "badge"] = "illustration"
    colors: int = Field(default=3, ge=1, le=6)
    remove_background: bool = True
    user_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    seed: Optional[int] = Field(default=None, ge=0, le=2**32 - 1)


def _job_or_404(job_id: str, user_id: str) -> Job:
    job = manager.get(job_id) if JOB_ID.match(job_id) else None
    # Un utilisateur ne voit que ses propres travaux.
    if job is None or job.user_id != user_id:
        raise HTTPException(status_code=404, detail="Design introuvable ou expiré.")
    return job


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/generate", status_code=202, dependencies=[Depends(require_api_key)])
def generate(req: GenerateRequest):
    prompt = clean_prompt(req.prompt)
    if len(prompt) < 3:
        raise HTTPException(status_code=422, detail="Décrivez votre design en quelques mots.")
    if prompt_filter.blocked_term(prompt):
        raise HTTPException(
            status_code=422,
            detail="Cette demande contient une marque ou un terme non autorisé. Reformulez votre idée.",
        )
    if manager.is_full():
        raise HTTPException(status_code=503, detail="Beaucoup de demandes en cours. Réessayez dans quelques minutes.")

    retry_after = rate_limiter.hit(req.user_id)
    if retry_after is not None:
        return JSONResponse(
            status_code=429,
            headers={"Retry-After": str(retry_after)},
            content={"detail": f"Limite de générations atteinte. Réessayez dans {retry_after // 60 + 1} min."},
        )

    job = manager.submit(Job(
        user_id=req.user_id,
        prompt=prompt,
        style=req.style,
        colors=req.colors,
        remove_background=req.remove_background,
        seed=req.seed if req.seed is not None else new_seed(),
    ))
    return {"job_id": job.id, "status": job.status, "position": manager.position(job)}


@app.get("/jobs/{job_id}", dependencies=[Depends(require_api_key)])
def job_status(job_id: str, user_id: str = Query(min_length=1, max_length=64)):
    job = _job_or_404(job_id, user_id)
    return {
        "job_id": job.id,
        "status": job.status,
        "position": manager.position(job),
        "error": job.error,
        "result": job.result,
    }


@app.get("/jobs/{job_id}/{filename}", dependencies=[Depends(require_api_key)])
def job_file(job_id: str, filename: str, user_id: str = Query(min_length=1, max_length=64)):
    job = _job_or_404(job_id, user_id)
    if filename not in FILES or job.status != "done":
        raise HTTPException(status_code=404, detail="Fichier indisponible.")
    return FileResponse(job.directory / filename, media_type=FILES[filename])
