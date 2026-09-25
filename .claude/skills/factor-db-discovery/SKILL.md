---
name: factor-db-discovery
description: Factor DB 활용 심화 + 신규 팩터 검증의 반복 프로세스(SOT). 발굴≠생산 substrate(pre-C13 raw)로 multi-axis 배터리(model×decay×feature×raw×horizon×style)를 실측하고, 방화벽 게이트(placebo·seed·book-marginal·holdout)로 **screen-tier 라벨 자격**을 판정한다(등급·BOOK 은 essence/Judge 층). 신규 팩터를 registry/빌더로 적재한 직후, 또는 "DB에 미추출 알파가 있나 / 어떻게 더 잘 쓰나" 질문 시 사용. 전략을 *생산*하는 게 아니라 DB *활용 표현공간*을 탐색.
---

# Factor DB Discovery — 활용 심화 + 신규 팩터 검증 프로세스 (SOT)

**발효**: 2026-07-01 (P7 발굴≠생산 표현분리 8라운드 실증에서 도출). **목적**: DB를 *우물로 파는* 대신, DB 활용 *표현공간*(어떤 결합·horizon·style·기질)을 체계적으로 탐색해 미추출 알파를 찾고, 신규 적재 팩터의 실효를 검증한다. **강령**: [[feedback-iterative-multi-methodology-research]](1방법론 단정 금지·자율반복) + [[feedback-factor-db-discovery-process]](방법·교훈 SOT).

## 언제 쓰나
- 신규 팩터를 **온보딩(§0)** 한 직후 → "이 팩터가 실제로 뭘 더하나" 검증.
- "DB에 아직 안 쓴 알파가 있나 / score_eff 너머 뭐가 있나 / 어떻게 더 잘 활용하나" 질문.
- **전략 생산 아님**(그건 alpha-research/worktask). 여기는 *DB 활용 표현 탐색*.

## §0 신규 팩터 온보딩 (적재) — 선언형 인터페이스 (2026-07-01)
DB에 새 팩터 넣기 = 코드 hand-surgery ❌ → **선언(spec)** ✓. PIT는 구조적 보장(빌더가 RAWDATA를 `[sig-1400d, sig]`로 pre-slice → 미래 불참조).

**A. 선언형(공식 포뮬러 가능 팩터)** — 코어 코드 수정 불필요:
```r
source("02_Infrastructure/factor_db/add_factor.R")
add_factor(id="M99_Mom_126_21", name="6M Momentum skip1M", category="momentum",
           template="momentum", params=list(window=126, skip=21))     # spec+registry 자동(최소diff)
# 검증(1개월·캐시 무오염): source(".../factor_db_builder.R"); build_factor_db("2026-05-31", save=FALSE, force=TRUE)
# 이력 적재(scoped ~초/월): backfill_custom_factor("M99_Mom_126_21", start_date="2005-01-01")
# 활용 검증: python 02_Infrastructure/discovery/discovery_explore.py --validate M99_Mom_126_21
list_custom_factors(); remove_custom_factor(id, from_registry=TRUE)
```
템플릿(PIT-safe, RAWDATA trailing): `momentum{window,skip}` · `reversal{window}` · `volatility{window[,col]}` · `mean_reversion{window}` · `trailing_agg{col,window,agg=mean|std|sum|median}` · `ratio{num,den}` · `gap_freq{window}`. 파일: spec `custom_factors.json` · compute `compute_custom_factors.R`(빌더 module_map "custom" 배선) · 헬퍼 `add_factor.R`.

**B. 전용 모듈(포뮬러 불가·FUND/CONSENSUS 복합)**: 여전히 `compute_<family>.R` 작성(계약 `fn(RAWDATA,sig_date,FUND,CONSENSUS)→dt(Ticker,Factor_Name,Raw_Value)`) + builder `module_map`/`func_name_map` 등록 + registry 수동. AC14/XF_Q06 선례.

**설계 원칙**: registry sync=라인 타겟 append(전체 reformat 금지 — round-trip은 13k줄 diff·동시성 위험) · backfill=신규 컬럼만 기존 parquet에 추가(276팩터 재계산 X, tmp-copy로 OneDrive arrow mmap 1224 회피, 비파괴·가역 실증). **적재 후 반드시 §1~5로 검증** → evidence_tier 갱신 근거. [[reference-factor-onboarding-interface]]

