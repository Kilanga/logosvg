"""Configuration lue depuis les variables d'environnement (.env)."""
import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def _int(name: str, default: int) -> int:
    return int(os.getenv(name, str(default)))


def _float(name: str, default: float) -> float:
    return float(os.getenv(name, str(default)))


@dataclass(frozen=True)
class Settings:
    api_key: str = os.getenv("API_KEY", "")

    generator_mode: str = os.getenv("GENERATOR_MODE", "mock")
    comfyui_url: str = os.getenv("COMFYUI_URL", "http://127.0.0.1:8188")
    comfyui_checkpoint: str = os.getenv("COMFYUI_CHECKPOINT", "sd_xl_base_1.0.safetensors")
    comfyui_timeout: int = _int("COMFYUI_TIMEOUT", 180)
    image_size: int = _int("IMAGE_SIZE", 1024)

    # Le modèle d'image. `sdxl` (défaut) : workflows sdxl_*.json, un seul fichier
    # checkpoint. `flux2_klein` : FLUX.2 [klein] 4B (Apache 2.0, usage commercial
    # permis), en trois fichiers — modèle, encodeur de texte, VAE — et ses propres
    # workflows flux2_klein*.json. Voir scripts/comparer-modeles.py.
    image_model: str = os.getenv("IMAGE_MODEL", "sdxl")
    flux_unet: str = os.getenv("FLUX_UNET", "flux-2-klein-base-4b-fp8.safetensors")
    flux_text_encoder: str = os.getenv("FLUX_TEXT_ENCODER", "qwen_3_4b.safetensors")
    flux_vae: str = os.getenv("FLUX_VAE", "flux2-vae.safetensors")
    # Le modèle « base » suit le négatif avec un CFG autour de 5, en ~20 pas. La
    # version distillée (flux-2-klein-4b-fp8) va cinq fois plus vite — 4 pas — mais
    # ignore le négatif : FLUX_STEPS=4 et FLUX_CFG=1 avec elle.
    flux_steps: int = _int("FLUX_STEPS", 20)
    flux_cfg: float = _float("FLUX_CFG", 5.0)

    ollama_url: str = os.getenv("OLLAMA_URL", "")
    ollama_model: str = os.getenv("OLLAMA_MODEL", "qwen2.5:3b")

    # Retouches : combien de reprises (variantes ou corrections) par design, et a quel point
    # la retouche s'ecarte de l'image de depart (0 = identique, 1 = image entierement nouvelle).
    # Passe haute définition, pour les techniques matricielles seulement (DTF, DTG,
    # sublimation). SDXL dessine en 1 024 px : à 25 cm de large, cela ne fait que 104 dpi
    # réels, et le fichier serait signalé « définition faible » à chaque commande. Une
    # seconde passe de diffusion agrandit l'image en *dessinant* les pixels manquants au
    # lieu de les interpoler. 1,5 tient confortablement dans 12 Go de VRAM ; 2,0 donne
    # 208 dpi mais frôle la limite. 1,0 désactive la passe.
    hires_scale: float = _float("HIRES_SCALE", 1.5)
    # Ce que la seconde passe a le droit de réinventer : assez pour créer du détail,
    # pas assez pour changer le dessin.
    hires_denoise: float = _float("HIRES_DENOISE", 0.35)

    # Agrandissement par modèle (ESRGAN), après la passe haute définition, pour que
    # le DTF atteigne vraiment la résolution de la technique (300 dpi). Nom d'un
    # fichier de ComfyUI/models/upscale_models ; vide = désactivé. Licence à
    # vérifier : RealESRGAN_x4plus(_anime_6B) est sous BSD, usage commercial
    # permis ; 4x-UltraSharp ne l'est pas.
    upscale_model: str = os.getenv("UPSCALE_MODEL", "")

    # Image de départ fournie par le client (croquis, ancien logo, photo) : à quel
    # point le dessin s'en écarte. Plus haut qu'une retouche (0,55), parce qu'il
    # faut souvent changer de style — d'une photo à des aplats imprimables.
    upload_denoise: float = _float("UPLOAD_DENOISE", 0.7)

    max_refinements: int = _int("MAX_REFINEMENTS", 3)
    max_variants: int = _int("MAX_VARIANTS", 3)
    refine_denoise: float = _float("REFINE_DENOISE", 0.55)

    rate_limit_count: int = _int("RATE_LIMIT_COUNT", 5)
    rate_limit_window: int = _int("RATE_LIMIT_WINDOW_SECONDS", 3600)
    max_queue: int = _int("MAX_QUEUE", 10)
    blocklist_file: Path = Path(os.getenv("BLOCKLIST_FILE", "blocklist.txt"))

    data_dir: Path = Path(os.getenv("DATA_DIR", "data"))
    job_ttl: int = _int("JOB_TTL_SECONDS", 3600)
    max_paths_warning: int = _int("MAX_PATHS_WARNING", 400)


settings = Settings()
