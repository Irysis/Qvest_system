# Self-Adversarial Challenge — WT-D20260714_001 (R25 FQ-004 audit-metadata)

Opus 4.8 native adversarial reasoning (v8.2 — no external Codex). Finalize-직전 devil's-advocate.
Verdict under review: **CONFIG_SCOPED_NEGATIVE** (audit-metadata exclusion not deployable in KR_top342 long-only).

## Concern 1 — 생존편향으로 exclusion 효과를 과소관측한 것 아닌가? (prereg C1)
- **Severity: MEDIUM. Classification: REBUTTAL (with concession).**
- 근거: 감사 데이터는 현재 348 constituents 대상 취득 — 비적정/going-concern 후 상장폐지된 종목의 감사 이력이 빠져 있다. 이 firms는 통상 폭락 후 퇴출 → 포함 시 flagged 그룹 수익 하락 → EW spread 덜 양(+)이거나 음(-)으로, cap-w도 더 음(-)일 수 있다. 즉 exclusion의 *잠재* 효익은 관측치보다 크다 (방향: 보수적).
- 그러나 REBUTTAL: (1) 배포 가능성 판정은 **forward-investable 대형주**에서 flag가 underperformance를 예측하는가이다. MEGA/MID tier는 생존편향과 무관하게 (관측된 대형주는 실재) 전부 insignificant. (2) 상폐 종목은 정의상 배포 유니버스 밖 — long-only exclusion으로 취할 수 있는 대상이 아니다. (3) 정량: non-clean 종목은 top-25에 0회 진입 → 생존편향을 최대로 보정해도 top-25 exclusion delta는 0에서 움직일 수 없다.
- 인정(concession): 소형주-포함 유니버스에서의 *역사적 distress 신호 강도*는 본 라운드가 과소평가 — next_probe #1로 승계.
- 학술: Beaver-McNichols-Rhie 2005 (bankruptcy prediction survivorship), Campbell-Hilscher-Szilagyi 2008 (distress risk = LOW returns, i.e. distress firms underperform — 우리 EW 양(+)부호는 그 반대 = KR small-cap size premium이 distress penalty를 압도한 sample-artifact임을 시사).

## Concern 2 — 비적정 희소성으로 검정력 벽(R24형)에 막힌 것을 "신호 부재"로 오판한 것 아닌가? (prereg C2)
- **Severity: HIGH. Classification: PARTIAL (S1 sparsity 인정 / S2-S5 REBUTTAL).**
- S1 non-clean: 순수 sparsity (2 firms) — "신호 부재" 주장 불가, 오직 "배포 유니버스 내 측정 불가". 이는 R24형 tier-국소 (distress = 소형주 현상, 대형주엔 부재). 정직 라벨: 검정력 벽 ⊂ 배포유니버스-부재.
- REBUTTAL (S2-S5): 이들은 검정력 문제가 아니다 — flagged 월평균 152(S2)/14(S3)/29(S4)건, 125개월. 표본 충분. cap-w null은 실재. 결정적 반증: **EW spread는 크게 양(+)인데 (검정력 있음) size-tier로 분해하면 SMALL tier 단독 구동** (S2 SMALL +5.90 vs MEGA -0.20). 검정력이 없는 게 아니라, 신호가 존재하되 그것이 size premium이고 exclusion 논지와 부호가 반대다.
- 자기합리화 자동검증: "미미/관행적" 미사용. "insignificant" 판정은 |t|<1 정량 근거 + 계약등급 canonical delta 0.024로 이중 확인.

## Concern 3 — KAM FY2019+ 한정의 표본 시대편중 (prereg C3)
- **Severity: LOW. Classification: ACCEPT (scope 명시로 처리).**
- KAM은 2019 실효 → S4는 2020-01+ (78개월)만. 이 구간은 covid 회복 + 2021 소형주 랠리 + 2022 하락 + 2023-24 반도체 mega-cap 레짐 (reference-kr-2025-megacap-semi-regime)을 포함 — 특이 레짐 편중. 따라서 S4 verdict를 pre-2019로 일반화 금지, verdict_scope에 "FY2019+ only" 명기.
- 처리: verdict를 period-scoped로 한정 (alpha_validation C3_kam_era_bias). full-period 판정 주장 안 함.

## Concern 4 (자발) — canonical base가 음(-1.99)인데 exclusion 판정에 오염 없나?
- **Severity: MEDIUM. Classification: REBUTTAL.**
- base_capw_top25 PORT_t = -1.994는 audit 신호가 아니라 mega-cap/cap-tilt drag (선행 라운드 다수 확립: project-megacap-anchor-construction-discovery, project-selfdev-benchaware-construction). 판정은 base 절대값이 아니라 **exclusion delta** (excl - base): going-concern +0.024, non-clean +0.000. delta ≈ 0이므로 base 음(-)은 판정 오염 아님 — 오히려 audit exclusion이 이 drag를 전혀 완화 못 함을 보인다.

## Concern 5 (자발) — S5를 "magnitude"라 부르면 prereg 위반 아닌가?
- **Severity: MEDIUM. Classification: ACCEPT.**
- prereg S4/S5는 정정 *magnitude* (재무제표 정정 vs 기재정정)를 신규 축으로 명시. 그러나 로컬 메타데이터는 정정 *rounds* (빈도-인접)만 산출 — 진짜 magnitude는 document.xml 파서 필요 (본 라운드 금지). 따라서 S5를 "FREQUENCY_ADJACENT, NOT true magnitude"로 전면 라벨, WT-005 재확인으로만 보고. 진짜 magnitude = next_probe #3 (파서 gate).

## Escalation check
- HIGH severity 건수: 1 (Concern 2, PARTIAL resolved). < 5 → escalate 불요.
- AX axiom hard FAIL: 0. PIT C1 (lockbox/lookahead) 위반: 0 (as-of join rcept_dt<=sig_date, forward return, PIT universe).
- → Q-Lead auto-escalate trigger 미발동. 정상 마감.

## Rationalization grep (self)
- 사용 회피표현 스캔: "미미/관행/보수적이면 OK/대부분 동일" → 미사용. "보수적(방향)"은 생존편향 *방향* 라벨로만 사용 (허용 — 정량 방향 진술).
- 모든 판정 = canonical/cap-w 정량 t값 + 계약등급 delta 근거.
