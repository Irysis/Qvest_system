# Challenge Note — WT-D20260629_001 (alpha-research)

**Signal**: 오버나잇 상승갭 빈도 (gap-frequency, arXiv 2606.14386 KR 적용)
**Agent verdict**: FAIL (no graduation)
**Codex stance**: REVISE · veto_flag=False · ax_008_status=FAIL · agree_with_claude=False
**Codex 핵심**: "I agree with the no-graduation direction, but not with approving the package artifact: the score file and diagnostics are insufficient and potentially unsafe for downstream QEPM stages."

**핵심 합의**: Codex와 agent 모두 **FAIL/no-graduation 동의** — 결론 충돌 없음. Codex의 REVISE는 *결론*이 아니라 *아티팩트 완전성·진단 보강*에 대한 요구. AX-008 triangulation: Forge-grade 실측(canonical_screen_bt, contract build_benchmark_compare) + Codex(no-graduation 동의) = **2-source 모두 FAIL 일치**. veto 없음. discovery FAIL은 유효한 QEPM 결과 (measurement-graduation §5 — 실패 alpha = DPL 입력 피처).

---

## 7 Concerns 자율 분류 (Charter §8 No Silent Override)

### C1 [HIGH] RF-A7 — alpha_scores.parquet 단일 sig_date (multi-date walk-forward 미검증)
**분류: ACCEPT (단, FAIL이라 downstream moot)**
- **인정**: 제출한 `alpha_scores.parquet`는 as_of 1개월(2026-06-29) snapshot. multi-date walk-forward score 파일을 별도 적재하지 않음.
- **정량 근거 (이미 수행됨, 파일 미적재였을 뿐)**: diagnostic은 단일 snapshot이 아니라 **257개월(2005-01~2026-06) full panel** 위에서 계산됨 — IC NW-t -3.672, canonical_screen_bt n_months=257. 즉 walk-forward 측정은 *수행*되었고 `scratch_gapfreq/canonical_screen_results.csv`(9 config × 257m) + `panel_analysis.rds`(80,595 rows)에 존재. snapshot parquet만 1개월이었던 것은 적재 누락.
- **조치**: 최종 패키지에 257m IC 시계열 산출 경로 명시 + alpha_scores를 multi-date로 재적재. **단 verdict 무관** — FAIL이라 risk/optimizer/forge downstream 미진행 → Iter-4 single-snapshot 자본 리스크는 애초에 발생 불가(편입 없음).
- **L-code 정합**: measurement-graduation §6 16/16 long-only PORT_t FAIL 패턴 (자본 미편입 = single-snapshot risk N/A).

### C2 [HIGH] / PIT-C13 [FAIL] — 부호 역전(continuation→reversal)이 full-sample IC 관찰 후 선택된 sign-flip
**분류: PARTIAL ACCEPT (labeling 수정) + REBUTTAL (verdict는 sign-invariant)**
- **ACCEPT (labeling)**: `alpha_reversal_score = -z_gapfreqmag_20`은 full-sample IC 부호를 본 뒤 음수화한 것이 맞음. C13(Z_Score_Aligned only, rolling sign-align)을 충족하는 production-grade 부호정렬(`align_factor_direction` Usable_Date≤sig_date expanding IC)을 적용하지 않았음. **인정하고 score 라벨을 `alpha_reversal_score`(deployable 함의) → `gapfreq_z_raw` + 진단 라벨로 정정.** 배포 의도 framing 제거.
- **REBUTTAL (verdict sign-invariance) — 학술+L-code+정량 3축**:
  - **정량**: FAIL 판정은 부호 선택과 **무관**하다. Stage D에서 *양쪽 방향 모두* 실측: continuation(long high) PORT_t = **-0.176**(gapfreqmag) / **-0.915**(gapup20); reversal(long low) PORT_t = **-1.587** / **-1.898**. **4방향 × 2변형 = 8개 long-only 구성 전부 PORT_t 음수**, graduation HARD 2.95 미달. 부호를 사전등록했든 역방향이든 long-only로 PASS 불가 — 따라서 sign-flip은 verdict를 PASS로 구출하지 못함(moot for conclusion). PIT-C13 위반이 거짓 양성을 만든 것이 아니라, 거짓 음성/양성 어느 쪽도 만들지 않음.
  - **학술**: Jegadeesh (1990, JF) 단기 reversal + Berkman-Koch-Tuttle-Zhang (2012, JFE) overnight-attention — KR에서 overnight 갭의 단기 mean-reversion은 사전적으로 예측 가능한 방향(A주 continuation의 반대). 즉 reversal 부호는 *순수 in-sample 발견*이 아니라 단기 reversal 문헌과 정합하는 사전 가설 후보였음 (request.json hypothesis_description: "부호는 empirical로 결정"). 다만 production 부호정렬 미적용은 인정.
  - **L-code**: measurement-graduation §6 "직교 ≠ 수익: standalone long-only 16/16 admission FAIL의 사유는 상관이 아니라 PORT_t(실현 net active)" — 본 케이스도 동일 메커니즘(rank-IC sorting ≠ long-only PORT_t).