## §0.5 모드 결합 배선 (W1/W2/W3, 2026-07-02) — discovery는 고아 CSV가 아니다
- **W1 (무결성)**: sweep 수치 = `metric_type="proxy"`(EW 산술평균·인라인 15bps 근사, 탐색용). **의사결정 수치는 `canonical_confirm`** (R `canonical_screen_bt` 경유 = contract-grade PORT_t `portfolio_alpha_t_nw_lag3` NW lag-3, `metric_type="canonical_screen"`, 자체합성 X). `--canonical`/`--validate`에서 자동. 브릿지 `run_canonical_screen.R`. **canonical은 frequency-native**: `canonical_confirm(mode="monthly"|"quarterly")` + `canonical_screen_bt(periods_per_year=)` — **horizon 신호를 자연 cadence(분기 ppy=4)로 잰다(월간 강제 금지, 도훈 mandate)**. ★**proxy 과대의 주범 = self-synthesis, cadence 아님**: earnings_rev H3 recent proxy 2.58 → 분기 contract 0.93(−1.65 self-synth) → 월간 contract 0.70(−0.23 cadence). H=1서 proxy=canonical ±0.003. **후보는 (a)자연 cadence로 (b)반드시 contract-grade로 둘 다 재라. proxy는 pre-filter일 뿐.**
- **W2 (→QEPM)**: `--export-seed [WT_id]` → CANDIDATE를 `qepm/mailbox/worktask/{WT}/discovery_seed.json`(family·horizon·factor_ids·proxy/canonical PORT_t·caveat)로. alpha-research Step 0가 1순위 소비(`alpha_research_init.md` Step 0). canonical≪proxy면 caveat에 분기-마킹 경고 자동 삽입.
- **W3 (온보딩 검증)**: `validate_new_factor(id)`(`add_factor.R`) = `--refresh-factor`(월별 factor_db→explore_panel 컬럼 증강, 스냅샷 패널의 신규팩터 부재 문제 해소) + `--validate`(score_eff 대비 proxy/canonical Δ).
- **(보류) W4** discovery→module_quarantine→register_module→strategy-rotation: screen-tier 후보 스트림이 쌓이면. / **(사료) W5** RAMP 상류 축-정찰 — 모드 퇴임(v9.21).

## 핵심 원리 — 발굴 기질 ≠ 생산 기질 (P7)
생산(book) 소비 = `load_month_factors` → **C13 정렬(단조·선형) → score_eff(1M)**. 이 파이프에서 발굴을 시작하면 basis span에 funnel되어 *같은 천장 재확인*만 한다. → **발굴은 별도 통로에서**:
- `02_Infrastructure/discovery/discovery_loader.R::load_factors_discovery()` — **C13 정렬 이전** Raw/Z를 wide로 노출(비단조·상호작용 보존, 방화벽 표식).
- 산출은 발굴 전용. **정밀 측정(QEPM/충실구현) 진입은 게이트 통과분만** — 등급·BOOK 은 essence/Judge 층.

## ★ 단일 엔트리 (제품화 2026-07-01) — 먼저 이걸로
```bash
# 카테고리/focused subset × horizon 스캔 + 게이트 + placebo + 후보플래그 (한 줄)
python 02_Infrastructure/discovery/discovery_explore.py \
    --families earnings_rev,earnings,value,momentum,quality,idiovol,liquidity,all \
    --horizons 1,3,6,12 --method composite --placebo
# 신규 적재 팩터 검증 (score_eff 대비 증분)
python 02_Infrastructure/discovery/discovery_explore.py --validate <FACTOR_ID>
# --method ridge|hgb (비선형, 느림·opt-in) / API: from discovery_explore import explore, validate_factor
```
산출: `explore_results.csv` (family×H별 full/recent/sub PORT_t·IR·TO·szPct·CANDIDATE) + placebo 백분위. 
CANDIDATE(recent PORT_t≥1.9 ∧ full_IR>−0.1 ∧ szPct≥0.5) 뜨면 → 아래 4·5 정밀게이트로. **검증: earnings_rev H3 recent_t 4.35·placebo 100%ile 재현.**
아래 §1~5는 그 내부 방법론(저수준 round 스크립트는 참조 구현).

## 프로세스 방법론 (discovery_explore가 내부 구현; 커스텀·심화 시)
### 1. 기질 선택 (어디서 출발)
- 팩터 결합/feature 탐색 → `discovery_loader`(pre-C13, `02_Infrastructure/discovery/assemble_phase0.py`로 패널화: features + score_eff(warm-start) + forward수익).
- raw 미세구조 → RAWDATA OHLCV 시퀀스(`phase1_raw.py` 템플릿, torch CNN).

