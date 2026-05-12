# WT-D20260508_008 — Alpha Challenge Note

**Generated**: 2026-05-08T15:30:00+0900
**Agent**: alpha-research (Q-Lead spawn)
**Codex Critic**: stance=REJECT veto_flag=false (gpt-5.5 xhigh)
**Final stance after rebuttal**: **DROP / NO-DEPLOY** (empirical fail, honest archive)

## Codex 7 Critical Concerns 처리

### C1 [HIGH | RF-A7 | AX-002] alpha_scores.parquet single-snapshot schema → ACCEPT (FIXED)

**Codex 지적**: alpha_scores.parquet has 348 rows and columns Ticker/Sector/mom_12_1/alpha_z/alpha_hat/confidence with no Date column; single snapshot.

**처리**: ACCEPT — 정확한 발견. v6.1 R7 contract violation.

**Fix**: `stage_artifacts/WT_D20260508_008/build_multi_sigdate_alpha.R` 작성 및 실행
- 결과 alpha_scores.parquet: **29,183 rows × 5 cols (Date | Ticker | Sector | mom_12_1 | alpha_z | alpha_hat)**
- 84 sig_dates (2019-06-28 ~ 2026-05-08), 604 tickers, RF-A7 PASS (60+ dates 충족)
- 2019년부터 84개월 (Codex 60+ dates rebuttal 1 충족)

### C2 [HIGH | RF-A6 | AX-002] Core diagnostics fail → ACCEPT (이미 명시)

**Codex 지적**: rank_ic=0.0243, ICIR=0.0741, Harvey t=1.6595, stock NW-t=1.8283, Q5 MDD=-65.82%.

**처리**: ACCEPT — alpha_package_draft.json `graduation_eval.overall_PASS = false` + `fail_count = 4` 명시. 이는 honest empirical fail로 archive 됨. Discovery → Deployment 전환 자격 없음.

**경제적 근거**: 한국 KOSPI200∪KOSDAQ150 시총 top1 sector (반도체) 48.13%, top3 60.84%. Cross-section breadth 부족. 과거 STR_055/STR_191/STR_089 모두 동일 family `insufficient` tier 실증 재현 (4번째 시도).

### C3 [HIGH | RF-A3 | PIT-C1] Recent 3Y ICIR 4.12× full → ACCEPT (정량 검증)

**Codex 지적**: Recent 3Y ICIR=0.3052 vs full ICIR=0.0741; ratio=4.12 > 1.5.

**처리**: ACCEPT — agent 자체 verify:
```
Recent 3Y (2023-05~2026-05): IC mean=0.0998, ICIR=0.3052, N=36
Full sample (1990-04~2026-05): IC mean=0.0243, ICIR=0.0741, N=422
Recent/Full ratio = 4.12 ✅ (RF-A3 trigger threshold 1.5)
Recent 5Y ratio = 2.64 (also above 1.5)
```

**경제적 의미**: alpha는 최근 3년 IT/반도체 cycle 집중 (Samsung+SKH 메가캡 momentum). 장기적 cross-section sector momentum mechanism이 약하고 최근 cycle artifact일 가능성 HIGH. Bailey-LdP DSR (n_trials=4, 0.6153) PASS이지만 recent-period 편향 의심.

### C4 [HIGH | PIT C13/C14/C15] manual z-score / no Usable_Date / direct parquet → PARTIAL ACCEPT

**Codex 지적**: 
- C13: manual z-score → Z_Score_Aligned 미사용
- C14: no Usable_Date check
- C15: load_month_factors() 미경유, .cache/rawdata.parquet direct read

**처리**: PARTIAL ACCEPT — agent 명시:

본 신호 `M_SECTOR_12_1_VW`는 **Factor DB 외 신규 설계 sector-level signal** (alpha_research_init.md scope 2-C "신규 팩터 직접 설계"). Factor DB 288개에는 sector portfolio momentum이 없음 (M07_IndMom는 stock-level industry momentum이며, 본 신호는 sector portfolio의 cross-section ranking).

- **C13 status**: 본 신호는 factor_db Z_Score_Aligned 대상이 아님 (factor_db에 없는 신규 sector-level signal). 그러나 cross-section z-score (alpha_z) 계산 시 NEGATE/FLIP 없이 `(x - mu) / sd` 표준 형식 → **C13 spirit compliant**. C13 본문 적용 대상 외.
- **C14 status**: month-end signal → t+1 application. PIT 위반 없음 (signal 산출 시점 t에 t-12 ~ t-2 sector returns만 사용. Usable_Date 의무는 factor_db usable_date 컬럼 적용 대상이며 본 sector-level signal은 month-end alignment로 strict equivalence 달성).
- **C15 status**: factor_db 적용 대상 외 (sector-level signal). **Infeasibility report**: Factor DB 288개 어디에도 sector portfolio value-weighted 12-1 momentum 신호 없음. RAWDATA 직접 read는 **명시적 신규 팩터 설계 경로 (alpha_research_init scope 2-C 허용)**. method_shopping_log에 `db_source = "new_designed"` 기록 (alpha_package에 추가 명시).

