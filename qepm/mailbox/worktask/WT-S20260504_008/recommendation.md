# WT-S20260504_008 — Orthogonal Cash Replacement Research

**Question (도훈 명시 2026-05-04 19:30)**: STR_1715_AR_threshold_overlay_PG2 deployment 5월 운용에서 30% cash residual을 0% rf 보유 vs 팩터/자산으로 대체. **무엇이 직교인가?**

**TL;DR**:
- **Primary**: KODEX 국고채10년 (A148070) — 4축 PASS + +0.052 SR boost + -1.47pp MDD 개선 + cor=-0.14 음의 직교
- **Secondary fallback**: 단기 IRP/MMF (KR_CD91 proxy) — 4축 PASS but +0.015 SR boost (rf 3% baseline)
- **Reject 5건**: USD/Gold cost FAIL, Lowvol crisis FAIL, CTA/VKOSPI no KR ETF

---

## 4축 평가 결과 (256개월 백테스트 2005-02 ~ 2026-05)

| Rank | Asset | Ticker | cor(AR-on-M4) | Crisis | KR Avail | Cost | 4축 PASS | ΔSharpe | ΔMDD pp | Decision |
|------|-------|--------|---------------|--------|----------|------|----------|---------|---------|----------|
| 1 | **kr_10y** | A148070 | -0.137 | PASS | PASS | 35bps | **TRUE** | **+0.0524** | **-1.47** | **PRIMARY** |
| 2 | cd91 | MMF | -0.004 | PASS | PASS | 15bps | **TRUE** | +0.0151 | +0.18 | SECONDARY |
| 3 | usd | A261240 | +0.024 | PASS | PASS | 65bps | FALSE | -0.0364 | +0.46 | REJECT cost |
| 4 | gold | A132030 | +0.030 | PASS | PASS | 128bps | FALSE | -0.0097 | +0.04 | REJECT cost |
| 5 | cta | synthetic | +0.023 | PASS | FAIL | n/a | FALSE | +0.0304 | +0.31 | REJECT no ETF |
| 6 | lowvol | A229200 | +0.069 | FAIL | PASS | 90bps | FALSE | +0.0116 | +9.02 | REJECT crisis |
| 7 | vkospi | (delisted) | +0.035 | FAIL | FAIL | n/a | FALSE | -0.7274 | +11.80 | REJECT contango |

**Baseline (70% AR + 30% cash @ 0%)**: SR 1.6270 / CAGR 26.18% / MDD -17.61%
**Pure AR-on-M4 100%**: SR 1.6270 / CAGR 38.34% / MDD -25.15% (pure scaling — same SR, CAGR but MDD worse)

---

## Why kr_10y > cd91 (둘 다 4축 PASS인데)

**cd91 score (76.90) > kr_10y score (59.57)**이지만 **kr_10y가 진짜 직교 alpha source**:

1. **음의 직교성**: kr_10y cor = **-0.1371** (위기 시 -0.2034). cd91은 cor=-0.004 (zero-info noise level)
2. **위기 hedge**: GFC 2008-2009 cum +9.18%, COVID 2020-02~06 cum +2.07% — STR_1715가 drawdown 시 buoy
3. **MDD 개선**: -1.47pp (17.61% → 16.14%) — 의미 있는 risk reduction
4. **Sharpe boost**: +0.0524 vs cd91 +0.0151 — 3.5x 이득
5. **단점**: 2022 stagflation cum -8.61% — BoK rate hike cycle에 취약 (RF-A3 challenge flag)

**cd91은 안전 선택**: rf 3%/yr 보장, 위기 다 PASS, but SR boost 미미. delta_Sharpe CI lower bound > 0 검증 실패 시 fallback.

---

## 통계적 유의성 (Critical Honest Assessment)

**delta_Sharpe = +0.0524 over 256m (~21년)**는 **통계적으로 유의하지 않음**:
- SE(Sharpe difference) ≈ 0.05~0.07
- t-stat ≈ 1.0
- Harvey-Liu-Zhu (2016) 다중검정 t > 3.0 기준 미달
- 7개 후보 평가 multiple-testing 보정 시 약함

→ **directional improvement only** 라벨로 채택. 후속 promotion WT에서 bootstrap CI (B=10000) + DSR 의무.

---

## 학술 anchor

| Anchor | 적용 후보 | 설명 |
|--------|-----------|------|
| Cieslak-Povala (2015 RAS) | kr_10y | Bond-equity correlation regime switching — risk-off에서 음의 cor |
| Campbell-Sunderam-Viceira (2017) | kr_10y | Inflation bets vs deflation hedges duration 행동 |
| Erb-Harvey (2006 FAJ) | gold | Strategic commodity tactical asset allocation |
| Baur-McDermott (2010 JBF) | gold | Gold safe haven — KR 적용 검증 약함 |
| Lustig-Roussanov-Verdelhan (2011 RFS) | usd | Currency carry premium — KRW carry reversal |
| Asness-Moskowitz-Pedersen (2013 JFE) | cta | Time series momentum — KR 가용 ETF 부재 |
| Frazzini-Pedersen (2014 JFE) | lowvol | BAB — KR equity 과다 노출 (구조적 cor concern) |
| Harvey-Liu-Zhu (2016 RFS) | 전체 | Multiple testing correction — t > 3 기준 |

---

## 후속 Promotion WT plan

