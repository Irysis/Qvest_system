# RAMP_03C 재실행 사전등록 (측정 전 동결) — FQ-020 / 태스크 #65

**동결 시각**: 2026-07-13 (측정 스크립트 실행 전)
**owner**: Q-Lead (도훈 승인 2026-07-13)
**성격**: n_trials=1 단일 config **재현**(reproduction) — 변형·튜닝·개선 라운드 아님.
**SOT 근거**: `04_Research/01_reports/agrade_rebase_audit_20260712.md` §4.3 · `06_Registry/alpha_frontier_queue.json` FQ-020

---

## 0. 원 config 복원 — L-code 식별 (모호점 #1, 명기)

- 태스크·FQ-020 source_refs는 원 L-code를 **`L-RAMP-20260620_161507 계열`**로 표기. 그러나 `161507` = **RAMP_03 MOMCONS**(combo 3.37, book60/mine40 결합)이고, HARD 3/3 명목통과(**pt 2.98 / oos 1.19 / calmar 0.89**)를 기록한 항목은 **`L-RAMP-20260620_184815` = RAMP_03C_BOOKMOM_CAPW**이다(감사 §2 row 17에서 확인).
- **보수적 해석 채택**: "계열"(family) 표기이므로 06-20 RAMP_03 family 전체를 지칭하는 loose reference로 간주하고, 2.98/1.19/0.89 수치가 유일하게 일치하는 **`L-RAMP-20260620_184815`(RAMP_03C)의 config 문면**을 원본으로 복원한다. 161507(MOMCONS 결합)은 다른 구성(book+sleeve 결합)이므로 본 재실행 대상 아님(감사 §2 row 15 = 별도 강등).

## 1. 복원 config (RAMP_03C_BOOKMOM_CAPW, 원 L-code 문면 기준)

원문(`l_code_RAMP_03C_BOOKMOM_CAPW_20260620.json`):
> "book score(shift0 PIT-verified, 실현book 2.64와 일치) **0.5** + **모멘텀6평균 0.5** → top-25 → **cap-weight**(Size비중, [0,0.20] cap). 결과(PIT-클린 164mo): pt 2.98(net) > 배포Book 2.64(gross), pt_OOS 1.95, oos_ret 1.19 ≫ Book 0.37. 가중함수 g 비교: EW(2.65/oos0.01)·score-tilt(2.72/0.15)·cap-w(2.98/1.19). 코드 search/run_construct.R + .cache/_wgt.R"

복원 파라미터:
| 항목 | 값 | 근거 |
|---|---|---|
| book 신호 | `score_eff` (STR_1715 alpha_scores_str1715_268m.parquet), 예측월 정렬(`ny()` = 다음달 ym) → 월별 zc | run_search2_book.R L13-16 / run_construct.R L11-13 |
| 모멘텀6 | {M05_Trended_Mom, M32_Composite_Mom_v2, M09_Composite_Mom, M13_VolAdj_Mom, M01_Mom_12_1, M08_Residual_Mom} — 각 Z_Score_Aligned를 월별 zc 후 **평균** | run_search2_book.R L26 `book_mom` 유니버스(BOOK 제외 6종) + RAMP_03 MOMCONS L-code 명시 |
| 결합 score | **0.5·zc(book) + 0.5·mom6평균** | L-code "book 0.5 + 모멘텀6평균 0.5" |
| 선택 | 결합 score top-25 | L-code "top-25" |
| 가중 | **cap-weight = cap_norm(Size)** (Size비중, [0,0.20] cap, Σw=1) | L-code "cap-weight(Size비중,[0,0.20]cap)" + weight_advanced.R `cap_norm` |
| 유니버스 | K200∪KQ150 (RAWDATA) | 헌법 Production Constraints |
| 유동성 | 20일 ADV ≥ 2e8 KRW | 헌법 |
| 비용 | 15bps one-way (delta-based) | 헌법 cost_model v2.4 |
| 측정 | `weighted_screen_bt`(cap-w 임의가중 → build_benchmark_compare NW lag-3) + `essence_score`(oos v2, calmar) | 계약 authoritative, proxy 손계산 금지 |

**부수 진단(원 pattern 재현 확인용)**: 동일 top-25 selection에 EW·score-tilt·cap-w 3가중 병렬 산출 → 원 기록 EW 2.65 / score-tilt 2.72 / cap-w 2.98 pattern 재현 여부 확인.

## 2. 모호점 & 보수적 해결 (전부 명기 — 임의 보완 금지)

