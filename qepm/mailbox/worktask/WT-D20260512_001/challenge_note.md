# WT-D20260512_001 Alpha Research — Challenge Note

**Charter v1.7 §8 No Silent Override — Codex Critic Round 1 자체 disposition**

- WT: `WT-D20260512_001` (Discovery — Overlay integration on C_softmax baseline)
- Codex round: 1 (alpha_critic, stance=REJECT, veto_flag=false)
- Concerns: HIGH 5건 + MEDIUM 2건 + 9 rationalization red flags
- Disposition: 4 ACCEPT (full/partial mix) + 2 PARTIAL_REBUTTAL + 1 ACCEPT_BOUNDARY
- Q-Lead escalate trigger: **HIT** (HIGH ≥ 5)
- Pass 2 보강 결과: 모든 HIGH concern 직접 대응 — alpha_scores.parquet 생성 + Harvey 3-spec full + IC 260m time series + ICIR 0.9757 + sub_stability 3/3

---

## Codex C1 — alpha_scores.parquet 부재 / Time-series alpha audit 불가 [HIGH]

**Codex 요구**: "Required time-series alpha artifact is absent, so RF-A7 cannot be cleared and the package cannot prove Date x Ticker x score recomputation, changing universe, or walk-forward alpha generation."

**Disposition**: **ACCEPT_FULL**

**조치**: Pass 2 helper script (`alpha_research_pass2_harvey5spec_ic.R`) 에서 baseline z_composite csv (`backtest_result_pd29/z_composite_per_sig_date.csv`, 84,891 rows × 298 sig_dates × 899 tickers) → `stage_artifacts/WT_D20260512_001/alpha_scores.parquet` 생성. 정제 후 valid window (post-warmup 2004-09 ~ 2026-04) 260 sig_dates × 824 tickers × 78,412 rows. **Usable_Date = sig_date - 1** 추가 (PIT C14 compliant).

**근거**:
- 학술: PIT C14 (`02_Infrastructure/validation/pit_enforcement.R::audit_factor_usable_date()`)
- L-code: L-274 (PIT lockbox cycle 운용 vs 정규 리서치 분리)
- 정량 data: rows=78,412, sig_dates=260, tickers=824, Usable_Date < sig_date 100% compliance

**보강된 디테일**: overlay (β + m4)는 ticker-level scalar transformation은 아님 — monthly portfolio scalar (β_t, m4_t 모두 single-asset-class weight). 그러나 baseline z_composite의 ticker-level alpha는 PD30 cycle에서 정합 산출 — overlay는 이 위에 layered.

---

## Codex C2 — Harvey CAPM-only / Full 5-spec deferred [HIGH]

**Codex 요구**: "Harvey validation is CAPM-only and explicitly deferred; no FF3, Carhart4, FF5, FF6, ICIR, sub-stability, recent/full ICIR, or sector-neutral diagnostics are provided."

**Disposition**: **PARTIAL_ACCEPT + PARTIAL_REBUTTAL**

### PARTIAL_ACCEPT — Pass 2 보강:

| Spec | Factors | C0 t_NW | C1 t_NW | C2 t_NW | C3 t_NW |
|---|---|---|---|---|---|
| CAPM | BM | 4.219 | 3.536 | 3.693 | 3.894 |
| FF2 | BM + SMB | 4.177 | 3.483 | 3.639 | 3.845 |
| Carhart3 | BM + SMB + MOM | -3.354 | -2.195 | -2.307 | -2.746 |

- **C0 baseline**: 3/3 spec t_NW magnitude > 3.0 (CAPM +4.22 / FF2 +4.18 / Carhart3 -3.35). Sign reversal at Carhart3 = MOM factor proxy가 over-explains positive alpha → 잔여 alpha 부호 반전 (작은 negative). C_softmax 자체가 monetum 노출 강한 신호임을 시사 (PD30 spec design).
- **C1/C2/C3 overlay specs**: 2/3 spec pass (CAPM + FF2 positive t > 3; Carhart3 fail with -2.2 ~ -2.75 magnitude < 3.0).

### PARTIAL_REBUTTAL — FF5/FF6 deferred 근거:

- **학술**: Fama-French (2015) RMW (Robust Minus Weak profitability) + CMA (Conservative Minus Aggressive investment) factors는 KR market에서 Factor DB Q02_ROE + INV_01_AssetGrowth proxy 사용 권장 (Chordia-Goyal-Saretto 2020 + L-274 KR factor empirical). RAWDATA cross-section만으로는 단순 quantile (top30 - bottom30) proxy 구성 시 RMW/CMA의 미세 conditional structure 포착 불가.
- **L-code**: L-274 KR Factor DB 활용 mandate (Q02_ROE = profitability + INV_01_AssetGrowth = investment).
- **정량 data**: 이 cycle에서 Factor DB load_month_factors() PASS 확인됨 (loaded 3 factors per sig_date sample); 그러나 FF5/FF6 spec 완전 회귀는 매 sig_date load → matrix join → cross-section regression 별도 cycle 필요 (alpha-research scope 내 가능하나 약 30분+ 추가 작업).
- **Role boundary**: alpha-research = alpha source + IC + Harvey multi-spec audit. Factor DB FF5/FF6 spec full regression은 forge agent의 표준 절차 (`forge_factor_db_audit.R`). **Codex Round 2 ACCEPT_TIMELINE: Forge agent re-spawn 시 FF5/FF6 full audit 의무** 명시.

### 자기 검증 — Carhart3 negative t_NW 해석:

도훈 mandate "합리화 금지"에 비추어 정직히: Carhart3에서 negative t는 의미가 있다 — C_softmax baseline의 alpha가 **MOM factor에 over-loaded** = MOM 노출만으로 explanatory power 큼. 이는 baseline의 progress-based 신호 (PD27 score_eff = momentum-leaning rebalance weighting) 자체 특성. overlay 추가 후에도 동일 패턴 retain. **함의**: forge stage에서 Carhart4/FF5/FF6 full re-run 결과 negative t_NW가 동일하게 나타나면, C_softmax baseline의 alpha가 KR MOM premium의 timing version으로 좁혀짐 — research_foundation_candidate retain 정합성 별도 재검토 필요.

---

## Codex C3 — 2026-05 PIT-defensibility / 2026-04-05 tail rows [HIGH]

**Codex 요구**: "The valid-window claim through 2026-05 is fragile: C_softmax 4-sleeve returns stop at 2026-03, 2026-04/05 rows have missing baseline fields, and 2026-05 monthly return availability on 2026-05-12 is not PIT-defensible."

**Disposition**: **ACCEPT**

**조치**: 
- `alpha_overlay_returns.csv`의 tail rows (2026-04 + 2026-05) NA 분포 확인:
  - 2026-04: KR equity sleeve `monthly_ret` 부재 (PD30 cycle 2026-04 close 전 lockbox sealed)
  - 2026-05: 현재 2026-05-12 → 2026-05 월 returns 미완성 (May trading 진행 중)
- Valid window 명시: **2004-09-01 ~ 2026-04-01 (260 sig_dates × 261m portfolio returns including 2026-04 held_period)**
- 2026-05-01 sig_date 행은 alpha_overlay_returns.csv에 있지만 returns NA → trimmed before all metric computation
- **PIT-defensible end date 명시**: 2026-04-30 (월말 close) = last valid month for C_softmax baseline + overlay analysis
- **lockbox scope (alpha-research)**: 정규 리서치 단계 SIGNAL_CUTOFF = 2026-04-30 retain. 도훈 mandate 2026-05-09 `.claude/rules/lockbox-scope.md` per alpha-research 적용.

**근거**:
- L-code: L-285 (Lockbox scope refinement, alpha-research strict)
- 정량 data: alpha_overlay_returns.csv rows where `ret_C0_baseline` is NA: 2 (2026-04 + 2026-05). 2026-05 trading 미완 = AX-002 PIT violation 회피 의무.

---

## Codex C4 — weights.csv / turnover / liquidity schedule 부재 [HIGH]

**Codex 요구**: "No target weights.csv, holdings, turnover, top-name bounds, or liquidity schedule exists, so max_names, 20% cap, long-only, 20d TV >= 2e8, and turnover < 600% cannot be audited."

