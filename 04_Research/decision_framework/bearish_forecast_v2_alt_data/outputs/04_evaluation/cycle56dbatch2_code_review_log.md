# Cycle 56D-Batch2 Codex Code Review Log

Target file: scripts/153_mamba_fedformer_q126.py
Review date: 2026-05-21
Reviewer: Codex (GPT-5.4)

## Bug Check Results (8 categories)

### 1. Mamba state-space causality
- [PASS]: `MambaBlock._selective_scan()` is a forward-only recurrence. The loop at lines 346-355 iterates `t = 0..L-1`, updates `h` from prior `h` plus `x_f32[:, t]`, and emits `y_t` from `C_in[:, t]`; there is no reference to `t+1..L-1`.
- [PASS]: The depthwise 1D conv uses `padding=d_conv - 1` at lines 229-234 and then keeps only `x_in_t[:, :, :L]` at lines 278-280. With PyTorch Conv1d symmetric padding, output index `t` depends on original positions `t-(d_conv-1)..t`, so keeping the first `L` outputs drops the non-causal/right-padded tail and prevents future-position contamination.
- [PASS]: `x_proj` and `dt_proj` are `nn.Linear` maps applied on the last dimension of `(B, L, d_inner)` tensors at lines 316-324, so `delta`, `B_in`, and `C_in` are position-wise functions of the causally-convolved `x_in[t]`.
- [PASS]: `A_log` is stored as `log(A)` at lines 252-256 and materialized as `A = -torch.exp(self.A_log.float())` at lines 312-313, giving a negative real diagonal SSM parameterization.

### 2. FEDformer FFT under AMP
- [CONCERN]: The requested AMP-specific checks pass, but the dynamic top-k mode selection is batch-wide and can leak future OOS feature information across rows.
- [PASS]: `FrequencyEnhancedBlock.forward()` disables autocast around the FFT block with `torch.amp.autocast(device_type=x.device.type, enabled=False)` at line 485.
- [PASS]: The FFT input is cast to fp32 via `x_f32 = x.float()` at line 486 before `torch.fft.rfft()` at line 488 and `torch.fft.irfft()` at line 510.
- [PASS]: DC is excluded by cloning `amp` and setting `amp_clone[0] = -float("inf")` before `torch.topk()` at lines 490-493.
- [PASS]: The complex projection shape is correct: `xf_top` is `(B, modes, D)` at line 496, `w_complex` is `(modes, D, D)` at line 501, and `torch.einsum("bmd,mde->bme", xf_top, w_complex)` at line 503 returns `(B, modes, D)`.
- [FAIL]: `amp = torch.abs(xf).mean(dim=(0, 2))` at line 490 averages over the batch dimension, and `top_idx` at line 493 is then shared by every row in the forward pass. During `predict_oos()`, rows are evaluated in chronological chunks of `bs=256` at lines 943-946, so an earlier OOS row can have its selected frequency modes determined partly by later OOS rows in the same chunk. That makes FEDformer and EW2 OOS predictions batch-composition dependent and not strictly point-in-time.

### 3. Walk-forward 5-fold CV
- [PASS]: The fold entries at lines 120-130 are non-overlapping: each `train_end` is before its corresponding `valid_start`.
- [PASS]: `SKIP_FOLDS_PER_TARGET["y_tail_q126"] = ["Fold3_CyprusTT"]` is defined at lines 133-135 and honored in `run_arch_walkforward()` at lines 1002-1021.
- [PASS]: Sequence-aligned `dates_seq = dates[SEQ_LEN - 1:]` is created at line 775, and both `train_idx` and `valid_idx` use `dates_seq` at lines 780-791.
- [PASS]: The `y_finite` mask is created at line 778 and applied to both `train_idx` and `valid_idx` at lines 780-791.
- [PASS]: Standardization is trained only on `train_mask` in `standardize_for_window()` at lines 710-719; medians, means, and standard deviations are computed from the training window only.

### 4. Logit-collapse + reseed rescue
- [PASS]: `detect_logit_collapse(p)` checks both collapse conditions: `p_max < 1e-4` and `logit_median < -15.0` at lines 745-752.
- [PASS]: With `SEED_BASE = 42` and `RESEED_MAX = 3` at lines 149-151, the final-training loop at lines 1053-1062 tries seeds `[42, 43, 44, 45]` and breaks on the first non-collapsed attempt at lines 1078-1092.
- [PASS]: If all attempts collapse, `selected_oos_pr = None` and `selected_oos_ic = None` are set at lines 1099-1109 for leaderboard exclusion.
- [PASS]: `train_one_window()` calls `set_seed_strict(seed)` at line 772 before standardization, DataLoader creation, and model construction. The reseed loop passes `seed=cur_seed` at line 1061, and a new model instance is created inside `train_one_window()` at line 821.

