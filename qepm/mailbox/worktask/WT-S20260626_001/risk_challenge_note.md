# Risk Challenge Note — WT-S20260626_001 (Risk role)

**WT type**: `sizing_only` (Σ INHERIT, 신규 공분산 추정 금지) · **discovery_of**: STR_1715_WT016_Iter31_GridBestProd · **as_of**: 2026-06-26

**역할 경계**: risk-research는 STR_1715 cross-sectional Σ를 inherit 참조 + 1개 정성 tradeoff flag만 제공. alpha 수정·weight 제안·오버레이 결합 연산자 설계 금지.

---

## Codex Critic Round 결과 (GPT-5.5 xhigh)

- **stance**: `REVISE` · veto_flag=false
- **weakest_assumption (Codex)**: "STR_1715 inherited covariance/tail이 max-cash 오버레이 연산자 변경 후에도 decision-relevant하다는 가정이 가장 취약 — max-cash가 cash schedule을 바꿔 realized tail path를 바꾼다."
- **자기 검증 합리화**: Codex critique는 devil's advocate이며 veto 권한 없음. 아래 ACCEPT/PARTIAL/REBUTTAL 자율 분류. **핵심 category 오류**: Codex는 본 단계를 discovery-grade 신규 risk 재추정으로 간주하나, 이 WT는 `sizing_only` Σ inherit이며 weights.csv/현재 covariance.parquet/regime artifact는 **state machine상 forge 단계 산출물**(RISK_DONE → OPTIMIZER_DONE → FORGE_DONE)이다. RISK_DONE 시점에 그 artifact 부재는 정상.

---

## Concern별 자율 분류 (Decision Protocol)

### C1 [HIGH] target WT artifacts 부재 (weights.csv / 현재 cov / alpha_scores / regime) → PIT C1/C9/C11/C12 FAIL
**분류: REBUTTAL (+ 부분 ACCEPT)**
- **REBUTTAL 근거 (3축)**:
  - (학술/프로세스) QEPM state machine: risk role은 RISK_DONE에서 종료하며 weights.csv·현재 backtest covariance·regime cash schedule은 **optimizer/forge 산출물**이다 (`state_machine_path`: SPEC_APPROVED → ALPHA_DONE → **RISK_DONE** → OPTIMIZER_DONE → FORGE_DONE). RISK_DONE에 그것을 요구하는 것은 단계 혼동.
  - (L-code/규율) PIT C9(vol_lag/dd_lag)·C11(external series lineage)·C12(factor-return construction)은 **오버레이 timing·regime·backtest 영역 = forge가 검증**. 본 risk 단계는 descriptive Σ inherit이므로 같은 book에 대한 선행 PIT audit(WT-S20260504_001 `pit_audit`: C1/C2/C12/C14/C15 PASS) inherit.
  - (정량) 가설은 cross-sectional Σ를 바꾸지 않음(오버레이=regime cash-scaling 레이어). alpha_inheritance_cor=1.0, Σ inherit-token.
- **부분 ACCEPT**: "risk-specific waiver 문서 부재"는 정당한 지적 → 본 risk_challenge_note.md가 그 waiver/scope 문서 역할 수행 (C7과 함께 해소).

### C2 [HIGH] inherited tail이 RF-R4 / CVaR cap 위반 (ES95 12.89% vs 2.5% cap, GFC −38.64% > 25%)
**분류: REBUTTAL**
- (학술/empirical) ES95 2.5% "cap"은 generic role-default이며 **25종목 집중 KR long-only book에는 부적용**. measurement-graduation §6: KR long-only 슬리브 β≈0.99, 시장성분 공유 → 월간 ES95 ~13%는 구조적 정상치. 실제 governing hard cap = **MDD ≤ -45%**, 실측 −41.69% = **미breach**(margin -3.31pp).
- (정량) GFC −38.64%는 단일 최대 stress이나 회복; AX-001 v2 conditional: highrisk/normal ES ratio 0.3997 = PASS_CONDITIONAL (예측력 보유). 전기간 SR 기준 적용 금지(AX-001 v2).
- (규율) 이 값들은 STR_1715 **inherited 실측**(metric_type=inherited)이며 본 WT 신규 추정 아님. "downplay"가 아니라 정확한 cap(MDD 45%) 적용. → 단, draft가 cap 적용 근거를 명시 안 한 점은 revise로 surface.