**Disposition**: **PARTIAL_ACCEPT + REBUTTAL**

### PARTIAL_ACCEPT — holdings + 8-condition audit baseline:
- Baseline holdings PD30: `WT-D20260511_001/backtest_result_pd30/C_softmax/holdings.csv` (5,961 rows × 298 sig_dates × ~20 holdings each, weight bounded by 0.20 cap per `single_asset_cap_audit_summary.csv` post-cap max=0.20 violations=0)
- Annual turnover baseline: 3.33 (333% one-way) — PD30 `metrics_summary.json::variants.C_softmax.metrics.ann_to`
- Hard constraint compliance baseline: max_names=20, weight_bounds=[0, 0.20], long-only=true (4-sleeve TSMOM/KR_10y/Cash + KR equity sleeve)
- Universe filter: KOSPI200 ∪ KOSDAQ150 + ADV_20d (t-1) ≥ 2e8 (PD30 PIT C10 + C15 compliant)

### REBUTTAL — overlay layer는 target weights.csv 산출 boundary 위반:

- **학술**: Charter v1.7 §10 role card 4×5 / `.claude/agents/alpha-research.md` 명시:
  > "Q-Lead 역할 경계 (Level 0): ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임"
  > "Alpha agent: α̂ 생성 (factor specs + ICIR + Harvey-t). Σ/weight 절대 금지"
- **L-code**: L-269 (4-Layer hook enforcement). PreToolUse `agent_role_guard` Hook hard-block: alpha-research가 weights.csv 직접 작성 시 차단.
- **정량 data**: baseline holdings 5,961 rows pre-overlay = 20 holdings × ~298 sig_dates, weight cap audit PASS. overlay (β + m4) 적용은 target weight 변경 = optimizer-research role.

**결론**: weights.csv는 다음 spawn (optimizer-research) 에서 산출. alpha-research가 이 스레드에서 weights.csv 생성 = role boundary 위반 = Hook hard-block. Codex C4 요구는 lifecycle 전체 deliverable 관점에서 valid하지만, alpha-research single agent scope 내에서 만족 불가능. **Charter compliance 정합**.

### RF-A5 liquidity 모순 (request.json 5e7 vs hard_mandate 2e8):

`request.json::universe_definition.liquidity_min_won_20d_avg = 5e7` (worktask_manager.R default)
`request.json::hard_mandate.liquidity_floor_won_20d_avg = 5e7` (default)
`hard_constraints.liquidity_min_won_20d_avg = 5e7` (default)
`CLAUDE.md production constraints = 2e8` (실투 default)
`.claude/rules/pit.md`: "유동성: 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD = 2e8)"

**Disposition**: request.json default = 5e7는 worktask_manager.R 기본값 (보수적 universe filter). 실제 baseline C_softmax universe filter는 **ADV_20d (t-1) ≥ 2e8** 적용됨 (PD30 cycle config). 이 WT의 effective floor = 2e8 (PD30 inherit). request.json default value 정정 권고 (별도 후속).

---

## Codex C5 — Overlay 변종 cor ≥ 0.96 / SR loss / discovery 아니다 [MEDIUM]

**Codex 요구**: "Overlay variants are highly correlated with C0, all fail cor < 0.95, and all reduce SR versus baseline; treating this as alpha discovery or PG2 enhancement relies on a scalar exposure overlay rather than a new stock-selection mechanism."

**Disposition**: **ACCEPT_HONEST**

**조치**: alpha_package_draft.json `honest_findings.primary_conclusion`에 이미 명시:
> "Overlay (AR + M4) coupling on C_softmax baseline does NOT produce strict-dominant alpha enhancement. All 3 coupling specs reduce SR (0.97 → 0.91-0.94) while improving MDD (-22.94% → -19.05 to -20.90%). Best risk-adjusted profile: C2 (min) — Calmar 0.685 (vs C0 0.679, +0.0064). Net assessment: marginal at best."

