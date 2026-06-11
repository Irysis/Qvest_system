# QEPM 가설 스캔 — 정식 풀파이프라인 1건 정당화 후보 랭킹

**작성**: 2026-06-11 (Q-Lead spawn, 가설 탐색 담당) · **도훈 mandate**: "정식 QEPM 풀파이프라인을 가동하되, 가설부터 직접 탐색해봐"
**방법**: 백테스트 실행 0건 — 기존 산출물·데이터 인벤토리 실확인·메모리 기반. 모든 수치는 출처 파일 인용 (이 문서 자체는 어떤 신규 측정도 포함하지 않음).
**PG0 gap 기준**: `.cache/portfolio_gap_vector.json` (2026-06-02) — `sleeve_needs="core_alpha"`, target CAGR 0.16 / SR 2.5(stretch) / MDD 0.25.

---

## 0. 스캔 중 확인된 전제 사실 (랭킹 판단의 토대)

| 사실 | 출처 (실확인) |
|---|---|
| FLOW가 16후보 중 유일한 PORT_t 게이트 정확 통과. forge 실측 full 2.35 (< 2.95), lockbox-trunc 3.66. 열화는 2024-01~ frozen-weights OOS deploy-extension에 집중 — 측정 아티팩트 아님 | `qepm/mailbox/worktask/WT-D20260529_001/forge_package.json` line 25~38 |
| 일간 수급 데이터 이 머신 가용: `.cache/investor_stock/*.parquet` + `.cache/flow_features_daily.parquet` — **2000-01-03 ~ 2026-03-26, 9,211,959행, 전종목** (arrow로 직접 확인) | 본 스캔 실측 (2026-06-11) |
| INV01~INV13 (수급 15 spec) factor_registry 등재 완료 (총 373팩터) | `02_Infrastructure/factor_db/factor_registry.json` |
| 전종목 value 재측정 **실패**: full PORT_t 1.71 / **2017+ PORT_t −0.135** (기억 anchor +1.41 미재현) / oos_retention 중앙값 0.064 / TO 16.4x/yr / net SR 0.375. 도훈 처분(2026-06-11): standalone admit화 중단, 조합재료 전환 | `04_Research/strategies/STR_WT-D20260611_001_value_sleeve/alpha_validation.json` + `qepm/mailbox/worktask/WT-D20260611_001/status.json` |
| 깨끗한 Z(census_v3, K200∪KQ150·top-25·canonical_screen_bt) 단일팩터 anchor: **IN03_RD_to_Market PORT_t 2.617** (p 0.0089, IR 0.67, SR_abs 0.823, MDD 53.6%, TO 2.89x/yr) > V02_EP 2.308 > V14_EBIT_EV 2.163. 가산 composite는 singles 이하 (val_rd_wc_A 1.276 / B 0.289) | `04_Research/factor_db/census_v3_targeted/census_v3_sweep.csv` (2026-06-11 run) + `run_census_v3.R` line 9~10 (universe 확인) |
| 책 엔진 = revision Core: C04_ESBR 전기간 NW-t 8.70·최근 36m hit 86.1%, C01_SUE 6.29. Q07 최근 36m IC 0.0522 (7팩터 중 1위), Q25_Ohlson_O 0.0031 (사멸). C01×C04 단일 클러스터 (score ρ 0.679) | `04_Research/pg2_forensics/b1_summary.md` §1~2 |
| consensus(eps_1y) 커버리지: 2000-03-16~2026-03-27, lifetime 2,731 tickers, **2025+ 854 tickers** (제한 유니버스 348의 2.45배) | `.cache/consensus/eps_1y.parquet` (arrow 실확인) |
| DART 공시 메타데이터: 일반 공시 적시성(rcept_dt) 캐시 **부재** — insider trades만 2024-03-22~2026-03-20, 280 tickers, 9,790행 | `.cache/dart/insider_trades.parquet` (실확인) |
| rawdata 일간 + Sector_Lv2 가용 (Transfer-Entropy 입력 충족) | `.cache/rawdata.parquet` 컬럼 실확인 |
| `qepm/memory/methodology_active.md` **이 머신에 부재** (미프로비저닝 클론 — 2026-06-10 아키텍처 감사 정합). L-code 근거는 memory 파일 + `.cache/lcode_corpus_methodology.json`(27건, 대부분 reference-only)로 대체 — 정직 보고 | 본 스캔 실측 |