### 5. Period-balanced PR-AUC
- [PASS]: `period_balanced_metrics()` defines four OOS periods at lines 961-966 and converts incoming `np.datetime64` dates with `pd.to_datetime(dates)` at line 967 before slicing each period at line 970.
- [PASS]: Each segment skips PR/IC calculation when `n_bear < 5` at lines 977-981.
- [PASS]: Segment metrics are computed only on `p_s = p[m]` and `y_s = y[m]` at lines 975-983, not on full OOS arrays.

### 6. Strict determinism
- [PASS]: `CUBLAS_WORKSPACE_CONFIG=':4096:8'` is set at line 57 before `import torch` at line 70.
- [PASS]: `torch.backends.cudnn.deterministic = True` and `torch.backends.cudnn.benchmark = False` are set at lines 92-93.
- [PASS]: `torch.use_deterministic_algorithms(True, warn_only=True)` is called at lines 94-96.
- [PASS]: DataLoader shuffling uses `torch.Generator().manual_seed(seed)` in `make_loader_generator()` at lines 734-737 and passes the generator into `DataLoader` at lines 813-818.
- [PASS]: `set_seed_strict(seed)` is called at the start of `train_one_window()` at line 772.

### 7. PIT integrity
- [CONCERN]: Label/date PIT handling passes, but FEDformer has the batch-wise top-k concern noted in category 2.
- [PASS]: `prepare_data_full()` marks labels invalid when either `ret_col` or `thr_col` is NaN via `label_ok` at lines 686-689, preserving unresolved labels as `NaN`.
- [PASS]: `make_sequences()` uses `np.lib.stride_tricks.sliding_window_view()` at line 615 and aligns labels to the window endpoint with `y[seq_len - 1:]` at line 616.
- [PASS]: `predict_oos()` excludes unresolved OOS labels with `y_finite_oos` and `oos_idx` at lines 930-933.
- [FAIL]: For FEDformer, `FrequencyEnhancedBlock.forward()` selects `top_idx` using a batch mean at lines 490-493. In OOS inference, the prediction batch can include future dates relative to an earlier row, so feature values from later OOS dates can influence the model path taken for earlier OOS dates.

### 8. OOS prediction
- [CONCERN]: OOS date/y alignment is preserved, but FEDformer OOS predictions are batch-composition dependent because of batch-wide frequency selection.
- [PASS]: `predict_oos()` uses `bs = 256` at line 943.
- [PASS]: OOS predictions, labels, and dates are produced from the same `oos_idx` mask at lines 930-956 and stored together in the prediction DataFrame at lines 1128-1138.
- [PASS]: EW2 explicitly checks Mamba/FEDformer OOS date and label alignment before averaging at lines 1291-1294.
- [FAIL]: Because `predict_oos()` evaluates chronological chunks at lines 943-946, FEDformer predictions within a chunk can depend on other rows in that chunk through the batch-wise `top_idx` selection at lines 490-493. Changing `bs` or row ordering can change predictions, which invalidates strict OOS metric interpretation for FEDformer and EW2.

## Critical Bugs Found
- Severity: HIGH / file line 490 / `FrequencyEnhancedBlock.forward()` computes `amp = torch.abs(xf).mean(dim=(0, 2))`, averaging over the batch dimension before selecting Fourier modes. In OOS evaluation, this lets later OOS feature rows influence the selected modes for earlier rows in the same batch. Suggested fix: make mode selection per-sample, or use a fixed non-DC mode set that is independent of evaluation batch contents.
- Severity: HIGH / file lines 943-946 / `predict_oos()` chunks chronological OOS rows with `bs=256`; combined with the batch-wise FEDformer `top_idx`, predictions are batch-size/order dependent. Suggested fix: after fixing FEDformer mode selection, add a regression check that FEDformer predictions are invariant to OOS batch size and row grouping.

## Non-Critical Concerns
- `FOLDS` is implemented as a list of per-fold dictionaries rather than a top-level dictionary at lines 120-130. This does not create overlap or metric leakage because all downstream iteration expects that list shape.
- `period_balanced_metrics()` skips segments with fewer than 5 bear events, and `pr_auc()` can still return `None` for very small total segment sizes because `pr_auc()` also requires at least 30 observations at lines 620-624. This is consistent with the local metric guard and does not mix full-OOS data into segment metrics.

