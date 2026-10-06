"""Génération d'image : simulation locale ou ComfyUI (création et retouche)."""
import asyncio
import io
import json
import math
import random
import time
import uuid
from pathlib import Path

import httpx
from PIL import Image, ImageDraw

from .config import settings

WORKFLOWS = Path(__file__).resolve().parent.parent / "workflows"
TEXT2IMG = WORKFLOWS / "sdxl_flat.json"
IMG2IMG = WORKFLOWS / "sdxl_img2img.json"
UPSCALE = WORKFLOWS / "upscale_model.json"


def _scaled_height(png: bytes, width: int) -> int:
    with Image.open(io.BytesIO(png)) as img:
        return max(int(round(img.height * width / img.width)), 1)


class GenerationError(Exception):
    pass


class MockGenerator:
    """Dessine un design plat aléatoire. Sert à tester tout le pipeline sans GPU."""

    async def generate(self, positive: str, negative: str, seed: int, colors: int) -> bytes:
        await asyncio.sleep(1)  # simule un temps de calcul
        rng = random.Random(seed)
        size = 768
        img = Image.new("RGB", (size, size), "white")
        draw = ImageDraw.Draw(img)
        palette = [tuple(rng.randint(0, 200) for _ in range(3)) for _ in range(max(colors, 1))]
        c = size // 2

        draw.ellipse([c - 230, c - 230, c + 230, c + 230], fill=palette[0])
        if colors >= 2:
            points = []
            for i in range(10):
                radius = 180 if i % 2 == 0 else 75
                angle = math.pi / 2 + i * math.pi / 5
                points.append((c + radius * math.cos(angle), c - radius * math.sin(angle)))
            draw.polygon(points, fill=palette[1])
        if colors >= 3:
            draw.rectangle([c - 260, c + 150, c + 260, c + 230], fill=palette[2])
        for i in range(3, colors):
            x = rng.randint(c - 120, c + 80)
            draw.ellipse([x, c - 40, x + 40, c], fill=palette[i])

        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    async def hires(self, positive: str, negative: str, seed: int,
                    init_png: bytes, denoise: float, size: int) -> bytes:
        """Sans GPU, la passe haute définition se réduit à un agrandissement."""
        await asyncio.sleep(0.2)
        img = Image.open(io.BytesIO(init_png)).convert("RGB")
        if size > img.width:
            img = img.resize((size, round(img.height * size / img.width)), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    async def upscale(self, png: bytes, width: int) -> bytes:
        """Sans GPU, l'agrandissement par modèle se réduit à un agrandissement simple."""
        await asyncio.sleep(0.1)
        img = Image.open(io.BytesIO(png)).convert("RGB")
        img = img.resize((width, _scaled_height(png, width)), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    async def refine(self, positive: str, negative: str, seed: int, colors: int,
                     init_png: bytes, denoise: float) -> bytes:
        """Repart de l'image fournie et la modifie visiblement, sans GPU."""
        await asyncio.sleep(1)
        img = Image.open(io.BytesIO(init_png)).convert("RGB")
        draw = ImageDraw.Draw(img)
        rng = random.Random(seed)
        w, h = img.size
        # Une marque dépendante du seed : l'image retouchée diffère de son parent.
        colour = tuple(rng.randint(0, 200) for _ in range(3))
        draw.rectangle([w // 8, h // 8, w // 8 + w // 4, h // 8 + h // 12], fill=colour)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()


class ComfyUIGenerator:
    """Envoie les workflows SDXL à ComfyUI et récupère l'image produite."""

    def __init__(self):
        self.text2img = json.loads(TEXT2IMG.read_text(encoding="utf-8"))
        self.img2img = json.loads(IMG2IMG.read_text(encoding="utf-8")) if IMG2IMG.exists() else None

    def _common(self, wf: dict, positive: str, negative: str, seed: int) -> dict:
        wf["3"]["inputs"]["seed"] = seed
        wf["4"]["inputs"]["ckpt_name"] = settings.comfyui_checkpoint
        wf["6"]["inputs"]["text"] = positive
        wf["7"]["inputs"]["text"] = negative
        return wf

    def _workflow(self, positive: str, negative: str, seed: int) -> dict:
        wf = self._common(json.loads(json.dumps(self.text2img)), positive, negative, seed)
        wf["5"]["inputs"]["width"] = settings.image_size
        wf["5"]["inputs"]["height"] = settings.image_size
        return wf

    def _workflow_refine(self, positive: str, negative: str, seed: int,
                         image_name: str, denoise: float, size: int = None) -> dict:
        if not self.img2img:
            raise GenerationError("Le workflow de retouche est absent du service.")
        wf = self._common(json.loads(json.dumps(self.img2img)), positive, negative, seed)
        wf["3"]["inputs"]["denoise"] = denoise
        wf["10"]["inputs"]["image"] = image_name
        target = size or settings.image_size
        wf["12"]["inputs"]["width"] = target
        wf["12"]["inputs"]["height"] = target
        return wf

    async def _upload(self, client: httpx.AsyncClient, png: bytes) -> str:
        """Dépose l'image de départ dans le dossier d'entrée de ComfyUI."""
        name = f"tsia_{uuid.uuid4().hex}.png"
        resp = await client.post(
            "/upload/image",
            files={"image": (name, png, "image/png")},
            data={"overwrite": "true", "type": "input"},
        )
        if resp.status_code != 200:
            raise GenerationError(f"ComfyUI a refusé l'image de départ : {resp.text[:200]}")
        body = resp.json()
        subfolder = body.get("subfolder") or ""
        stored = body.get("name", name)
        return f"{subfolder}/{stored}" if subfolder else stored

    async def _run(self, workflow: dict) -> bytes:
        payload = {"prompt": workflow, "client_id": uuid.uuid4().hex}
        deadline = time.monotonic() + settings.comfyui_timeout
        try:
            async with httpx.AsyncClient(base_url=settings.comfyui_url, timeout=60) as client:
                resp = await client.post("/prompt", json=payload)
                if resp.status_code != 200:
                    raise GenerationError(f"ComfyUI a refusé le workflow : {resp.text[:300]}")
                prompt_id = resp.json()["prompt_id"]

                while time.monotonic() < deadline:
                    history = (await client.get(f"/history/{prompt_id}")).json()
                    entry = history.get(prompt_id)
                    if entry:
                        status = entry.get("status", {})
                        if status.get("status_str") == "error":
                            raise GenerationError("ComfyUI a signalé une erreur pendant la génération.")
                        for node in entry.get("outputs", {}).values():
                            for image in node.get("images", []):
                                view = await client.get("/view", params={
                                    "filename": image["filename"],
                                    "subfolder": image.get("subfolder", ""),
                                    "type": image.get("type", "output"),
                                })
                                view.raise_for_status()
                                return view.content
                        if status.get("completed"):
                            raise GenerationError("ComfyUI n'a produit aucune image.")
                    await asyncio.sleep(1)
        except httpx.HTTPError as exc:
            raise GenerationError(f"ComfyUI injoignable : {exc}") from exc
        raise GenerationError("La génération a dépassé le délai autorisé.")

    async def generate(self, positive: str, negative: str, seed: int, colors: int) -> bytes:
        return await self._run(self._workflow(positive, negative, seed))

    async def hires(self, positive: str, negative: str, seed: int,
                    init_png: bytes, denoise: float, size: int) -> bytes:
        """Seconde passe de diffusion, à la taille voulue : les pixels sont dessinés.

        Le même workflow que la retouche, avec un bruit faible : la composition ne bouge
        pas, mais les bords et les détails sont réellement redessinés à la nouvelle
        résolution, là où un agrandissement se contenterait d'étaler les pixels existants.
        """
        try:
            async with httpx.AsyncClient(base_url=settings.comfyui_url, timeout=60) as client:
                name = await self._upload(client, init_png)
        except httpx.HTTPError as exc:
            raise GenerationError(f"ComfyUI injoignable : {exc}") from exc
        return await self._run(
            self._workflow_refine(positive, negative, seed, name, denoise, size=size)
        )

    async def upscale(self, png: bytes, width: int) -> bytes:
        """Agrandit par un modèle (ESRGAN) puis ramène à la largeur d'impression.

        Un modèle d'agrandissement dessine les bords et les textures au lieu de
        les étaler : c'est ce qui sépare un DTF net à 300 dpi d'un fichier en
        300 dpi interpolé. Pas de diffusion ici, donc rien de réinventé.
        """
        if not UPSCALE.exists():
            raise GenerationError("Le workflow d'agrandissement est absent du service.")
        try:
            async with httpx.AsyncClient(base_url=settings.comfyui_url, timeout=60) as client:
                name = await self._upload(client, png)
        except httpx.HTTPError as exc:
            raise GenerationError(f"ComfyUI injoignable : {exc}") from exc
        wf = json.loads(UPSCALE.read_text(encoding="utf-8"))
        wf["1"]["inputs"]["image"] = name
        wf["2"]["inputs"]["model_name"] = settings.upscale_model
        wf["4"]["inputs"]["width"] = width
        wf["4"]["inputs"]["height"] = _scaled_height(png, width)
        return await self._run(wf)

    async def refine(self, positive: str, negative: str, seed: int, colors: int,
                     init_png: bytes, denoise: float) -> bytes:
        try:
            async with httpx.AsyncClient(base_url=settings.comfyui_url, timeout=60) as client:
                name = await self._upload(client, init_png)
        except httpx.HTTPError as exc:
            raise GenerationError(f"ComfyUI injoignable : {exc}") from exc
        return await self._run(self._workflow_refine(positive, negative, seed, name, denoise))


FLUX_TEXT2IMG = WORKFLOWS / "flux2_klein.json"
FLUX_IMG2IMG = WORKFLOWS / "flux2_klein_img2img.json"


def _multiple_of_16(value: int) -> int:
    """Le latent de FLUX.2 se découpe en carreaux de 16 px : une taille qui n'en est
    pas un multiple est refusée par ComfyUI. Arrondi vers le haut : on ne perd
    jamais de définition."""
    return max(16, math.ceil(value / 16.0) * 16)


class Flux2KleinGenerator(ComfyUIGenerator):
    """FLUX.2 [klein] 4B dans ComfyUI : même contrat que SDXL, autre graphe.

    Le modèle se charge en trois fichiers (modèle, encodeur Qwen3, VAE) et
    s'échantillonne par SamplerCustomAdvanced, comme dans le modèle de workflow
    officiel de ComfyUI. Une retouche et la passe haute définition sont de
    l'img2img classique : l'image encodée sert de latent de départ, et
    SplitSigmasDenoise ne garde que la fin du planning de bruit.
    """

    def __init__(self):
        self.text2img = json.loads(FLUX_TEXT2IMG.read_text(encoding="utf-8"))
        self.img2img = json.loads(FLUX_IMG2IMG.read_text(encoding="utf-8"))

    def _common(self, wf: dict, positive: str, negative: str, seed: int) -> dict:
        wf["1"]["inputs"]["unet_name"] = settings.flux_unet
        wf["2"]["inputs"]["clip_name"] = settings.flux_text_encoder
        wf["3"]["inputs"]["vae_name"] = settings.flux_vae
        wf["4"]["inputs"]["text"] = positive
        wf["5"]["inputs"]["text"] = negative
        wf["7"]["inputs"]["steps"] = settings.flux_steps
        wf["8"]["inputs"]["noise_seed"] = seed
        wf["10"]["inputs"]["cfg"] = settings.flux_cfg
        return wf

    def _sized(self, wf: dict, size: int) -> dict:
        size = _multiple_of_16(size)
        wf["7"]["inputs"]["width"] = size
        wf["7"]["inputs"]["height"] = size
        if "6" in wf:
            wf["6"]["inputs"]["width"] = size
            wf["6"]["inputs"]["height"] = size
        if "15" in wf:
            wf["15"]["inputs"]["width"] = size
            wf["15"]["inputs"]["height"] = size
        return wf

    def _workflow(self, positive: str, negative: str, seed: int) -> dict:
        wf = self._common(json.loads(json.dumps(self.text2img)), positive, negative, seed)
        return self._sized(wf, settings.image_size)

    def _workflow_refine(self, positive: str, negative: str, seed: int,
                         image_name: str, denoise: float, size: int = None) -> dict:
        wf = self._common(json.loads(json.dumps(self.img2img)), positive, negative, seed)
        wf["14"]["inputs"]["image"] = image_name
        wf["17"]["inputs"]["denoise"] = denoise
        return self._sized(wf, size or settings.image_size)


def get_generator():
    if settings.generator_mode != "comfyui":
        return MockGenerator()
    if settings.image_model == "flux2_klein":
        return Flux2KleinGenerator()
    return ComfyUIGenerator()