**전략 진실 (measurement-graduation §6)**: KR long-only 수익률직교 구조적 불가 (16/16 standalone FAIL). 따라서 모든 후보의 admission 경제성은 standalone이 아니라 **book-marginal ΔIR ≥ 0.05** 또는 **incumbent book 후계(replacement)** 프레임으로 평가했다.

---

## 후보 #1 — FLOW family E6 fair-trial 풀파이프라인 (전종목 확장 + 최신 데이터 재측정) ★최우선

1. **제목/메커니즘**: KR 결제주체(외국인/기관/개인) 장기 순매수 흐름의 crowding/price-pressure reversal — 과매집 종목의 unwind 역행 포지셔닝. 결제-신원 데이터 축이라 fundamentals(1715)·가격 미시구조와 정보원 자체가 다름 (Choe-Kho-Stulz 2005 RFS, alpha_package_FLOW.json factor_specs의 economic_rationale).
2. **expected_role**: core_alpha (PG0 `sleeve_needs` 정합) — book과 직교하는 비-펀더멘털 신호축. **why_now**: ① graduation 허들 최근접 유일 후보 — forge 실측 2.35 vs 2.95 (`WT-D20260529_001/forge_package.json` line 25). ② 열화가 frozen-weights deploy-extension(2024-01~, 29개월)에 집중 — 신선한 데이터(2026-03까지)로 rolling 재추정 시 회복 여부가 검증 가능한 명제. ③ 구 WT의 유니버스는 349종목(alpha_vector_n_total=349) — **전종목 레버 미적용 상태**. ④ `program_charter.md` Cycle 1 Track S가 이미 "FLOW family fair-trial Stage A"를 차터함 — 본 후보는 그 Stage A→B→C를 QEPM 풀파이프라인 1건으로 완주하는 것.
3. **데이터 가용성 (실확인)**: `.cache/investor_stock/` 6 parquet + `.cache/flow_features_daily.parquet` — 2000-01-03~2026-03-26, 9.21M행, 전종목. INV01~INV13 registry 등재. **즉시 가용.**
4. **반증영역/Axiom**: 사전제외 비해당 — 단일팩터 standalone 아님(가족 내 5팩터 composite, E6 "팩터군 수준 표준처치 재도전 허용" 조항 정면 해당). 이질 가산 Z composite 금지는 *이질* 간 — 동질 flow family 내 composite은 production Core 선례 구조. AX-007 예외 충족 경로: 전종목 확장(50+ 분산) 또는 multi-sleeve 편입. 구 spec의 OOS 방향고정(train 2005-2014 sign-frozen, oos_t 3.3)은 sign-fishing 방어 선례.
5. **QEPM 풀파이프라인 적합성**: **두껍다.** alpha(6~10 spec 사전등록 grid: horizon 20d/60d/126d × 주체 분해 × 전종목/제한 × contrarian/momentum 방향) → risk(flow = crowding 그 자체 — crowding_score·Σ 상호작용, crisis-strengthening 주장 검증은 risk agent 고유 과제) → optimizer(낮은 TO 신호의 가중 설계, v2.4 delta 비용에서 저회전 우위) → forge(full-window NW lag-3 재측정). 단순 스크린이 아님.
6. **리스크 + 측정 경로**: ① 2024+ 열화가 진짜 alpha decay일 가능성(공매도 재개·수급 데이터 보편화에 의한 crowding-of-crowding) — full-window PORT_t가 그대로 판정. ② E6 grid = **sweep** → `selection_type="sweep"`, DSR≥0.5 HARD + n_trials 6~10 전량 계상 (charter 거버넌스 그대로). ③ PIT: investor_flow t-1 settlement (C2 — 구 WT request.json lag_rules 선례), Hawkes 전례(rank-IC 통과 → portfolio-α t −2.09 FAIL, `reference_creative_alpha_idea_bank.md`)가 보여주듯 rank-IC 중간산출에 의미 부여 금지, PORT_t만 권위. 측정 사다리: Stage A `canonical_screen_bt` (PORT_t≥1.96 ∧ 2017+ >0) → Stage B production-fidelity `build_bt_result` + book-marginal(cor<0.30 ∧ blend ΔSR>0) → Stage C 정식 forge + ΔIR≥0.05 + governor(도훈 수동).

---

