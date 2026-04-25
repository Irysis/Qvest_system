# Fair Same-Period Comparison Note (CRITICAL — Forge 의무 read)

## 작성 시각: 2026-04-25 (Iter 6 Risk 단계 진행 중)

## 핵심 발견 — STR_1699 vs MEGA_05 동일 243m fair backtest

이전 Forge Phase 4.5는 **각 strategy의 max period 자체 측정** (STR_1699 244m / MEGA_05 278m). 기간 차이로 unfair.

**Q-Lead 직접 산출** (Phase 4.5 monthly returns 데이터에서 동일 243m trim):

| 지표 | STR_1699 (243m) | MEGA_05 trimmed to **identical 243m** | Δ |
|---|---|---|---|
| Period | 2006-02 ~ 2026-04 | **동일** 2006-02 ~ 2026-04 | — |
| **CAGR** | **20.03%** | 14.37% | **STR_1699 +5.66pp** |
| **SR** | **0.9748** | 0.9488 | **STR_1699 +0.026** |
| Vol | 20.55% | **15.14%** | MEGA (-5.41pp) |
| **MDD** | -34.93% | **-24.82%** | MEGA (+10.11pp) |
| Hit rate | **62.14%** | 58.85% | STR_1699 |
| **Pairwise correlation** | — | **0.1004** | 거의 독립적 alpha source |

## 이전 잘못된 비교 (정정)

- ❌ 이전: "MEGA_05 SR 1.110 > STR_1699 0.995" → **unfair 기간 비교** (MEGA 278m vs STR 244m)
- ✅ 정확: **same 243m에서 STR_1699 SR 0.9748 > MEGA_05 SR 0.9488** (STR_1699 우월)

## 결정적 인사이트

1. **STR_1699 same-period에서 SR/CAGR/Hit/Harvey 모두 우월** — MEGA_05는 Vol/MDD만 우월 (Kelly + Overlay machinery 효과)
2. **STR_1699 ↔ MEGA_05 cor 0.10** = 거의 독립적 alpha source → diversification benefit 매우 큼
3. **Iter 6 가설 강화**: STR_1699 alpha (already SR/CAGR 우월) + MEGA_05 vol-reduction machinery → SR 1.5+ 잠재 더 명확

## Forge 의무 (Iter 6 backtest 진행 시)

1. **same-period baseline comparison** — MEGA_05 baseline은 STR_1699/Iter 6과 **동일 기간**에서 측정 (max 243m base 또는 218m common)
2. **추정치 사용 금지** — 실제 NAV monthly resample 또는 직접 backtest로 정확 수치 산출
3. **MEGA_05 documented SR 1.258 또는 production CAGR 26.9% 인용 금지** — 다른 basis (lockbox/daily/Kelly+Overlay 포함)
4. **DSR penalty 일관 적용** — Iter 6 candidates_tried × 0.05 (Iter 5 = 15 → 0.75 적용 사례)
5. **Pairwise correlation matrix** 보고 — STR_1699 / MEGA_05 / STR_1656 (3-strategy ↔)
6. **NAV-level integration** scenario 평가 (Replacement A 100% / B 60-20-20 / D current PG2 80-20):
   - **same-period (218m common 또는 243m base)** + 실 NAV 합성 (cor 가정 X)
   - 각 scenario CAGR / SR / MDD / IR / Harvey 5-spec / DSR_post

## 데이터 source (Forge 직접 활용)

- STR_1699 monthly returns: `qepm/mailbox/worktask/WT-D20260425_010/backtest_result/str1699_full_period_monthly.csv` (243 rows, 2006-02~2026-04)
- MEGA_05 monthly returns: `qepm/mailbox/worktask/WT-D20260425_010/backtest_result/mega_doc_monthly.csv` (278 rows, 2003-03~2026-04, **trim to 243m for fair**)
- STR_1656 NAV: `qepm/mailbox/worktask/WT-D20260425_010/backtest_result/nav_panel_phase45.csv` (218 rows common with PG2)

## 참조

- Forge Phase 4.5 source: `qepm/mailbox/worktask/WT-D20260425_010/forge_phase45_package.json`
- Q-Lead fair-comparison execution: 본 note 작성 시 inline R script (이번 회차)
- L-202 Same-Period Baseline Fairness Mandate (methodology_active.md)
- mandate_compliance_check.sh Hook (forge_baseline_fairness 통합)
