# Research: existing human-labeled datasets for judge-vs-human kappa validation

## Summary

Judge-vs-human Cohen's kappa (Phase G) does not require new manual annotation. Two existing public datasets cover this need at different fidelity levels. ASSET is the immediate no-cost calibration set: general-domain and downloadable today, with clean multi-axis human ratings. PLABA's TREC shared-task human evaluations are the stronger, health-domain option, though whether they can be downloaded at item level still needs a direct data-acquisition check.

## Sources

- [ASSET](https://github.com/facebookresearch/asset) (Alva-Manchego et al., 2020) - `asset/ratings` config, 4,500 human ratings, fields: `aspect` (meaning preservation, fluency, simplicity), `original`, `rating`, `simplification`, `worker_id`. Also on HuggingFace and TFDS (`tfds.datasets.asset`).
- [PLABA corpus](https://www.nature.com/articles/s41597-023-02879-0) (Attal et al., Nature Sci Data 2023) and the TREC PLABA shared task (2023, 2024): `trec.nist.gov/data/plaba.html`, `github.com/HECTA-UoM/PLABA-MU`, `github.com/HECTA-UoM/PLABA2024`. 12 teams, 38 system runs, scored by biomedical experts on accuracy, completeness, simplicity, brevity. Per-system average scores are public in participant papers (e.g. BoschAI@PLABA2023, MALEI@PLABA2024). The track overview (arXiv:2507.14096) references per-sentence raw judgments, but item-level public release is unconfirmed from search alone.
- [SimpEval](https://github.com/Yao-Dou/LENS) (Maddela et al., ACL 2023, LENS's training data) - SimpEval_past (~12K ratings, 2.4K simplifications, 24 systems), SimpEval_2022 (1K+ ratings, 360 simplifications, includes GPT-3.5 output). Rank-and-Rate format, needs massaging into per-item axis scores. A follow-up paper (arXiv:2504.09394) reports low inter-annotator reliability (ICC roughly 0.2-0.3), a real caveat before treating it as unimpeachable gold truth.
- Med-EASi (`github.com/Chandrayee/CTRL-SIMP`, `huggingface.co/datasets/cbasu/Med-EASi`) - only has a small internal 2-3-rater check of the authors' own model output rather than a redistributable per-item human-rating file, which makes it a weak fit here.
- Cochrane PLS - no public per-item human quality rating dataset found. Related primary studies exist (a 2025 trial protocol, a 2026 crowdsourced-evaluation paper) but no confirmed data release. Not usable now.

## Recommendation

1. Use ASSET as the primary, zero-friction judge calibration set. Downloadable today, clean three-axis fields matching the simplicity/fidelity/fluency rubric already in the plan. Compute judge-vs-human kappa against it as a general-domain construct-validity check built on ratings that already exist.
2. Pursue PLABA's TREC track data as the domain-relevant check. Check `trec.nist.gov/data/plaba.html` directly for a per-sentence judgment file, or contact the track organizers if only system-level averages are public. Acquiring it is a download-or-request job, which keeps the effort in data engineering where it belongs.
3. Treat SimpEval as a fallback second general-domain set if a larger sample is wanted, with the ICC caveat noted in the plan/scratchpad.
4. Drop Med-EASi and Cochrane PLS as human-rating sources. Neither has a usable released dataset for this purpose.
5. Treat new manual annotation as a fallback. Reach for it only if the PLABA item-level request fails and ASSET/SimpEval coverage of the health domain is judged too thin, and even then as a small supplementary batch rather than a full label set.

This changes Phase G's corpus dependency from "hand-label 30-50 items" to "download ASSET, request/verify PLABA TREC per-item judgments," which fits the stated preference: data acquisition isn't the constraint, so don't substitute manual labor for it.