### 2. Multi-axis 배터리 (직교축을 *동시에* 스윕 — 1개 아님)
`battery_phase0.py`(model×decay) / `battery_round2.py`(feature) / `round4~7`(horizon·성분·검증) 템플릿:
| 축 | 값 |
|---|---|
| **model class** | Ridge·ElasticNet(결정적) · HGB(bagged, seed안정) · MLP · 앙상블 |
| **decay/window** | expanding · rolling(36/60) · recency-weighted · **regime-conditional** |
| **feature** | 전체 · recency-IC 선택 · interaction · exclude-decayed |
| **기질** | pre-C13 factor · raw OHLCV 시퀀스 |
| **★horizon** | **1/3/6/12M** (감쇠는 horizon-특정 — 1M死라도 3-6M生 가능. earnings-3M 실증) |
| **★style/family** | value·momentum·quality·earnings-revision·liquidity·idiovol 등 성분 분해 |

★**교훈(고가치 축)**: **horizon × style/family**. 1M·재조합·feature·raw는 최근 소진이나 **earnings-revision@3M**은 최근 강건이었다. 새 탐색은 이 두 축을 먼저.

### 3. 올바른 metric (IC≠PORT_t)
`net_series`(top-25 long-only, 15bps delta) → **full + 최근(2021-26) + sub-period**의 **net active IR / PORT_t(NW lag-3)**. rank-IC만으론 판정 금지(short-leg trap). 실패는 *다음 라운드 입력*(왜 실패했나 메커니즘 → 다음 축 공략).

### 4. 방화벽 게이트 (screen-tier 자격)
헤드라인 나오면 *적대적으로* deflate 시도:
1. **sub-period 안정성** (front-loaded/decay 여부)
2. **calmar/MDD ≥ 0.64** · **turnover** (배포성)
3. **look-ahead offset**(−1/0/+1, 누수 무)
4. **seed-robustness**(동일설정 seed만 바꿔 edge 유지?) · **placebo 다중검정**(랜덤 composite 분포 대비 백분위>97.5%)
5. **★book-marginal + 오버레이**(bare 아닌 *현 book*에 얹어 ΔIR≥0.05·특히 최근) — `verify4_overlay.R` 패턴
6. **forward holdout 사전등록**(탐색기간=최근이면 forward 필수. `holdout_falsification.R`)
전부 통과 → **정밀 측정 후보**(정본 계약 `run_paper_replication` → essence 로 권위 등급 산출 · QEPM WT 체인은 동결 `QEPM-R0-FREEZE`). BOOK 등록은 essence A + Judge PIT PASS + **도훈 confirm**(v10) — 이 스킬은 등록하지 않는다. [[measurement-graduation]] 게이트 준수.

### 5. 강령 (규율)
- 1방법론 실패로 "소진" 단정 금지 — 여러 라운드·직교축·메커니즘 규명까지([[feedback-iterative-multi-methodology-research]]).
- prior 정직 표기(over-claim 방지). 실측·PIT·정직보고. **멈춰서 "다음 뭐" 묻지 말 것** — 목표 도달/공간 진짜 소진까지 자율.

## 산출 + 메모리
- 유의한 결과/의미있는 실패 → 메모리 적립(발견 = project, 방법·교훈 = feedback/reference). PASS 후보는 `/advisor` 안내(도훈 `QEPM-ADVISOR-MODE` — **메모(자문)까지만 · 측정은 도훈 승인**(채팅 발화) 뒤 정본 계약 · 명령은 도훈이 직접 부르고 이 스킬은 `--measure` 를 넘기지 않는다)로. ★dossier(qvest-dossier-pipeline)는 **동결**(`QEPM-R0-FREEZE` — 실행 즉시 종료 · 해제 = decision_register 재상정).
- 신규 팩터 검증 결과는 registry `evidence_tier` 갱신 근거로.

## 참조
- 코드 템플릿: `02_Infrastructure/discovery/` (discovery_loader.R · assemble_phase0.py · battery_*.py · round*_*.py · verify*.R · phase1_raw.py)
- 로더 계약: `02_Infrastructure/factor_db/factor_db_connector.R`(생산 C15) / discovery_loader(발굴, pre-C13)
- 게이트: `02_Infrastructure/contracts/canonical_screen_bt.R` · `essence_score.R` · `holdout_falsification.R`
- 메모리: [[feedback-factor-db-discovery-process]] · [[project-discovery-substrate-phase0]] · [[project-earnings-revision-3m-horizon-lead]] · [[measurement-graduation]]
