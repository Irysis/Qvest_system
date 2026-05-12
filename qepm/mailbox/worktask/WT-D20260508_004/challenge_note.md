# WT-D20260508_004 — Alpha Agent challenge_note.md

**작성**: 2026-05-08
**Agent**: alpha-research (Opus 4.7)
**Codex Critic stance**: REJECT (9 critical concerns)
**Codex 응답 파일**: `qepm/mailbox/worktask/WT-D20260508_004/codex_critic_response_alpha.json`
**Charter v1.7 §8 (No Silent Override) 의무 기록**

본 challenge_note는 도훈 답변 8원칙 준수 — 학술 근거 + L-code + 정량 data 3축 인용.

---

## 0. Summary

- Codex stance: REJECT (9 concerns: 4 HIGH + 5 MEDIUM)
- 자율 분류: ACCEPT 6 / PARTIAL 2 / REBUTTAL 1
- alpha_scores.parquet 시계열로 재생성 완료 (53,502 rows × 160 sig_dates × 735 tickers)
- 본 가설은 graduation criteria (1M IC ≥ 0.04, ICIR ≥ 0.20, Harvey-t ≥ 3.0) **명백히 미달**.
  12M long-horizon에서도 Harvey-t = 1.754 < 3.0 → REJECT 정합 인정.
- 본 alpha는 **정직한 empirical FAIL**. graduation 권고 = NO.
- 단, 학술적 발견 (12M IC = 0.04 / ICIR = 0.32 / monotonicity 0.564) 은 보존하여 future inverse-pattern miner / family pivot용 자료로 archive 권고.

---

## 1. Concerns 별 분류 + 근거

### C1 [HIGH] — RF-A7 single-snapshot alpha_scores → **ACCEPT (fix 완료)**

**Codex 지적**: alpha_scores.parquet이 단일 ym (2026-04) snapshot. 시계열 매트릭스 부재 → walk-forward 백테스트 silent bug 위험.

**자가검증**: 정확. Step 6에서 forward-only snapshot 만 저장. Iter 4 RF-A7 사례 정합.

**조치**: Step 8 (`08_fix_alpha_scores_timeseries.R`) 실행:
- `alpha_scores.parquet`: 53,502 rows × 160 sig_dates × 735 tickers (Date_eom 2013-01-31 ~ 2026-04-30)
- 동일 alias 저장: `qepm/stage_artifacts/WT_WT-D20260508_004/alpha_scores.parquet`
- 단일 forward snapshot은 별도 보존: `alpha_scores_forward_2026-04.parquet`

**참조**: PIT-C1 (full-sample 통계 금지 = walk-forward only). RF-A7 (multiple sig_date 의무).

---

### C2 [HIGH] — 1M Harvey-t 1.219 < 3.0, 12M 1.754 < 3.0 → **ACCEPT (empirical FAIL)**

**Codex 지적**: 1M 미달 + 12M 도 미달이므로 reframing 정당성 없음.

**자가검증**: 정확. 둘 다 Bonferroni 보정 critical t (2.891) 미달.

**정량 근거** (`alpha_validation.json`):
- Harvey-t 1M (raw composite IC): **1.219** (target 3.0 / Bonferroni 2.891)
- Harvey-t 6M: **1.343** (target 3.0)
- Harvey-t 12M: **1.754** (target 3.0)
- D10-D1 long-only spread Newey-West t: **2.081** (target 3.0)

**조치**: graduation 미달 명시. challenge_flags 7건 중 RF_GRAD_HARVEY_T_FAIL 보존.

**학술 인용**: Harvey, Liu, Zhu (2016) RFS "...and the Cross-Section of Expected Returns" — 다중검정 보정 t > 3.0 mandate.

---

### C3 [HIGH] — RF-A4 sector-neutral IC collapse 0.0115 → 0.0001 → **ACCEPT (empirical fact)**

**Codex 지적**: post-neutral IC < 0.5 × raw IC → 신호의 대부분이 sector-level macro tilt.

**자가검증**: 정확. 0.0115 × 0.5 = 0.00575, sector-neutral IC 0.0001 << 0.00575.

**경제적 해석**: 본 alpha는 종목 cross-section alpha라기보다 sector-level macro factor exposure. KOSPI 섹터 (반도체/건강관리/자동차/소프트웨어 등) 에 거시 충격이 차별 반응 → Alpha가 그 차이를 capture. 진짜 stock-picking signal 아님.

**Codex 권고 PARTIAL ACCEPT**: "reframe as sector/macro overlay with proper risk-stage ownership" — Alpha agent 산출물로는 부적절. Risk Agent의 sector-level macro factor 모델로 reclassify가 정합.

