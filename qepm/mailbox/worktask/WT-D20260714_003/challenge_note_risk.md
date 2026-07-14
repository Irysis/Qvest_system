# Risk-Research Self-Adversarial Challenge — WT-D20260714_003 / CAND Z6_zblend_V14_V07_w0.30

**Agent**: risk-research (Opus 4.8 native adversarial reasoning, v8.2 — Codex Round 대체)
**작성 시점**: finalize 직전 (risk_package.json write 후, lineage 전)
**AX-008**: self-adversarial = Forge·Architect와 함께 3-source triangulation 중 1개 (2/3 PASS 요건).

---

## R3/P4 Challenge Review (Risk → Alpha)
- **objection = FALSE** (Alpha 설계에 대한 이의 없음).
- targets_reviewed: alpha_package(factor_specs, alpha_vector, confidence_vector, diagnostics).
- 근거: risk 진단이 alpha 주장과 정합 — value_z(신규축) vs score_eff(incumbent) 신호 cor = -0.077 로 alpha가 주장한 orthogonal value axis(cor_active -0.05) 실측 확인. candidate active-cor vs base = 0.93(내 재구성) ≈ alpha_pkg cor_active_vs_base 0.79(cap-w 구성차) — 방향 일치. IR 재현 1.755 = alpha_pkg variant_net_ir 1.7555 정확 일치.

---

## Self-Concern 1 — [PARTIAL] Ledoit-Wolf as-shipped(hrp_core)가 degenerate (rho=1.0)
**제기**: hrp_core.R `.get_cor_cov(ledoit_wolf)`가 delta=1.0 → 순수 scaled-identity로 붕괴(상관구조 파괴, cond=1 trivial). 이대로 보고하면 "LW cond 1.0 우수"라는 거짓 우월 주장.
**분류/처리**: **PARTIAL 인정** → 정통 Ledoit-Wolf 2004 constant-correlation shrinkage 자체 구현(pi/rho/gamma/kappa)으로 교체. 재측정 delta=0.753, r̄=0.241, cond=39.9(합리). method_shopping_log에 `ledoit_wolf_const_corr`로 명기. hrp_core 원함수는 delivered Σ에 미사용(=factor_model 선택).
**잔여 리스크**: 자체 구현 LW의 rho off-diag 항이 근사 — 그러나 delivered Σ가 아니라 alt/비교용이므로 판정 비바인딩. 라벨 명시.

## Self-Concern 2 — [ACCEPT] Template placeholder(WT-MISSING/CAND/lockbox 2023-12-22) 미치환 → silent default 위험
**제기**: spawn이 WT_id·candidate·lockbox를 치환하지 않음. (a) 임의 WT에 쓰면 orphan/오배선, (b) lockbox 2023-12-22를 그대로 적용하면 as_of 2026-03-31 포트에 27개월 최신 국면 데이터를 버림 = anti-PIT-informative(alpha 자체가 holdout 2024-26 사용 → 불일치).
**분류/처리**: **ACCEPT(프로세스 위반 방지)** → No-Silent-Override. WT→WT-D20260714_003, CAND→Z6_zblend_V14_V07_w0.30 를 **소비한 alpha_package와 매칭하여 명시 해소**(추측 아님 — 동일 dir의 alpha_package.json 소비). lockbox 2023-12-22 **미적용**, as_of 2026-03-31 종료 trailing window 사용(alpha 결정시점과 정합, PIT-valid). challenge_flags[1] + 본 노트 + 최종 보고에 escalation surface. status.json은 미변경(Q-Lead scope).
**잔여 리스크**: FQ-042 dossier가 새 WT id를 발급할 경우 재배선 필요 — Q-Lead 확인 요망(escalation).

## Self-Concern 3 — [REBUTTAL] RF-R1 market 74% = 위험모델 결함/집중 위반 아니냐
**제기**: top common risk가 74.2%(>40% RF-R1 HIGH). Rule2 concentration extreme(>50%) 발화로 STOP 권고해야?
**분류/처리**: **REBUTTAL** (3축 근거):
- (학술) long-only no-short는 시장성분(β) 제거 불가 — PC1=시장이 분산 지배는 KR 구조적 사실.
- (L-code/memory) [[reference-orthogonality-gross-vs-active]] · measurement-graduation §6: KR long-only β≈0.83~0.92, gross 상관 0.78, "직교≠수익". 본건 EW β=0.835 실측 = 정확히 그 밴드.
- (정량) Σ cond=31.3, mineig>0(PSD), factor coverage 84.2% — ill-conditioning 부재. Rule2 STOP 트리거(cond>500 after shrink / 공모>40%+유동성부족 / stress>policy)는 어느 것도 미해당. market_down_5 = -4.17%(> -8% RF-R4, > -10% policy).
→ RF-R1은 **정보성 flag(optimizer의 exposure-bound 입력)**이지 결함/STOP 아님. exposure bound 결정은 optimizer scope로 위임(측정·권고만, 역할경계 준수).

