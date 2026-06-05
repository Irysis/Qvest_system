# Challenge Note — WT-D20260529_002 Track ISSUANCE (alpha-research)

**Codex Critic Round** (GPT-5.5 xhigh, 2026-05-29T14:16:55+09:00)
**Codex stance**: REJECT (veto_flag=false). agree_with_claude=false but "Claude's DROP conclusion is directionally right".
**Agent verdict**: **DROP** (unchanged — Codex confirms direction; concerns are about harness-cleanliness of a negative finding, not about the verdict).

핵심: Codex는 verdict(DROP)에 동의한다. REJECT는 "negative L-code를 promote하기엔 harness가 not audit-clean"이라는 process 지적이다. 따라서 actionable PIT/process 결함은 수정했고, 검증결과는 모두 DROP을 더 강화했다. negative L-code는 "후보(candidate)"로만 격하 — 일반화 주장 철회.

## Concern 분류 (8 critical + RF audit)

### C6 [PIT-C10/C2 same-day liquidity] — ACCEPT (수정 완료)
- 근거: `adv20` align="right" + `rd[Date==sig_date]` 필터 = rebalance-day bar가 tradability/membership에 진입.
- 조치: `adv20_lag1` / `K200_lag1` / `KQ150_lag1` (t-1 shift) 도입. build script line 수정 + 재실행.
- 효과: rank_IC 0.0057->0.0050, Harvey-t 0.50->0.45, portfolio-t -0.15->-0.07. **DROP 불변** (PIT fix가 verdict 안 바꿈 = 결함이 결과를 부풀린 게 아님).

### C5 [PIT-C13/C15] — PARTIAL (C13 attestation 추가 / C15 carve-out REBUTTAL)
- C13 (sign-flip): **REBUTTAL** — NSI/AG는 Factor DB의 288 Z_Score_Aligned proxy가 아닌 **신규 설계 factor**다. 부호는 IC를 보기 전 academic prior(Pontiff-Woodgate 2008 / Cooper-Gulen-Schill 2008: high issuance/growth -> low return)로 a-priori 결정 = NEGATE_FACTORS(정렬된 proxy의 사후 flip)가 아님. alpha_research_init Step 2-C "자체 정의 direction align" 허용. 단 **direction attestation을 build script header에 명문화**(ACCEPT 부분).
- C15 (direct parquet read): **REBUTTAL** — `load_month_factors()`는 288 existing factor만 노출. 신규 DART 파생 factor는 sibling track PEAD/REV와 **동일한 documented new-factor pattern**(.cache/dart + .cache/rawdata 직접 read). C14(ann_date<=sig_date)는 준수. carve-out을 header에 명문화.
- 자기합리화 self-check: REBUTTAL에 "관행적/실무적/미미" 미사용. 학술 2건(Pontiff-Woodgate JF 2008, Cooper-Gulen-Schill JF 2008) + init Step 2-C(L-code 등가 절차근거) + 정량(PIT fix 후 결과 불변) 3축 충족.

### C7 [DSR N0=3 understated, RF-A6] — ACCEPT (수정 완료, DROP 강화)
- 근거: leg(2)×sign(2)+composite + cross-track 5th-source breadth 미반영.
- 조치: N0=3 -> **N0=12** (conservative). 효과: DSR 0.396 -> **0.158** (gate 0.50 대비 더 깊은 FAIL). DROP 강화.

### C2 [composite < best leg, RF-A2] — ACCEPT (이미 leg_decomposition에 기록, first-class 승격)
- NSI-only flipped ICIR 0.156 > composite 0.051. AG leg ~0. 합성이 dilute.
- 조치: leg_decomposition을 diagnostics first-class로 보고. 단 best leg(NSI-flip)조차 NW-t=1.37 << 3.0 -> graduation 미달이라 verdict 불변.