**Action**: alpha_package.json factor_specs[0]에 다음 추가:
```json
"db_source": "new_designed_sector_portfolio_signal",
"c15_exception_rationale": "Factor DB 288개 산출 단위 = stock-level. Sector portfolio cross-section signal은 factor_db scope 외이므로 RAWDATA 직접 read는 명시적 허용 경로 (alpha_research_init 2-C). load_month_factors() 미적용은 본 신호 정의상 정합."
```

### C5 [MEDIUM | RF-A4] post_neutralization_ic = raw → ACCEPT + 정량 보강

**Codex 지적**: post_neutralization_ic copied from raw rank_ic; no sector-neutral ICIR drop test.

**처리**: ACCEPT + 추가 측정 (`extended_diagnostics.json`):

```
Recent 84-month panel:
- raw IC = 0.0263 / ICIR 0.1556
- sector-neutral IC = NaN (degenerate by definition)
- sector+size-neutral IC = 0.0222 / ICIR 0.3333
- RF-A4 threshold (0.3 * raw) = 0.0079
- sector+size-neutral FAIL = FALSE (passes RF-A4 mathematically)
```

**그러나 sector-neutral IC = NaN의 의미가 결정적**:
- 본 신호의 정의는 "sector portfolio momentum을 모든 constituent stocks에 동일하게 매핑"
- 따라서 sector demean 시 모든 alpha_z = 0 → IC undefined
- 이는 **본 신호의 100% alpha가 sector-bet 컴포넌트에 있다는 직접적 정량 증거**
- WT_005 retention 0.42 (raw 0.0193 → sector-neutral 0.008)와 다른 관점: WT_005는 stock-level signal에 sector noise 섞임 / 본 WT는 sector-level signal 자체

**Implication**: 본 신호를 stock-level alpha로 사용 불가 (sector-only allocation signal). C6 (AX-007) 직접 연결.

### C6 [HIGH | AX-007 | L-484] sector-score-to-stock max-20 mapping → ACCEPT (DEPLOYMENT BLOCKER)

**Codex 지적**: alpha maps one sector score to all constituent stocks; under max-20 long-only deployment AX-007 mechanism break.

**처리**: ACCEPT — 가장 결정적 ground.

**AX-007 인용**: "roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing)."

**본 WT 적용**:
- structure: **single_sleeve_long_only_top20** (Production Constraints)
- signal: sector-level (모든 constituent에 동일 alpha)
- translation: sector top decile → constituent stocks → top20 → 결국 top sector(s) 내 시총상위 종목 집중
- 결과: 반도체 sector 압도적 우위 → 사실상 Samsung + SK Hynix + 기타 반도체 5-10종목 portfolio
- AX-007 4 exception 모두 미충족:
  - multi-sleeve? NO (Hybrid 70/15/15는 별도 결정 영역, 본 WT는 single signal)
  - long-short? NO (long-only mandate)
  - 50+ 분산? NO (max 20 hard)
  - ML sizing? NO (rule-based ranking)

**결론**: 본 신호는 stock-level alpha로 변환 시 AX-007 mechanism break 직접 트리거. Deployment 자격 자체가 없음.

**경로 B 검토 (혹시 가능한 변형)**:
- (a) sector-level allocation signal → portfolio-level overlay (Hybrid component) — 가능하지만 본 WT scope 외
- (b) sector × stock-level signal composite → mechanism preserve — 본 WT scope 외 (별도 hypothesis)
- (c) 본 WT는 archive — empirical fail confirmed

### C7 [HIGH | AX-008 | AX-002] missing weights/cov/challenge_note → REBUTTAL

**Codex 지적**: weights.csv, covariance.parquet, challenge_note, other agent packages missing.

**처리**: REBUTTAL — 역할 경계 위반.

**근거 1 (학술/규정)**: Common Charter v1.7 §8 "No Silent Override" + alpha_research_init.md `<strict_prohibitions>`:
> 1. 공분산행렬 추정 금지 — Risk Agent 영역
> 2. 포트폴리오 비중 제안 금지 — Optimizer Agent 영역
> 5. 앞/뒤 단계 agent 산출물 수정 금지

**근거 2 (L-code)**: L-269 v6.0 Codex Critic Round 우회 사례. alpha agent가 weights/cov 산출 시 PreToolUse Hook `agent_role_guard.sh` block + AX-002 위반 동급.

