# Challenge Note — WT-D20260529_002 Track DISPERSION (alpha-research)

**Codex stance**: REJECT (7 concerns: 4 HIGH / 3 MEDIUM; veto_flag=false)
**Agent self-verdict**: DROP (모든 graduation gate FAIL — Codex와 방향 합치)
**Charter §8 No Silent Override 준수**: 각 concern 분류(ACCEPT/PARTIAL/REBUTTAL) + 근거

## 자기-합리화 자동 검사 (Codex rationalization_red_flags 직접 대응)
Codex가 지적한 표현 6건을 점검하고 정정:
- "best-available estimate-uncertainty proxy" → 사실 진술로 retain하되, **C2 ACCEPT로 verdict 프레임을 "proxy failure"로 변경** (KR-DMS 판정 아님).
- "statistically zero regardless" → 정량 근거로 대체: rank_ic=−0.0012, NW t=−0.147, |t|<<1.96. 합리화 아닌 측정값.
- "does not survive in KR" → **삭제**. 정정: "본 *temporal-CV proxy*는 KR에서 예측력 없음. 이는 DMS *cross-analyst* dispersion의 KR 판정이 아님 (입력 데이터 부재)."
- "Honest finding (AX-000)" while true DMS input unavailable → C2 ACCEPT: proxy 한계와 DMS 판정을 명시 분리.
- "conservative N0=6" → C6 ACCEPT: N0=9 (3 internal + 6 sibling)로 정정. DSR 0.129는 N0 무관 FAIL.
- challenge_note_PEAD "immaterial" (sibling 파일, 본 track 무관) → 본 note에서는 PIT-fix 영향을 **정량 delta(−0.00015)** 로만 보고, "immaterial" 라벨 대신 수치 제시.

## Escalate trigger 점검
- HIGH severity ≥ 5: HIGH=4 → 미충족.
- AX axiom hard FAIL ≥ 3: 해당 없음 (self-verdict=DROP, admit 시도 아님 → AX-007 예외 입증 불요).
- PIT C1 lockbox/lookahead 위반: **없음** (C4 strict t-1 재감사 결과 PIT가 결과를 inflate하지 않음, 아래 C4 참조).
- Codex stance=REJECT + agent ALL-rebuttal? → 아님. 대부분 ACCEPT/PARTIAL, verdict 합치 → escalate 불요.

---

## Concern 분류

### [C1] HIGH — 모든 alpha gate FAIL, anti-theory decile → **ACCEPT**
rank_ic=−0.0012, ICIR=−0.0117, Harvey rankIC t=−0.147, portfolio t=−1.323, DSR=0.129, monotonicity=−0.855.
**완전 동의.** "weak alpha"가 아니라 anti-theory ordering의 non-signal. 자체 verdict도 DROP.
근거: graduation 6/6 FAIL + decile dec1(low-disp)=0.11%/mo → dec10(high-disp)=0.89%/mo 단조 상승(DMS 정반대).

### [C2] HIGH — temporal-CV proxy ≠ DMS cross-analyst dispersion → **ACCEPT (핵심 reframe)**
**완전 동의 + verdict 프레임 변경.** QuantiWise consensus export는 (Date,Ticker)별 **aggregate point value** (consensus-MEAN eps_1y, coverage, esbr, sue)만 제공. per-analyst estimate panel과 estimate-stdev/high-low field가 **부재** → DMS canonical std/|mean| (cross-analyst) **계산 불가**.
사용한 proxy = 63일 rolling std(consensus-MEAN) / |mean| = **temporal forecast instability**. 이는 cross-analyst disagreement가 아님.
→ verdict를 "KR에서 DMS dispersion 실패"가 **아니라** "**(a) 가용 proxy는 KR 예측력 없음 + (b) 진짜 DMS 입력은 본 인프라에서 측정 불가(infeasible)**"로 명시 분리. L-code 적립 시 "DMS KR negative"로 일반화 금지 (Codex rebuttal item 6 수용).

### [C3] HIGH — negated 구성 + 열등 variant 선택 + C13/C15 → **PARTIAL/ACCEPT**
- **negation**: alpha=−dispersion은 DMS prior(high disp → low ret)의 정직한 부호. raw(un-negated) IC=+0.0012, negated IC=−0.0012 — 둘 다 zero. 부호 선택이 결론 바꾸지 않음.
- **열등 variant 선택**: method_log에서 negated(−0.0012) < raw(+0.0012) < high-cov(+0.0116). 셋 다 |IC|<0.04 FAIL. "더 나은 variant 누락" 지적 타당하나 admit 가능 variant 없음 → DROP 불변. **ACCEPT** (전수 보고).
- **C13**: cross-sectional scale() 사용은 Z_Score_Aligned 미경유. DISPERSION은 신규 설계 factor(registry 미등재)라 sign-align IC history 없음 → direction은 economic prior(DMS)로 명시. registry 등재 시 Z_Score_Aligned 의무 **ACCEPT**.
- **C15**: `.cache/consensus/*.parquet` 직접 read는 load_month_factors() 미경유. **신규 factor 설계(scope 2-B/2-C: db_derived) 경로에서 consensus cache 직접 가공은 init prompt 허용**. production 승격 시 factor_db builder 통합 의무 **ACCEPT**. DROP이라 통합 불요.