## 후보 #2 — Revision Core 커버리지-유니버스(~854종목) 후계 재구성 (book 엔진 breadth 확장)

1. **제목/메커니즘**: 책의 검증된 엔진(earnings-revision Core: C01/C02/C04/C06 + Q07)을 K200∪KQ150(348)에서 consensus 커버리지 전체(2025+ 854 tickers)로 재구성 — 살아있는 신호의 breadth 확장. 애널리스트 정보 확산은 중소형 커버리지 종목에서 더 느리게 가격화(정보 확산 지연 메커니즘)되므로 동일 신호의 한계 IC가 더 클 개연성.
2. **expected_role**: core_alpha — 단 신규 직교 sleeve가 아니라 **incumbent book 후계(replacement)** 프레임 (동일 family라 cor<0.3 직교 게이트는 구조적으로 통과 불가 — 정직 명시). admission 경제성 = `pg1_admission_with_book_context` ΔIR = new_book_ir − incumbent_book_ir ≥ 0.05. **why_now**: ① b1 실증 — 엔진은 최근도 강함 (C04 최근 36m IC 0.0440·hit 86.1%, Q07 0.0522 1위; `b1_summary.md` §1). conditional_ic_matrix 최근 3y ICIR: Q07 0.929 / C01 0.777 / C04 0.547 (`.cache/conditional_ic_matrix.csv` line 149/146/95). ② Cycle 9 L-code가 "Core전종목재구성"을 SR2.5 잔여 gap 3대 레버로 명시 (`project_sr25_autonomous_program.md`). ③ B1이 클러스터 관리(C01×C04 ρ0.68)·Q25 제거·Q07 승격이라는 구체 재설계 입력을 이미 제공.
3. **데이터 가용성 (실확인)**: `.cache/consensus/` 13 parquet (eps_1y: 2000-03~2026-03, 2,731 tickers lifetime, 2025+ 854) — **즉시 가용.** 단 월별 PIT 커버리지 시계열(초기 연도 커버 폭) 검증은 WT 내 1차 과제.
4. **반증영역/Axiom**: standalone 단일팩터 아님(production 기검증 다신호 composite의 universe 변경). 이질 가산 금지 비해당(동질 revision family). AX-007 비해당(multi-sleeve 구조 유지 + 854 분산). **주의**: 전종목 레버의 1차 실증(value Cycle 4 anchor)이 오늘 재측정에서 **미재현**(2017+ −0.135, 위 §0) — "breadth 확장 = 입증된 레버" 주장은 금지되며, 본 후보의 차별점은 *죽은 신호의 부활(value)이 아니라 살아있는 신호의 확장*이라는 사전 가설임을 명시. 실패 시 그 자체가 INV-7 ledger 가치.
5. **QEPM 풀파이프라인 적합성**: **가장 두껍다.** alpha(coverage-universe revision composite + 클러스터 처리 + Q07 편입) → risk(중소형 유동성·용량·Σ 재추정 — 제한 유니버스와 질적으로 다른 위험구조) → optimizer(λ-tilt 재최적화, top-20/25) → forge(M4/AR/R05 overlay 재적용 후 book 후계 실측). QEPM 모드 정의("신호-only 알파 정밀 검증·편입")에 정확히 부합.
6. **리스크 + 측정 경로**: ① 중소형 consensus 품질(추정치 희소·stale) — C08_Coverage로 커버 강도 필터, 초기 연도 표본 절단 가능성 정직 보고. ② 후계 프레임이라 실패 시 기회비용 큼 — Stage A에서 coverage-universe canonical screen (PORT_t≥1.96 ∧ 2017+ >0) 선행 후 진행. ③ TO: revision 신호는 월간 갱신 — v2.4 delta에서 비용 실측 필수 (value 16.4x/yr 전례 경계). ④ 비교 기준 = production `period_returns_layer5.csv` ret_orig (backtested 권위).

---

## 후보 #3 — IN03_RD_to_Market 중심 intangible-value family fair-trial (E6 표준처치)

