"""API du service de génération, de retouche et de vectorisation."""
import asyncio
import base64
import binascii
import logging
import re
import uuid
from contextlib import asynccontextmanager
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import settings
from .init_image import InitImageError
from .init_image import decode as decode_init_image
from .jobs import CREATE, REFINE, VARIANT, Job, JobManager, child_job, new_seed
from .prompt_filter import PromptFilter, clean_prompt
from .security import RateLimiter, require_api_key
from .techniques import DEFAULT_PRINT_WIDTH_CM, DEFAULT_TECHNIQUE, KEYS, catalog_payload, resolve

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

JOB_ID = re.compile(r"^[a-f0-9]{32}$")
FILES = {
    "design.svg": "image/svg+xml",
    "print.png": "image/png",
    "source.png": "image/png",
}
USER_ID = r"^[A-Za-z0-9_-]+$"
# 12 Mo d'image une fois décodée : une image de départ de 1 024 px en pèse deux.
MAX_RESTORE_B64 = 16 * 1024 * 1024

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


app = FastAPI(title="Prêt-à-tirer — génération vectorielle", lifespan=lifespan, docs_url=None, redoc_url=None)


class GenerateRequest(BaseModel):
    prompt: str = Field(min_length=3, max_length=300)
    style: Literal["logo", "illustration", "mascotte", "badge"] = "illustration"
    # Technique de l'atelier : elle borne `colors` et décide du fichier produit.
    # `colors` n'a de sens que pour les techniques à encres comptées ; laissé vide,
    # c'est la valeur par défaut de la technique qui s'applique.
    technique: Literal[KEYS] = DEFAULT_TECHNIQUE
    colors: Optional[int] = Field(default=None, ge=1, le=6)
    print_width_cm: float = Field(default=DEFAULT_PRINT_WIDTH_CM, ge=3, le=60)
    remove_background: bool = True
    user_id: str = Field(min_length=1, max_length=64, pattern=USER_ID)
    seed: Optional[int] = Field(default=None, ge=0, le=2**32 - 1)
    # Facultative : une image du client (PNG, JPEG ou WebP en base64) dont le
    # dessin part, transformée selon le prompt.
    init_image: Optional[str] = Field(default=None, max_length=MAX_RESTORE_B64)
    # Propositions à dessiner pour cette demande, plafonnées par PROPOSALS.
    count: int = Field(default=1, ge=1, le=6)


class RefineRequest(BaseModel):
    instruction: str = Field(min_length=3, max_length=200)
    user_id: str = Field(min_length=1, max_length=64, pattern=USER_ID)
    count: int = Field(default=1, ge=1, le=6)


class RestoreRequest(BaseModel):
    """Un design que Rails a gardé et que la machine a oublié."""
    user_id: str = Field(min_length=1, max_length=64, pattern=USER_ID)
    prompt: str = Field(min_length=3, max_length=300)
    # La description anglaise du parent : sans elle, une variante repartirait du
    # français et une retouche réécrirait autre chose que ce que le client voit.
    subject: Optional[str] = Field(default=None, max_length=600)
    style: Literal["logo", "illustration", "mascotte", "badge"] = "illustration"
    technique: Literal[KEYS] = DEFAULT_TECHNIQUE
    colors: Optional[int] = Field(default=None, ge=1, le=8)
    print_width_cm: float = Field(default=DEFAULT_PRINT_WIDTH_CM, ge=3, le=60)
    remove_background: bool = True
    seed: Optional[int] = Field(default=None, ge=0, le=2**32 - 1)
    # Le compte tenu par Rails : il borne la lignée restaurée.
    used_refinements: int = Field(default=0, ge=0, le=20)
    # L'image de départ (source.png), en base64.
    source_png: str = Field(min_length=8, max_length=MAX_RESTORE_B64)
    # L'image du client dont le design est parti, s'il y en avait une : sans
    # elle, une variante du design restauré repartirait de zéro.
    init_image: Optional[str] = Field(default=None, max_length=MAX_RESTORE_B64)


class VariantsRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=64, pattern=USER_ID)
    count: int = Field(default=3, ge=1, le=6)