### [C4] HIGH — same-day circular liquidity (adv20 align='right' on sig_date) → **ACCEPT + 검증완료**
**인정 + 즉시 재감사.** robustness_dispersion.R로 strict t-1 (adv20_lag + K200_lag/KQ150_lag) 재계산:
- 원본(same-day filter): rank_ic=−0.0012
- C4-FIX(t-1 liq+membership): **rank_ic=−0.0013, ICIR=−0.0130, 245행 drop**
→ delta=−0.00015. **PIT가 결과를 inflate하지 않음** (양쪽 모두 near-zero non-signal). liquidity/membership은 tradability screen이지 return predictor 아님. verdict DROP 불변. 정량 입증.

### [C5] MEDIUM — Charter §8 evidence 부재 (challenge_note/lineage/risk/opt 등) → **PARTIAL**
**부분 인정.** (1) challenge_note_DISPERSION.md = 본 파일(생성). (2) artifact_lineage.json DISPERSION entry → finalize에서 append. (3) weights.csv/covariance.parquet/risk_package/optimization_package는 **후속 agent(risk/optimizer) 산출물** — alpha 단계(pipeline 1/6) 부재가 정상. DROP verdict라 후속 pipeline 미진행 → triangulation(AX-008) 적용 대상 아님.

### [C6] MEDIUM — RF-A6 N0 과소 (internal variant + sibling 무시) → **ACCEPT**
**인정.** N0=6 → **N0=9** 정정 (3 internal DISPERSION variant + 6 Cycle-3 sibling tracks). DSR=0.129는 N0=6 기준이며 N0=9에서 더 낮아짐 → durable negative finding의 search budget 정확 보고. verdict 강화.

### [C7] MEDIUM — RF-A4 sector-neutral 검증 부재 → **ACCEPT + 검증완료**
**인정 + 즉시 검증.** sector field가 panel에 없어 Size-decile(10그룹) 내 demean으로 size/composition 효과 제거 후 재계산:
- raw rank_ic=−0.0012, **size-neutral rank_ic=−0.0014** (retention 116%).
→ 신호는 size/composition artifact가 **아님** — 중립화 후에도 동일하게 zero. stock-level analyst-dispersion proxy 자체가 무신호임을 확인.

---

## 종합 disposition
- **ACCEPT**: C1, C2(reframe), C3(C13/C15), C4(+검증), C6, C7(+검증)
- **PARTIAL**: C3(variant), C5(후속 agent 산출물)
- **REBUTTAL**: 없음 (Codex 지적 전부 타당, verdict 방향 합치)
- Codex REJECT ↔ agent DROP: **결론 합치**. No silent override 없음.

## Codex rebuttal_required 6항목 disposition
1. challenge_note + lineage append → **완료** (본 파일 + finalize).
2. strict t-1 liquidity/membership 재감사 → **완료** (C4, delta −0.00015).
3. C13 direction attestation + C15 carve-out → **완료** (C3, prior-based direction + db_derived 경로 명시). 또는 proxy-failure 라벨 → **채택**.
4. sector-neutral-after ICIR + variant 비교 → **완료** (C7 size-neutral + method_log 3-variant).
5. DSR full variant + cross-track budget → **완료** (C6, N0=9).
6. KR DMS negative L-code를 proxy 한계와 분리 → **채택** (C2 reframe).

## 최종 verdict
**DROP (proxy-infeasibility + non-signal).** 두 층위로 정직 보고:
1. **측정 가능한 proxy (temporal-CV)**: KR 2014-2023 lockbox에서 예측력 통계적 zero (rank_ic −0.0012, t −0.147, DSR 0.129, size-neutral −0.0014, strict-PIT −0.0013). 직교성은 우수(vs STR_1715=0.192, vs D=0.043, vs FLOW=−0.071, 전부 <0.30 mandate PASS)하나 무신호의 직교성은 book 다각화 기여 0.
2. **측정 불가능한 진짜 DMS dispersion (cross-analyst std)**: 본 인프라(QuantiWise aggregate-only export)에서 **infeasible** (AX-000 정직 보고). DMS 2002의 KR 판정은 본 결과로 내릴 수 없음 — per-analyst estimate panel 확보 시에만 가능.