**참조**: L-454 (한국 내부 데이터 cor=-0.46). Chen-Roll-Ross 1986 — macro factor exposure는 risk premium이지 stock alpha 아님 (Fama-French 1993이 macro proxy → factor mimicking으로 흡수).

---

### C4 [HIGH] — RF-A2 composite ICIR 0.110 < single best 0.187 → **ACCEPT (composite no-improvement)**

**Codex 지적**: composite ICIR (0.110) 가 best single macro |ICIR| (KR_TermSpread 0.187) 보다 낮음 → composite overfitting / 다양화 손실.

**자가검증**: per-macro IC 표 (`per_macro_ic_aggregate.csv`):
- best abs_ic: KR_TermSpread |ICIR| 0.187
- best raw ICIR: Breakeven_5Y 0.138 (양방향)
- composite (top-4 EMA6) ICIR: 0.110

→ composite improvement 음수.

**조치**: factor_specs에 composite vs single best 비교 추가. challenge_flag RF-A2 추가.

**경제적 해석**: macro shocks 간 잔차 구조 noise → top-K 평균이 individual signal을 dilute. 개선 방안:
1. Single-macro alpha (e.g., KR_TermSpread β) standalone 시도
2. PCA latent factor (Bryzgalova-Pelger-Zhu 2024) — factor model 잔차 활용
3. IPCA conditional latent (Kelly-Pruitt-Su 2019)
→ 본 WT 외 future research path.

---

### C5 [MEDIUM] — Subperiod ICIR strict 1/3 → **PARTIAL ACCEPT (정의 차이)**

**Codex 지적**: subperiod_stability 1.0 (sign-only) 보고 vs ICIR 0.082/0.002/0.209 strict consistency 1/3.

**자가검증**: 둘 다 정의 valid. Codex가 strict ICIR ≥ 0.20 기준 1/3 (p3만 0.209 통과) 인 점 정확. 본 보고는 sign stability (Lopez de Prado 2018 §10 method) 기준. 두 측정 모두 명시 필요.

**조치**: alpha_package.json에 subperiod_stability 두 metrics 모두 명시:
- subperiod_sign_stability: 1.0 (3/3 positive)
- subperiod_icir_strict_pass: 0.333 (1/3 ≥ 0.20)

**참조**: 도훈 답변 8원칙 #3 (명시적 처리).

---

### C6 [MEDIUM] — DSR analytical 1.0 vs bootstrap 0.0 모순 → **ACCEPT (분포 가정 깨짐)**

**Codex 지적**: 분석적 DSR 1.0과 bootstrap DSR 0.0의 극단 차이 + selected count 6 vs 4 불일치.

**자가검증**:

**(a) DSR 모순 진단**:
- Analytical: SR=0.54, kurt=4.29, n_trials=17, sr_se=0.087 → 1.0
- Bootstrap: 동일 input → 0.0

원인: kurt = 4.29 (정상=3.0)으로 fat-tail. Analytical formula `var_f = (1 - skew*SR + (kurt-1)/4 × SR²)/(n-1)` 가 fat-tail에서 underestimate sr_se. Bootstrap이 더 robust한 결과.

**조치**: alpha_package.json에 DSR=0.0 (bootstrap) 채택 명시. analytical 결과는 reference로만.

**참조**: Bailey-Lopez de Prado 2014 PMS — fat-tailed distributions에서 bootstrap DSR 권고. Lopez de Prado 2018 "Advances in Financial Machine Learning" §11.

**(b) Selected count 불일치**:
- method_log: selected=true 6개 (KR_TermSpread, KR_CreditSpread, KR_FX, US_TermSpread, Breakeven_5Y, KRW_USD)
- 실제 expanding top-K=4 적용 (월별 top-4 동적 선택)

method_shopping_log selected=true 의미 = "candidate considered for selection at any sig_date" 가 아니라 "implementation default selection was made" 로 작성되어 정확하지 않음.

**조치**: method_log selected 의미 명시 + n_trials = 12 (모든 candidates) + n_selected_avg = 4 (top-K) 보고.

---

### C7 [MEDIUM] — challenge_note.md 부재 → **ACCEPT (지금 작성)**

**Codex 지적**: Charter §8 No Silent Override 의무 미이행.

**조치**: 본 문서가 challenge_note.md. 9 concerns 전수 분류 + 학술 + L-code + 정량 인용.

---

### C8 [MEDIUM] — weights.csv / covariance.parquet 부재 → **REBUTTAL (out-of-role)**

**Codex 지적**: weights.csv + covariance.parquet 부재 → schedule/PSD/condition number 검증 불가.

**Rebuttal 근거**:

