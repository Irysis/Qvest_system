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
