"""File d'attente en mémoire : un seul travail à la fois, le GPU ne se partage pas bien.

Chaque design forme une lignée : la création est la racine, les variantes et les retouches
sont ses enfants. Le budget de reprises (settings.max_refinements) se compte sur la lignée,
pas sur l'utilisateur : passé ce budget, le site propose un graphiste.
"""
import asyncio
import logging
import random
import shutil
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .config import settings
from .generator import GenerationError, get_generator
from .prompt_builder import build_prompts
from .prompt_filter import PromptFilter
from .raster import rasterize
from .refine import apply_instruction
from .techniques import DEFAULT_PRINT_WIDTH_CM, DEFAULT_TECHNIQUE, resolve
from .translate import to_english
from .vectorizer import vectorize

log = logging.getLogger(__name__)

CREATE, VARIANT, REFINE = "create", "variant", "refine"


@dataclass
class Job:
    user_id: str
    prompt: str
    style: str
    colors: int
    remove_background: bool
    seed: int
    # Technique d'impression de l'atelier : elle décide du prompt, du fichier produit
    # et des alertes. Voir app/techniques.py.
    technique: str = DEFAULT_TECHNIQUE
    print_width_cm: float = DEFAULT_PRINT_WIDTH_CM
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    mode: str = CREATE  # create | variant | refine
    parent_id: Optional[str] = None
    root_id: Optional[str] = None
    instruction: Optional[str] = None
    subject: Optional[str] = None  # description anglaise réellement envoyée au modèle
    status: str = "queued"  # queued | running | done | error
    error: Optional[str] = None
    result: Optional[dict] = None
    created_at: float = field(default_factory=time.time)

    @property
    def directory(self) -> Path:
        return settings.data_dir / self.id


class JobManager:
    def __init__(self, prompt_filter: PromptFilter):
        self.jobs: dict = {}
        self.pending: list = []
        self.queue: asyncio.Queue = asyncio.Queue()
        self.generator = get_generator()
        self.prompt_filter = prompt_filter

    # ------------------------------------------------------------------ file d'attente
    def is_full(self) -> bool:
        return len(self.pending) >= settings.max_queue

    def free_slots(self) -> int:
        return max(settings.max_queue - len(self.pending), 0)

    def submit(self, job: Job) -> Job:
        if job.root_id is None:
            job.root_id = job.id
        self.jobs[job.id] = job
        self.pending.append(job.id)
        self.queue.put_nowait(job.id)
        return job

    def position(self, job: Job) -> Optional[int]:
        if job.status != "queued":
            return None
        try:
            return self.pending.index(job.id) + 1
        except ValueError:
            return None

    def get(self, job_id: str) -> Optional[Job]:
        return self.jobs.get(job_id)

    # ------------------------------------------------------------------------- lignée
    def lineage(self, root_id: str) -> list:
        return [j for j in self.jobs.values() if j.root_id == root_id]

    def used_refinements(self, root_id: str) -> int:
        """Nombre de reprises déjà demandées sur ce design (hors création initiale)."""
        return len([j for j in self.lineage(root_id) if j.id != root_id and j.status != "error"])

    def refinements_left(self, root_id: str) -> int:
        return max(settings.max_refinements - self.used_refinements(root_id), 0)

    # -------------------------------------------------------------------------- worker
    async def worker(self) -> None:
        while True:
            job_id = await self.queue.get()
            job = self.jobs.get(job_id)
            if job is None:
                continue
            job.status = "running"
            try:
                await self._run(job)
                job.status = "done"
            except GenerationError as exc:
                job.status, job.error = "error", str(exc)
            except Exception:
                log.exception("Échec du travail %s", job.id)
                job.status, job.error = "error", "Erreur interne pendant la création du design."
            finally:
                if job_id in self.pending:
                    self.pending.remove(job_id)
                self.queue.task_done()

    async def _subject_for(self, job: Job) -> str:
        if job.mode == CREATE:
            return await to_english(job.prompt)

        parent = self.get(job.parent_id) if job.parent_id else None
        if parent is None:
            raise GenerationError("La version précédente a expiré. Relancez la création.")
        base = parent.subject or await to_english(parent.prompt)
        if job.mode == VARIANT:
            return base
        return await apply_instruction(base, job.instruction or "")

    def _init_image(self, job: Job) -> bytes:
        parent = self.get(job.parent_id) if job.parent_id else None
        source = (parent.directory / "source.png") if parent else None
        if source is None or not source.exists():
            raise GenerationError("L'image de départ a expiré. Relancez la création.")
        return source.read_bytes()

    async def _run(self, job: Job) -> None:
        subject = await self._subject_for(job)
        # Les marques survivent à la traduction comme à la réécriture : on refiltre le texte.
        if self.prompt_filter.blocked_term(subject):
            raise GenerationError("Cette demande contient un terme non autorisé.")
        job.subject = subject
        profile = resolve(job.technique)
        colors = profile.clamp_colors(job.colors)
        job.colors = colors
        positive, negative = build_prompts(subject, job.style, colors, profile.key)

        if job.mode == REFINE:
            png = await self.generator.refine(
                positive, negative, job.seed, colors,
                self._init_image(job), settings.refine_denoise,
            )
        else:
            png = await self.generator.generate(positive, negative, job.seed, colors)

        job.directory.mkdir(parents=True, exist_ok=True)
        (job.directory / "source.png").write_bytes(png)

        # Préparation du fichier d'impression : du calcul CPU, sorti de la boucle asynchrone.
        if profile.family == "vector":
            out = await asyncio.to_thread(
                vectorize, png, colors, job.remove_background,
                settings.max_paths_warning, profile.key,
            )
            (job.directory / "design.svg").write_text(out["svg"], encoding="utf-8")
        else:
            out = await asyncio.to_thread(
                rasterize, png, profile, job.remove_background, job.print_width_cm
            )
            (job.directory / "print.png").write_bytes(out["png"])

        job.result = {
            "technique": profile.key,
            "technique_label": profile.label,
            "output": profile.family,
            "print_file": profile.file_name,
            "colors": colors,
            "palette": out["palette"],
            "inks": out["inks"],
            "stats": out["stats"],
            "warnings": out["warnings"],
            "prompt_used": positive,
            "subject": subject,
            "instruction": job.instruction,
            "mode": job.mode,
            "parent_id": job.parent_id,
            "seed": job.seed,
        }

    async def cleanup_loop(self) -> None:
        while True:
            await asyncio.sleep(300)
            limit = time.time() - settings.job_ttl
            for job_id, job in list(self.jobs.items()):
                if job.status in ("done", "error") and job.created_at < limit:
                    shutil.rmtree(job.directory, ignore_errors=True)
                    self.jobs.pop(job_id, None)


def new_seed() -> int:
    return random.randint(0, 2**32 - 1)


def child_job(parent: Job, mode: str, instruction: Optional[str] = None) -> Job:
    """Construit une variante ou une retouche à partir d'un design existant."""
    return Job(
        user_id=parent.user_id,
        prompt=parent.prompt,
        style=parent.style,
        colors=parent.colors,
        remove_background=parent.remove_background,
        seed=new_seed(),
        # Une reprise reste destinée à la même machine que son parent.
        technique=parent.technique,
        print_width_cm=parent.print_width_cm,
        mode=mode,
        parent_id=parent.id,
        root_id=parent.root_id or parent.id,
        instruction=instruction,
    )