### C3 [HIGH] method-shopping 모순: Gerber-RMT cond 23.4 < LW 40.95인데 LW 선택
**분류: REBUTTAL (inherited rationale 존재)**
- 이 method log는 **WT-S20260504_001 inherit**이며 그 precedent가 이미 명시: Gerber-RMT는 *simplified proxy implementation, canonical Gerber statistic 아님* → **frozen B_ref와의 coherence를 위해 reject**, LW를 canonical Σ로 선택. selection_objective=condition_number는 *informative PSD estimator 중*(Sample 43.63 vs LW 40.95) 적용된 것이며, proxy Gerber는 후보 자격 제외. → draft에 이 inherited rationale을 surface (revise).

### C4 [MEDIUM] HHI / TDC-vs-PG2 미제공
**분류: REBUTTAL**
- sizing_only Σ inherit — HHI/TDC 재추정 out of scope. 제공값(TDC_MKT 0.65, L219 56%, style_cor 0.745)은 STR_1715 inherited passthrough이며 metric_type=inherited 라벨. PG2-active-book TDC 재계산은 governor/optimizer 영역.

### C5 [MEDIUM] overlay가 co-activation에서 cash exposure 변경 → tail이 forge로 deferred
**분류: ACCEPT (framing) + REBUTTAL (demand)**
- ACCEPT: Codex가 정확히 본 tradeoff flag의 메커니즘을 재진술 — max-cash는 AR·R05 동시발화 구간에서 곱셈 대비 디리스크 약화 → tail path 변경. **이것이 본 risk 단계의 핵심 산출(tradeoff flag)**이다.
- REBUTTAL(demand): overlay-conditioned MDD/CVaR A/B 측정은 **forge가 backtest로** 수행(risk role은 backtest 미수행 + 수치 추측 금지 = answer-principles). risk는 정성 flag로 위험을 명시 등재했고, 측정 owner를 forge로 명시 = No Silent Override 준수.

### C6 [MEDIUM] regime mapping 불완전 (BULL/NORMAL/CAUTION/CRISIS 매핑·switch-rate 부재)
**분류: REBUTTAL**
- sizing_only inherit — 신규 regime 추정 out of scope. inherited regime_correlation(4-state Normal/HighRisk/Crowded/Extreme, daily n: 356/244/247/77 전부 n>30)을 ref. Codex도 "daily Extreme n=77 avoids RF-R8" 인정. BULL/NORMAL/CAUTION/CRISIS 매핑은 forge regime cash schedule 영역.

### C7 [LOW] risk_challenge_note.md 부재 (No Silent Override path)
**분류: ACCEPT**
- 정당. 본 문서가 risk role No Silent Override 경로를 충족 — Codex 7 concern 전부 명시 분류 + tradeoff flag 등재 + 측정 owner(forge) 명시.

---

## 처리 요약

| Concern | Severity | 분류 | 처리 |
|---|---|---|---|
| C1 artifacts 부재 | HIGH | REBUTTAL + 부분 ACCEPT | state machine scope 명시 + risk waiver 문서화(본 note) |
| C2 tail RF-R4 | HIGH | REBUTTAL | MDD 45% cap(미breach) governing 명시 + §6/AX-001 v2 근거 surface |
| C3 method shopping | HIGH | REBUTTAL | inherited Gerber=proxy reject rationale surface |
| C4 HHI/TDC | MEDIUM | REBUTTAL | inherit passthrough, 재추정 out-of-scope 명시 |
| C5 overlay tail | MEDIUM | ACCEPT(framing)+REBUTTAL(demand) | tradeoff flag 강화 + forge measurement owner 명시 |
| C6 regime mapping | MEDIUM | REBUTTAL | inherit ref, 신규 regime out-of-scope |
| C7 challenge note | LOW | ACCEPT | 본 문서 작성 |

**자동 escalate trigger 점검**: HIGH=3 (<5) · AX axiom hard FAIL(substantive)=0 (Codex AX FAIL은 scope 혼동 유래) · **Σ PD violation 없음**(PSD verified, cond 40.95, min_eig 1.57e-4) · PIT hard violation(substantive) 없음(forge-scope mis-attribution). → **Q-Lead escalate 불요**, risk role 자율 종결.

**최종 stance 대응**: REVISE 수용 부분(C1 waiver 문서·C2/C3 rationale surface·C5 flag 강화·C7 note) 반영해 risk_package.json finalize. 나머지 REBUTTAL은 scope 경계(sizing_only Σ inherit + RISK_DONE state) 근거로 정당화.

**Verification Triangulation (AX-008)**: risk-research = Source 1 of 3. Codex = Source 2 (REVISE, scope-mismatch 기반). 본 분류로 위험 항목 silent-pass 없음 확인. Forge(Source 3)가 max-cash A/B 실측으로 tradeoff flag 검증 시 triangulation 완성.

> risk role No Silent Override 충족. Σ inherit + tradeoff flag만, 역할 경계 준수.
