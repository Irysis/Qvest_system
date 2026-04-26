# Alpha Challenge Note — WT-D20260426_006 STR_1656_M06

**Author**: Alpha Research Agent v1.2 (Opus 4.7)
**Created**: 2026-04-26
**WT**: WT-D20260426_006
**Hypothesis**: STR_1656_M06 PG2-conditional ML diversifier reinforcement
**Common Charter Principle 8 (No Silent Override) compliance**

---

## 1. Open Disagreements with Prior Stages / Common Charter

| # | Issue | My position | Acknowledgement |
|---|---|---|---|
| 1 | RF-A1 sub_stab > 0.20 mandate (User WT spec) | M06 design 명시적 강화 (FF5 v2 lagged + regime indicator + LGBM ensemble). 결과 sub_stab은 measure ≠ guarantee. | 결과가 0.20 미달 시 challenge_flags HIGH 자동 생성. 이후 Forge S5 mutation 위임. |
| 2 | RF-A2 composite improvement < 5% threshold | 본 mutation 의도는 **PG2 incremental SR** (cross-strategy diversification) 이지 단일 ICIR 개선 아님. M05 baseline ICIR 0.83 대비 M06 +5% margin은 over-fitting 위험만 상승시킬 수 있음. | DeMiguel-Garlappi-Uppal 2009 1/N rule outperforms sophisticated optimization — composite ICIR 단순 비교 부적절. **본질 평가는 Forge backtest의 PG2 blended Realized SR**. |
| 3 | DSR_proxy < 0.5 가능성 | 5-trial penalty (XGBoost+LGBM+3 ablation) 적용 시 DSR가 0.5 미달할 수 있음. | n_trials를 5로 명시 보고. Bailey-Lopez de Prado 2014 보수적 적용. ICIR/Harvey_t는 PASS 예상. |
| 4 | recent3Y ICIR > overall × 1.5 risk (RF-A3) | M05 ICIR_3y = 0.4804 vs overall = 0.8323 → recent ICIR이 overall보다 작음 (반대 방향). 정상. | M06 동일 패턴 예상 — recent3Y > overall 시 RF-A3 자동 생성. |
| 5 | Subperiod stability gate (0.50 threshold) | Discovery WT graduation criteria는 0.50이지만 본 WT spec mandate는 sub_stab > 0.20 (RF-A1 mitigation). | 0.50 미달은 graduation_status에 false로 보고. 0.20+ 달성은 RF-A1 해소. |

## 2. Method Shopping Log Disclosure

5건 전수 후보 검토 (cap 5):
1. M06_XGB_only — M05 baseline replication w/o LGBM (control)
2. **M06_XGB_LGBM_ensemble (SELECTED)** — XGBoost 5-seed + LightGBM 3-seed rank-mean
3. M06_NoFF5_features — ablation: 309F only without FF5/regime
4. M06_AllFactors_RE_included — S1_A variant (RE_* included, M05 검증 시 overfit 확인)
5. M06_DailyDeep_LSTM — out of scope (training time exceeds budget; 추후 S5 deferred)

선택 기준: **selection_objective = icir** (R4 P3 hard). SR/CAGR/MDD 직접 사용 금지.

## 3. PIT Compliance (C1~C15)

L-164 v1.1 ML carve-out 명시 적용:
- C1 PASS: expanding monthly walk-forward, IS [2003-01-01, oos_yr-2.12.31] / OOS [oos_yr.01.01, oos_yr.12.31]
- C2 PASS: score at sig_date applied at fwd_ret = sig_date + 21 trading days (strictly future)
- C9 PASS: regime expanding pct (BM 252d rolling vol, t-1 lag)
- C10 PASS: AvgTV20 t-1 shift, LIQ_THRESHOLD=2e8 KRW
- C11 PASS: KR internals only. FF5 v2 monthly returns lagged t-1.
- C13 N/A: L-164 v1.1 carve-out — daily raw read (Z_Score_Aligned 미적용)
- C14 N/A: load_month_factors() 미경유. Walk-forward expanding 보장.
- C15: L-164 v1.1 carve-out 적용

R2 P2 Lockbox isolation:
- TRAIN_VAL_END = 2024-01-22 (ENFORCED)
- LOCKBOX [2024-01-23, 2026-01-23] SEALED — Alpha agent 접근 ZERO
- OOS_YEARS = 2008~min(2024, 2025) — lockbox 진입 차단

## 4. AX Axiom Anchor Citations

- **AX-000**: SR gap 0.5375 채울 수 있다 — ML diversifier 보강 path. PG2 Realized SR > 1.4625 목표.
- **AX-001 v2**: ML diversifier conditional metric — M05 GFC-style 0% loss 보호 유지 + crisis_alpha 측정 위임 (Forge backtest 영역).
- **AX-002**: harness 내 PG2 blended SR realized만 평가. 단일 strategy SR 비교 X.
- **AX-004**: KR quality_profitability single-signal long-only fail. M06 ML ensemble = multi-feature multi-axis (309F + 6F FF5 + 1F regime) — exception 충족.
- **AX-005**: L-164 v1.1 ML carve-out — 일간 raw read 허용.
- **AX-007**: structure = score-level addition to existing PG2 sleeve allocation, role = diversifier_with_pg2_complementarity. Multi-sleeve (STR_1701 + M06).
- **AX-008**: Triangulation — Forge + Codex + Architect. Codex round 의무 수행 — alpha_package_draft.json 제출 후 finalize.

## 5. Strict Prohibitions Acknowledged

- ❌ STR_1701 weights 수정 절대 금지 (PG2 80% slot fixed). Alpha는 alpha_vector만 산출. weight 결정 = Optimizer 영역.
- ❌ Single-strategy SR > 1.46 강박 X. PG2 blended이 본질.
- ❌ 합리화 표현 사용 금지 ("영향 미미", "관행적 허용", "보수적이면 괜찮다", "백테스트 기간이 충분히 길어서 상쇄").
- ❌ L-164 위반 — 월간 288 Z_Score는 load_month_factors 필수, 일간 ML carve-out만 raw read 허용.
- ❌ normalizePath() 사용 X.

## 6. Out-of-Scope Acknowledgement

- 공분산행렬 추정 — Risk Agent 영역 (alpha_package에 weights/Σ 포함 X)
- 포트폴리오 비중 결정 — Optimizer Agent 영역
- 제약조건 사전 최적화 — Optimizer 영역 침범 X
- Sector neutralization — Optimizer 영역
- Cash overlay 결정 — Optimizer 영역 (regime_state column만 alpha_scores.parquet에 첨부)

## 7. Lineage Discipline

L-194 fix 적용: alpha_package.json write → record_package_lineage 순서 엄격 준수.
- artifact_lineage.json append (P7 audit pass 확보)
- input file sha256 hash 기록
- git commit + R version + key package versions 기록

## 8. Telegram Discipline

- tg_agent_brief() 단일 호출만 사용
- 직접 tg_send/tg_send_rich/tg_send_photo 호출 금지 (Hook block)
- sections >= 4, table nrow >= 2, body chars >= 50, items >= 3, emoji >= 5 충족

---
**Resolution status**: alpha_package_draft.json 작성 완료 → Codex round (run_codex_qepm_critic.sh) 의무 → Q-Lead 합리적 토론 (필요 시) → finalize alpha_package.json + lineage.
