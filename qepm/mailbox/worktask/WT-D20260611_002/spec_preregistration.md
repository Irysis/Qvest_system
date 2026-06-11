# Spec Pre-Registration — WT-D20260611_002 FLOW family E6 fair-trial

**박제 시각**: 2026-06-12 (탐색 전 사전등록 — measurement-graduation §3 chain/sweep 정합)
**Agent**: alpha-research (QEPM 모드)
**selection_type**: `sweep` (n_trials 전량 계상, DSR≥0.5 HARD 대상, spec 선택 IS-only)
**가설**: KR 기관/외국인 일간 순매수 흐름의 정보거래 비대칭 — 수급 주체별 매집 패턴이 1~3개월 가격 발현에 선행.

---

## 0. 데이터 + 측정 프로토콜 (전 spec 공통, 박제)

- **신호 소스**: `.cache/flow_features_daily.parquet` (2000-01-03~2026-03-26, 22 col, 9.21M행). C15 carve-out 명시 승인(request.json `data_carveout`).
  - 모든 flow feature는 `01_flow_features.R`에서 `shift(1L,'lag')` 후 `frollsum` 구성 — **t-1 lag, C2 PASS**. `liq_20d`도 t-1 lag turnover (C10 PASS).
  - **금지 컬럼 (forward label)**: `fwd_inst_foreign_netbuy_21d`, `fwd_flow_top20`. 신호 입력 절대 사용 금지(C7). 본 sweep에서 read조차 하지 않음.
- **sig_date grid + forward 1M return**: STR_1715 PG2 panel `alpha_scores_str1715_268m.parquet` (`Date`, `Ticker`, `Ret_1m` = PIT-aligned forward 1M 실현수익, 268 month-grid 2004-01~2026-04). flow 신호를 각 sig_date의 last-available daily(`Date < sig_date`)로 snap → panel grid에 merge (C2 lag).
- **benchmark basis**: **universe-EW monthly return** (anchor qmj_alpha_build.R line 159-161 precedent). active = top-N EW − universe-EW. calendar-self-consistent(Ret_1m과 동일 시간축), cross-sectional alpha 측정 정합. (benchmark.parquet 일간 KOSPI는 panel Ret_1m과 calendar-label 정합 미확인 → 회피, screening 표준 basis 채택.)
- **실측 엔진**: `02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt()` (top-N EW long-only + 유동성 2e8 + cost). metric_type=`canonical_screen`. **proxy 손계산·prod(1+r) 자체합성 금지.**
- **cost**: v2.4_kr_retail_15bps delta-based (canonical_screen_bt 내장: traded_t=Σ|w_t−w_{t−1}|, cost=traded×15bps).
- **유동성 필터**: `liq_20d ≥ 2e8` KRW (t-1, C10). holdings top-N=20 (기본).
- **universe**: 전종목 신호 추정(도훈 기허용 2026-06-02) → flow 데이터 가용 전 ticker. **단, K200∪KQ150(KR_top342 panel ticker) 비교군 수치 병기** (구 WT 재현 대조 anchor).
- **정규화 의무**: netbuy 컬럼은 raw KRW (sd~2.8e10, q99~5e10). 대형주 편향 방지 위해 **유동성·시총 정규화 후 cross-sectional z** (각 spec 명시). winsorize 1%/99% (Charter §11).
- **IS/OOS 분리**: IS = grid ≤ 2021-12-31 (spec 선택·argmax 전용). OOS = 2022-01-01~2026-04 (held-out, 선택 후 1회 조회). 게이트 판정의 2017+ 서브윈도우는 IS 내 평가.

## 0-bis. screen 게이트 (통과 spec만 alpha_package 후보)

`PORT_t(NW lag-3) ≥ 1.96` (IS) **AND** `2017+ 서브윈도우 PORT_t > 0`. graduation HARD(PORT_t≥2.95, DSR≥0.5)는 forge-authoritative — 본 alpha 단계는 screening + DSR 진단 산출.

---

## 1. 사전등록 Spec (8개 — 박제, 탐색 중 추가·수정 금지)

각 spec: 신호 정의 + lookback + 메커니즘 1줄 + 방향(momentum/contrarian). 방향은 **IS sign-freeze**(2005-2014 학습) 후 고정 — full-sample sign fishing 회피.