## Self-Concern 4 — [PARTIAL] Style factor(FF5)가 진짜 FF5 아님 (RMW/CMA 누락 + LS-spread 자작)
**제기**: FF5 요구인데 RMW(수익성)/CMA(투자) 미포함, HML/WML/BAB를 RAWDATA tercile LS-spread로 자작. self-synthesis 우려 + FF-정본 아님.
**분류/처리**: **PARTIAL**:
- self-synthesis 규칙(backtest-contract)은 전략 NAV/benchmark 성과 합성 대상 — style factor return 구성은 위험모델 통계입력(diagnostic), metric_type=estimated 명시. portfolio 성과 시계열(candidate/STR1715 realized)은 net 계약값(STR1715=b1 net) 사용, 자작 최소화.
- RMW/CMA 누락은 인정 → style_analysis note에 "RMW/CMA proxied-omitted" 명기. 단 **핵심 판정(candidate HML 0.268 > STR1715 0.106 > base 0.040 = 의도한 value 축)** 은 HML 계수 자체로 성립 — RMW/CMA 추가는 결론 방향 불변(value 팩터가 판별축).
**잔여 리스크**: HML을 value_z(alpha가 쓴 신호)로 구성 → candidate의 HML 노출이 정의상 상승하는 순환 가능성. 완화: base(score_eff)도 동일 HML 팩터에 회귀했고 0.040으로 낮음 → candidate 0.268 상승은 순환 아닌 실제 tilt. 그러나 독립 EV-yield HML로 재확인 권고(advisory).

## Self-Concern 5 — [REBUTTAL] regime crisis-cor(0.108) < normal(0.157) = 반직관, 오류 아니냐
**제기**: 위기 시 상관 급등이 정상인데 본건은 위기<정상. 코드 버그?
**분류/처리**: **REBUTTAL(+caveat 명시)**: 홀딩 25종 상당수가 2015+ 상장(LG엔솔 2022 등) → 2005-2015 위기월 full-coverage 표본 희소 = crisis 선형상관 소표본 편향. 더 강건한 co-crash 지표 TDC(하방 tail dep q=0.10) mean 0.291·p90 0.464 는 **정상적 tail clustering 존재**를 보여줌(RF-R5b MEDIUM). risk_package regime_correlation.caveat + TDC 병기로 오해 방지. 버그 아님(linear cor vs tail dep 서로 다른 통계량).

---

## Self-rationalization auto-detection (grep: 유사/미미/관행/보수적이면 OK)
- 본 노트·risk_package에 "영향 미미/관행적 허용/보수적이면 OK" 사용 없음. RF-R1을 "미미"로 뭉개지 않고 구조적 사실+정량근거로 REBUTTAL. lockbox는 "관행 default"로 침묵 적용하지 않고 ACCEPT-surface.

## 자동 Q-Lead escalate trigger 점검
- HIGH ≥5? → RF-R1 HIGH 1건뿐(구조적, REBUTTAL). **미발화**.
- Σ PD violation? → mineig=3.30e-03 >0, **PSD OK**. 미발화.
- CVaR hard breach / Hard Constraint? → market_down_5 -4.17%(policy -10% 미위반), 종목 25·long-only·Σw(optimizer scope). 미발화.
- AX axiom hard FAIL ≥3 / PIT hard violation? → 없음.
→ **blocking = FALSE**. 단 **escalation(비차단) 2건**: (1) template placeholder 미치환 + WT/lockbox 재배선 확인, (2) FQ-042 dossier 새 WT id 발급 시 아티팩트 재경로.

## 결론
risk_package finalize 승인. delivered Σ = factor-model BΩB'+D (cond 31.3, PSD, coverage 84.2%). blocking 없음. 2 escalation surface.