def _job_or_404(job_id: str, user_id: str) -> Job:
    job = manager.get(job_id) if JOB_ID.match(job_id) else None
    # Un utilisateur ne voit que ses propres travaux.
    if job is None or job.user_id != user_id:
        raise HTTPException(status_code=404, detail="Design introuvable ou expiré.")
    return job


def _parent_ready(job_id: str, user_id: str) -> Job:
    parent = _job_or_404(job_id, user_id)
    if parent.status != "done":
        raise HTTPException(status_code=409, detail="La version précédente n'est pas encore prête.")
    return parent


def _budget_refusal(root_id: str, requested: int):
    """Renvoie une réponse 429 si la lignée a épuisé son budget de reprises."""
    left = manager.refinements_left(root_id)
    if requested <= left:
        return None
    if left == 0:
        detail = (
            f"Vous avez utilisé vos {settings.max_refinements} reprises pour ce design. "
            "Un graphiste peut le reprendre pour aller plus loin."
        )
    else:
        detail = f"Il ne reste que {left} reprise(s) pour ce design."
    return JSONResponse(
        status_code=429,
        content={"detail": detail, "refinements_left": left, "reason": "refine_budget"},
    )


def _init_png(data_b64: Optional[str]) -> Optional[bytes]:
    """L'image du client ramenée au carré de travail, ou 422 avec un message lisible."""
    if not data_b64:
        return None
    try:
        return decode_init_image(data_b64, settings.image_size)
    except InitImageError as exc:
        raise HTTPException(status_code=422, detail=str(exc))


