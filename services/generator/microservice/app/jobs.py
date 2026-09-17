"""File d'attente en mémoire : un seul travail à la fois, le GPU ne se partage pas bien."""
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
from .translate import to_english
from .vectorizer import vectorize

log = logging.getLogger(__name__)


@dataclass
class Job:
    user_id: str
    prompt: str
    style: str
    colors: int
    remove_background: bool
    seed: int
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
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

    def is_full(self) -> bool:
        return len(self.pending) >= settings.max_queue

    def submit(self, job: Job) -> Job:
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

    async def _run(self, job: Job) -> None:
        subject = await to_english(job.prompt)
        # Les marques survivent à la traduction : on refiltre le texte traduit.
        if self.prompt_filter.blocked_term(subject):
            raise GenerationError("Cette demande contient un terme non autorisé.")
        positive, negative = build_prompts(subject, job.style, job.colors)

        png = await self.generator.generate(positive, negative, job.seed, job.colors)
        # La vectorisation est du calcul CPU : on la sort de la boucle asynchrone.
        out = await asyncio.to_thread(
            vectorize, png, job.colors, job.remove_background, settings.max_paths_warning
        )

        job.directory.mkdir(parents=True, exist_ok=True)
        (job.directory / "source.png").write_bytes(png)
        (job.directory / "design.svg").write_text(out["svg"], encoding="utf-8")

        job.result = {
            "palette": out["palette"],
            "inks": out["inks"],
            "stats": out["stats"],
            "warnings": out["warnings"],
            "prompt_used": positive,
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
