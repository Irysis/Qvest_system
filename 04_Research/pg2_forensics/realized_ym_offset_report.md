# realized_ym Label Offset — Forge Forensic Report

**Agent**: forge (measurement) | **Date**: 2026-06-12 | **Type**: non-WT measurement-defect tracking
**Scope**: tracking + documentation + corrected re-measurement only. **No 05_Production modification** (fix proposals are flagged for 도훈 manual confirm).

---

## 1. 의미론 확정 — realized_ym = 1-month label offset (컨벤션 결함, 데이터/계산은 정확)

### 1.1 결론 (한 줄)
`period_returns_layer5.csv`의 `realized_ym` 라벨은 **실제 수익 실현 달력월보다 +1개월 앞선 라벨**이다. 즉 **book label m = 달력월 m−1에 벌린 수익**. 이는 순수 **라벨링 컨벤션 결함**이며, 수익값 자체·시계열 순서·SR/CAGR/MDD/Calmar는 **불변(정확)**. 벤치마크-상대 지표(IR/TE/beta/cor/PORT_t)와 다른 달력월-keyed 시계열과의 join만 왜곡된다.

### 1.2 코드 인용 (provenance chain, 3-hop)

**Hop 1 — STR_1715 base PR `date` = period_end (period 끝 anchor)**
`04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/run_all.R`:
```r
L289:  sig_label <- sig_dates[i]                          # period i 결정월 (예: 2004-02-01)
L291:  start_d   <- min(raw[Date >= sig_label]$Date)       # 첫 영업일 (예: 2004-02-02) = 매수 시점
L293-298: end_d  <- min(raw[Date >= next_sig_label]$Date)  # 다음 anchor 첫 영업일 (예: ~2004-03-02)
L354:  period_data <- raw[Date > start_d & Date <= end_d]   # 수익 구간 = (start_d, end_d]  ← 다음 달
L391-393: period_start = start_d, period_end = end_d, port_ret = port_ret_net
...
L1143: bt_dates <- as.Date(bt_dt$period_end)               # ★ PR date 컬럼 = period_end (= end_d)
L1233-1242: fwrite(data.table(... date = bt_dates ...), "03_period_returns.csv")
```
즉 PR row의 `date`(= period_end)에는 **그 직전 구간 (start_d, period_end]에 벌린 수익**이 담긴다. 수익은 대체로 `period_end`의 *전(前)* 달력월에 실현되나, `date`는 *끝* anchor(period_end)의 월을 가리킨다.

**Hop 2 — Layer5 production이 PR date를 그대로 realized_ym으로 변환**
`05_Production/.../01_reproducible_code/run_layer5_R05_overlay.R` (Read 도구로 확인):
```r
L87-89:  pr <- fread(pr_path); pr[, date := as.Date(date)]; pr[, ym := format(date, "%Y-%m")]
L96-98:  panel <- pr[, .(date = date, realized_ym = ym, ret_orig = ret_net, ...)]
L313:    panel[, anchor_date := date]                       # anchor_date = period_end
```
→ `realized_ym = format(period_end, "%Y-%m")`. period_end-anchored 구간 수익이 period_end의 월 라벨을 받음.

**첫 행 정의 (anchor 2004-02-02, realized_ym 2004-02)**: 이 행의 수익은 (start_d, 2004-02-02] 구간 ≈ **2004년 1월** 수익이나 라벨은 `2004-02`. 따라서 첫 행부터 label = 실현월 + 1.

**Hop 3 — value/bench는 정상 달력월 keyed → 불일치 발생**
`04_Research/composition_search/value_sleeve_combination/run_blend.R`:
```r
# value sleeve: sig_date EOM → 다음 달 forward return을 그 다음 달로 라벨 (정상 달력월)
L84-86:  sleeve <- merge(sleeve, next_map[...]); sleeve[, realized_ym := <ym_next>]
# bench: BM_Ret를 해당 달력월에 compounding (정상 달력월)
L109-111: bmret <- bm[, .(bm_mret = prod(1+BM_Ret)-1), by=ym]; bmret[, realized_ym := <ym>]
# book: ret_L5_V2를 production realized_ym 키로 join (offset 라벨 그대로 상속)
L102-104: book_v <- book[, .(realized_ym, book_ret = ret_L5_V2)]
```
value·bench는 실현 달력월, book은 +1 offset 라벨 → realized_ym join 시 book이 1개월 어긋남.

