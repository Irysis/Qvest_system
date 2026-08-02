# Factor DB — 시총 척도 결함 (V13_EV_Sales EV 항 무력화의 진짜 기전)

**일자**: 2026-08-02
**브랜치**: `claude/sad-tharp-11d987` (worktree). 결함은 main 공유 코드.
**발단**: `04_Research/01_reports/factor_db_dedup_20260802.md` §3.1 — 저장 DB에서 `V13_EV_Sales`의 Z_Score가 `V08_PSR`과 258/258개월 cor = 1.000000.
**판정**: 결함 확인. 단 **기전은 사전 혐의(NA→0 coalesce)가 아니었다.**

---

## 1. 결론 먼저

`02_Infrastructure/factor_db/compute_value.R:33`

```r
snap[, MarketCap := Close * Size]     # 결함
```

**`RAWDATA$Size`는 이미 시가총액이다.** 거기에 주가를 한 번 더 곱해 시총이 종목별 ~5e3배(=Close)만큼 부풀었다. 그 결과:

1. **더해지는 재무 항이 수치적으로 소멸한다.** `EV = MarketCap + TotalDebt − Cash`에서 부풀린 MarketCap이 TotalDebt/Cash를 압도 → `EV ≡ MarketCap` → `V13_EV_Sales ≡ V08_PSR`. Tobin's Q의 `+ TotalLiab`도 같은 이유로 소멸 → `V16_Tobins_Q ≡ 1/V18_AM`.
2. **`/MarketCap` 비율 전부에 주가 수준이 섞여 들어간다.** 오차가 상수가 아니라 종목별 `Close`이므로, `V01_BM`은 "장부/시총"이 아니라 "장부/(시총×주가)"가 된다 — 재척도가 아니라 **다른 팩터**다.

`NA→0 coalesce`(`:109-111`)는 **실재하지만 부차적**이다(§3).

---

## 2. 확정 증거

### 2-1. `Size`는 시가총액이다 (원천 대조)

2026-06-30 실측:

| 종목 | Close | Size | Size/Close | 판정 |
|---|---|---|---|---|
| 삼성전자 (A005930) | 334,000 | 1,952.7조 | 5.85e9 | Size = 실제 시총, Size/Close = 실제 주식수 |
| SK하이닉스 (A000660) | 2,650,000 | 1,888.7조 | 7.13e8 | 〃 |

- `Close*Size` = 삼성전자 기준 **6.52e8 조원** — KOSPI 전체 시총(~2,000조)의 30만 배. 물리적으로 불가능.
- 유니버스 중앙값: `Size` = 943억원(정상), `Close*Size` = 442조원(중앙값 기업이 삼성전자보다 큼 — 불가능).

### 2-2. 코드베이스가 스스로 규약을 명시하고 있었다

- `compute_size.R:38` — `# Size = Market Cap (RAWDATA의 Size 컬럼은 시가총액)`, `S01_Size = -log(Size)`
- `factor_db_builder.R:350` — `est_shares = Size / Close` (주식수를 **역산**)
- `factor_db_daily_phase6.R:488` — `V18_AM = safe_div(TotalAssets, Size)` (일간 DB는 **올바른 규약**)
- ↔ `compute_value.R:127`(구) — `# shares_est = Size (RAWDATA). MarketCap = Close * Size.` ← **정반대 주장**

즉 **월간 빌더와 일간 빌더가 같은 팩터를 서로 반대 규약으로 계산해 왔다.** 월간(`compute_value.R` 경유, `.cache/factor_db/`)이 결함 경로다.

### 2-3. 저장값에서 시총을 역산 (결정적)

저장된 `V18_AM = TotalAssets/MarketCap`, `V08_PSR = MarketCap/Revenue`에서 MarketCap을 역산:

| 역산 기준 | 일치율 (<1e-6) |
|---|---|
| `Size` | 0.00% |
| `Close * Size` | **100.00%** (V18 경유) / **99.78%** (V08 경유) |

→ 저장 DB는 `compute_value.R`이 만들었고, 그 MarketCap은 `Close*Size`다. 확정.

### 2-4. 사전 혐의(컬럼 유실) 반증

`.cache/fundamental_merged.parquet`에 필요한 Item이 **전부 존재**한다:

`ShortTermBorr` 103,958행 · `LongTermBorr` 68,272행 · `CashAndEquiv` 112,486행 · `TotalLiab` 112,669행

`factor_db_builder.R:747-750`의 pre-filter는 `Factor_Date <= sig_d` **행 필터일 뿐 컬럼 필터가 아니다.** 컬럼은 유실되지 않았다.

내부 교차검증도 같은 결론: `V19_Debt_to_Market`(= TotalDebt/MarketCap)이 **100% 양수**로 저장돼 있다 — TotalDebt가 0으로 뭉개졌다면 나올 수 없는 값이다. 다만 그 중앙값이 **1.5e-5**(경제적으로 ~0.2여야 함)로 ~1e4배 어긋나 있었고, 이것이 척도 결함을 가리키는 지문이었다.

**Task 2(V16의 TotalLiab) 답**: TotalLiab 항도 유실되지 않았다. `V16*V18 = 1 + TotalLiab/MarketCap`의 중앙값이 1.000103 — 항은 살아 있으나 부풀린 시총에 압도돼 소멸했다. 수리 후 0.600(정상 범위).

---

## 3. 부차 결함 — 결손을 0으로 내려앉힘 (실재)

`compute_value.R:109-111`(구):

```r
dt[, TotalDebt := fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) + fifelse(!is.na(LongTermBorr), LongTermBorr, 0)]
dt[, Cash := fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0)]
```

2026-06-30 기준 **14.70%** 종목이 세 항목 전부 결측 → `NetDebt`가 **결손이 아니라 정확히 0**으로 산출됐다. 부채를 모른다는 사실이 "부채가 없다"로 내려앉으면서 **가짜 커버리지**를 만들었다.

프로젝트 기지(旣知) 계열 그대로다: **결손을 정상값으로 내려앉힘**.

---

## 4. Task 3 — 영향 범위 (실측)

`Close * Size` 구성은 **6개 모듈**에 있었다:

| 모듈 | 위치 | 영향 팩터 |
|---|---|---|
| `compute_value.R` | :33 | V01~V24 대부분 |
| `compute_accrual.R` | :108 | `AC25_Accrual_Size_Interaction` |
| `compute_growth.R` | :302 | `IN03_RD_to_Market` |
| `compute_quality.R` | :370 | `Q24_Altman_Z` (0.6·MktCap/TL 항이 나머지 4항을 ~5e3배로 압도) |
| `compute_risk.R` | :180 | `R17_Market_Leverage` |
| `xlsx_factor_calculator.R` | :147 | xlsx 경로 |

구/신 정의 간 횡단면 순위 일치도(Spearman, 6개월 중앙값 — **1.0이면 순위 불변**):

| 팩터 | rho(구, 신) | 해석 |
|---|---|---|
| `V21_Composite_Equity_Issuance` | **0.126** | Close가 `log(1+cum_ret)`와 상쇄돼 CEI가 **단순 시총 성장률**로 축소돼 있었다 — 발행 신호 자체가 소멸 |
| `V07_EV_EBITDA` | 0.639 | |
| `V16_Tobins_Q` | 0.657 | |
| `V01_BM` | **0.682** | 표준 장부/시총이 아니었다 |
| `V13_EV_Sales` | 0.709 | |
| `V18_AM` / `V20_SP` / `V08_PSR` | 0.72 | |
| `V24_Residual_Income` | 0.808 | |
| `V14_EBIT_EV` | 0.854 | |
| `V19_Debt_to_Market` | 0.852 | |
| `V15_NetDebt_Adj_EP` | 0.867 | |
| `V11_Shareholder_Yield` | 0.886 | |
| `V02_EP` / `V03_CFP` | 0.90 | |
| `V22_FCFF_EV` | 0.925 | |
| `V10_FCF_Yield` | 0.935 | |
| **`V17_Payout_Ratio`** | **1.000** | 음성 대조 — 시총 미사용, 불변 |
| **`V23_RAFI_Weight`** | **1.000** | 음성 대조 — 시총 미사용, 불변 |

음성 대조 2건이 정확히 1.0인 것이 수리가 **표적화**돼 있음을 보인다(무차별 변경 아님).

