# Research: Bumblebee (native Elixir) vs Python sidecar for model-based metrics

## Summary (revised after pressure-test pass)

First pass concluded: 2 of 5 metrics native (SummaC, BERTScore), 2 behind a Python sidecar (LENS, QAFactEval), SLE dropped as unavailable. A deeper pressure-test pass corrected two of those four claims:

- SLE is available. The earlier "no public code" finding came from the anonymized OpenReview submission copy rather than the published artifact. The real paper (Cripwell et al., EMNLP 2023) comes with a working pip package and an HF checkpoint. It should stay in scope, and its checkpoint (RoBERTa-base plus a linear regression head) ports to Bumblebee with little effort.
- QAFactEval stays, and the "not worth porting" claim was overstated. Both QAFactEval's own paper and the TRUE benchmark (with later factuality-metric work agreeing) find that QA-based and NLI-based (SummaC) metrics catch different error classes. QA-based metrics are better at localizing entity/number-level omissions, which is this project's central risk (dropped dosage/contraindication content). Its actual architecture (T5 question generation, extractive QA, a single linear layer on BERT's `[CLS]` for the LERC-QUIP classifier) maps directly onto Bumblebee task shapes already implemented (`Bumblebee.Text.generation`, `Bumblebee.Text.question_answering`). Estimated port effort: 4-7 days.
- LENS should still be dropped, but for a different reason than portability: its distinguishing signal (better correlation with human simplicity/quality judgment than SARI) duplicates the readability axis already covered by FK, SMOG, sentence-length, and grade-band, and it does not target factual omission at all. A port would take only 2-4 days, so what kills it is redundancy.

Net effect: the Python sidecar is no longer necessary at all. All four kept metrics (SummaC, BERTScore, SLE, QAFactEval) map to Bumblebee task shapes already implemented in the library. Phase M (the FastAPI sidecar) can be eliminated from Phase 1 scope.

## Sources

### Bumblebee capability

- [Bumblebee hexdocs](https://hexdocs.pm/bumblebee/Bumblebee.Text.html) - `text_embedding`, `cross_encoding`, `zero_shot_classification`, `question_answering`, `generation` tasks, EXLA-backed
- [Bumblebee GitHub](https://github.com/elixir-nx/bumblebee) - supported architectures (BERT, RoBERTa, E5, T5, ModernBERT, cross-encoders, BART-MNLI)
- `lib/bumblebee/text/t5.ex` - native T5 encoder-decoder module, used for question generation

### Metric internals and availability

- [SummaC](https://github.com/tingofurro/summac) (arXiv:2111.09525) - standard RoBERTa MNLI/SNLI checkpoint, softmax over 3 logits
- [LENS](https://github.com/Yao-Dou/LENS) (arXiv:2212.09739) - copies COMET's code per its own README; scoring head is a `FeedForward` stack (`Linear -> Tanh -> Dropout`, ending `Linear(hidden, 1)`) plus a learned layer-mix (`LayerwiseAttention`), both small and inference-only
- [Unbabel/COMET](https://github.com/Unbabel/COMET) - `ranking_metric.py`, `feedforward.py` - source of LENS's head architecture
- [QAFactEval](https://github.com/salesforce/QAFactEval) (arXiv:2112.08542) - T5 question gen, extractive QA, LERC-QUIP answerability classifier
- MOCHA repo `lerc_model.py` - LERC-QUIP's actual architecture: `BertModel` plus `[CLS]` embedding plus one `Linear(embedding_dim, 1)`, MSE loss
- [SLE](https://github.com/liamcripwell/sle), [HF checkpoint](https://huggingface.co/liamcripwell/sle-base) (Cripwell et al., EMNLP 2023, ACL Anthology 2023.emnlp-main.739) - RoBERTa-base plus regression head, MIT license, public and pip-installable
- On whether QAFactEval adds signal beyond SummaC, the QAFactEval paper (Fabbri et al., NAACL 2022) states QA-based and entailment-based metrics "offer complementary signals". The TRUE benchmark (Honovich et al., NAACL 2022) independently confirms "complementary results", and arXiv:2409.15090 (2024) finds similarity-based metrics "make different errors to QA and NLI-based metrics".
- On LENS, Cripwell et al. (arXiv:2404.03278, READI 2024) show SARI and LENS both collapse simplicity and meaning-preservation into one score. Devaraj et al. (PMC9671157) find SARI has near-zero, sign-inconsistent correlation with human-annotated information errors (omission/insertion/substitution).
- PlainQAFact (You & Guo, arXiv:2503.08890, in press J. Biomedical Informatics 2026) - health-domain-specific finding that both SummaC-family and QAFactEval-family metrics misflag legitimate elaborative explanation as hallucination in plain-language rewrites (calibration caveat below)

## Recommendation (revised)

Drop the Python sidecar (Phase M) from Phase 1 scope entirely. Implement all four kept metrics as native `MetricProvider.Bumblebee` adapters:

1. **SummaC** - `cross_encoding` or `zero_shot_classification` over a standard RoBERTa MNLI/SNLI checkpoint, the simplest of the four.
2. **BERTScore** - `text_embedding` (E5/BERT/RoBERTa) plus a hand-rolled aggregation (pairwise cosine, greedy max per token, precision/recall/F1) that fits in a few dozen lines.
3. **SLE** - load `liamcripwell/sle-base` (RoBERTa-base plus linear regression head) via Bumblebee's standard text-classification/embedding path. The load is easy and it fills a real gap: no other metric here is both reference-less and simplification-specific, so it catches degenerate or infantilizing over-simplification that FK/SARI cannot (a sentence can score maximally simple by FK while reading as garbled or patronizing).
4. **QAFactEval** - `generation` (T5 question gen, native module already exists) plus `question_answering` (native task) plus a small ported linear head for LERC-QUIP (copy weights from a standard BERT `[CLS]`-plus-linear classifier). Estimated 4-7 days: three checkpoints to convert/validate, each mapping to an already-implemented Bumblebee task shape. Keep it because it's the single most relevant metric to this project's stated risk (safety-critical content omission) and it complements SummaC instead of duplicating it.

Drop **LENS**: it is portable (2-4 days) but its signal duplicates FK/SMOG/SARI already in Phase B/F, and it does not address the omission-safety axis. It gets cut for redundancy even though the port is feasible.

This removes the "two runtimes forever" operational cost entirely: there is no FastAPI service to run and no container or version-drift surface to babysit. All model inference lives in the BEAM via Nx/EXLA, sharing a single deploy artifact with the rest of the app.

## Watch out for

- Bumblebee requires the HF checkpoint to include a fast tokenizer (`tokenizer.json`). Some older checkpoints only have Python tokenizer configs and would need re-export first.
- EXLA compiles on first inference (5-30s warm-up), fine for a batch eval run, but worth knowing if wiring into a live request path.
- Reproducing "published numbers" still requires pinning the exact same HF checkpoint id the papers used, native or sidecar. That reproducibility requirement from the plan's original Phase M note doesn't go away.
- LENS's and QAFactEval's actual checkpoint formats are PyTorch-Lightning `.ckpt` files, not clean HF repos. A one-time Python conversion script (split into encoder weights plus small head weights) is needed regardless of which metrics get ported. Verify numerical parity against reference scores afterward. That conversion is the only Python dependency left.
- PlainQAFact's finding applies regardless of native-vs-sidecar: both SummaC-family and QAFactEval-family metrics misflag legitimate elaborative explanation (background/definitions the plain-language rewrite legitimately adds) as hallucination. Plan to spot-check and calibrate against health-domain output rather than trust either verdict blindly. This is a scoring-calibration task that applies to Phase G/H regardless of which decision is made here.
- Memory/compute footprint: running 4 model checkpoints (SummaC's RoBERTa, BERTScore's embedding model, SLE's RoBERTa, QAFactEval's T5+QA+BERT trio) inside the BEAM app adds real memory pressure to whatever process boots them. Worth a boot-time budget check before committing, especially if deploying to a small instance.
