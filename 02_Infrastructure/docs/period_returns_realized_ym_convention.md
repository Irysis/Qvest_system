# period_returns_layer5.csv — realized_ym 라벨 컨벤션 (SOT)

**작성**: forge (measurement) | **2026-06-12** | **상태**: documented (05_Production 미수정, 도훈 confirm 대기)
**적용 대상**: `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv` 및 동일 계보(STR_1715 base `03_period_returns.csv`, ret_L5_V1~V5, ret_orig 컬럼)를 realized_ym 키로 join하는 모든 다운스트림.

---

## 1. 의미론 (semantics)

`realized_ym` 라벨은 **수익이 실제 실현된 달력월보다 +1개월 앞선다**.

> **book label m = 달력월 m−1 에 벌린 수익.**

### 왜 그런가 (anchor-to-anchor period)
백테는 anchor(rebalance) 시점 간 구간 수익을 측정한다:
- period i: 매수 = `start_d` (sig_date i의 첫 영업일), 청산/재평가 = `period_end` (다음 anchor 첫 영업일)
- 수익 구간 = `(start_d, period_end]` ≈ 한 달력월
- PR `date` 컬럼 = **`period_end`** (STR_1715 `run_all.R` L1143: `bt_dates <- as.Date(bt_dt$period_end)`)
- layer5가 `realized_ym = format(period_end, "%Y-%m")` 채택 (`run_layer5_R05_overlay.R` L96-98)

→ 구간 `(start_d, period_end]`의 수익은 대체로 `period_end`의 *전(前)* 달력월에 실현되나, 라벨은 *끝* anchor의 월(`period_end`의 월)을 쓴다. 결과적으로 라벨이 실현월보다 1개월 앞선다.

### 첫 행 정의
| anchor_date (=period_end) | realized_ym | 실제 수익 구간 | 실현 달력월 |
|---|---|---|---|
| 2004-02-02 | 2004-02 | (start_d, 2004-02-02] | ≈ 2004-01 |
| 2004-03-02 | 2004-03 | (2004-02-02, 2004-03-02] | ≈ 2004-02 |

첫 행부터 `realized_ym = 실현월 + 1`.

---

## 2. 증거 (248m, qlead_offset_diag.R / verify_lens4b.R 재현)

```
cor(book_m,     bench_m) = -0.0044   ← 어긋남 (무상관)
cor(book_{m+1}, bench_m) = +0.5707   ← 정렬 복원 (book label m+1 = 달력월 m)
cor(value_m,    bench_m) = +0.5660   ← value는 정상 달력월 (대조군)
```
이벤트: label `2008-10` book +6.69% vs bench −23.13% (Lehman). book의 실제 위기 반응은 label `2008-11`(−1.94%). value/bench는 같은 달력월에 정렬됨.

---

## 3. ★ Downstream Join 규칙 (필수)

`period_returns_layer5` book 시계열을 **달력월-keyed 시계열**(value sleeve forward-return, BM_Ret 월간 compounding, FF5 factor returns 등)과 join할 때:

> **book 라벨을 1개월 당겨 정렬한다: `book label m+1` ↔ `calendar month m`.**

### R 패턴 (corrected/run_blend_corrected.R 구현)
```r
M <- readRDS("aligned_series.rds")   # realized_ym 키 (book offset 상속 상태)
setorder(M, realized_ym); n <- nrow(M)
C <- data.table(
  realized_ym = M$realized_ym[1:(n-1)],
  book_ret    = M$book_ret[2:n],     # ★ book 1개 당김 -> 참 달력월
  value_ret   = M$value_ret[1:(n-1)],
  bench_ret   = M$bench_ret[1:(n-1)]
)
# 마지막 1개월(book m+1 없음) 손실. n -> n-1.
```

### 무엇이 영향받나
| 영향 받음 (보정 필수) | 불변 (라벨 무관) |
|---|---|
| benchmark-상대: IR, TE, beta, cor_to_bm, PORT_t, Active CAGR/MDD | book 단일 시계열: SR, CAGR, MDD, Calmar, Vol, hit_rate |
| 다른 달력월 시계열과의 cor / orthogonality | book NAV 모양 (순서 보존) |
| blend (Return.portfolio book × calendar-sleeve) | admit `sr_realized_share_based` 1.9536 |

---

## 4. 영향 범위 (실측)

| 산출물 | 왜곡 값 | 보정 값 |
|---|---|---|
| production `benchmark_comparison_metrics.json` Active.TE | 0.3025 | **0.1921** |
| production `benchmark_comparison_metrics.json` Active.IR | 1.0505 | **1.3985** |
| book PORT_t (NW lag-3) | (미산출) | **5.998** |
| book beta_to_bm | ≈ −0.004 (artifact) | **0.5959** |
| value_sleeve cor_vs_ret_orig (alpha_validation.json) | −0.042245 | **≈ +0.31** |
| value_sleeve_combination blend best ΔSR | +0.152 (거짓) | **−0.037 (개선 없음)** |

상세: `04_Research/pg2_forensics/realized_ym_offset_report.md` §4 오염 스캔.

---

## 5. 05_Production 수정 제안 (도훈 manual confirm — 본 문서는 documented only, 수정 금지)

1. **저침습 (권고)**: 데이터 유지 + 본 §3 join 규칙을 다운스트림에 강제. corrected/ 가 구현체.
2. **근본 (대규모)**: STR_1715 `run_all.R` L1143을 `period_start` 기반으로 변경 — M4/AR/R05 outer schedule join 키 전면 연쇄 → outer overlay 재실행 + 재검증 동반. 별도 WT.
3. benchmark_comparison_metrics.json Active 블록을 보정값(TE 0.1921 / IR 1.3985)으로 재산출 검토 (Strategy/Benchmark 블록 유지 — 이미 정확).

**비가역 자본·운용 산출물(book_state, admit cert)은 SR/CAGR/MDD가 label-invariant이므로 영향 없음.** 오직 benchmark-상대 진단 지표와 orthogonality 판단만 재검토 대상.

---

## 6. 참조
- `04_Research/pg2_forensics/realized_ym_offset_report.md` + `.json` (forensic 본체)
- `04_Research/composition_search/value_sleeve_combination/qlead_offset_diag.R` (진단 재현)
- `04_Research/composition_search/value_sleeve_combination/corrected/` (보정 재측정)
- STR_1715 `run_all.R` L289-401, L1143, L1233-1242 (provenance)
- `run_layer5_R05_overlay.R` L96-98 (라벨 변환 지점)