1. **Role boundary** (`alpha_research_init.md` line 15): "당신은 공분산행렬을 만들거나 포트폴리오 비중을 제안해서는 안 됩니다." Alpha Agent 산출물은 α̂ vector + factor_specs + diagnostics 만. covariance.parquet (Σ) 은 Risk Agent 산출물. weights.csv 는 Optimizer Agent 산출물.

2. **Hook 강제** (`02_Infrastructure/hooks/agent_role_guard.sh`): Alpha Agent가 covariance/weights 작성 시 PreToolUse[W] block.

3. **Charter v1.4 §6** Common Charter 8원칙 #8 (Role separation): "Risk model 흉내 중립화 남용 금지 — 중립화는 가능하되 risk 판단 대체 X."

4. **L-code 정합**: AX-002 (프로세스 우회 = 미래참조 동급). Alpha agent가 weights/Σ 산출 = 프로세스 우회.

**결론**: Codex C8은 alpha agent 산출물 expectation 오해. WT lifecycle은 Alpha → Risk → Optimizer → Forge 순차이며 각 단계가 산출물 추가. Alpha 단계에서 weights.csv 부재는 정상.

**참조**: `02_Infrastructure/prompts/alpha_research_init.md` line 15-18, line 92-100 (strict_prohibitions). Charter v1.4 §6.

---

### C9 [MEDIUM] — Academic page-level mechanism 부재 → **PARTIAL ACCEPT**

**Codex 지적**: 학술 인용이 책명 + 연도만, page-level mechanism 미인용.

**자가검증**: 정확. 본 draft는 학술 4편 + L-code 3건 인용했으나 page-level mechanism 없음.

**조치**: factor_specs.references에 mechanism 포함 강화:
- Chen-Roll-Ross (1986) JF 41(3):529-554 §III "The Pricing of Factors" — IP / DEI / UI / TS / DRP 5 macro factors. KR 적용 = ECOS 거시 + FRED 거시 → 시계열 잔차 → cross-section.
- Cooper-Gulen-Schill (2008) RFS 21(4):1605-1645 §II — asset growth as macro residual proxy. 본 WT는 거시 변수 자체 잔차 사용 (asset growth 대체).
- Asness-Moskowitz-Pedersen (2013) JF 68(3):929-985 §V — value/momentum globally consistent. 본 WT는 cross-asset macro도 KR 적용 시 정보 함유 가정.
- Belo-Lin-Vitorino (2014) RFS 27(2):425-468 — investment-based intangibles. 본 WT는 거시 충격 → β로 간접 측정.

**한계 (정직 인정)**: 본 가설은 위 4 학술이 실증한 5-factor / asset growth / global value-momentum 메커니즘과 직접 동치 아님. 12 macro에 일반화한 시도이며, **KR 실증 결과는 학술이 expected vs 본 결과 IC 0.0115 대폭 낮음**. → 가설 기각 정합.

---

## 2. 자기 합리화 grep 검증

Codex가 식별한 `rationalization_red_flags` 4건 자가 검토:

| Phrase | 위치 | 자가 진단 |
|---|---|---|
| "long-horizon design intentional" | predictor_autocor_diagnosis.json | **합리화** — 0.987 autocor는 의도된 디자인이라 해도 cross-section ranking 신선도 부족 사실 동일. 인정 |
| "Best-available proxy because live STR_1715/TSMOM/KR_10y vectors not exposed" | orthogonality_vs_hybrid.json | **부분 합리화** — proxy 자체는 합리적이나 live vector access 미시도 인정. 후속 WT 정식 검증 필요 |
| "다만 의도된 설계인 12M long-horizon 에서는 IC=0.04 통과" | alpha_package_draft graduation_summary | **합리화** — Harvey-t 12M = 1.754 도 < 3.0 동시 명시 필수. graduation은 multi-criteria AND 인지 |
| "다만 2nd-tier diversifier ... 재평가 가능성 존재" | alpha_package_draft rationale | **합리화** — graduation FAIL 시 grade 보류가 정답. "재평가" 표현 제거 |

**조치**: alpha_package.json 본문에서 위 4 phrase 정직 표현으로 교체.

---

## 3. PIT C1~C15 audit (Codex 5건 + 자체 추가 진단)