## Overall Verdict
- CODE_APPROVED_WITH_FIXES
- The Mamba causality, split/mask handling, reseed rescue, label masking, determinism, and date-aligned OOS storage checks pass. FEDformer needs a local correctness fix for batch-wise Fourier mode selection before FEDformer or EW2 OOS metrics should be treated as point-in-time valid.

## Optional: Test Patches
Suggested local fix direction for `FrequencyEnhancedBlock.forward()`:

```python
# Current batch-wide mode selection leaks across OOS rows:
# amp = torch.abs(xf).mean(dim=(0, 2))
# top_idx = torch.topk(amp_clone, self.modes).indices

# Safer option: fixed non-DC modes, independent of batch contents.
top_idx = torch.arange(1, self.modes + 1, device=x.device)
xf_top = xf[:, top_idx, :]
```

Suggested regression check:

```python
model.eval()
with torch.no_grad():
    p_full = torch.sigmoid(model(X_oos_t)).cpu().numpy()
    p_chunks = []
    for i in range(0, X_oos_t.size(0), 17):
        p_chunks.append(torch.sigmoid(model(X_oos_t[i:i + 17])).cpu().numpy())
    p_chunks = np.concatenate(p_chunks)
assert np.allclose(p_full, p_chunks, atol=1e-6), "OOS predictions depend on batch grouping"
```

---

## Q-Lead Fix Application (2026-05-21 by Forge agent)

**Bug 1 (HIGH severity)**: ACCEPT — FEDformer `top_idx` batch-wide selection bug confirmed.

**Fix applied** to `153_mamba_fedformer_q126.py::FrequencyEnhancedBlock.forward()`:
- Replaced `amp = torch.abs(xf).mean(dim=(0,2)); top_idx = torch.topk(amp_clone, modes).indices` with `top_idx = torch.arange(1, modes+1, device=x.device)` (FIXED non-DC modes 1..modes).
- Comment added explaining the PIT violation + fix rationale.
- This is a simplification of FEDformer's dynamic mode selection; for L=21 (only 11 non-DC modes) and modes=3, picking 3 lowest-frequency modes captures dominant seasonal structure while guaranteeing batch-independence.

**Bug 2 (HIGH severity)**: RESOLVED by Bug 1 fix — batch-composition dependency eliminated.

**Regression check executed**: smoke test (full vs chunked predictions) confirms FEDformer max|diff|=0.0 (bit-identical) and Mamba max|diff|=2.98e-8 (machine epsilon, expected). Both architectures now batch-invariant.

**Re-launch**: 153 training re-launched with patched FEDformer. Original run killed at ~7:44 elapsed before producing any predictions (only provenance.json saved).

**Final code status**: CODE_APPROVED (all 8 categories PASS post-fix).

---

## Post-Training Outcome (2026-05-21)

Cycle 56D-Batch2 completed successfully on patched code (FEDformer batch-invariance fix applied + verified).

**Final OOS PR-AUC (single seed=42, no reseed rescue triggered)**:

| Architecture | y_tail_q15 | y_tail_q126 |
|---|---|---|
| Mamba | 0.1777 (IC -0.1716) | **0.4265** (IC +0.1613) |
| FEDformer | 0.1750 (IC +0.0147) | 0.2935 (IC +0.0144) |
| EW2 | 0.1559 | 0.3231 |

**Mamba q126 = 0.4265 > 53H PatchTST fair baseline 0.4016 (Δ +0.0249)**
**Verdict: ARCH_BREAKTHROUGH** (> 0.42 threshold).

**Reseed rescue audit**: All 4 archs adopted seed=42 attempt 1 (no logit collapse). No reseed needed (PatchTST 54A collapse pattern NOT observed in Mamba/FEDformer — different inductive bias).

**Sanity check S1**: WARN_HIGH (0.4265 ∈ (0.40, 0.50]) — within strong-signal range but not implausibly high. Mandate cycle 56D-third multi-seed stability test if Q-Lead/도훈 approves promotion.

**Period-balanced caveat**: Mamba q126 single-period dominance by S2020-21 (COVID) lift 2.98 vs S2018-19 lift 0.96 and S2022-24 lift 0.71. NOT 3/3 lift>1 (only 1/3). This is a STABILITY concern for single-seed first-pass — requires multi-seed confirmation.

**FEDformer batch-invariance fix verification**: smoke test post-fix confirmed max|diff|=0.0 between full-batch and chunked-7 predictions (bit-identical, no batch-composition dependency). Mamba also batch-invariant (max|diff|=2.98e-8, machine epsilon).