### 1.3 실증 (재현 가능: `value_sleeve_combination/qlead_offset_diag.R`, 248m aligned_series.rds)
```
cor(book_m, bench_m)      = -0.0044     ← 어긋난 조합 (≈ 무상관)
cor(book_{m+1}, bench_m)  = +0.5707     ← book label m+1 = 달력월 m (정렬 복원)
cor(value_m, bench_m)     = +0.5660     ← value는 달력월 정상 (대조군)
cor(value_m, book_m)      = -0.0455     ← Stage1 사용치 (아티팩트)
cor(value_m, book_{m+1})  = +0.3132     ← 보정 정렬 시 (참값)
```
**이벤트 증거 (Lehman, label 기준)**: label `2008-10` book **+6.69%** vs bench **−23.13%** — book이 위기에 +6.7% 번 게 아니라, 라벨이 1개월 앞서 09월(평온) 수익을 10월 라벨에 붙인 것. book의 실제 Lehman 반응은 label `2008-11`(−1.94%)·`2008-12`에 위치. value(−0.3884 @label 2008-10)와 bench(−0.2313)는 같은 달력월에 정렬 → 이 둘만 정상.

### 1.4 admit SR 영향 없음 확인
SR/CAGR/MDD/Calmar는 단일 시계열 내 통계(라벨 순서 보존, 시점 이름만 +1 shift) → **label-invariant**. admit `sr_realized_share_based = 1.9536` (255m), `benchmark_comparison_metrics.json` Strategy.SR 1.9536 / CAGR 0.415 / MDD 0.2481 = **전부 유효**. **벤치-상대 지표(Active TE/IR)만 왜곡** (§3).

**판별 결과: 라벨 컨벤션 문제 (데이터·계산 정확). 계산 버그 아님.**

---

## 2. 보정 book benchmark-상대 지표 (corrected/run_blend_corrected.R, contract build_benchmark_compare 경유)

보정: book label을 1개 당겨 (`book_true[m] = book_ret[m+1]`) value/bench(달력월)와 정렬. 마지막 1개월(book m+1 없음) 손실 → n 248→247m (2005-09..2026-03). metric_type=`backtested`.

| 지표 | production benchmark_comparison_metrics.json (왜곡) | 보정 정렬 (참값) | 진단 |
|---|---|---|---|
| Active TE | **0.3025 (30.25%)** | **0.1921 (19.21%)** | +57% 과대 (offset이 active를 noise spread로 만듦) |
| Active IR | **1.0505** | **1.3985** | −33% 과소 |
| PORT_t (NW lag-3) | — (미산출) | **5.998** | lens-4 추정 ~6.0 검증 ✓ |
| Beta_to_BM | (artifact −0.004) | **0.5959** | offset이 beta를 0 근처로 붕괴시킴 |
| cor_to_BM | (artifact −0.004) | **0.5707** | 실제 시장 노출 0.57 |
| book SR | 1.9536 (255m) / 1.9175 (248m artifact) | 1.9005 (247m) | label-invariant, 표본·기간 차이만 |
| book MDD | 0.2481 | 0.2481 | 불변 ✓ |

lens-4 잠정치 **검증**: IR ~1.40 ✓ (1.3985), PORT_t ~6.0 ✓ (5.998), 기존 TE 30.25% 과대 ✓ (참값 19.21%).

**production benchmark_comparison_metrics.json은 Active 블록(TE/IR/HitRate/MDD_active)이 offset 왜곡 상태.** Strategy/Benchmark 블록(절대지표)은 유효. → **수정 제안만, 수정 금지** (§6).

---

## 3. ★ Stage 1 blend 보정 재측정 — 도훈 질문 "value 조합 시 개선되는가" 재답

corrected/results_corrected.csv. book-only(corrected) baseline: SR 1.9005 / MDD 0.2481 / Calmar 1.6210 / IR 1.3985 / PORT_t 5.998. 동일 사전등록 grid·동일 방법(Return.portfolio months + sleeve-rebal 15bps).