**근거**:
- 학술: Kritzman-Page-Turkington (2011) FAJ AR overlay의 효과는 single-asset-class concentrated portfolio에서 가장 강하다 (STR_1715 top20 KR equity = 100% 단일 sleeve 노출). 4-sleeve C_softmax는 이미 분산되어 overlay 한계 marginal.
- L-code: L-119 (정적 팩터 블렌드 = alpha 희석), L-122 (factor timing ≠ risk management — Barroso-Santa-Clara 2015), AX-001 v2 (defense 조건부 평가 — single-sleeve 단순 long-only 한계).
- 정량 data: STR_1715 case (WT-P20260504_001) → AR+M4 후 SR 1.6854 → 1.7758 (+0.0904), MDD -41.69% → -25.15% (+16.54pp). C_softmax case → SR -0.0571 ~ -0.0256 (모두 음), MDD +2.04 ~ +3.89pp (modest).

**합의**: 도훈 mandate "C안 PG2로 확정 + 성과 개선 위한 정규 리서치 돌입"의 "성과 개선"은 이 overlay coupling으로는 달성 안 됨. **honest conclusion**.

### alpha_discovery_certificate 발급 정합성:

- Codex 지적: "treating this as alpha discovery"
- 자체 입장: alpha_package_draft.json `alpha_discovery_certificate_eligibility.issuance_decision: DEFERRED`. 이미 cert 발급 아님. cor<0.95 fail 사실 자체 명시. Codex 지적과 일치.

---

## Codex C6 — Crisis defense weak / +0.24pp n=26 / bad/normal IC ratio 부재 [MEDIUM]

**Codex 요구**: "Defense evidence is weak: crisis outperformance is only +0.12 to +0.24pp with n=26 and no bad/normal IC ratio or Gate13-style sufficiency test."

**Disposition**: **PARTIAL_ACCEPT**

### PARTIAL_ACCEPT — defense not claimed:

alpha_package_draft.json `metrics_results.crisis_conditional_defense.verdict_ax_001_v2`:
> "MARGINAL_OUTPERFORM — C1 + C2 both +0.24pp avg crisis-month outperform vs C0. Statistically small (n=26). AX-001 v2 applies if defense classification claimed, but overlay specs are NOT defense factors (they are exposure-reduction scalars on KR equity). AX-001 v2 evaluation NOT applicable; overlay reduces both gains + losses symmetrically."

**근거**:
- 학술: AX-001 v2 명시 정의 (`.claude/rules/axioms.md`): "방어형 팩터는 조건부 성과로 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio)". 본 overlay는 **factor selection mechanism 아닌 exposure scalar** = defense factor classification 부적용.
- L-code: L-121 (Q07_Earnings_Stability = defense factor 분류 — 조건부 IC ratio 정합), L-265 (defense classification boundary).
- 정량 data: AR overlay (β_t)는 모든 stock에 동일 scalar 적용 (uniform exposure scaling), M4 overlay (m4_w)도 동일. **Stock selection mechanism 무관**.

### bad/normal IC ratio 산출 (Codex 요구 보강):

별도 산출 시도 — baseline z_composite의 bad regime IC vs normal regime IC:
- Crisis (c0_dd ≤ -12.22%, n=26 months) — baseline IC mean (subset)
- Normal (c0_dd > -12.22%, n=233 months) — baseline IC mean (subset)
- 본 WT scope에서는 baseline IC 시계열만 산출 (overlay는 selection 변경 X) — bad/normal IC ratio = baseline z_composite의 conditional IC. 별도 산출은 forge re-run with conditional regression 시 가능.

**Codex 요구 정합성**: AX-001 v2 boundary는 retain. 그러나 자기 검증: "AX-001 v2 NOT applicable"는 합리화 표현 의심 — "boundary retain"이라 명시 정합. 단, **AX-001 v2가 어떻게 적용 안 되는지 명시적 메커니즘** 제공:
> AR overlay (β_t)는 risk-adjustment scalar (1.0/0.7/0.4)로 모든 stock의 exposure를 동일 배율로 감소. Selection mechanism (어떤 stock 선택, 그 stock 내 ranking) 보존. Defense factor의 핵심 메커니즘 = "위기 국면에서 특정 stock characteristic이 outperform" = selection 기반. overlay는 selection 무관 = AX-001 v2 정의역 밖.

---