`V09_PEG`도 별건으로 어긋나 있었다: `trailing_eps = NetIncome/Size`가 Size를 주식수로 취급 → 주당이 아닌 **수익률**을 산출한 뒤 주당 컨센서스 EPS와 차분해 `eps_growth`가 ~1e5배 부풀었다. `NetIncome/SharesOut`으로 수리.

---

## 5. 수리 내용

`compute_value.R`:
- `:33` `MarketCap := Size` + `SharesOut := Size/Close` 신설
- `TotalDebt`: 두 차입 항목이 **모두** 결측이면 `NA`(미커버). 하나라도 보고되면 나머지는 0으로 간주(KR 공시는 영(零) 잔액을 생략) — 전부-결측만 NA 전파
- `Cash := CashAndEquiv` (대체 없음, 결측은 NA 유지)
- `EV` NA 전파를 **설계로 명시** — 부채/현금 입력이 없는 EV 팩터는 "EV == MarketCap"이 아니라 **미커버**
- `V09` `trailing_eps := NetIncome/SharesOut`
- `V21` `me := Size` (Close 중복 곱 제거 → 상쇄돼 있던 `−log(1+R)` 항이 되살아남)

동일 1줄 결함 수리: `compute_accrual.R` · `compute_growth.R` · `compute_quality.R` · `compute_risk.R` · `xlsx_factor_calculator.R`

**`05_Production` 코드에는 이 구성이 없다**(`Close * Size` / `MarketCap` / `MktCap` 매치 0건). 다만 §7 참조.

---

## 6. Task 5 — 검증

### 6-1. 통제된 A/B (동일 입력, 구/신 모듈)

`git show HEAD:compute_value.R` vs worktree 판을 **같은 RAWDATA·FUND 입력**에 걸어 6개 시점 실행:

| 쌍 | 구 (cor) | 신 (cor) |
|---|---|---|
| `V13_EV_Sales ~ V08_PSR` | 1.0000000 | **0.929 ~ 0.981** |
| `V22_FCFF_EV ~ V10_FCF_Yield` | 1.0000000 | **0.984 ~ 0.996** |
| `V16_Tobins_Q ~ V18_AM` | −0.9999999 | **−0.797 ~ −0.933** |
| `V07_EV_EBITDA ~ V08_PSR` | 0.826 ~ 0.869 | **0.463 ~ 0.673** |

> ⚠ 사전 기대치는 "~0.90"이었으나 **실측 Spearman은 0.93~0.98**이다(2026-06 기준 0.929). 차이는 NetDebt 정의·커버리지 차이에서 온다. 수용 기준 "1.000000에서 이탈"은 확정적으로 충족되나, **기대 수치가 아니라 실측 수치를 기록한다.**

커버리지 영향은 EV/NetDebt 팩터에만 국한(−0.9% ~ −4.2%) — §3 결손 종목이 정직하게 미커버로 떨어진 결과다.

### 6-2. 상설 검사 (신설)

`08_Tests/factor_db/test_ev_term_not_inert.R` — 배터리 `run_all_hooks.sh` SUITES 등재. **8/8 PASS, exit 0.**

5축: A 회귀(순위-동일 금지) · B **위반 주입**(구 `Close*Size` 복원 시 3/3 쌍 검거) · C 결손 경로(coalesce 복원 시 5/5 팩터 커버리지 부풀음) · D 척도 불변(TotalLiab/MarketCap ∈ [0.05, 5]) · E 음성 대조(V17/V23 불변).

설계상 유의점 2가지:
- **주입이 실제로 적용됐는지 매번 단언한다.** 리팩터로 needle이 어긋나면 주입이 무해해져 B/C가 공허하게 통과한다 — 그건 초록이 아니라 검사 사망이다.
- **앵커를 코드/데이터로 분리했다.** 코드 정체성은 self-first(`commandArgs()` `--file=`)여야 worktree 검사가 자기 트리를 검사한다. `.cache/`는 추적되지 않는 단일 산출물이라 정본 루트에서 읽는다. 두 앵커를 묶으면 worktree에서 검사가 통째로 SKIP돼 상시 무해해진다.

**실증된 앵커 함정**: 샌드박스 재빌드 시 `factor_db_builder.R`을 worktree에서 source했는데도 `COMPUTE_MOD_DIR`이 `main`의 모듈을 가리켰다(`FUNC_PATH` 유래). 단언이 없었다면 **수리 안 된 코드로 재빌드하고 "검증 완료"로 보고**할 뻔했다.

