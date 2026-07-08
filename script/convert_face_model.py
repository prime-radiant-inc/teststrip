#!/usr/bin/env python3
"""Convert AuraFace-v1 (glint-r100 ArcFace) ONNX to Core ML.

When to use: one-time, to (re)generate the bundled face-recognition model at
sample-data/models/auraface-v1.mlpackage. Run again only when you want a fresh
conversion (e.g. new coremltools) or to re-derive the manifest md5/size.

Why AuraFace: it is a glint-r100 ArcFace whose weights ship under Apache-2.0
(https://huggingface.co/fal/AuraFace-v1), so the converted model is
redistributable in a commercial product — unlike InsightFace's w600k_r50
weights, which are research/non-commercial only.

Requires (in a venv):
    pip install torch coremltools numpy onnx onnx2torch

coremltools 9 dropped direct ONNX conversion, so this routes the ONNX graph
through PyTorch (onnx2torch) and traces it before converting to Core ML.

AuraFace's glintr100.onnx takes input `data` (1x3x112x112, BGR, normalized
(x-127.5)/128) and outputs a 1x512 embedding. This emits an mlpackage with a
112x112 RGB image input; the ImageType `channel_first` + BGR color layout +
scale/bias reproduce the ONNX preprocessing so the Core ML model consumes an
ordinary CGImage.

The script prints the md5 and byte size of the zipped artifact for the download
manifest (sample-data/face-recognition-model.tsv).
"""
import hashlib
import shutil
import urllib.request
import zipfile
from pathlib import Path

import coremltools as ct

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "sample-data" / "models"
OUT_MODEL = OUT_DIR / "auraface-v1.mlpackage"

ONNX_URL = "https://huggingface.co/fal/AuraFace-v1/resolve/main/glintr100.onnx"


def find_onnx() -> Path:
    """Locate AuraFace's glintr100.onnx, downloading it if needed."""
    cache = Path.home() / ".cache" / "auraface"
    cache.mkdir(parents=True, exist_ok=True)
    onnx = cache / "glintr100.onnx"
    if not onnx.exists():
        print(f"downloading {ONNX_URL}")
        urllib.request.urlretrieve(ONNX_URL, onnx)
    return onnx


def convert(onnx_path: Path) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if OUT_MODEL.exists():
        shutil.rmtree(OUT_MODEL)

    import torch
    from onnx2torch import convert as onnx_to_torch

    torch_model = onnx_to_torch(str(onnx_path)).eval()
    example = torch.rand(1, 3, 112, 112)
    with torch.no_grad():
        traced = torch.jit.trace(torch_model, example)

    # ArcFace preprocessing: BGR, (x - 127.5) / 128.  Core ML applies
    # scale*x + bias per channel, so scale = 1/128, bias = -127.5/128.
    image_input = ct.ImageType(
        name="data",
        shape=(1, 3, 112, 112),
        scale=1.0 / 128.0,
        bias=[-127.5 / 128.0] * 3,
        color_layout=ct.colorlayout.BGR,
        channel_first=True,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        minimum_deployment_target=ct.target.macOS14,
    )
    mlmodel.save(str(OUT_MODEL))
    print(f"saved {OUT_MODEL}")


def zip_and_hash() -> None:
    zip_path = OUT_DIR / "auraface-v1.mlpackage.zip"
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(OUT_MODEL.rglob("*")):
            zf.write(path, path.relative_to(OUT_DIR))
    data = zip_path.read_bytes()
    print(f"zip:  {zip_path}")
    print(f"md5:  {hashlib.md5(data).hexdigest()}")
    print(f"size: {len(data)}")


if __name__ == "__main__":
    onnx_path = find_onnx()
    print(f"onnx: {onnx_path}")
    convert(onnx_path)
    zip_and_hash()