1. **제목/메커니즘**: R&D 자본화 가치(R&D/Market) — 회계상 비용처리된 무형투자를 시장이 과소평가 (Chan-Lakonishok-Sougiannis 2001 계열). 분모가 Market인 scaling만 작동 (XF_RI01 RnD_to_Revenue PORT_t −0.008 vs IN03 2.617 — 같은 분자, 분모 차이로 생사가 갈림 = value-scaling 메커니즘).
2. **expected_role**: core_alpha 후보이나 1차로는 screen_route=OVERLAY_CANDIDATE 개연성 (아래 ⑥). **why_now**: census_v3 (2026-06-11, 깨끗한 Z, 현 머신) 전 anchor 중 1위 — **canonical PORT_t 2.617, p 0.0089, IR 0.67, TO 2.89x/yr** (`census_v3_sweep.csv` line 29). 저회전이라 v2.4 delta 비용 체계의 수혜군. IN03은 conditional_ic_matrix에 부재 — 조건부 거동 미지(신규 검증 가치).
3. **데이터 가용성 (실확인)**: factor DB 등재 + census_v3가 이미 `load_month_factors()` 경유로 측정 완료 (233개월, 2006-12~2026-04) — **즉시 가용.**
4. **반증영역/Axiom**: **경계 사안 정직 처리** — "standalone 단일팩터 top-N" 사전제외에 형식상 저촉되나, 허용 단서("팩터군 수준 표준처치 — 전종목+composite+book-marginal — 재도전 허용")를 적용하려면 *family로 격상*해야 함: IN03 + Q26_RnD_Intensity + XF_RI01/RI03 (+ distress 필터 on/off) × 전종목 LIQ2E8 grid. 단 census_v3가 동시에 보여준 것 — 가산 composite(val_rd_wc_A 1.276)이 single(2.617)보다 나쁨 → family 처치는 가산 평균이 아니라 *필터/조건부 결합*으로 설계해야 함. AX-003(EP standalone)과는 별개 family.
5. **QEPM 풀파이프라인 적합성**: **아직 얇다 — 정직 분류: E6 Stage A 스크린(alpha-search 모드 또는 광역 screen) 선행이 맞다.** 2017+ 서브윈도우 PORT_t가 미측정(census_v3는 full-window만) — 대형주 value가 2017+ 죽은 전례상 이 관문 통과 전 풀파이프라인 투입은 비용 비대칭 위반. Stage A 통과 시에만 #1/#2와 동급 승격.
6. **리스크 + 측정 경로**: ① MDD 53.6% → calmar 0.407 — graduation calmar≥0.64 단독 불가, 게이트 2계층상 screening pass → overlay 결합 전제 (OVERLAY_CANDIDATE 라우팅). ② R&D 공시 lag PIT (C4 annual 5월) 재확인. ③ 측정 경로: census_v3 인프라 재사용 → 2017+ 서브윈도우 + 전종목 grid 사전등록(sweep, DSR 계상) → 통과 시 QEPM WT.

---

## 후보 #4 — Q07 중심 defense sleeve 재조합 (Q25 퇴출 + 내부 가중 재설계)

1. **제목/메커니즘**: defense sleeve(현 EW 1/3 고정)에서 IC-사멸 Q25_Ohlson_O를 빼고 Q07_Earnings_Stability를 승격, 내부 가중을 동적화. earnings 안정성이 최근 장세의 지배 quality 축 (b1 §1).
2. **expected_role**: defense 보강 (core_alpha 아님 — PG0 gap과 부정합). **why_now**: Q07 최근 36m IC 0.0522 1위·recent_3y_icir 0.929 (`conditional_ic_matrix.csv` line 149), Q25 0.0031 사멸 (`b1_summary.md` §1). 단 b1 §4의 반증 주의 — Q25단독-defense blend가 27m SR 2.07 최고(rank-IC와 포트 성과 괴리 실례, low-info) → 제거는 placebo 검증 후.
3. **데이터 가용성**: factor DB 기등재 (b1이 `load_month_factors()`로 측정 완료) — 즉시 가용.
4. **반증영역/Axiom**: AX-004 단서 준수 필수 — Q07 단독 승격 금지, multi-axis composite + multi-sleeve 내 Q07만 허용. defense 3팩터 복합 > 모든 단독 대체 (b1 §3: 1.044 vs 0.915~0.982)가 이를 재확인.
5. **QEPM 풀파이프라인 적합성**: **부적합 — 정직 분류: 신규 WT가 아니라 production 개선(E7 sleeve tilt) / composition_search Track C 영역.** alpha 단계가 "기존 7팩터 재가중"이라 풀파이프라인의 alpha-research를 정당화할 신규 신호가 없음. b1 §5가 이미 E7 입력으로 설계해 둠.
6. **리스크 + 측정 경로**: 27m 윈도우 PASS_LOW_INFO (Sharpe SE ±0.6) — tilt 설계는 PORT_t 실측 + placebo 의무 (b1 §5 ③). composition_search Cycle 1b Track V/W (사전등록 완료, 2026-06-11)와 중복 회피 조율 필요.