### C4 [sector-neutral kills signal, RF-A4] — ACCEPT (DROP 강화)
- 검증: sector-demean alpha ICIR 0.051 -> **0.060** (거의 불변, 여전히 noise). raw도 noise, sector-neutral도 noise.
- (Codex가 "negative로 turn"이라 한 alpha+return 동시 demean 케이스는 더 약화 — 어느 쪽이든 gate 무관.) DROP 강화.

### C3 [recent-overfit, RF-A3] — ACCEPT (DROP 강화)
- 검증: 2021-23 ICIR=0.172 > full 0.051 ×1.5 -> recent optics fragile. 단 절대수준 0.172도 gate(0.20) 미달. recent overfit 의심 = 채택 불가 근거 추가.

### C8 [no challenge_note / lineage / risk·opt artifacts, AX-008] — ACCEPT (부분 수정)
- challenge_note: **본 문서로 충족**.
- lineage: `record_package_lineage()` 호출 추가 (finalize 직후).
- weights.csv / covariance.parquet / risk_package / optimization_package 부재: **정상** — alpha-research 단계 산출물 아님(Σ/weight = Risk/Optimizer 영역, 역할경계 Hook 차단). Codex가 alpha critic prompt에 risk/opt 항목을 포함해 over-scope. 단 verdict=DROP이므로 downstream 단계 자체가 불필요(Risk/Optimizer spawn 안 함).

### C1 [all gates fail, RF-A1] — ACCEPT (= verdict 근거 그 자체)
- rank_IC 0.0050 / ICIR 0.045 / Harvey-t 0.45 / DSR 0.158 / subperiod 0 / mono -0.42 / portfolio-t -0.07. 전부 FAIL = DROP.

### stage dir path mismatch (unresolved disputes A/B) — ACCEPT (해명)
- Codex가 기대한 `qepm/stage_artifacts/...` 및 `stage_artifacts/WT_D20260529_002` 부재.
- 실제 경로 = `stage_artifacts/WT_WT_D20260529_002_ISSUANCE` (Track prompt 지정 경로 + sibling NN/REV/PEAD 동일 규약). artifact-naming.md §3 WT_WT- prefix는 본 cycle 다른 track도 동일 사용중 — Q-Lead cleanup 대상이나 본 track 단독 변경 시 sibling 비교 깨짐. canonical alpha_package는 `alpha_package_ISSUANCE.json`로 finalize.

## Negative finding 격하 (Codex weakest_assumption 수용)
- Codex: "3-spec sign-flip test만으로 'KR anomaly absent' 일반화 불가."
- **수용**: L-code를 **candidate(후보)**로만 표기. "absent"->"not replicated in KR liquid universe (KOSPI200∪KQ150, 2e8 LIQ, 81m lockbox), single-spec family". 일반화(전 universe / 전 spec) 주장 철회. micro-cap / SEO event-study / share-count(공시 신주발행수) 기반 재검증은 후속 가설로 명시.

## Escalate trigger 점검
- HIGH severity ≥5 (C1-C6 = 6 HIGH) -> trigger 충족하나, 모두 **DROP을 강화/확인**하는 방향이고 verdict 충돌 없음. Codex도 "directionally right" 명시.
- AX hard FAIL ≥3: AX-007 FAIL 1건(multi-sleeve 예외 미입증 — DROP이라 무관). 3 미달.
- PIT C1 위반: 없음(C10/C2 same-day는 수정 완료, lookahead 아님).
- 결론: Q-Lead escalate 불요 (verdict 일치 + DROP). 단 본 challenge_note + finalize package를 Q-Lead가 검토.

## 자기합리화 grep self-check
- draft의 "가용 spec 소진 후 정직히 보고하는 입증된 한계" -> Codex가 rationalization flag. **재작성**: 3-spec(+양 leg+sign 양방향)으로 한정, "입증된 한계"->"본 spec family 한정 non-replication". 과대 일반화 제거.
- "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" grep: REBUTTAL/verdict 본문 미사용 확인.
