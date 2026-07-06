# Self-Adversarial Challenge — Alpha (WT-D20260706_MIDCAP)

**Agent**: alpha-research | **Date**: 2026-07-06 | **AX-008 self-adversarial (Opus 4.8 native)**

Alpha = tier-conditional (mid-cap emphasized) `score_eff` (tierEmph_B). Challenge finalize 직전 자체 적대검증.

## Concerns raised (devil's advocate) + classification

### C-1 [ACCEPT] "이 알파는 orthogonal sleeve가 아니다 — score_eff의 tier-restriction일 뿐"
- 측정: cor(tierEmph_B, score_eff) = **0.973** (cross-sectional, month-avg). 이건 새 정보원이 아니라 기존 PG2 incumbent 알파를 size-tier로 재가중한 것.
- **분류 ACCEPT** (명백): success_criterion "orthogonal book-marginal ΔIR≥0.05" 의 orthogonality 전제가 alpha 단계에서 이미 무너짐. spec에 redundancy_cluster_id로 명시, CF-1 HIGH 기록. spec 수정: "orthogonal sleeve" 주장 철회 → "tier-restriction of incumbent" 정직 라벨.

### C-2 [ACCEPT] "within-tier LS-t가 높아도 cap-w 벤치 대비 active는 음수일 것 (trap)"
- 측정: canonical top-25 EW vs cap-w KOSPI200(IKS200, monthly-aligned) post-2017 active_t = **−0.49** (tierEmph_B), **−1.26** (MIDonly). oos_v2 = **−0.231** (HARD FAIL <0.5).
- **분류 ACCEPT**: mid-cap 집중이 cap-w active를 오히려 악화(base −0.50 → MIDonly −1.26). 상대(within-tier) 엣지가 절대(vs cap-w) active로 전이 안 됨. CF-2 HIGH.

### C-3 [PARTIAL] "엣지 자체가 spurious한 것 아닌가 (과적합/lookahead)"
- 반박 근거 (정량 3축): ① lag+1 PIT stress — real IC 0.0435(t5.74) > lookahead IC 0.0289 (leakage 없음, PIT graceful) ② placebo — shuffled-alpha IC −0.004(t−0.88) null ③ vs EW-universe benchmark post-2017 t=1.58 (fair-peer 상대 엣지는 실재).
- **분류 PARTIAL**: 엣지는 spurious 아님 (vs EW-univ 실재). 단 mandate 벤치가 cap-w이므로 배포 가치는 없음. "엣지 있음 ≠ cap-w book 기여." CF-3 MEDIUM.

### C-4 [PARTIAL] "tier 경계 11-30이 cherry-pick 아닌가"
- 측정: within-tier LS post2017 t = 11-25:1.90 / 11-30:2.80 / 11-40:2.14 — 선택한 11-30이 peak. mild boundary-selection.
- **분류 PARTIAL**: 방향(MID이 live tier)은 robust하나 magnitude는 경계 민감. 단 이 caveat는 verdict를 바꾸지 않음 — 어느 경계든 cap-w active는 음수. CF-4 MEDIUM.

## Self-rationalization auto-detection
"미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" 사용 여부 자기검증: **미사용**. 모든 판정은 실측 수치(canonical PORT_t·oos_v2·orthogonality) 기반. 회피표현 없음.

## Escalation check
- HIGH severity = 2 (CF-1, CF-2) < 5 → auto-escalate 미발동.
- AX axiom hard FAIL / PIT C1 위반 없음.
- **결론**: escalate 불요. 정직 negative measurement로 downstream 진행.

## Verdict
Guarded prior가 crude 진단으로 주장한 cap-tier trap을 **정식 파이프라인 alpha 단계에서 confirm**. tier-conditional 알파는 (a) not orthogonal (0.973) (b) cap-w post-2017 active 음수 (c) oos_v2 HARD FAIL. Success criterion 대비 **PREDICTED_FAIL**. Downstream(optimizer/forge)이 authoritative 확정하되, alpha-stage 증거가 이미 명확. AX-000: 조기 한계단정 아님 — 완결된 measurement.

---

# Self-Adversarial Challenge — Risk (WT-D20260706_MIDCAP)

**Agent**: risk-research | **Date**: 2026-07-06 | **AX-008 self-adversarial (Opus 4.8 native)**

Risk = Σ = BΩB'+D (market + market-orthogonalized sector factors), cond=42.4, PSD. Role: Σ + tail + stress + crowding + concentration ONLY. No alpha edit, no weights. Challenge finalize 직전 자체 적대검증.