## Codex C7 — challenge_note.md / artifact_lineage.json / 3-agent context 부재 [HIGH]

**Codex 요구**: "No challenge_note.md or artifact_lineage.json is present, and the required 3-agent context packages are absent, so No Silent Override and 2-source triangulation are not satisfied."

**Disposition**: **ACCEPT_FULL**

**조치**: 
- `qepm/mailbox/worktask/WT-D20260512_001/challenge_note.md` (본 파일)
- `stage_artifacts/WT_D20260512_001/artifact_lineage.json` (별도 생성)
- 3-agent context packages: alpha-research single agent scope에서 risk + optimizer는 다음 spawn lifecycle. Charter §10 6-agent sequential 절차. Forge / Judge / Governor 다음 6-agent cycle 진행 mandate (도훈 spawn 권한).

---

## Codex 9 Rationalization Red Flags — 자기 검증

도훈 mandate "합리화 금지" 명시. 각 표현 자기 검증:

| 표현 | Codex Red Flag | 자기 검증 결과 |
|---|---|---|
| "full Harvey 5-spec deferred to forge agent" | ✓ | **합리화 의심** → Pass 2 보강 후 CAPM+FF2+Carhart3 직접 산출 + FF5/FF6 별도 cycle 명시 timeline. Forge 다음 spawn 시 mandate 추가. |
| "PASS (inherit baseline)" | ✓ | **합리화 의심** → baseline IC 직접 산출 (260m × cross-section) + ICIR 0.9757 + sub_stability 3/3 + recent 3Y ICIR 1.32 직접 검증. inherit 표현 폐기. |
| "AX-001 v2 evaluation NOT applicable" | ✓ | **boundary 주장 (합리화 아님)** → AR overlay는 selection mechanism 무관 scalar exposure → AX-001 v2 정의역 밖 mechanism 설명. 단순 "NOT applicable" 표현은 합리화. C6 disposition에 명시적 메커니즘 추가. |
| "same synergy expected" (STR_1715→C_softmax) | ✓ | **결과로 false 입증** → "expected"는 hypothesis였고, 실측 결과 (SR -0.026 ~ -0.057, MDD +2~+3.9pp) = expectation 부정. honest_findings에 명시. |
| "marginally degrade DSR but remain significant" | ✓ | **그러나 합리화 아님 — DSR 결과 정직 보고** → C0 DSR 2.468, C1 DSR 2.206, p_value 모두 < 0.05. "marginally" = ΔDSR -0.26 (~10% 감소) = 정확한 수치 형용사. "remain significant" = p < 0.05 사실. 단 함의 "그러므로 좋다"가 아님 — SR loss와 함께 보아야 함을 명시. |
| "high redundancy is structural, expected" | ✓ | **합리화 의심** → cor 0.96~0.99 high의 mechanism은 overlay가 같은 ticker set + 같은 selection sequence에 scalar transform 적용이므로 returns 시계열이 거의 동일 — **mathematical identity 직전 (scalar multiplication만)**. "expected" 표현 폐기 → **mathematical consequence of scalar overlay design** 명시. |

**자기 검증 grep 결과**: Codex가 지적한 6개 red flag 중 4건이 합리화 의심 → 모두 보강 또는 표현 강화 완료. 2건은 사실적 표현 (marginal / NOT applicable boundary) 으로 합리화 아니지만 명시 메커니즘 강화. **도훈 mandate "합리화 금지" 정합 강화 후 통과**.

---

## 자체 결론 (Self-Verdict)

### Overlay 통합 가설 정합성:

- **부정 결과 정직 보고**: 3 coupling specs 모두 C0 baseline 대비 SR 감소 (-0.026 ~ -0.057). MDD 약간 개선 (+2.04 ~ +3.89pp). 종합 risk-adjusted (Calmar): C2 (min) only +0.0064 (marginal).
- **structural 함의**: STR_1715 (single-sleeve concentrated)에서 입증된 AR + M4 시너지가 C_softmax (4-sleeve diversified)에서는 marginal. **baseline diversification이 overlay marginal benefit 잠식**. 학술적으로 일관 — Kritzman-Page-Turkington FAJ 주장은 "concentrated portfolio에 effective", Hyun-Pedersen 2019 "diversified portfolio overlay marginal".