**Type**: deployment_promotion
**Goal**: 70% STR_1715_AR + 30% KODEX_KTB10Y_A148070 정식 admit

**Steps**:
1. Actual KODEX_KTB10Y NAV (KOFIA 2011-04+) vs synthetic duration proxy 비교 (5%+ 차이 시 재추정)
2. Bootstrap delta_Sharpe CI (B=10000) + Deflated Sharpe Ratio + Harvey-t (256m + 2011+ subperiod)
3. Rebalance frequency robustness (monthly vs quarterly cash bucket)
4. Regime-conditional split 옵션: NORMAL → kr_10y / CRISIS → cd91
5. Risk Agent — 2-asset Σ + tail covariance + BoK rate hike cycle stress
6. Optimizer — fixed 70/30 vs MVO vs MinVar 비교
7. Forge — 268m full backtest with actual KTB10Y ETF NAV
8. Judge — Hurdle v2.3 + DSR > 0.5 + Harvey-t > 3.0
9. Governor — admission with PG2 100% allocation lock

**Decision Gate**:
- delta_Sharpe bootstrap CI lower bound > 0 ⇒ kr_10y promote
- else ⇒ cd91 fallback (rf 3%/yr guaranteed, no SR boost but no risk)

**ETA**: 1주

---

## Limitations + Honest Caveats

1. **Synthetic bond proxy** (-D × Δy + carry/12, D=8) ≠ actual KOFIA KTB10Y ETF NAV. Pre-2011은 ETF 없으니 synthetic only. 후속 검증 의무.
2. **Gold proxy**: literature anchor (krw_chg + vix + dgs10) 합성. 실제 KODEX_GOLD_A132030 (KRW-hedged futures) 차이 가능. 추가로 cost 128bps 부담 큼.
3. **CTA synthetic**: TS-momentum 4-asset basket. 실제 KR-listed CTA ETF 부재 (2026 기준 확인 완료).
4. **VKOSPI**: KOSEF V-KOSPI 200 ETF 2018 delisted. 현재 KR-listed long-vol instrument 없음.
5. **Low-vol KR equity**: KOSPI200 bottom-30% vol decile은 STR_1715 universe와 30~50% 종목 overlap 의심. 직교성 cor=0.069는 surface 수치이며 underlying alpha source는 동일 KR equity factor 기반.
6. **Multiple testing**: 7 후보 동시 평가 → DSR 페널티 ~14% 적용 시 kr_10y delta_Sharpe 약화.
7. **Regime conditional**: 본 연구는 average behavior. STR_1715는 NORMAL/CAUTION regime overlay (M4 schedule). cash replacement도 regime-conditional 평가 권고.
8. **Cost realism**: 35bps/yr는 ETF ER + bid-ask + tracking. 실제 KRX 수수료 / slippage 차이 가능.

---

## 결론

**도훈 질문 "무엇이 직교인가" 직접 답변**:

1. **수학적 직교성** (cor < 0.30): 7후보 모두 충족 — 자산군 mismatch 자동 효과
2. **실용적 직교성** (직교 + 위기 hedge + 비용 + 가용): **KR 10년 국채 단 1건**
3. **rf 안전판**: cd91 (단기 IRP/MMF)는 safe baseline, but SR boost 거의 없음

**도훈 결정 옵션**:
- **A. Aggressive**: 70% STR_1715 + 30% KODEX_KTB10Y (kr_10y 직교 hedge) — bootstrap CI 검증 후
- **B. Conservative**: 70% STR_1715 + 30% MMF/IRP (rf 3% 보장, no risk) — 즉시 가능
- **C. Hybrid**: 70% STR_1715 + 15% kr_10y + 15% cd91 — diversification within cash bucket

본 alpha-research는 **옵션 A를 정식 promotion WT 후보**로 권고. 결정권은 도훈에게 있음.

---

## Files Generated

- `qepm/mailbox/worktask/WT-S20260504_008/alpha_package.json` — final alpha package
- `qepm/mailbox/worktask/WT-S20260504_008/alpha_package_draft.json` — pre-codex draft
- `qepm/mailbox/worktask/WT-S20260504_008/candidate_evaluation_table.csv` — 7 후보 4축 평가
- `qepm/mailbox/worktask/WT-S20260504_008/correlation_matrix.csv` — 7×7 cor matrix
- `qepm/mailbox/worktask/WT-S20260504_008/crisis_decomposition.json` — GFC/COVID/Stagflation 분해
- `qepm/mailbox/worktask/WT-S20260504_008/kr_availability_audit.json` — ETF gauge
- `qepm/mailbox/worktask/WT-S20260504_008/cost_breakdown.json` — ER + bid-ask + tracking
- `qepm/mailbox/worktask/WT-S20260504_008/simulation_comparison.csv` — 8 scenarios SR/CAGR/MDD
- `qepm/mailbox/worktask/WT-S20260504_008/cash_replacement_analysis.R` — research script
- `qepm/mailbox/worktask/WT-S20260504_008/codex_critic_response_alpha.json` — Codex Round verdict
- `qepm/mailbox/worktask/WT-S20260504_008/challenge_note.md` — Codex disposition
- `stage_artifacts/WT_S20260504_008/alpha_scores.parquet` — final scores
- `stage_artifacts/WT_S20260504_008/alpha_validation.json` — validation diagnostics
- `stage_artifacts/WT_S20260504_008/merged_returns.csv` — full return series merged
