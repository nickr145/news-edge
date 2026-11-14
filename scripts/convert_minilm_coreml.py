"""Convert sentence-transformers/all-MiniLM-L6-v2 to Core ML for the iOS app (run once; needs torch + coremltools).

    python3.12 -m venv /tmp/mvenv && /tmp/mvenv/bin/pip install torch==2.5.1 coremltools transformers==4.46.3 "numpy<2" huggingface_hub
    /tmp/mvenv/bin/python scripts/convert_minilm_coreml.py

Writes ios/NewsEdge/NewsEdge/Resources/MiniLM.mlpackage (gitignored; ships as a release asset like FinBERT, see
package_finbert_model.py). Mean pooling over the attention mask and L2 normalisation are part of the model, so the
output "embedding" (1 x 384) is already unit length. MiniLM uses the same uncased BERT vocabulary as FinBERT, so the
app reuses finbert_vocab.txt for tokenizing. Validated against the reference cosines in data/embedding_fixtures.json.
"""
import json
import shutil
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

MODEL = "sentence-transformers/all-MiniLM-L6-v2"
SEQ_LEN = 64  # must match SentenceEmbedder.sequenceLength in Swift (and config.embedding.max_tokens)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ios/NewsEdge/NewsEdge/Resources"

tok = AutoTokenizer.from_pretrained(MODEL)
model = AutoModel.from_pretrained(MODEL, torchscript=True).eval()


class Embed(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, input_ids, attention_mask):
        hidden = self.m(input_ids=input_ids, attention_mask=attention_mask)[0]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(pooled, dim=-1)


ids = torch.zeros(1, SEQ_LEN, dtype=torch.long)
traced = torch.jit.trace(Embed(model), (ids, ids))
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType("input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
        ct.TensorType("attention_mask", shape=(1, SEQ_LEN), dtype=np.int32),
    ],
    outputs=[ct.TensorType("embedding")],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
)
mlmodel = cto.linear_quantize_weights(
    mlmodel, cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric"))
)
OUT.mkdir(parents=True, exist_ok=True)
pkg = OUT / "MiniLM.mlpackage"
shutil.rmtree(pkg, ignore_errors=True)
mlmodel.save(str(pkg))
# The default (GPU/ANE) compute path fails to compile the pooled graph on some macOS builds; headlines are tiny, so the
# app and this check both run on the CPU.
mlmodel = ct.models.MLModel(str(pkg), compute_units=ct.ComputeUnit.CPU_ONLY)


def embed(text):
    enc = tok(text, padding="max_length", truncation=True, max_length=SEQ_LEN, return_tensors="np")
    return mlmodel.predict({"input_ids": enc["input_ids"].astype(np.int32),
                            "attention_mask": enc["attention_mask"].astype(np.int32)})["embedding"][0]


def text(company, headline):  # mirrors embeddingText() in the clients
    return headline if company.lower() in headline.lower() else f"{company}: {headline}"


pairs = json.loads((ROOT / "data/embedding_fixtures.json").read_text())["pairs"]
worst = 0.0
for p in pairs:
    a, b = embed(text(p["company"], p["a"])), embed(text(p["company"], p["b"]))
    worst = max(worst, abs(float(a @ b) - p["cosine"]))
print(f"{len(pairs)} fixture pairs: max |coreml cosine - reference| = {worst:.4f}")
