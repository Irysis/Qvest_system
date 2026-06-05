# Cycle 56D-prelim Codex Code Review Log

**Date**: 2026-05-21
**Scope**: 코드만 (결과 평가 미포함). DLinear + Informer + TimesNet 1차 구현 검증.
**File reviewed**: `scripts/146_megamulti_3arch_q126.py`
**Codex agent**: codex-companion (gpt-5.3-codex, --wait foreground)
**Codex thread**: 019e47d7-e060-75d1-882b-13b4ddd3a1a5

## Codex verdict

**CODE_FIX_REQUIRED** — DLinear/Informer 핵심 구현은 대체로 OK이나, TimesNet AMP+FFT 경로와 forward-label valid mask가 코드 수정 필요.

## per architecture

### DLinear — PASS
- **line 153** (`SeriesDecomposition`): replicate padding은 관측 window edge만 반복하므로 PIT 위반 없음. DLinear 공식 moving_avg 방식과 정합.
- **line 181** (head): shared channel-independent Linear는 classifier adaptation으로 허용 가능. 엄밀한 forecast DLinear는 seasonal+trend sum 후 output.

### Informer — WARN
- **line 239** (`_prob_QK`): ProbSparse max-mean/top-u 구조는 공식 구현과 대체로 정합.
- **line 247** (sample_idx): `torch.randint`가 eval에서도 호출되어 prediction이 forward-call/chunk RNG에 의존. seed로 run-level 재현은 가능하나 call-level deterministic은 아님. L=21이면 full attention 또는 cached deterministic sample_idx 권장. (단, 본 cycle에서는 run-level seed로 단일 결과 산출이라 acceptable.)
- **line 283** (`_update_context`): `context_in` inplace update는 공식 구현 패턴과 동일. CPU smoke backward PASS.
- **line 337** (distilling): conv1d k=3 + ELU + maxpool stride=2 정합.

### TimesNet — FAIL
- **line 440 + line 735** (CUDA AMP `rfft`): CUDA AMP에서 `rfft`가 fp16으로 들어가면 L=21 non-power-of-2라 실패 가능. PyTorch 문서상 CUDA half FFT는 power-of-2 length 제한. **FFT만 autocast disable + float32 강제 필요**.
- **line 445** (`amp_mean[0]=0`): CPU backward smoke PASS. 그래도 `clone()` 후 수정 권장.
- **line 452** (freq=0 fallback): infinite loop 없음. 단 DC tie 방지를 위해 `-inf` 사용이 더 명확.
- **line 406** (InceptionBlock2D): Inception V1-like 2D conv 정합. C=74는 embed 후 d_model=64이므로 직접 문제 아님. L=21에서 period=21이면 row=1이라 padding 영향은 WARN.

## PIT integrity

- **Forward shift**: `scripts/103_compute_long_horizon_targets.R` line 74의 `shift(..., n=H, type="lead")`는 forward 방향 OK.
- **FAIL (label valid mask)**: line 616/626가 `target_col`만 읽고 `fillna(0)` 처리. 현재 parquet 기준 q126 last valid ret=2025-11-18인데 OOS는 2026-04-30까지라 q126 OOS 108 rows가 unresolved label=0으로 포함됨. → **모든 3 arch에 영향, PR-AUC 부정확**.
- **Walk-forward split**: line 92 split은 53H와 동일. line 632 standardize train window only PASS. Final OOS는 2016-2017 gap으로 purged PASS.
- **WARN**: CV fold train/valid는 인접이라 horizon label embargo는 없음. 53H 동일 패턴이면 PASS, "CV purged" 주장에는 WARN.
- **FFT/ProbSparse PIT**: 둘 다 input window L=21 내부만 사용. Future window 침범 없음.

## numerical / gradient flow

- **Feature NaN** (line 635): median fill, clip, nan_to_num PASS.
- **Label NaN** (line 626): unresolved label masking FAIL → fix 의무.
- **Grad clip** (line 740): unscale 후 clip PASS.
- **AMP scope**: TimesNet FFT만 FAIL. DLinear/Informer는 smoke forward/backward CPU PASS.
- **GPU fraction** (line 73): 0.20 설정 PASS, aggregate 0.90은 fragmentation/OOM margin WARN.
- **EW3** (line 954): 단순 평균. fitted weight가 없어 ensemble 자체 overfit은 낮음. calibration 없음 WARN.

## Patch applied (Forge 2026-05-21 09:15)

### Fix 1: label valid mask (FAIL → PASS)
```python
# In prepare_data_full():
tgt_all = pd.read_parquet(tgt_path)
ret_col = target_col.replace("y_tail_", "ret_")
thr_col = target_col.replace("y_tail_", "q15_thr_")
# Keep label as NaN where forward return is unresolved (last H bus days)
label_ok = tgt_all[ret_col].notna() & tgt_all[thr_col].notna()
tgt = tgt_all[["Date", target_col]].copy()
tgt.loc[~label_ok, target_col] = np.nan
y_raw = panel[target_col].values.astype(np.float32)  # NaN preserved (no fillna)
```

Then in train/valid/oos selection, mask by `np.isfinite(y_seq)`.

### Fix 2: TimesNet FFT AMP disable (FAIL → PASS)
```python
# In fft_topk_periods():
with torch.amp.autocast(device_type=x.device.type, enabled=False):
    xf = torch.fft.rfft(x.float(), dim=1)
    amp = torch.abs(xf).mean(dim=-1)
    amp_mean = amp.mean(dim=0).clone()
    amp_mean[0] = -float("inf")  # exclude DC, -inf for tie safety
    top_freqs = torch.topk(amp_mean, k).indices
    sample_w = F.softmax(amp[:, top_freqs], dim=-1).to(dtype=x.dtype)
```

### Informer non-determinism (WARN — accepted)
- Single-seed first-pass cycle, run-level seed=42 fixed. eval-call sample_idx variance acknowledged but acceptable for first-pass. Multi-seed 56D-second에서 deterministic full attention 변형 검토.

### GPU fraction 0.90 aggregate (WARN — accepted)
- Cycle 54C는 0.30 + 56B/56-2stage는 still pending, 56D=0.20 marginal but acceptable. 실제 OOM 발생 시 retry with 0.15.

## Refs used by Codex

- DLinear official: https://github.com/cure-lab/LTSF-Linear
- Informer paper + ref impl: https://ar5iv.labs.arxiv.org/html/2012.07436 + https://raw.githubusercontent.com/zhouhaoyi/Informer2020/main/models/attn.py
- TimesNet paper + ref impl: https://ar5iv.labs.arxiv.org/html/2210.02186 + https://raw.githubusercontent.com/thuml/Time-Series-Library/main/models/TimesNet.py
- PyTorch rfft docs: https://docs.pytorch.org/docs/2.8/generated/torch.fft.rfft.html

## Overall verdict (post-fix)

**CODE_PASS_WITH_WARN** (post-fix anticipated). Forge applies 2 critical fixes (label valid mask + TimesNet FFT AMP). 2 WARN accepted with rationale.
