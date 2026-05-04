# challenge_note — WT-P20260505_001 (Hybrid 70/15/15 Promotion)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
promotion_wt — 3 alpha source 모두 prior WT에서 검증 완료:
1. STR_1715_AR_threshold_overlay_PG2 (WT-P20260504_001 admitted, FINALIZED_POST_CODEX)
2. KR 10y bond ETF passive carry (WT-S20260504_008 ALPHA_DONE)
3. TSMOM Cross-Asset ETF rotation (WT-S20260504_009 ALPHA_DONE CONDITIONAL_PASS)

본 WT는 **static 70/15/15 hybrid allocation** 결정만 수행. 새 alpha engine 없음.

### codex_critic_skip_waiver
alpha role only. Hybrid는 weight allocation 결정이지 alpha 아님. 후속 5 agent (Risk + Optimizer + Forge + Judge + Governor) 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub via inherit_ref + parent_sha references.

---

## Section: Hybrid Paradigm 정당화

### 도훈 Path C 결정 (2026-05-05)
"Hybrid TSMOM 15% + KR 10y 15%" — WT-008/WT-009 두 직교 source의 강점을 보완 결합.

### 두 source 직교성 + 보완성

| 차원 | WT-008 KR 10y | WT-009 TSMOM | 결합 효과 |
|---|---|---|---|
| cor with STR_1715 base | -0.137 | 0.077 | 평균 -0.030 (강한 직교) |
| ΔSharpe (30% allocation) | +0.0524 | +0.0663 | 부분 합산 ~+0.06 |
| ΔMDD pp | -1.47 (개선) | +1.04 (악화) | net 약 -0.2pp 개선 |
| Cost bps | 35 | 58 | 평균 ~46 |
| 위기 hedge | flight-to-quality | trend-based switch | 두 메커니즘 보완 |
| 학술 anchor | Cieslak-Povala 2015 | Moskowitz 2012 | 60/40 + managed futures |

### 9-step prereq 의무
1. P1 Architect 3rd-source independent verification (in progress)
2. P2 KOFIA NAV validation plan (RF-A1 HIGH 해소)
3. P3 Optimizer 30% cap (RF-A8 TSMOM 79.86% breach 해소)
4. P4 Risk Manager correlation + tail audit
5. P5 Forge 5-strategy backtest (S0~S4 sensitivity)
6. P6 Judge verdict (AX-008 2/3 PASS)
7. P7 Codex Round + Governor admit
8. P8 Telegram brief
9. P9 POST_DEPLOY 11+ extension

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_ADMITTED.

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.
LRO SHA frozen ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18 unchanged.
M4 schedule WT-D20260430_001/judge_ready/weights.csv unchanged.