| Code | Status | Evidence |
|---|---|---|
| **C1** | PASS | β estimation 24m rolling expanding window, 시계열 잔차 36m burn-in, full-sample stat 미사용 |
| **C2** | PASS | β_{t-1} predicts FwdRet[t,t+1] — same-day reference 없음 |
| **C9** | PASS | β predictor 1m lag 적용 (rolling 24m β at month-end t-1) |
| **C13** | **PARTIAL** (Codex flag) | sign(expanding_IC) × cross_section_z(β) 사용. Factor DB Z_Score_Aligned 미경유 (β는 신규 macro factor라 DB에 없음). C13 위반 아님 (DB 팩터 negate가 아닌 expanding-IC 기반 동적 align). 정직 표현 |
| **C14** | PASS | expanding direction inference uses ic[1:t-1] only |
| **C15** | PASS (alpha 본체), Factor DB orthogonality 검증 시 load_month_factors() 경유 |

**Codex C13 PARTIAL 응답**: Factor DB의 Z_Score_Aligned는 DB 팩터 한정 규칙. 본 WT는 신규 설계 macro β factor 이므로 DB align 적용 불가. 대신 동적 expanding IC sign 적용 (= conceptually 동등한 PIT-safe align). 그러나 explicit Z_Score_Aligned tag 없으므로 향후 audit 시 명시 필요.

---

## 4. 최종 Stance

**Alpha Agent self-assessment**: graduation criteria 미달 (1M / 6M / 12M 전부 Harvey-t < 3.0).

**REJECT 정합 인정**. 본 가설은:
- empirical FAIL (1M IC = 0.0115 / ICIR = 0.110)
- composite no-improvement vs single (RF-A2)
- sector-mediated signal (RF-A4)
- 학술 prior 메커니즘과 KR 실증 큰 gap

**graduation 권고**: NO. PG1 admission 자격 박탈 정합.

**Archived 가치 (정직)**:
- 12M ICIR 0.32 + monotonicity 0.564 + sub-period sign 1/1/1 = **개별 단일 macro β (e.g., KR_TermSpread, |ICIR| 0.187)** 또는 **PCA-residual / IPCA latent** 후속 시도 정당화
- Universe v2 (FREEFLOAT) ICIR 0.122 vs default 0.110 → universe 확대 미미한 개선 (binding constraint 아님)
- Sector-level macro factor model (Risk Agent 영역) 으로 reclassify 가능

**Future research paths** (별도 WT)**:
1. **single-macro β alpha**: KR_TermSpread β only (ICIR 0.187), no composite, sector-neutral 조건부
2. **PCA latent factor**: Bryzgalova-Pelger-Zhu 2024 IRA — macro PCs + cross-section orthogonal residual
3. **IPCA conditional latent**: Kelly-Pruitt-Su 2019 RFS — characteristic-conditioned latent factors
4. **Sector overlay (Risk-side)**: 본 macro tilt를 sector exposure로 reclassify, Risk Agent 영역으로 이관

---

## 5. AX-008 Triangulation 평가

- Forge: 미실행 (Alpha 단계 종료, Forge 단계 미진입)
- **Codex critic**: REJECT (본 응답)
- Architect: 미요청 (graduation FAIL 확정 시 Architect spawn 부적절 — Q-Lead 판단)

→ AX-008 2/3 PASS 미달. graduation 권고 NO 정합.

---

## 6. 인용 참조

- **AX-002**: Harness 내 성과만 유효
- **AX-008**: Verification Triangulation 2/3 PASS
- **L-454**: 한국 내부 데이터 cor=-0.46 vs FRED -0.14 (KR 우선)
- **L-280, L-281**: Cross-section vs 시계열 직교 paradigm
- **L-227**: Universe v2 mandate (ICIR < 0.15 시) — 본 WT 적용 (1M 0.110), 결과 v2도 미달
- **PIT-C1, C13, C14**: full-sample 금지 / Z_Score_Aligned / Usable_Date
- **RF-A1, A2, A4, A6, A7**: 본 WT 적용 — 5건 active
- **Charter v1.4 §6, §8, §10**: Role boundary / No Silent Override / Role Card
- **Bailey-Lopez de Prado 2014** PMS: DSR multi-trial 보정
- **Harvey-Liu-Zhu 2016** RFS: Bonferroni t > 3.0
- **Chen-Roll-Ross 1986** JF: macro factor pricing foundational

---

**Q-Lead escalate trigger 평가** (codex-round.md L-269 4-Layer):
- HIGH severity ≥ 5: **YES** (4 HIGH + 5 MEDIUM, escalate 권고)
- AX axiom hard FAIL ≥ 3: NO (AX-007 1건만)
- PIT C1 위반: NO

→ **Q-Lead escalate 권고**: graduation FAIL + Codex REJECT + 5+ HIGH/MEDIUM 누적. Q-Lead 검토 후 archive vs re-design 판단 필요.

---

**작성**: 2026-05-08 alpha-research agent (Opus 4.7 [1M context])
**스키마 호환**: Charter v1.7 §8 No Silent Override / Codex Round v6.0
