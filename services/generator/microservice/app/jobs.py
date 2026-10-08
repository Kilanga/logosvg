"""File d'attente en mémoire : un seul travail à la fois, le GPU ne se partage pas bien.

Chaque design forme une lignée : la création est la racine, les variantes et les retouches
sont ses enfants. Le budget de reprises (settings.max_refinements) se compte sur la lignée,
pas sur l'utilisateur : passé ce budget, le site propose un graphiste.
"""
import asyncio
import io
import logging
import random
import shutil
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from PIL import Image

from .config import settings
from .generator import GenerationError, get_generator
from .moderation import review
from .prompt_builder import build_prompt
from .prompt_filter import PromptFilter
from .raster import rasterize, target_pixels
from .refine import apply_instruction
from .techniques import DEFAULT_PRINT_WIDTH_CM, DEFAULT_TECHNIQUE, resolve
from .translate import to_english
from .vectorizer import vectorize

log = logging.getLogger(__name__)

CREATE, VARIANT, REFINE = "create", "variant", "refine"
# Le visuel du client préparé tel quel pour l'atelier : ni modèle, ni prompt.
CONVERT = "convert"


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
    # Les trois variantes nées d'un même clic partagent ce jeton : elles comptent
    # alors pour UNE reprise, et non trois. Voir used_refinements.
    batch_id: Optional[str] = None
    # Le registre de la proposition dans son lot (0, 1, 2) : voir prompt_builder.
    flavour: int = 0
    parent_id: Optional[str] = None
    root_id: Optional[str] = None
    instruction: Optional[str] = None
    # Reprises déjà consommées avant que cette lignée n'arrive sur la machine : un
    # design restauré par Rails (voir /jobs/restore) apporte son compte avec lui,
    # sinon un redémarrage du service rendrait des reprises au client.
    prior_refinements: int = 0
    # L'image de départ du client, déjà ramenée au carré de travail (init_image.py).
    # Une variante la reprend de son parent : elle redessine la même image.
    init_png: Optional[bytes] = None
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
        self.batch_subjects: dict = {}
        # Le refus de la modération, une fois par lot comme la traduction.
        self.batch_refusals: dict = {}

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
        """Nombre de reprises déjà demandées sur ce design (hors création initiale).

        Une reprise est une **action du client**, pas une image. Chaque clic —
        retouche ou « d'autres versions » — produit trois propositions et ne
        coûte qu'une reprise : elles partagent un `batch_id` et ne valent qu'un.
        Un enfant sans lot ne peut venir que d'une version antérieure du
        service : il compte seul, faute de mieux.
        """
        enfants = [j for j in self.lineage(root_id) if j.id != root_id and j.status != "error"]
        lots = {j.batch_id for j in enfants if j.batch_id}
        orphelins = sum(1 for j in enfants if not j.batch_id)
        racine = self.get(root_id)
        anterieures = racine.prior_refinements if racine else 0
        return anterieures + len(lots) + orphelins

    def restore(self, job: Job, source_png: bytes) -> Job:
        """Remet sur la machine un design que Rails a gardé, sans le régénérer.

        Les travaux vivent en mémoire et leurs fichiers une heure : passé ce
        délai, ou après un redémarrage — c'est-à-dire chaque fois que la machine
        à GPU est éteinte —, une reprise n'avait plus de parent et échouait.
        Rails, lui, a gardé l'image de départ et la description : il les
        renvoie ici, et le design redevient un parent prêt, à la racine d'une
        nouvelle lignée qui hérite du compte de reprises.
        """
        job.root_id = job.id
        job.status = "done"
        job.directory.mkdir(parents=True, exist_ok=True)
        (job.directory / "source.png").write_bytes(source_png)
        job.result = {
            "technique": job.technique,
            "mode": "restored",
            "from_image": job.init_png is not None,
            "subject": job.subject,
            "seed": job.seed,
            "colors": job.colors,
            "restored": True,
        }
        self.jobs[job.id] = job
        return job

    def refinements_left(self, root_id: str) -> int:
        root = self.jobs.get(root_id)
        if root is not None and root.mode == CONVERT:
            return 0  # un visuel déposé tel quel n'a rien à reprendre
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
        """La description anglaise, calculée une fois par lot : les trois
        propositions d'un clic décrivent la même chose, et chaque appel au
        traducteur recharge son modèle à froid.

        La demande du client est relue avant d'être traduite : refusée, aucune
        image n'est dessinée, et les trois propositions du clic échouent
        ensemble avec la même phrase."""
        if job.batch_id and job.batch_id in self.batch_refusals:
            raise GenerationError(self.batch_refusals[job.batch_id])
        if job.batch_id and job.batch_id in self.batch_subjects:
            return self.batch_subjects[job.batch_id]
        refusal = await self._review(job)
        if refusal:
            if job.batch_id:
                self.batch_refusals[job.batch_id] = refusal
            raise GenerationError(refusal)
        subject = await self._fresh_subject(job)
        if job.batch_id:
            self.batch_subjects[job.batch_id] = subject
        return subject

    async def _review(self, job: Job) -> Optional[str]:
        """Ce que le client a écrit, relu par le modèle. Une variante n'écrit
        rien de neuf : elle reprend une description déjà relue."""
        if job.mode == CREATE:
            return await review(job.prompt)
        if job.mode == REFINE:
            parent = self.get(job.parent_id) if job.parent_id else None
            context = (parent.subject or parent.prompt) if parent else ""
            return await review(job.instruction or "", context)
        return None

    async def _fresh_subject(self, job: Job) -> str:
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

    async def _hires(self, png: bytes, prompt: str, seed: int) -> tuple:
        """Redessine l'image plus grande, pour les techniques matricielles.

        Une poitrine de t-shirt se demande à 25 cm : en 1 024 px, le fichier ne vaut que
        104 dpi réels et l'atelier voit passer une alerte « définition faible » sur chaque
        commande. Cette passe ne se contente pas d'agrandir — elle repasse l'image dans le
        modèle à la taille voulue, avec un bruit faible : les détails sont dessinés.

        Elle n'est jamais bloquante : si le GPU manque de mémoire, on garde l'image
        d'origine et on le dit au client plutôt que de perdre sa génération.
        """
        target = int(settings.image_size * settings.hires_scale)
        try:
            return await self.generator.hires(
                prompt, seed, png, settings.hires_denoise, target
            ), None
        except GenerationError as exc:
            log.warning("Passe haute définition abandonnée : %s", exc)
            return png, (
                "La passe haute définition n'a pas abouti : le fichier reste imprimable, "
                "mais les détails fins seront plus doux à grande taille."
            )

    async def _upscale(self, png: bytes, profile, print_width_cm: float) -> tuple:
        """Porte l'image à la résolution de la technique par un modèle d'agrandissement.

        Seulement si un modèle est configuré (UPSCALE_MODEL) et si l'image est plus
        petite que le fichier visé. Jamais bloquant, comme la passe haute définition.
        """
        wanted = target_pixels(print_width_cm, profile.dpi)
        with Image.open(io.BytesIO(png)) as img:
            width = img.width
        if not settings.upscale_model or wanted <= width * 1.05:
            return None, None
        try:
            return await self.generator.upscale(png, wanted), None
        except GenerationError as exc:
            log.warning("Agrandissement par modèle abandonné : %s", exc)
            return None, (
                "L'agrandissement n'a pas abouti : le fichier reste imprimable, "
                "mais il est interpolé au-delà de la définition du dessin."
            )

    async def _run(self, job: Job) -> None:
        if job.mode == CONVERT:
            return await self._convert(job)

        subject = await self._subject_for(job)
        # Les marques survivent à la traduction comme à la réécriture : on refiltre le texte.
        if self.prompt_filter.blocked_term(subject):
            raise GenerationError("Cette demande contient un terme non autorisé.")
        job.subject = subject

        # `to_english` renvoie le texte inchangé quand la traduction échoue, et
        # elle échoue en silence par construction : une génération ne doit
        # jamais s'arrêter parce qu'un traducteur n'a pas répondu. Le prix, si
        # personne ne le dit, est un prompt français envoyé à un modèle qui ne
        # comprend que l'anglais, et un dessin à côté de la demande sans la
        # moindre erreur nulle part. L'égalité est donc la signature exacte de
        # l'échec, et elle remonte jusqu'au client.
        traduction_manquee = bool(settings.ollama_url) and subject == job.prompt

        profile = resolve(job.technique)
        colors = profile.clamp_colors(job.colors)
        job.colors = colors
        prompt = build_prompt(subject, job.style, colors, profile.key, job.flavour)

        if job.mode == REFINE:
            png = await self.generator.refine(
                prompt, job.seed, colors,
                self._init_image(job), settings.refine_denoise,
            )
        elif job.init_png:
            # Une création (ou une variante) qui part de l'image du client : la
            # même voie que la retouche, avec un écart plus grand.
            png = await self.generator.refine(
                prompt, job.seed, colors, job.init_png, settings.upload_denoise,
            )
        else:
            png = await self.generator.generate(prompt, job.seed, colors)

        job.directory.mkdir(parents=True, exist_ok=True)
        # L'image de référence gardée pour le client et pour l'atelier est celle que le
        # modèle a dessinée, avant toute préparation d'impression.
        (job.directory / "source.png").write_bytes(png)

        hires_warning = None
        if profile.family == "raster" and settings.hires_scale > 1:
            png, hires_warning = await self._hires(png, prompt, job.seed)

        # Préparation du fichier d'impression : du calcul CPU, sorti de la boucle asynchrone.
        if profile.family == "vector":
            out = await asyncio.to_thread(
                vectorize, png, colors, job.remove_background,
                settings.max_paths_warning, profile.key,
            )
            (job.directory / "design.svg").write_text(out["svg"], encoding="utf-8")
        else:
            upscaled, upscale_warning = await self._upscale(png, profile, job.print_width_cm)
            out = await asyncio.to_thread(
                rasterize, png, profile, job.remove_background, job.print_width_cm, upscaled
            )
            (job.directory / "print.png").write_bytes(out["png"])
            for warning in (hires_warning, upscale_warning):
                if warning:
                    out["warnings"].append(warning)


        if traduction_manquee:
            out["warnings"].append(
                "La demande n'a pas pu être traduite : le dessin peut s'écarter du texte. "
                "Relancez la génération si le résultat ne correspond pas."
            )

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
            "prompt_used": prompt,
            "flavour": job.flavour,
            "subject": subject,
            "instruction": job.instruction,
            "mode": job.mode,
            "parent_id": job.parent_id,
            "seed": job.seed,
            # Parti d'une image du client : le dessin en dérive.
            "from_image": job.init_png is not None,
        }

    async def _convert(self, job: Job) -> None:
        """Le visuel du client, mis au format de l'atelier sans rien redessiner.

        Décidé le 08/10/2026 : un client qui a déjà son image — faite ailleurs,
        par une autre IA ou à la main — veut seulement l'envoyer à l'atelier dans
        le bon format. Aucun appel au modèle d'image ni au traducteur : les
        mêmes étapes de préparation que pour un dessin du modèle (vectorisation
        en aplats, ou PNG détouré à 300 dpi agrandi au besoin), à partir de
        l'image telle qu'elle est.
        """
        png = job.init_png
        if png is None:
            raise GenerationError("Le visuel est introuvable. Déposez-le à nouveau.")

        profile = resolve(job.technique)
        colors = profile.clamp_colors(job.colors)
        job.colors = colors

        job.directory.mkdir(parents=True, exist_ok=True)
        (job.directory / "source.png").write_bytes(png)

        if profile.family == "vector":
            small = await asyncio.to_thread(_shrink, png, settings.convert_vector_side)
            out = await asyncio.to_thread(
                vectorize, small, colors, job.remove_background,
                settings.max_paths_warning, profile.key,
            )
            (job.directory / "design.svg").write_text(out["svg"], encoding="utf-8")
        else:
            upscaled, upscale_warning = await self._upscale(png, profile, job.print_width_cm)
            out = await asyncio.to_thread(
                rasterize, png, profile, job.remove_background, job.print_width_cm, upscaled
            )
            (job.directory / "print.png").write_bytes(out["png"])
            if upscale_warning:
                out["warnings"].append(upscale_warning)

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
            "prompt_used": None,
            "flavour": 0,
            "subject": None,
            "instruction": None,
            "mode": CONVERT,
            "parent_id": None,
            "seed": None,
            "from_image": True,
        }

    async def cleanup_loop(self) -> None:
        while True:
            await asyncio.sleep(300)
            limit = time.time() - settings.job_ttl
            for job_id, job in list(self.jobs.items()):
                if job.status in ("done", "error") and job.created_at < limit:
                    shutil.rmtree(job.directory, ignore_errors=True)
                    self.jobs.pop(job_id, None)
            live = {j.batch_id for j in self.jobs.values() if j.batch_id}
            for batch in list(self.batch_refusals):
                if batch not in live:
                    self.batch_refusals.pop(batch, None)
            for batch in list(self.batch_subjects):
                if batch not in live:
                    self.batch_subjects.pop(batch, None)


def _shrink(png: bytes, side: int) -> bytes:
    """La même image, ramenée à `side` px de grand côté au plus."""
    with Image.open(io.BytesIO(png)) as img:
        if max(img.size) <= side:
            return png
        img = img.copy()
        img.thumbnail((side, side), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="PNG")
        return out.getvalue()


def new_seed() -> int:
    return random.randint(0, 2**32 - 1)


def child_job(parent: Job, mode: str, instruction: Optional[str] = None,
              batch_id: Optional[str] = None, flavour: int = 0) -> Job:
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
        batch_id=batch_id,
        flavour=flavour,
        # Une variante redessine l'image de départ du client, s'il y en avait une.
        init_png=parent.init_png if mode == VARIANT else None,
        parent_id=parent.id,
        root_id=parent.root_id or parent.id,
        instruction=instruction,
    )