---

## 7. Task 6 — 재측정 플래그

플래그 원장: `06_Registry/factor_remeasure_queue.json` (schema `factor_remeasure_queue_v1`)

- 영향 팩터 **22건 전부가 `06_Registry/ramp/approved_factor_library.parquet`(316건)에 등재**돼 있다. 등재 수치(`rank_ic_mean`/`net_sr`/`portfolio_alpha_t_nw`/`information_ratio` 등)는 **전부 구 정의 위에서 산출된 것**이다.
- 이 팩터들을 소비한 **과거 선별 라운드**도 동일하게 구 정의 기반이다.

**추가로 확인된 노출 (보고 필요)**:
`05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/` 의 `harvey_5spec_results.json` · `architect_independent_verification.json` · `ax008_compliance_summary.json`이 **HML 레그를 `V01_BM` Z-score로 구성**한다. `V01_BM`은 rho 0.682로 영향 상위군이다.

> 범위 한정: 확인한 것은 **"이 산출물들이 V01_BM을 HML로 쓴다"**까지다. 이것이 북의 *보유종목*에 들어가는지, 아니면 귀속/검증(Harvey 다중검정 스펙, AX-008 3-source)에만 쓰이는지는 **이번에 검증하지 않았다** — 별도 확인 항목.

---

## 8. 미수행 / 남은 항목

- **운영 `.cache/factor_db/` 258개월은 재빌드하지 않았다.** 도훈 결정(2026-08-02): 샌드박스 검증 우선, 운영 전면 재빌드(~13h, main 포함 전 트리에 동시 반영)는 병합 후 별도 결정.
- **일간 DB(`.cache/factor_db_daily/`, phase6/8)는 손대지 않았다.** 일간 경로는 원래 올바른 규약이라 이번 수리 대상이 아니다. 다만 **같은 팩터명이 두 DB에서 서로 다른 정의를 갖고 있었다**는 사실 자체가 별도 정합 항목이다.
- `V13`을 `V08`의 alias/중복으로 접지 **않았다**. dedup 원장의 `role="redundant"` / `cluster_label="sales_to_price"` 판정은 **결함 위에서 내려진 것**이므로 재빌드 후 재판정 대상이다 — 접었다면 결함이 라벨 뒤로 사라졌을 것이다.

---

## 9. next_probe

1. **`V21_Composite_Equity_Issuance` 단독 재측정** — rho 0.126은 사실상 미측정 팩터가 하나 생긴 것과 같다. KR 순발행(net issuance)은 비-return 원천에 가까운 축이고 FQ 재료 lane과 정합적이다. 수리 후 IC/PORT_t를 처음부터 잰다.
2. **월간↔일간 DB 정의 정합 감사** — 같은 `Factor_Name`이 두 DB에서 다른 값을 갖는 팩터를 전수 대조한다. 이번 건은 그 감사의 1건이 우연히 발견된 것이며, **감사 자체가 부재**다. `V18_AM`처럼 양쪽에 있는 팩터가 몇 개이고 몇 개나 어긋나 있는지 아직 모른다.
3. **부활 조건**: 운영 재빌드 완료 + `approved_factor_library` 22건 재측정 후, `V13`/`V08` 중복 판정과 `V16`/`V18` 판정을 재수행. 재판정 전까지 두 쌍의 dedup 결론은 **보류**로 취급한다.

---

## 10. 산출물

| 경로 | 내용 |
|---|---|
| `02_Infrastructure/factor_db/compute_value.R` | 근본 수리 + 결손 경로 |
| `02_Infrastructure/factor_db/{compute_accrual,compute_growth,compute_quality,compute_risk,xlsx_factor_calculator}.R` | 동일 1줄 수리 |
| `08_Tests/factor_db/test_ev_term_not_inert.R` | 상설 검사 5축 (8/8 PASS) |
| `08_Tests/hooks/run_all_hooks.sh` | SUITES 등재 |
| `06_Registry/factor_remeasure_queue.json` | 재측정 플래그 원장 |
| `04_Research/01_reports/factor_db_marketcap_scale_defect_20260802.md` | 본 보고서 |
