"""Génération d'image : simulation locale ou ComfyUI."""
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

WORKFLOW_PATH = Path(__file__).resolve().parent.parent / "workflows" / "sdxl_flat.json"


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


class ComfyUIGenerator:
    """Envoie le workflow SDXL à ComfyUI et récupère l'image produite."""

    def __init__(self):
        self.template = json.loads(WORKFLOW_PATH.read_text(encoding="utf-8"))

    def _workflow(self, positive: str, negative: str, seed: int) -> dict:
        wf = json.loads(json.dumps(self.template))
        wf["3"]["inputs"]["seed"] = seed
        wf["4"]["inputs"]["ckpt_name"] = settings.comfyui_checkpoint
        wf["5"]["inputs"]["width"] = settings.image_size
        wf["5"]["inputs"]["height"] = settings.image_size
        wf["6"]["inputs"]["text"] = positive
        wf["7"]["inputs"]["text"] = negative
        return wf

    async def generate(self, positive: str, negative: str, seed: int, colors: int) -> bytes:
        payload = {"prompt": self._workflow(positive, negative, seed), "client_id": uuid.uuid4().hex}
        deadline = time.monotonic() + settings.comfyui_timeout
        try:
            async with httpx.AsyncClient(base_url=settings.comfyui_url, timeout=30) as client:
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


def get_generator():
    if settings.generator_mode == "comfyui":
        return ComfyUIGenerator()
    return MockGenerator()