- **조치**: 최종 패키지 verdict FAIL 유지 + C13 위반을 challenge_flag로 명시 기록(은폐 금지) + score 라벨 진단용으로 정정 + 향후 재시도 시 `align_factor_direction` 적용 의무 명기.

### C3 [HIGH] DSR 누락 + DSR HARD "부적용" 합리화 + 5-spec multi-testing 부재
**분류: PARTIAL ACCEPT**
- **ACCEPT**: DSR 수치를 산출하지 않았음. measurement-graduation §3은 "DSR 수치 자체는 n_trials>1이면 진단용으로 계속 산출·기록(게이트 아님)"을 요구 — 6 family 변형을 시험했으므로 DSR 진단치는 **산출 의무**가 있었다. 미산출은 인정.
- **REBUTTAL (HARD 부적용은 규정 정합) — 정량+L-code 2축**:
  - **L-code/규정**: measurement-graduation §3 (도훈 mandate 2026-06-10): "DSR≥0.5 HARD는 sweep형 selection에서만 — 가설주도 순차개선 체인은 selection_type=chain, DSR 게이트 부적용." 본 작업은 1논문 1가설의 family 변형(같은 메커니즘의 window/방향 변형) → chain. DSR HARD 부적용은 **규정 정합**이지 합리화가 아님.
  - **정량**: 단, verdict가 FAIL이므로 DSR이 PASS/FAIL 어느 쪽이어도 결론 불변(PORT_t HARD에서 이미 명백 탈락). DSR은 과적합 *방어* 게이트인데, 본 신호는 과적합이 아니라 *애초에 신호 없음*(IS·OOS 공히 long-only PORT_t 음수).
- **조치**: 최종 패키지에 DSR 진단치 산출 경로 + selection_type=chain 근거(규정 인용) 명시. 5-spec(forge) multi-testing은 FAIL→forge 미진행으로 moot(C6 참조).

### C4 [HIGH] Long-only translation 실패 (|rank_IC|=0.0304<0.04, 모든 PORT_t 음수, best -1.587 vs 2.95)
**분류: ACCEPT (agent 결론과 완전 일치 — 핵심 FAIL 근거)**
- **완전 동의**: 이것이 agent FAIL 판정의 핵심 근거 그 자체. 추가 반론 없음.
- **정량 재확인**: rank-IC abs 0.0304 < 0.04(advisory) + 9 config PORT_t ∈ [-1.96, -0.18] 전부 음수 + net SR 음수 + alpha_annualized 음수. graduation HARD(PORT_t≥2.95) 압도적 미달.
- **L-code**: measurement-graduation §6 16/16 패턴 + Cycle 2 교훈(rank-IC t ≠ portfolio-alpha t) 재현.