---

## 후보 #5 — Transfer-Entropy sink (섹터 정보전파 그래프 방향성)

1. **제목/메커니즘**: 섹터 간 비선형 lead-lag 정보전파 그래프에서 정보 sink(후행 수신) 종목 long — price_delay(L19)·CR07이 못 보는 *방향성* 축 (`reference_creative_alpha_idea_bank.md` Top 4 #3).
2. **expected_role**: core_alpha (미검증 직교축). **why_now**: idea bank 15건 중 cheap-screen 미실행 잔여 최상위. 단 동일 뱅크의 실측 전례가 경고 — CGO-Drift cheap FAIL, Hawkes rank-IC 통과 후 contract PORT_t −2.09 FAIL.
3. **데이터 가용성 (실확인)**: `.cache/rawdata.parquet`에 Date/Ticker/Ret/Close + Sector_Lv2 확인 — **즉시 가용** (계산비용만 큼).
4. **반증영역/Axiom**: 사전제외 비해당 (관계형 신호, factor zoo 밖). AX 충돌 없음.
5. **QEPM 풀파이프라인 적합성**: **부적합(현시점) — alpha-search 모드행.** cheap rank-IC screen → `canonical_screen_bt` PORT_t 관문 통과 전 풀파이프라인 비용 정당화 불가 (Hawkes 교훈의 직접 적용).
6. **리스크 + 측정 경로**: TE 추정 노이즈(표본 길이 민감)·C2 same-day 주의. 경로: alpha-search 모드 1편 검증 → 생존 시 QEPM 승격.

---

## 탈락 기록 (스캔 중 검토 후 제외 — 사유 명시)

| 후보 | 탈락 사유 |
|---|---|
| **전종목 value sleeve 재도전** | 오늘(2026-06-11) `WT-D20260611_001` ALPHA_REMEASURE_FAIL (2017+ PORT_t −0.135, retention 0.064) + 도훈 처분: standalone admit화 중단·조합재료 전환 (`status.json`). 재상정 금지. |
| **DART 공시 메타데이터 (idea bank #4)** | 데이터 게이트 FAIL — 일반 공시 rcept_dt 캐시 부재, insider만 2024-03~2026-03 (280종목, 24개월) — graduation 측정 불가 길이. 새 데이터 빌드는 본 스캔 제약 위반. DART API 수집 백필 후 재상정 가능 (INV-7 트리거: 데이터 연장). |
| **위험예측 시스템 반전 (분포예측+exposure 정책)** | 모드 부적합 — 이는 모듈 생산이 아니라 book overlay (Track O 영역). `program_charter.md` Cycle 1 Track O (B3 combine 재설계)가 이미 전담. QEPM은 신호-only 알파 검증·편입 모드 — exposure 정책은 forge/FR 레이어 소관. 정직 분류: QEPM 후보 아님. |

---

## 최종 랭킹

| 순위 | 후보 | 처리 |
|---|---|---|
| **1** | FLOW family E6 fair-trial (전종목+최신 데이터, Stage A→C) | **QEPM 풀파이프라인 즉시 착수 권고** — charter Track S 정합 |
| **2** | Revision Core 커버리지-유니버스 후계 재구성 | QEPM 풀파이프라인 적격 — 단 Stage A coverage-universe screen 선행 |
| 3 | IN03 intangible family fair-trial | E6 Stage A 스크린 먼저 (2017+ 관문) → 통과 시 승격 |
| 4 | Q07 defense 재조합 | QEPM 아님 — E7/composition_search Track C로 라우팅 |
| 5 | Transfer-Entropy sink | QEPM 아님 — alpha-search 모드행 |

**n_trials 회계 예고**: #1 grid 6~10 + #3 grid 6~10은 각각 사전등록 sweep — DSR≥0.5 HARD + 전량 계상. #2는 가설주도 chain 자격요건(IS-only 선택 + 진단사유 기록 + holdout 1회) 충족 시 chain 분류 가능.
