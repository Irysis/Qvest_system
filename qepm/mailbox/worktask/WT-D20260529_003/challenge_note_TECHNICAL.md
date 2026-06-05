# Challenge Note — WT-D20260529_003 Track TECHNICAL (alpha-research)

**Codex stance**: REJECT (gpt-5.5 xhigh). **Agent verdict**: DROP (자체 결론 일치).
**Note**: 첫 Codex round은 canonical `alpha_package_draft.json`이 병렬 VALUE track agent에 의해 overwrite되어 VALUE 내용으로 평가됨 (artifact-naming collision). track-scoped `alpha_package_TECHNICAL_draft.json`로 재실행 → 본 critique가 TECHNICAL 실제 내용 대상.

Codex stance REJECT이 agent verdict DROP과 방향 일치하므로 escalation 불요. 단 Decision Protocol에 따라 8 concern 분류 의무 기록.

## 자기 합리화 자동 검증
challenge_note 내 "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" grep → 0 hit. 합리화 표현 없음.

## 8 Concern 분류

### C1 [HIGH] — PIT expanding-IC sign-flip = C13(Z_Score_Aligned) 위반 여부
**분류: PARTIAL ACCEPT**
- Codex 지적: registry Z_Score_Aligned 대신 historical IC로 부호 flip = C13 breach.
- 반론(부분): factor_db_connector.R::align_factor_direction() v2.0 (L-168 fix)이 **정확히 동일한 방법** 사용 — "Usable_Date <= sig_date 36-month burn-in expanding-window IC로 방향 추론". 즉 인프라 표준 PIT 방향정렬과 동일. C13 금지는 *full-sample* sign-flip / arbitrary NEGATE이지, expanding-window PIT 부호추론은 connector가 채택한 정합 방법.
- 인정(부분): 그럼에도 본 cycle은 registry 명시 방향(Variant A)을 **무시**하고 데이터-구동 방향에 의존했고, Variant A(registry)는 ICIR -0.157(역전)이라 **방향 robustness가 본질적으로 취약**. 이 취약성 자체가 DROP 근거(RF-DIRECTION-PRIOR). → 결론 변경 없음(이미 DROP).
- L-code: L-168 (align_factor_direction Usable_Date PIT). 정량: Variant A ICIR -0.157 vs Variant B +0.415.