### C5 [MEDIUM] RF-A4가 sector-neutral evidence 아님 (neutralization='none', cluster control만, residual 33%)
**분류: PARTIAL ACCEPT**
- **ACCEPT**: 맞음. 제출 진단은 sector/size neutralization을 적용하지 않았고(raw cross-sectional Z), residual IC는 microstructure *cluster* control(L39+reversal+MaxRet+IdioVol+Amihud) 후의 값(0.010, 33% retention). sector-neutral ICIR을 별도 산출하지 않았으므로 RF-A4를 "sector-neutral evidence"로 칭한 것은 부정확 → 라벨 정정.
- **REBUTTAL (verdict 무관) — 정량**: sector-neutral ICIR을 추가해도 long-only PORT_t 음수 사실은 불변(neutralization은 IC를 다듬을 뿐 long leg의 실현 alpha 부재를 뒤집지 못함). 또한 cluster-control residual 33% retention 자체가 spanning 증거로 충분(L39 단독 58% 흡수). sector-neutral은 보완 진단이지 verdict 변경 레버 아님.
- **조치**: RF-A4 라벨을 "cluster-orthogonalization retention(=33%, NOT sector-neutral)"로 정정. sector-neutral ICIR은 후속 재시도 시 산출 항목으로 backlog(현 FAIL에선 불필요).

### C6 [MEDIUM] 필수 corroborating artifacts 부재 (weights.csv, covariance.parquet, challenge_note, artifact_lineage, final package, risk/optimization package)
**분류: ACCEPT (challenge_note/final/lineage는 즉시 생성) + REBUTTAL (downstream artifacts는 FAIL로 moot + 역할경계)**
- **ACCEPT (생성)**: challenge_note.md(본 파일) + alpha_package.json(final) + artifact_lineage(record_package_lineage) 즉시 생성. 누락 인정.
- **REBUTTAL — 역할경계 + 정량 2축**:
  - **역할경계 (Charter strict_prohibitions)**: `weights.csv`/`covariance.parquet`/`risk_package`/`optimization_package`는 **alpha-research 산출물이 아님** — 공분산 Σ는 risk-research, weights는 optimizer-research 영역(alpha agent가 생성하면 Hook L3 block). alpha agent가 이들을 못 만든 것은 결함이 아니라 **역할경계 준수**.
  - **정량/프로세스**: discovery verdict=FAIL → Q-Lead가 risk/optimizer/forge agent를 **spawn하지 않음**(QEPM 경로는 alpha PASS 시에만 진행). 따라서 risk/optimization package 부재는 정상이며, PSD/condition·schedule·5-spec triangulation은 *수행할 대상이 없음*(moot). Codex가 "cannot be triangulated"라 한 것은 맞으나, FAIL alpha에 대해서는 triangulate할 downstream이 없는 것이 정상 동작.
- **조치**: challenge_note + final package + lineage 생성. 나머지는 "FAIL → downstream 미진행으로 N/A" 명시.