| ID | 신호 정의 | lookback | 정규화 | 방향(가설) | 메커니즘 1줄 |
|----|-----------|----------|--------|-----------|--------------|
| **S1_INST20** | inst_netbuy_20d / liq_20d | 20d | /liq, z, wins | momentum(+) | 기관 20일 순매집(거래대금 대비)이 1M 가격 선행 — 기관 정보거래 우위 |
| **S2_FRGN20** | foreign_netbuy_20d / liq_20d | 20d | /liq, z, wins | momentum(+) | 외국인 20일 순매집이 1M 가격 선행 — Choe-Kho-Stulz 2005 외국인 정보우위 |
| **S3_COMBO20** | (inst_netbuy_20d+foreign_netbuy_20d)/liq_20d | 20d | /liq, z, wins | momentum(+) | 기관+외국인 합산 스마트머니 순매집 동조 — 정보거래 집중 |
| **S4_FRGN_OWN** | foreign_own_chg_20d (외인지분율 변화 proxy) | 20d | z, wins | momentum(+) | 외인 지분율 상승 = 구조적 매집, 시총 정규화된 flow — 지속 매집 신호 |
| **S5_INST_MOM** | inst_flow_momentum / liq_20d (5d−20d 가속) | 5d vs 20d | /liq, z, wins | momentum(+) | 기관 flow **가속**(최근 매집 강화)이 단기 발현 선행 — flow acceleration |
| **S6_COMBO_SMOOTH** | 3-month EMA of S3_COMBO20 z | 20d, 3m EMA | EMA, re-z | momentum(+) | S3 평활(저회전 변형) — 잡음 제거 + TO 절감, cost-aware spec |
| **S7_COMBO_CONTRA** | −1 × S3_COMBO20 (반대 방향) | 20d | /liq, z, wins | contrarian(−) | 구 WT-D20260529_001 채택 방향(crowding/price-pressure reversal) 재현 대조 anchor |
| **S8_DISAGREE** | z(frgn20/liq) − z(indiv5d/liq) | 20d/5d | /liq, z each | momentum(+) | 외국인 매집 ∧ 개인 매도(스마트−우매 머니 divergence) — 정보 비대칭 극대 |

### 방향(momentum vs contrarian) 사전 입장

- 본 가설(request.json)은 **momentum 방향**(flow가 가격에 *선행*)을 주장 → S1~S6, S8은 momentum(+).
- 구 WT-D20260529_001은 동일 데이터에서 **contrarian**(crowding reversal)을 채택해 forge PORT_t=2.35 달성. 이는 본 가설과 방향 상충 → **S7로 재현 대조 anchor 박제**. 두 방향 모두 사전등록, IS sign-freeze로 데이터가 방향 결정(sign fishing 아님).
- **n_trials 계상**: 8 spec × (방향은 사전 고정이므로 추가 trial 아님). DSR n_trials=8 (sweep 정합). lookback/정규화 변형은 spec 내 고정(추가 grid 없음).

## 2. 선택 규칙 (IS-only, argmax)

- IS(≤2021-12) PORT_t(NW lag-3) 기준 **상위 spec 선택**. OOS는 선택 후 1회 조회(반복 금지).
- screen 게이트(0-bis) 통과 spec만 alpha_package 후보. 전 spec 탈락 시 FAIL 정직 기록(AX-000, WT-D20260611_001 선례).
- alpha_package 채택 spec: cor<0.95 vs 기존 admitted(STR_1715 score_eff) + mechanism≥50자 + factor_specs≥1 + harvey_t 3 spec.

## 3. 산출물

- `stage_artifacts/WT_D20260611_002/alpha_scores.parquet` (채택 spec score, 전종목)
- `qepm/mailbox/worktask/WT-D20260611_002/alpha_validation.json` (8 spec screen 결과표 + universe_comparison + DSR)
- `alpha_package_draft.json` → Codex Round → `alpha_package.json`

**무결성 박제**: 본 문서는 탐색 결과 확인 전 작성. 결과에 따라 spec 추가/방향 변경 금지. 탈락은 탈락으로 기록.
