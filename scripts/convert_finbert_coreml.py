"""Convert ProsusAI/finbert to Core ML for the iOS app (run once; needs torch + coremltools).

    python3.12 -m venv /tmp/cvenv && /tmp/cvenv/bin/pip install torch==2.5.1 coremltools transformers==4.46.3 "numpy<2"
    /tmp/cvenv/bin/python scripts/convert_finbert_coreml.py

Writes ios/NewsEdge/NewsEdge/Resources/{FinBERT.mlpackage,finbert_vocab.txt}.
The .mlpackage is gitignored (too big for GitHub); the app falls back to NLTagger without it.
Output probs order: [positive, negative, neutral] (ProsusAI id2label).
"""
import shutil
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
from huggingface_hub import hf_hub_download
from transformers import AutoModelForSequenceClassification, AutoTokenizer

MODEL = "ProsusAI/finbert"
SEQ_LEN = 64  # headlines are short; must match FinBERTScorer.sequenceLength in Swift
OUT = Path(__file__).resolve().parent.parent / "ios/NewsEdge/NewsEdge/Resources"

tok = AutoTokenizer.from_pretrained(MODEL)
model = AutoModelForSequenceClassification.from_pretrained(MODEL, torchscript=True).eval()


class Probs(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, input_ids, attention_mask):
        return torch.softmax(self.m(input_ids=input_ids, attention_mask=attention_mask)[0], dim=-1)


ids = torch.zeros(1, SEQ_LEN, dtype=torch.int32)
traced = torch.jit.trace(Probs(model), (ids.long(), ids.long()))
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType("input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
        ct.TensorType("attention_mask", shape=(1, SEQ_LEN), dtype=np.int32),
    ],
    outputs=[ct.TensorType("probs")],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
)
# 8-bit weights: ~4x smaller than fp32 with negligible accuracy loss (validated below).
mlmodel = cto.linear_quantize_weights(
    mlmodel, cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric"))
)
OUT.mkdir(parents=True, exist_ok=True)
pkg = OUT / "FinBERT.mlpackage"
shutil.rmtree(pkg, ignore_errors=True)
mlmodel.save(str(pkg))
shutil.copy(hf_hub_download(MODEL, "vocab.txt"), OUT / "finbert_vocab.txt")

# Validate against the PyTorch model.
headlines = [
    "Apple beats earnings expectations as iPhone sales surge",
    "Apple shares fall after regulators announce antitrust probe",
    "Apple to hold annual developer conference in June",
    "Tesla recalls 200,000 vehicles over safety defect",
    "Nvidia stock jumps on record data center revenue",
]
worst = 0.0
for h in headlines:
    enc = tok(h, padding="max_length", truncation=True, max_length=SEQ_LEN, return_tensors="pt")
    ref = torch.softmax(model(**enc)[0], dim=-1)[0].detach().numpy()
    got = mlmodel.predict({"input_ids": enc["input_ids"].numpy().astype(np.int32),
                           "attention_mask": enc["attention_mask"].numpy().astype(np.int32)})["probs"][0]
    worst = max(worst, float(np.abs(ref - got).max()))
    print(f"{h[:55]:55s} ref={np.round(ref, 3)} coreml={np.round(got, 3)}")
print("max abs prob diff:", round(worst, 4))
