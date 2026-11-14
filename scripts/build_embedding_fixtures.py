"""Labelled headline pairs + the reference cosine similarity of all-MiniLM-L6-v2 for each (data/embedding_fixtures.json).

    pip install sentence-transformers && python3 scripts/build_embedding_fixtures.py

The web (ONNX q8) and iOS (Core ML) embedders are checked against these reference values, and the event/storyline
thresholds are tuned on them. Add pairs freely; `label` is one of same_event, same_story, same_company_other_event,
shared_name, unrelated_sector, unrelated. `company` is the ticker's company, used to prefix headlines that omit it
(must mirror embeddingText in frontend/src/lib/local/embeddings.js).
"""
import json
from pathlib import Path

import numpy as np
from sentence_transformers import SentenceTransformer

PAIRS = [
    ("same_event", "Nvidia", "Nvidia CEO Jensen Huang announces resignation", "Chipmaker's chief executive steps down unexpectedly"),
    ("same_event", "Nvidia", "Nvidia CEO announces surprise resignation", "Chipmaker chief steps down after a decade"),
    ("same_event", "Apple", "Apple beats earnings expectations as iPhone sales surge", "Apple tops Wall Street estimates on strong iPhone demand"),
    ("same_event", "Tesla", "Tesla recalls 200,000 vehicles over software glitch", "Tesla issues recall for 200K cars due to software bug"),
    ("same_event", "Amazon", "Amazon to cut 10,000 corporate jobs", "Amazon plans layoffs of about 10,000 office workers"),
    ("same_event", "Boeing", "Boeing wins $5 billion order from Emirates", "Emirates places multibillion-dollar Boeing jet order"),
    ("same_event", "Microsoft", "Microsoft agrees to buy gaming studio for $2 billion", "Microsoft acquires game developer in $2B deal"),
    ("same_event", "Federal Reserve", "Fed holds interest rates steady, signals cuts later this year", "Federal Reserve leaves rates unchanged, hints at easing ahead"),
    ("same_event", "Pfizer", "Pfizer's weight-loss drug fails late-stage trial", "Pfizer obesity pill misses goal in phase 3 study"),
    ("same_event", "Meta", "Meta fined $1.3 billion by EU over data transfers", "EU regulators hit Meta with record 1.3 billion euro penalty"),
    ("same_event", "JPMorgan", "JPMorgan profit jumps 20% on higher interest income", "JPMorgan quarterly earnings climb a fifth as net interest income rises"),
    ("same_event", "Intel", "Intel delays next-generation chip factory in Ohio", "Intel pushes back Ohio fab opening"),
    ("same_story", "Nvidia", "Nvidia CEO Jensen Huang announces resignation", "Nvidia board appoints interim CEO"),
    ("same_story", "Nvidia", "Nvidia CEO Jensen Huang announces resignation", "Analysts weigh what the CEO exit means for Nvidia's future"),
    ("same_story", "Nvidia", "Nvidia board appoints interim CEO", "Nvidia begins search for permanent chief executive"),
    ("same_story", "Boeing", "Boeing 737 MAX grounded after mid-air panel blowout", "FAA opens investigation into Boeing quality control"),
    ("same_story", "Boeing", "FAA opens investigation into Boeing quality control", "Boeing CEO faces Senate questions over safety lapses"),
    ("same_story", "Tesla", "Tesla recalls 200,000 vehicles over software glitch", "NHTSA opens probe into Tesla software recall"),
    ("same_company_other_event", "Nvidia", "Nvidia posts record data center revenue", "Nvidia CEO Jensen Huang announces resignation"),
    ("same_company_other_event", "Apple", "Apple beats earnings expectations as iPhone sales surge", "Apple faces new EU antitrust probe over App Store"),
    ("same_company_other_event", "Tesla", "Tesla recalls 200,000 vehicles over software glitch", "Tesla opens new factory in Mexico"),
    ("same_company_other_event", "Amazon", "Amazon to cut 10,000 corporate jobs", "Amazon expands same-day delivery to 50 new cities"),
    ("same_company_other_event", "Microsoft", "Microsoft agrees to buy gaming studio for $2 billion", "Microsoft announces new Copilot features for Office"),
    ("same_company_other_event", "Nvidia", "Nvidia posts record data center revenue", "Chipmaker's chief executive steps down unexpectedly"),
    ("shared_name", "Nvidia", "Jensen Huang comments on Nvidia strategy", "Alice Huang faces unrelated legal investigation"),
    ("shared_name", "Tesla", "Elon Musk buys social network", "Elon Musk Foundation donates to school"),
    ("shared_name", "Apple", "Apple Hospitality REIT raises dividend", "Apple unveils new iPhone with improved camera"),
    ("shared_name", "Amazon", "Amazon rainforest fires hit record levels", "Amazon to cut 10,000 corporate jobs"),
    ("unrelated_sector", "Nvidia", "Nvidia posts record data center revenue", "AMD wins major cloud contract"),
    ("unrelated_sector", "Intel", "Intel delays next-generation chip factory in Ohio", "Qualcomm launches new smartphone processor"),
    ("unrelated_sector", "JPMorgan", "JPMorgan profit jumps 20% on higher interest income", "Bank of America to close 100 branches"),
    ("unrelated", "Nvidia", "Nvidia CEO Jensen Huang announces resignation", "Apple unveils new iPhone with improved camera"),
    ("unrelated", "Tesla", "Fed holds rates steady", "Tesla recalls vehicles over software bug"),
    ("unrelated", "Pfizer", "Pfizer's weight-loss drug fails late-stage trial", "Boeing wins $5 billion order from Emirates"),
]


def text(company, headline):  # mirrors embeddingText() in embeddings.js
    return headline if company.lower() in headline.lower() else f"{company}: {headline}"


model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
a = model.encode([text(c, x) for _, c, x, _ in PAIRS], normalize_embeddings=True)
b = model.encode([text(c, y) for _, c, _, y in PAIRS], normalize_embeddings=True)
rows = [{"label": l, "company": c, "a": x, "b": y, "cosine": round(float(np.dot(u, v)), 4)}
        for (l, c, x, y), u, v in zip(PAIRS, a, b)]
out = Path(__file__).resolve().parent.parent / "data/embedding_fixtures.json"
out.write_text(json.dumps({"model": "all-MiniLM-L6-v2", "pairs": rows}, indent=1) + "\n")
print(f"wrote {len(rows)} pairs to {out}")