| w_value | SR | ΔSR | MDD | ΔMDD | Calmar | ΔCalmar | IR | ΔIR | PORT_t | blend TO/yr |
|---|---|---|---|---|---|---|---|---|---|---|
| **0.00 (book)** | 1.9005 | — | 0.2481 | — | 1.6210 | — | 1.3985 | — | 5.998 | — |
| 0.05 | 1.8988 | **−0.0017** | 0.2360 | −0.0120 | 1.6570 | +0.0360 | 1.4162 | +0.0177 | 6.099 | 7.1% |
| 0.10 | 1.8869 | **−0.0136** | 0.2239 | −0.0241 | 1.6969 | +0.0759 | 1.4289 | +0.0304 | 6.176 | 13.5% |
| 0.15 | 1.8637 | **−0.0368** | 0.2118 | −0.0363 | 1.7411 | +0.1201 | **1.4345** | **+0.0360** | 6.218 | 19.2% |
| 0.20 | 1.8285 | **−0.0720** | 0.1995 | −0.0486 | 1.7900 | +0.1689 | 1.4311 | +0.0326 | 6.214 | 24.1% |
| 0.30 | 1.7213 | **−0.1792** | 0.2438 | −0.0042 | 1.3682 | −0.2528 | 1.3889 | −0.0096 | 6.024 | 31.7% |

### 보정 전(아티팩트) vs 보정 후 대비
| 항목 | 아티팩트 (results.csv, INVALIDATED) | 보정 (참값) |
|---|---|---|
| cor(value, book) | −0.0455 (직교 착시) | **+0.3132** (양의 상관) |
| best ΔSR (sweep argmax IR) | +0.152 (w=0.20) | **−0.0368 (w=0.15)** / 모든 w에서 ΔSR ≤ 0 |
| best ΔIR | +0.025 | +0.036 (여전히 0.05 hurdle 미달) |
| best ΔCalmar | +0.142 | +0.120 (w=0.15) |
| 결론 | "조합 시 SR +0.15 개선" (거짓) | "SR 개선 없음, MDD/Calmar만 한계개선" |

### 도훈 질문 재답 (AX-000 정직보고, 미화 없음)
**아니오 — value sleeve 조합은 위험조정성과(SR)를 개선하지 않는다.** 보정 정렬에서 cor(value, book) = **+0.31** (직교 아님 — 둘 다 KR long-only로 시장 1st eigenmode 공유, 헌법 §6 "수익률직교 구조적 불가" 재확인). 분산효과가 SR 축에서 **소멸**: 모든 w_value에서 ΔSR ≤ 0 (w=0.20 −0.072). 

남는 한계 효익은 **MDD/Calmar**뿐 — w=0.15에서 MDD −3.6pp(0.248→0.212), Calmar +0.120. IR도 +0.036(w=0.15)로 양수이나 **admission book-marginal hurdle ΔIR ≥ 0.05 미달**. blend TO도 종목수 union > 25 (admission max 25 위반)로 연구단계 보고만.

**판정: book-marginal 부적격 (ΔIR 0.036 < 0.05, ΔSR < 0). 졸업/편입 권고 불가.** 아티팩트가 보여준 "+0.15 SR 개선"은 offset이 만든 가짜 직교성의 산물이었다.

---

## 4. 오염 범위 스캔 (보고만, 수정 금지)

realized_ym(또는 period_end-anchored book 시계열)을 **달력월-keyed 다른 시계열과 join**한 산출물:

| 산출물 | 오염 여부 | 영향 받는 값 | 비고 |
|---|---|---|---|
| `value_sleeve_combination/results.csv` + `blend_result.json` | **오염** | book IR/TE/beta/cor_bm, 모든 blend dSR/dMDD/dIR | INVALIDATED 마커 추가됨. corrected/ 참조 |
| `value_sleeve_combination/aligned_series.rds` | **오염 (입력)** | realized_ym join 산물 | 보정본 corrected/aligned_series_corrected.rds 생성 |
| `04_Research/strategies/STR_WT-D20260611_001_value_sleeve/alpha_validation.json` | **오염** | `cor_vs_ret_orig = -0.042245` | 보정 시 ≈ +0.31. "직교 axis" 결론 무효 |
| `stage_artifacts/WT-D20260611_001/alpha_validation.json` | **오염** | `cor_vs_ret_orig = -0.042245` (동일) | 위와 동일 알파의 stage artifact 사본 |
| `stage_artifacts/WT_WT-D20260610_001/alpha_validation.json` | **오염** | `orthogonality_vs_book.cor_net = -0.0346`, `cor_active = -0.0392` | book_base = period_returns_layer5 ret_orig. "Strongly orthogonal" 결론 무효 (보정 ≈ +0.31). book-marginal escalation note도 영향 |
| `stage_artifacts/WT_D20260515_002/alpha_validation.json` | **오염 가능** | "realized_ym ↔ ym_signal anchor align" (ret_L5_V1 기준) | alpha_overlap 60m 표본. ret_L5_V1도 동일 offset 라벨 → 재검토 권고 |
| `04_Research/pg2_forensics/b1_*` (family attribution / IC / ablation) | **비오염** | — | 모두 factor panel/alpha_scores에서 forward Ret_1m을 **네이티브 재구성** (book CSV join 없음). rank-IC·inter-factor·inter-variant corr는 자기 시계열 내 정렬 → offset 무관 |
| `04_Research/pg2_forensics/b2_governor_overlap.json` | **비오염** | — | regime severity overlap (M4/AR/R05 신호 동월 정렬), book-vs-calendar join 아님 |
| production `benchmark_comparison_metrics.json` Active 블록 | **오염** | TE 0.3025 / IR 1.0505 / MDD_active 0.3274 | §2. Strategy/Benchmark 블록 유효 |

**공통 패턴**: "value(또는 신규 알파, 달력월 forward-return keyed) vs book(period_returns_layer5, offset 라벨) 의 realized_ym join → cor ≈ −0.04 직교 착시". 보정 시 모두 ≈ +0.31. 이 cor에 의존한 모든 "직교 sleeve" / "book-marginal orthogonal" 결론은 재검토 필요.

---

## 5. 05_Production 수정 제안 (도훈 manual confirm 사항 — 본 과제는 수정 금지)

1. **STR_1715 run_all.R L1143** `bt_dates <- as.Date(bt_dt$period_start)` 로 변경 검토 — PR `date`를 period 시작(매수 시점, 실현월 시작)으로 재정의. 또는 명시적으로 `realized_ym = format(period_start, "%Y-%m")` 라벨 채택. 단 이는 M4/AR outer schedule의 join 키 전체에 연쇄 → outer overlay 재실행 필요 (대규모).
2. **대안 (저침습)**: 데이터는 그대로 두고 **다운스트림 join 규칙으로 흡수** — book을 달력월 시계열과 join 시 `book label m+1 ↔ calendar m` 으로 정렬 (book을 1개 당김). 본 보고의 corrected/ 가 이 규칙 구현. 02_Infrastructure 컨벤션 문서로 명문화 (별도 작성: `02_Infrastructure/docs/period_returns_realized_ym_convention.md`).
3. **benchmark_comparison_metrics.json Active 블록 재산출** — 보정 정렬로 TE 0.1921 / IR 1.3985 재기록 검토. (Strategy/Benchmark 블록 유지.)

**권고**: 대안 2(다운스트림 join 규칙 + 컨벤션 문서) 우선 — 비가역 production 재실행 회피. 대안 1은 outer schedule 전면 재검증 동반이므로 도훈 confirm 후 별도 WT.

---

## 6. 산출물 매니페스트
- `04_Research/pg2_forensics/realized_ym_offset_report.md` (본 문서)
- `04_Research/pg2_forensics/realized_ym_offset_report.json` (구조화 수치)
- `04_Research/composition_search/value_sleeve_combination/corrected/run_blend_corrected.R`
- `04_Research/composition_search/value_sleeve_combination/corrected/results_corrected.csv`
- `04_Research/composition_search/value_sleeve_combination/corrected/blend_result_corrected.json`
- `04_Research/composition_search/value_sleeve_combination/corrected/aligned_series_corrected.rds`
- `02_Infrastructure/docs/period_returns_realized_ym_convention.md` (컨벤션 SOT)
- INVALIDATED 마커: `value_sleeve_combination/results.csv` + `blend_result.json` (삭제 안 함)