## Concerns raised (devil's advocate) + classification

### C-1 [ACCEPT-PARTIAL] "GPD tail fit이 신뢰불가 (xi=-1.38 비정상)"
- 측정: 120개월 중 q90 초과 exceedance ~12개뿐 → GPD MLE 불안정, xi=-1.38 (bounded-tail 아티팩트). EVT 패키지(fExtremes/evir) 미설치라 inline MLE 사용.
- **분류 ACCEPT-PARTIAL**: EVT-GPD를 어떤 gate에도 사용 안 함. empirical ES95=-14.4%/ES99=-16.9% (n=120서 well-defined) 주도 + Hill α=1.49로 heavy-tail 판정. tail_risk.json에 evt_gpd confidence=LOW 명시.

### C-2 [ACCEPT] "장기 위기(GFC/EuDebt) stress가 book_coverage<0.85인데 수치를 인용"
- 측정: GFC bookcov=0.50, EuDebt 0.58, China2015 0.71, KR_Bear2018 0.79 — mid-cap 종목 미상장분 아티팩트. reliable = (months≥50% ∧ bookcov≥0.85)로 판정 → 4개 UNRELIABLE 라벨, hard-fail 아님(skill 준수). COVID(0.88)·RateHike2022(1.0)만 reliable.
- **분류 ACCEPT**: skill "book coverage<85% 구간은 UNRELIABLE 명시(부분 상장 아티팩트 hard-fail 금지)" 정확 준수.

### C-3 [REBUTTAL] "60개월 cov window가 과소 — 추정 불안정 아닌가"
- 반박 (정량 3축): ① 24 신모델명 중 반도체/mid-cap 최근상장으로 complete-case 60개월이 최대 ② factor model BΩB'+D는 저랭크 정규화로 60-obs sample(cond=128)보다 cond=42로 개선, 둘 다 PSD·<500 ③ 추정기 선택 objective=condition_number (return-based 금지 준수, method_shopping 4후보 로그).
- **분류 REBUTTAL**: window는 데이터-제약(mid-cap 특성)이지 방법 결함 아님. factor model이 shrinkage 역할.

### C-4 [ACCEPT] "market β가 처음 ~0으로 나온 건 명백한 모델 오류"
- 초기 sector-EW 팩터가 market과 collinear → market 계수 흡수(β→-0.02). 
- **분류 ACCEPT (수정 완료)**: sector 팩터를 market에 orthogonalize 후 재추정 → mean β=0.79 (range 0.21-1.39), KR long-only β≈0.92 substrate와 정합. RESOLVED, 최종 Σ는 교정본.

### C-5 [REBUTTAL] "Risk가 alpha의 negative 결론을 그대로 받아 override 아닌가"
- Risk는 alpha 수정/weight 제안 안 함. RF-R1(Market 61% 분산·β0.79 non-neutralizable)은 독립 측정한 구조적 exposure 사실 — alpha의 cap-w trap 결론과 수렴하나 이는 override 아닌 독립 확증. challenge_review objection=TRUE로 alpha에 구조 사실 통보.
- **분류 REBUTTAL**: 역할경계 준수. Σ 사실이 우연히 alpha 결론 지지.

## Self-rationalization auto-detection
"미미/관행적/보수적이면 OK" 사용 여부: **미사용**. 모든 판정 실측(cond/ES/bookcov/β) 기반.

## Escalation check
- HIGH severity flags = RF-R1(1개) < 5 → auto-escalate 미발동.
- Σ PD violation 없음 (min eigenvalue ≥ 0, PSD 확인).
- CVaR hard breach / PIT hard violation 없음.
- **결론**: escalate 불요.

## Verdict
Σ 추정 완결(factor model cond=42.4, PSD, R2=0.50, β=0.79). 구조 진단:
(1) **RF-R1 HIGH — Market = 61% 포트 분산**, β0.79 long-only non-neutralizable → cap-w active edge는 β-순 selection에 의존하나 alpha가 post-2017 음수 측정. 
(2) **RF-R6 MEDIUM — 반도체 6/25 집중** (sector HHI 0.122, n_eff_sec 8.2).
(3) **RF-R7 MEDIUM — heavy tail** (Hill 1.49, ES99 -16.9%, RateHike -26%): return-selection sleeve라 tail은 비용.
(4) RF-R3 MEDIUM — passive_overlap 0.96 (capacity/exit-flow risk).
Risk는 cap-tier trap을 **독립 구조 증거로 확증**(Market 분산 지배 + β 바닥). AX-000: 완결된 measurement.
