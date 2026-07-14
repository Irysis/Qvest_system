# Forge Self-Adversarial Challenge — WT-D20260714_006 (B2_value_nonmega_conditional)

**v8.2 Self-Adversarial (Codex Round 대체, Opus 4.8 native). finalize 직전 약점 자가제기 → 분류 → 처리.**
**AX-008 3-source 중 1개 (Optimizer challenge·Architect와 함께 2/3 PASS).**
날짜 2026-07-14 / role = forge pure-function / bt integrity=WARNING(audit PASS) / hash immutable=TRUE.

핵심 실측: SR_realized(total,m)=0.929 · IR_active(m)=0.520 · CAGR 20.8% · MDD -44.7% · Calmar(daily)=0.378 · PORT_t(daily NW l3)=2.74 · TO_rt 8.90 · overlay SR(est)=1.113.

---

## 자가제기 약점 (5건)

### F1. divergence -0.545 (forge IR 0.52 vs factor_engine 1.065) = FABRICATION_SUSPECTED 문턱(0.6) 근접. schedule fidelity 위반인가?
**분류: REBUTTAL (검증 완료)**
- weights.csv 268-date를 **AS-IS 소비** — alpha_scores top-N 재선택 없음, schedule 재생성 없음(`schedule_fidelity.reselection_from_alpha_scores=FALSE`, `consumed_as_is=TRUE`). setorder+head 패턴 부재. Schedule Fidelity Mandate 준수.
- divergence는 **기계적**이고 분해됨: (a) 동일기간(≤2026-03, 267m) forge IR=0.741 vs 1.065 → -0.324 = share-based floor(shares)+일간경로+delta-cost + 실현 TE 0.169(optimizer 예상 0.135 대비 高 — continuous weighted_screen이 active vol 과소평가). (b) deploy-extension 4m(2026-04~07 frozen, mean active -9.4%/m)이 full-period IR을 0.741→0.520으로 추가 견인. 둘 다 fabrication 아님.
- full-period -0.545 < 0.6 문턱 → **SIGNIFICANT_DRAG**(fabrication 아님). forge 실측이 오히려 screening-tier verdict를 독립 확증 — OOS(2024+) IR -0.82로 factor_engine 1.065(IS-heavy)보다 나쁨을 실현 basis로 드러냄.

### F2. PG2 overlay SR 1.113은 fabrication 아닌가? (β ladder 임의 매핑)
**분류: ACCEPT (라벨 명시)**
- `metric_type=estimated` 명기. β ladder {BULL/NORMAL=1.0, CAUTION=0.7, CRISIS=0.4}는 carrier decision_date(prior-month PIT) regime schedule에 적용한 **투명 시나리오** — production 정확 β와 다를 수 있음 명시(`pg2_overlay_scenario.note`).
- C5 overlay 타이밍 준수: regime은 holding월 시작 전(decision_date=전월 1일) 확정분만 사용 → 동월 look-ahead 없음(riskoverlay FALSIFIED 사건 방지).
- optimizer ESTIMATE ~1.8과 divergence 큼 — 내 투명 시나리오(1.11)가 더 보수적. 이유: optimizer는 incumbent 98% corr × 1.84로 추정했으나, 본 후보의 style-rotation 감쇠는 market-regime overlay가 헤지 못함(caveat 명시). **forge-authoritative 아님** — judge는 bare SR 0.929를 권위로 사용.

### F3. bt integrity=WARNING (3 WARN: lookahead_bias_checked / c15_factor_db_load_path / lookahead_detector_self_scan). PIT 우회 아닌가?
**분류: REBUTTAL**
- 3 WARN 전부 **forge 역할 특성**: forge는 lockbox-scope 폐기 대상(정규 리서치 alpha/risk/optimizer만 lockbox 적용). forge는 weights.csv를 소비하지 factor_db를 직접 load 안 함 → `factor_engine_path` 부재는 정상(C15 self-scan skip). PIT은 signal-construction(alpha, cutoff 2023-12-22) 단계에서 강제됨.
- critical FAIL 0 → audit_bt_result=PASS. integrity=WARNING은 severity=medium WARN에서 유래(official metrics 차단 없음). hash immutable=TRUE로 3-package 불변 입증.

### F4. gross/net 2-pass 방식 — floor(shares)가 gross/net에서 달라 cost 추정 왜곡?
**분류: PARTIAL (ACCEPT-기록)**
- gross(0bps)/net(15bps) 독립 2-pass → floor(shares)가 미세하게 달라질 수 있음(cash 잔액 차이 → target_shares 반올림 경계). cost_ret = gross-net은 근사.
- 단 SR/IR/CAGR/MDD **권위 지표는 전부 NET path 단일 소스**에서 산출 — gross는 cum_cost 표기용 보조. 판정 왜곡 없음. build_bt_result 계약 경로(PerformanceAnalytics) 사용, 자체합성 없음.

### F5. benchmark 정합 — forge는 benchmark.parquet(KOSPI200), optimizer canonical은 다른 벤치? IR 비교가 apples-to-oranges?
**분류: REBUTTAL**
- weighted_screen_bt는 `benchmark_id="KOSPI200_total_return"`(BM_Ret) — forge benchmark.parquet과 동일 개념(교정된 IKS200 KOSPI200). 벤치 basis 정합 → divergence는 벤치 아티팩트 아닌 실제 share-based drag.
- 월별 정합: strategy·BM 동일 calendar-YM 일간윈도우 aggregation(realized_ym lag 사건 회피). active series 노이즈 최소.

---

## 분류 요약

| ID | 약점 | 분류 | 처리 |
|---|---|---|---|
| F1 | divergence -0.545 fabrication 근접 | REBUTTAL | schedule as-is 입증 + 기계적 분해(matched 0.74 + deploy-ext) |
| F2 | overlay SR fabrication | ACCEPT | estimated 라벨 + C5 PIT + forge-authoritative 아님 |
| F3 | integrity WARNING | REBUTTAL | forge lockbox-exempt, critical FAIL 0, audit PASS |
| F4 | gross/net 2-pass floor 왜곡 | PARTIAL | net 단일소스 권위, gross 보조 |
| F5 | benchmark 정합 | REBUTTAL | KOSPI200 동일 basis, YM 정합 |

**Q-Lead escalate trigger**: Hard Constraint 위반 0 (25종/Σw=1/[0,0.20]/long-only/TO 8.90<=11). hash immutable TRUE. audit critical FAIL 0. AX 위반 0. schedule fidelity 위반 0 (pure_function_violation=FALSE). → **escalate 불요**.

## 결론
Forge pure-function 통합 완료 — target_weights/cov/alpha 무수정, weights.csv AS-IS. Share-based 실측(net 15bps)은 **screening-tier verdict를 독립 확증**: PORT_t(daily) 2.74 < 2.95 HARD, Calmar 0.378 < 0.64 HARD 둘 다 미달, OOS(2024+) IR -0.82. SR 2.5 도달 불가(bare 0.929 / overlay est 1.11 / book-marginal ~0). divergence -0.545는 fabrication 아닌 share-based+deploy-extension 기계적 drag. No silent override — 정직 판정을 judge로 전달.