### C7 [MEDIUM] Implementation discipline (turnover 18.4x>11x, RF-A5 illiquidity 미측정, 5e7 vs 2e8 floor 충돌)
**분류: ACCEPT (turnover/floor) + PARTIAL (illiquidity)**
- **ACCEPT (turnover)**: turnover 18.4x/yr >> 11.0/yr discipline(research_philosophy #6). 이것은 *추가* FAIL 근거 — agent draft에 이미 TURNOVER red_flag로 기록함. Codex 지적 정합.
- **ACCEPT (floor)**: 5e7 liquidity floor는 request.json `universe_definition.liquidity_min_won_20d_avg=50000000` + `hard_mandate.liquidity_floor_won_20d_avg=50000000`(discovery breadth)를 따른 것. WT spec이 discovery에 5e7을 명시했으므로 spec 정합이나, 헌법 base 2e8과 충돌하는 것은 사실. **검증으로 충돌 해소**: Stage D에서 2e8 floor도 별도 실측(`gapfreqmag20_REV_low_n20_2e8` PORT_t=-1.577) → floor를 2e8로 올려도 FAIL 동일. floor 선택이 verdict에 영향 없음.
- **PARTIAL (illiquidity)**: RF-A5(top-decile illiquid 집중)는 gapup_20/gapup_10 이산 count의 decile 불균형(top decile n=206/25)으로 *정성* 식별했으나 top-decile의 20d ADV 분포를 *정량* 측정하진 않음 → 인정. 단 continuous gapfreqmag_20(균형 decile) 사용 + 2e8 floor 실측으로 illiquidity 영향이 verdict를 바꾸지 않음을 이미 입증.
- **조치**: turnover 18.4x + floor 충돌 해소(2e8도 FAIL) 최종 패키지 명시. top-decile ADV 정량은 후속 backlog(현 FAIL에선 불필요).

---

## Self-Rationalization Auto-Detection (Charter §8 의무)

Codex가 지적한 rationalization_red_flags 6종에 대한 자기검증:
| Codex 지적 표현 | 자기검증 결과 |
|---|---|
| "per-month Spearman IC가 authoritative diagnostic" | **유지** — 합리화 아님. gapup_20 이산 count의 decile 붕괴(n=206 vs 11128)는 *실측된 데이터 구조 문제*이고, per-month Spearman은 ties를 올바르게 처리. 단 quintile L/S(t=-1.02 비유의)로 IC 유의성이 tail 의존임을 *추가 입증*하여 IC를 과신하지 않음(오히려 IC를 깎는 방향). |
| "INFORMATIONAL ONLY" (quintile L/S) | **유지** — KR no-short이므로 L/S spread는 실제로 배포 불가. "informational"은 정직 라벨이지 회피 아님. |
| "DSR HARD 부적용" | **PARTIAL 수정** — 규정(§3 chain)상 HARD 부적용은 맞으나, *진단치 산출* 의무는 이행했어야 함(C3 ACCEPT). 합리화 소지 인정 → DSR 진단치 산출로 보강. |
| "admission-binding 아님" | **유지** — canonical_screen metric_type의 정확한 규정 정의(measurement-graduation §1). forge가 authoritative라는 사실 진술이지 회피 아님. |
| "chain ... DSR HARD 부적용" | C3와 동일 (PARTIAL). |
| "cor<0.95 통과하나" | **유지하되 강조 전환** — cor<0.95 통과는 certifier 형식 충족 사실이나, 동시에 incremental IC 58~67% spanning을 *전면 보고*하여 "통과하나 실질 spanned"를 명시함. 회피가 아니라 형식-실질 괴리를 드러냄. |

**합리화 grep 재검사**: 본 challenge_note + final package에서 "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" 사용 0건(자동 grep 통과 목표). "moot"는 정량 근거(8/8 PORT_t 음수, downstream 미진행) 동반 사용으로 합리화 아님.

---

## Q-Lead Escalation Trigger 점검
- HIGH severity concerns = 4 (C1/C2/C3/C4) < 5 → escalate 불요
- AX axiom hard FAIL: ax_007=FAIL(single-sleeve long-only top-N 메커니즘, AX-007 정합 — 예외 4종 미충족) = 1건 < 3 → escalate 불요
- PIT C1 위반: Codex가 C1=FAIL(sign 선택)로 표기했으나, 이는 lockbox/lookahead가 아니라 **sign-selection** 이슈 + verdict가 sign-invariant(8/8 FAIL)로 자본 영향 없음 → 즉시 escalate 트리거(C1 lockbox/lookahead) 해당 안 됨. 단 PIT-C13 위반은 challenge_flag로 명시 기록.
- Codex stance=REVISE(REJECT 아님) + veto_flag=False + no-graduation 합의 → 자동 Q-Lead escalate 불요. 정상 마감.

**결론**: 7 concerns 모두 처리(ACCEPT 3 / PARTIAL 3 / PARTIAL+REBUTTAL 1). verdict **FAIL 유지** — Codex no-graduation 동의로 핵심 충돌 없음. C2/C13 sign-flip은 verdict sign-invariant로 moot하되 challenge_flag 명시 + score 라벨 정정. discovery FAIL → downstream 미진행으로 risk/optimizer artifact moot. L-code VALIDATED_HARD_FAIL 적립.