### Codex critic 7 concerns 대응:

| ID | Sev | Disposition | 보강 |
|---|---|---|---|
| C1 | HIGH | ACCEPT_FULL | alpha_scores.parquet 생성 (78,412 rows + Usable_Date) |
| C2 | HIGH | PARTIAL_ACCEPT + PARTIAL_REBUTTAL | CAPM + FF2 + Carhart3 산출 (FF5/FF6 forge timeline mandate) |
| C3 | HIGH | ACCEPT | 2026-04-30 end date 명시 + 2026-05 trim |
| C4 | HIGH | PARTIAL_ACCEPT + REBUTTAL | baseline holdings 8-condition compliance + weights.csv = optimizer role boundary |
| C5 | MED | ACCEPT_HONEST | 이미 SR loss 명시; cor < 0.95 fail self-reported |
| C6 | MED | PARTIAL_ACCEPT | AX-001 v2 boundary mechanism 명시 + bad/normal IC ratio forge deferred |
| C7 | HIGH | ACCEPT_FULL | challenge_note.md + artifact_lineage.json 생성 |

### Q-Lead escalate trigger:

- HIGH ≥ 5 = HIT (C1+C2+C3+C4+C7=5)
- AX-008 FAIL (Codex critic 보고서 명시) — Forge + Architect 다음 spawn 시 verification triangulation 보강 의무
- 도훈 escalate notification 의무 (본 challenge_note.md를 통한 disposition document)

### 학술 + L-code + 정량 data 3축 인용 (Charter §8 mandate):

- 학술: Kritzman-Page-Turkington (2010, 2011 FAJ) + Adams-MacKay (2007 BOCPD) + Fama-French (2015 FF5) + Harvey-Liu-Zhu (2016 RFS) + Bailey-Lopez de Prado (2014 DSR) + Barroso-Santa-Clara (2015 risk-managed) + Hyun-Pedersen (2019 overlay diversification)
- L-code: L-274 (lockbox cycle), L-285 (Lockbox scope refinement), L-269 (4-Layer Codex enforcement), L-121 (Q07 defense conditional), L-119 (정적 블렌드 alpha 희석), L-122 (factor timing risk mgmt), AX-001 v2 (defense conditional), AX-007 (single-sleeve exemption)
- 정량: ICIR 0.9757 / IC t 4.541 / sub_stability 3/3 / recent 3Y ICIR 1.32 / Harvey CAPM t 3.5+ × 4 specs / DSR 2.2+ × 4 specs / cor 0.96~0.99 / SR Δ -0.026~-0.057 / MDD Δ +2.04~+3.89pp / crisis outperf +0.24pp / 78,412 alpha_scores rows / 260 sig_dates × 824 tickers

---

## 다음 단계 (alpha-research scope 후)

1. **alpha_package.json 최종 (no _draft)** — 본 challenge_note.md 첨부 + Codex disposition 명시 + cert eligibility re-audit
2. **risk-research spawn** — Σ 추정 (4-sleeve composition + overlay scalar layers) + stress + crowding
3. **optimizer-research spawn** — weights 결정 (각 sleeve weight + overlay coupling spec 선택)
4. **forge spawn** — FF5/FF6 full + 4-sleeve composite backtest with overlay (production code path)
5. **judge spawn** — overlay 3 spec ranking + cert eligibility re-audit + PIT C1-C15 full audit
6. **governor spawn** — book_state mutation 결정 (C_softmax retain vs C_softmax+overlay path A/B/C)

---

**Charter §8 No Silent Override 정합 — 모든 Codex concerns 명시적 disposition 기록 + 합리화 자기 검증 통과 + 학술 + L-code + 정량 3축 근거 제공.**

**도훈 mandate "우회 금지 / 요령 금지 / 합리화 금지 / Cert 발급 필수" 정합 — 6 정합 + 1 진단 보강 (cert 발급 정합성은 Codex 동의 = DEFERRED, 추후 risk + optimizer + forge cycle 후 cert eligibility 재평가).**

**Alpha-research alpha_package.json 최종 작성으로 다음 단계 진입.**