| # | 모호점 | 보수적 해결 |
|---|---|---|
| #1 | L-code cite 161507 vs 실제 184815 | §0 — 2.98/1.19/0.89 일치하는 184815 문면 채택 |
| #2 | **164mo 창의 정확한 월-집합** = 소실된 `_bo_fwdgic.rds` fwd_dates에서 유래. 생존 입력(book 268mo·6mom 2005+·carrier 256mo) 어느 것도 164mo를 자연 생성하지 않음 | book PORT_t 5.01(256mo)→2.64(164mo) 감쇠는 **트레일링 최근 창**과 정합(post-2017 감쇠). → **① full 자연창(~256mo) 1급 측정 + ② trailing-164mo 부창 병기**. 어느 창이 원 2.64 book-pt를 재현하는지 실측으로 164mo 정의 pin. 단일 창 임의 선택 금지 |
| #3 | 모멘텀6 = 개별 z 평균 vs 평균 후 재-z | run_construct의 factor별 `zc()` 패턴 → **개별 zc 후 평균** 채택(primary). 경계 판정 시 대안(평균 후 zc) 민감도 병기 |
| #4 | **벤치 basis**: RAMP-native cap-w 프록시(build_monthly_forward_returns, RAWDATA에서 신선 산출 = 원 RAMP가 실제 사용) vs 태스크 지정 교정 IKS200(benchmark.parquet) | **양측 병기.** RAMP-native 프록시 = 원 방법 충실 재현(권위 후보) / IKS200 교정 = 태스크 재베이스 지정. **가장 보수적 = 둘 다 통과해야 pass 주장.** ⚠ 원 RAMP는 IKS를 쓰지 않았으므로 "IKS001→IKS200 벤치버그"는 RAMP에 직접 적용 안 됨 — RAMP의 "벤치버그기" = RAWDATA April-gap 미백필분(1개월, 말단, 영향 미미) |
| #5 | oos_retention basis | 원 `_wgt.R`가 run_construct `oosr(ret_net−benchmark_ret)` 사용 = cap-w bench active. essence_score와 동일 컨벤션 → cap-w bench active로 산출 |

## 3. 사전 예상치 (측정 전 동결 — 하락 방향 명시 의무)

**예상: HARD 3종 통과 실패(강등) 방향.** 근거:
1. **재베이스 선례 전량 하락**: 벤치버그기 A급 2건 재베이스가 PORT_t 2.52→1.94, 1.94→1.37로 큰 폭 하락(감사 §3.1). 방향 동일 예상(단 다른 창·주기라 수치 이전 불가, 방향만).
2. **경계값(+0.03)**: 원 2.98은 문턱 2.95를 +0.03만 초과 — 재측정 노이즈로 쉽게 미달 전환.
3. **cap-weight ↔ cap-tier 국소화 긴장**: [[project-captier-alpha-localization-20260706]] "mega-cap signal-dead" — cap-weight는 mega-cap에 비중을 실어 신호를 희석하는 방향. cap-w가 원 기록서 OOS 레버였다는 주장(oos 0.01→1.19)은 이 실측과 상충 → 재현 시 oos_retention 하락 예상.
4. **full-window 확장**: 원 164mo(트레일링, book-pt 낮은 창)에서 full ~256mo로 확장 시 초기(2005-2011) 고알파 구간이 book 대비 상대성과를 바꿀 수 있음 — 방향 불확실이나 보수적으로 미달 가정.

**예상 미충족 시**(= HARD 3종 실측 통과) → 재현 성공으로 정직 보고하되, 자본 편입은 governor 수동(도훈 confirm)임을 명기하고 벤치버그 아티팩트 격리(challenge #2) 재검토.

## 4. 판정 기준 (동결)

graduation HARD 3종 (measurement-graduation §3):
- **cap-w PORT_t (NW lag-3) ≥ 2.95** (권위 basis)
- **oos_retention v2 ≥ 0.7** (band [0.5,0.7) = 보강증거 2/3 escalation)
- **calmar ≥ 0.64** (own NAV, 벤치독립)

+ dual-basis 병기(EW-uni 진단, M2) + 원 기록(2.98/1.19/0.89) 대비 Δ. **판정 = 두 벤치 basis 모두 통과 시에만 "재현 통과" 주장**(가장 보수적). 자본 편입 = governor 정지(도훈 수동).

## 5. 거버넌스 · pin

- canonical 경로만(weighted_screen_bt/essence_score — proxy 손계산 금지). R = .R source·setDTthreads(1)·arrow io(2)·백테 전 잔류 R 프로세스 0 확인(완료).
- vintage pin: `pin_cache(c(RAWDATA, benchmark.parquet), tag="ramp03c_rerun_20260713_*")` — pin tag를 산출물 manifest에 기록(measurement-graduation §7).
- config hash: 복원 config JSON md5 → verdict.json 기록.