**근거 3 (정량/구조)**: WT-D20260508_008 cycle 현 단계 = alpha-research only. Risk-research / optimizer-research는 alpha 후속 spawn이며 본 WT가 graduation 미달이므로 **Q-Lead가 후속 agent spawn 자체를 stop**해야 함.

**Codex 응답**: weights.csv / covariance.parquet 제공 = alpha agent 영역 절대 위반. challenge_note.md는 본 문서 작성 중 (5단계 흐름 step 4). 다른 worktask `WT_WT-D20260508_008` 경로는 잘못된 명명 — 정합 path = `stage_artifacts/WT_D20260508_008/` (확인됨, 12 files).

## Self-Rationalization 자가검증 (Charter §8 No Silent Override)

본 challenge_note 작성 후 grep:
- "정직한 empirical fail" 표현 사용됨 (alpha_package_draft.json) → **유보적 합리화 가능성**
- 그러나 grep 검사: "미미", "관행적", "보수적이면 OK", "대부분 결과 동일", "실무적", "이정도면" → **0 hit**
- "honest empirical fail" 표현은 합리화가 아닌 **graduation_eval overall_PASS=FALSE + fail_count=4의 직접 라벨**. method_shopping_log에 4 candidates 모두 차이 없음 (모두 fail) 명시 → 합리화 아닌 정직한 보고

## HIGH severity ≥ 5 → Q-Lead Escalate Trigger

**HIGH count = 5** (C1, C2, C3, C4, C6) → Q-Lead 자동 escalate trigger (alpha-research SOP).

본 cycle은 **alpha-research finalize → Q-Lead가 후속 agent (risk/optimizer) spawn STOP** 결정 권고:
1. Discovery graduation 4/5 FAIL (cooperative behavior = stop pipeline)
2. AX-007 mechanism break 직접 trigger (sector-to-top20 deployment 본질 위반)
3. RF-A3 recent 3Y bias (4.12×) — 일반화 가능성 의심
4. AX-008 verification triangulation FAIL (Codex agree_with_claude=false on multiple fronts but agree on alpha empirical reject)

## 최종 자율 결정

**Stance**: **NO-DEPLOY / ARCHIVE_AS_LCODE**
- alpha_package.json 작성 (post-Codex final, with all rebuttal updates)
- multi-sig-date alpha_scores.parquet 보관 (RF-A7 fix 충족)
- L-code 적립 권고: "KR sector momentum KSI Lv1 27 sectors single-factor cross-section, 4번째 동일 family 시도 재실증 fail. AX-007 mechanism break trigger. Multi-axis composite (sector × value, sector × regime, sector × flow) 또는 portfolio-level overlay 변형 제외하고 archive."
- 후속 agent (risk/optimizer) spawn은 Q-Lead 결정 (graduation 미달 시 stop이 SOP)

## 학술 + L-code + 정량 3축 인용 요약

**학술**:
- Asness, Moskowitz, Pedersen (2013) JF 68(3) "Value and Momentum Everywhere" — 글로벌 sector momentum t-stat ~3-4. 한국 미달.
- Moskowitz, Grinblatt (1999) JF 54(4) "Do Industries Explain Momentum?" — US 1963-1995 industry momentum t > 4. 한국 1990-2026 t = 1.66.
- Hong, Torous, Valkanov (2007) JFE 83(2) — industry-leading effect.

**L-code**:
- L-135 (BCSNA Sector Neutral Accrual 한국시장 희석 실패): 섹터-축 처리가 alpha 희석 사례
- L-160/L-165/L-166 (AX-005 family Defense long-only structural failure): 섹터 cleanly 처리해도 portfolio-level survival 보장 안 됨
- L-484 (수익률 블렌드 앙상블 종목수 위반): top20 mechanism break 사례

**정량 (본 WT 실증)**:
- Sector rank IC 0.0243 (vs hurdle 0.04, ratio 0.61, FAIL)
- ICIR 0.0741 (vs hurdle 0.20, ratio 0.37, FAIL)
- Harvey-NW t = 1.66 (vs 3.0, ratio 0.55, FAIL)
- Recent 3Y ICIR 0.3052 / Full ICIR 0.0741 = ratio 4.12 (RF-A3 HIGH)
- Sector-neutral IC = NaN (100% sector-bet 컴포넌트, AX-007 mechanism break 직접 증거)
- Q5 portfolio MDD -65.82% (vs <25% deployment, ratio 2.63 위반)

## Codex Round 5단계 status

1. Draft 작성 ✅ (`alpha_package_draft.json` 22.6 KB)
2. Codex auto-spawn ✅ (~3분, gpt-5.5 xhigh, REJECT stance)
3. Codex response 검토 ✅ (7 critical concerns, 5 HIGH)
4. challenge_note.md ✅ (본 문서, 학술+L-code+정량 3축, 합리화 0 hit)
5. Final alpha_package.json 작성 → 다음 단계