def _submitted(jobs: list) -> dict:
    return {
        "job_ids": [j.id for j in jobs],
        "job_id": jobs[0].id,
        "status": jobs[0].status,
        "position": manager.position(jobs[0]),
        "refinements_left": manager.refinements_left(jobs[0].root_id),
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/techniques", dependencies=[Depends(require_api_key)])
def techniques():
    """Catalogue des techniques : Rails y lit les libellés et les bornes, sans les dupliquer."""
    return {"techniques": catalog_payload()}


def _room_for(count: int) -> int:
    """Combien de propositions la file peut prendre, ou 503 si aucune."""
    wanted = min(count, settings.proposals, manager.free_slots())
    if wanted < 1:
        raise HTTPException(status_code=503, detail="Beaucoup de demandes en cours. Réessayez dans quelques minutes.")
    return wanted


def _rate_limited(user_id: str):
    """Une demande du client compte une fois, quel que soit le nombre de propositions."""
    retry_after = rate_limiter.hit(user_id)
    if retry_after is None:
        return None
    return JSONResponse(
        status_code=429,
        headers={"Retry-After": str(retry_after)},
        content={"detail": f"Limite de générations atteinte. Réessayez dans {retry_after // 60 + 1} min."},
    )


def _batch(count: int):
    """Le jeton qui scelle les propositions d'un même clic : une seule reprise."""
    return uuid.uuid4().hex if count > 1 else None


@app.post("/generate", status_code=202, dependencies=[Depends(require_api_key)])
def generate(req: GenerateRequest):
    """Dessine `count` propositions d'une même idée, dans des registres voisins."""
    prompt = clean_prompt(req.prompt)
    if len(prompt) < 3:
        raise HTTPException(status_code=422, detail="Décrivez votre design en quelques mots.")
    if prompt_filter.blocked_term(prompt):
        raise HTTPException(
            status_code=422,
            detail="Cette demande contient une marque ou un terme non autorisé. Reformulez votre idée.",
        )
    # Lue avant de compter la demande : une image refusée ne coûte rien.
    init_png = _init_png(req.init_image)
    wanted = _room_for(req.count)
    limited = _rate_limited(req.user_id)
    if limited is not None:
        return limited

    profile = resolve(req.technique)
    lot = _batch(wanted)
    created = [manager.submit(Job(
        user_id=req.user_id,
        prompt=prompt,
        style=req.style,
        colors=profile.clamp_colors(req.colors),
        remove_background=req.remove_background,
        technique=profile.key,
        print_width_cm=req.print_width_cm,
        # Le tirage demandé pour la première, un neuf pour les autres.
        seed=req.seed if (req.seed is not None and index == 0) else new_seed(),
        init_png=init_png,
        batch_id=lot,
        flavour=index,
    )) for index in range(wanted)]
    return _submitted(created)


@app.post("/jobs/{job_id}/refine", status_code=202, dependencies=[Depends(require_api_key)])
def refine(job_id: str, req: RefineRequest):
    """Applique une demande de modification : `count` propositions, une reprise."""
    parent = _parent_ready(job_id, req.user_id)
    instruction = clean_prompt(req.instruction)
    if len(instruction) < 3:
        raise HTTPException(status_code=422, detail="Décrivez la modification en quelques mots.")
    if prompt_filter.blocked_term(instruction):
        raise HTTPException(
            status_code=422,
            detail="Cette modification contient une marque ou un terme non autorisé. Reformulez.",
        )

    refusal = _budget_refusal(parent.root_id, 1)
    if refusal is not None:
        return refusal
    wanted = _room_for(req.count)
    limited = _rate_limited(req.user_id)
    if limited is not None:
        return limited

    lot = _batch(wanted)
    created = [manager.submit(child_job(parent, REFINE, instruction, batch_id=lot, flavour=index))
               for index in range(wanted)]
    return _submitted(created)


@app.post("/jobs/{job_id}/variants", status_code=202, dependencies=[Depends(require_api_key)])
def variants(job_id: str, req: VariantsRequest):
    """Relance le même design avec d'autres tirages, pour que le client choisisse."""
    parent = _parent_ready(job_id, req.user_id)
    # Un clic, une reprise — quel que soit le nombre de tirages qu'il produit.
    refusal = _budget_refusal(parent.root_id, 1)
    if refusal is not None:
        return refusal
    wanted = _room_for(req.count)
    limited = _rate_limited(req.user_id)
    if limited is not None:
        return limited

    lot = uuid.uuid4().hex
    created = [manager.submit(child_job(parent, VARIANT, batch_id=lot, flavour=index))
               for index in range(wanted)]
    return _submitted(created)


@app.post("/jobs/restore", status_code=201, dependencies=[Depends(require_api_key)])
def restore(req: RestoreRequest):
    """Recrée un parent prêt à partir de ce que Rails a gardé. Aucun calcul GPU."""
    try:
        png = base64.b64decode(req.source_png, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="Image de départ illisible.")
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise HTTPException(status_code=422, detail="L'image de départ doit être un PNG.")

    profile = resolve(req.technique)
    job = manager.restore(Job(
        user_id=req.user_id,
        prompt=clean_prompt(req.prompt),
        style=req.style,
        colors=profile.clamp_colors(req.colors),
        remove_background=req.remove_background,
        technique=profile.key,
        print_width_cm=req.print_width_cm,
        seed=req.seed if req.seed is not None else new_seed(),
        subject=req.subject,
        prior_refinements=min(req.used_refinements, settings.max_refinements),
        init_png=_init_png(req.init_image),
    ), png)
    return {"job_id": job.id, "status": job.status,
            "refinements_left": manager.refinements_left(job.root_id)}


@app.get("/jobs/{job_id}", dependencies=[Depends(require_api_key)])
def job_status(job_id: str, user_id: str = Query(min_length=1, max_length=64)):
    job = _job_or_404(job_id, user_id)
    return {
        "job_id": job.id,
        "status": job.status,
        "position": manager.position(job),
        "error": job.error,
        "result": job.result,
        "mode": job.mode,
        "parent_id": job.parent_id,
        "root_id": job.root_id,
        "refinements_left": manager.refinements_left(job.root_id),
    }


@app.get("/jobs/{job_id}/{filename}", dependencies=[Depends(require_api_key)])
def job_file(job_id: str, filename: str, user_id: str = Query(min_length=1, max_length=64)):
    job = _job_or_404(job_id, user_id)
    path = job.directory / filename
    # Selon la technique, le fichier d'impression est un SVG ou un PNG : demander l'autre
    # n'est pas une erreur du service, c'est un fichier qui n'existe pas.
    if filename not in FILES or job.status != "done" or not path.exists():
        raise HTTPException(status_code=404, detail="Fichier indisponible.")
    return FileResponse(path, media_type=FILES[filename])