### C2 [HIGH] — C15 위반 (load_month_factors 미경유, 직접 parquet read)
**분류: ACCEPT (방법론 흠)**
- Codex 지적 타당: 본 분석은 .cache/factor_db_daily/*.parquet 및 .cache/factor_db/*.parquet 직접 read. C15는 load_month_factors() 경유 mandate.
- 사유: 11개 T factor가 **월간 DB(factor_db monthly)에 미구축**(342 factor 중 T 전무) — load_month_factors()로는 접근 불가. daily DB에만 존재. 따라서 daily에서 월말 snapshot 직접 build가 불가피했음.
- 영향: 본 신호가 admit 후보였다면 C15 정합을 위해 monthly DB에 T factor 빌드 + load_month_factors 경유 재산출 필수. **그러나 verdict가 DROP이므로 admit 경로 진입 안 함** → C15 흠은 결과에 영향 없음(연구단계 진단용).
- 후속: T factor monthly 미구축은 인프라 gap (architect 보고 권장).

### C3 [HIGH] — max_names=25 (base 20) override = process bypass + AX-007 risk
**분류: REBUTTAL (task mandate) + ACCEPT(AX-007)**
- max_names=25: task prompt 명시 "max 25 names(도훈 mandate 20→25)". 도훈 직접 mandate가 base context의 20보다 우선 (Charter: 사용자 명시 override 정당). bypass 아님.
- AX-007 (single-sleeve top25 mechanism break): **ACCEPT**. portfolio-alpha t(net)=-0.27, net SR=-0.10이 정확히 AX-007 signal→portfolio 단절을 실증. 이것이 DROP 핵심 근거.
- L-code: AX-007 (L-160/165/166). 정량: rank-IC t=3.64 (signal PASS) but portfolio-alpha t=-0.27 (translation FAIL).

### C4 [HIGH] — TO 10.17 PASS(11.0 cap)이나 net SR -0.097 = costed translation failure
**분류: ACCEPT (DROP 강화)**
- TO 11.0 cap은 task mandate (base 600%와 다름, 더 엄격). 10.17 < 11.0 PASS는 사실.
- 그러나 Codex 핵심 지적 타당: gross active +0.148%/mo가 15bps×10.17/yr에 완전 잠식 → net -0.103%/mo, net SR -0.097. **Cost-aware Alpha(research_philosophy ②) FAIL**. DROP 강화.
- 정량: gross active +0.00148/mo, cost drag ~0.00251/mo, net -0.00103/mo.

### C5 [HIGH] — FLOW 독립성: cor_vs_FLOW 0.746이 signal cor (return cor 아님)
**분류: ACCEPT (사실 정정 + DROP 강화)**
- Codex 정확: run_technical.R의 cor_vs_FLOW=0.746은 **signal-level spearman**. task는 return cor를 핵심 요구.
- 재측정: TECHNICAL composite top25 vs FLOW(REV) top25 **RETURN cor = 0.916** (검증 완료). signal cor보다 더 높음 → 수익률 비직교 더 심각.
- 결론: IC-aligned T-composite는 reversal sleeve로 수렴 → FLOW와 수익률 0.916 비직교. **5th 직교 sleeve 개구부 실패** 확정. validation JSON에 return_cor_vs_FLOW_REV=0.916 기록.

### C6 [HIGH] — Harvey N_candidates=20이 VALUE/ACCRUAL/TECHNICAL 전체 sweep 누락; 5-spec regression 부재
**분류: PARTIAL ACCEPT**
- 인정: N_candidates=20은 본 TECHNICAL track 내부 후보만(11 factor + 3 axis ×2 + 2 composite + sign-search). cross-track sweep(VALUE/ACCRUAL/TECHNICAL 동시) 미포함 → 진짜 multiple-testing burden은 더 큼 → DSR은 보고치(0.017)보다 더 낮을 것. DROP 강화.
- 반론(부분): portfolio-alpha t는 Newey-West(lag=3) 단일 회귀로 보고(harvey_t_portfolio_net=-0.27). forge 5-spec은 alpha 단계 산출물 아님 — Judge가 forge 단계에서 authoritative 채택(qvest-alpha-style 명시). alpha 단계 의무는 rank-IC t + portfolio-alpha t 둘 다 보고이며 충족.
- 정량: DSR 0.017 (이미 ≪0.5). 추가 sweep 반영 시 더 낮음 → 결론 불변.

### C7 [MEDIUM] — challenge_note/lineage/weights/cov/risk/opt package 부재 → No Silent Override + AX-008 미통과
**분류: PARTIAL ACCEPT**
- challenge_note: 본 문서로 충족.
- weights.csv/covariance.parquet/risk_package/optimization_package: **alpha 단계 산출물 아님** (Σ/weight 절대 금지 — agent_role_guard). 이들은 risk/optimizer 단계 산출물. alpha가 만들면 역할 위반. → 부재가 정상.
- AX-008 triangulation: verdict=DROP은 admit 경로 아님 → risk/opt/forge 진입 안 함. triangulation은 admit 후보에만 적용.
- lineage: DROP track은 lineage 기록 선택적. 기록 추가 권장이나 admit 미진입으로 필수 아님.

### C8 [MEDIUM] — academic mechanism 미구체 (paper/page 부재); KR reversal이 data-driven sign에서 파생(C13)
**분류: PARTIAL ACCEPT**
- 인정: 본 draft는 구체 paper/page 인용 부재. KR reversal mechanism은 메모리 learning_kr_lottery_anomaly_reversal (Boyer-Mitton 2010 + Bali 2011 KR retail lottery reversal)와 정합하나 draft에 명시 미인용.
- 반론(부분): KR 단기 reversal은 광범위 실증(Jegadeesh 1990 short-term reversal; KR 적용 다수). 단 본 cycle은 reversal을 신규 alpha로 주장하지 않고 **DROP** 결론이므로 mechanism 정당화 부담 낮음.
- C13 파생 우려는 C1 분류 참조(connector PIT 방법과 동일).

## 종합
8 concern 중 HIGH 6 / MEDIUM 2. 그러나 **모든 concern이 agent 자체 DROP 결론과 동일 방향**(net cost fail / portfolio-alpha fail / FLOW 비직교 / DSR fail). Codex REJECT = agent DROP. C5(FLOW return cor 0.916)는 사실 정정으로 DROP 더 강화. escalate trigger(REJECT+ALL rebuttal) 미해당 — agent도 DROP이므로 dispute 없음.

**최종**: TECHNICAL multi-axis composite는 (1) cross-sectional rank-IC 0.041/t=3.64 + composite>single은 진짜 발견이나, (2) net-of-cost portfolio alpha 음수 + (3) FLOW 수익률 cor 0.916 비직교 + (4) DSR 0.017 + (5) beta 1.01 분산효과 없음 → **DROP**. 5th 직교 sleeve 개구부로 부적합.
