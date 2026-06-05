# Challenge Note — WT-D20260529_005 Track SECTOR_REL (alpha-research)

**Codex stance**: REJECT (veto_flag=false — devil's advocate, no veto power).
**Decision protocol**: 8 concerns 자율 분류 (ACCEPT / PARTIAL / REBUTTAL). 합리화 자기검증 포함.
**Resolution artifacts**: `stage_artifacts/WT_WT_D20260529_005_SECTOR_REL/rebuttal_addenda.json` + clean `alpha_scores.parquet`.

---

## C2 (HIGH) — alpha_scores.parquet에 Ret_1m forward label 포함 → leakage hazard
**분류: ACCEPT.** 명백히 타당 (PIT-C2/C3 leakage path). 다운스트림이 alpha artifact에서 미래수익을 학습/랭킹할 수 있음.
**조치**: `alpha_scores.parquet` 재생성 — `Date,Ticker,Sector,score_sectorrel,score_marketwide`만, **Ret_1m 제거 확인**. forward return은 측정 스크립트 내부에만 존재(canonical_screen_bt 입력 `returns_dt`는 별도, artifact에 미저장).

## C3 (HIGH) — 2004-2023을 lockbox validation으로 라벨, 2024+ OOS 부재. E3 rank-IC negative
**분류: ACCEPT (가장 중요한 발견).** Codex 지적이 정확하고 material.
**조치 + 정직 보고**: post-cutoff OOS (2024-01 ~ 2026-04, 27m) 실측 →
- **portfolio-alpha t = -1.665, net_sr = -0.813 (REVERSAL)**. rank_ic_oos는 +0.0312로 양수 유지(횡단면 순위력 잔존)이나 **long-only top-25 실현 alpha는 OOS에서 음수로 역전**.
- 이는 in-sample E3(2020-2023) rank-IC -0.004 decay의 연장 — sector-relative V/Q/M 신호의 **최근 alpha decay 확정**.
- **결론(scoped)**: 이 구성은 2004-2023 in-sample에서 portfolio-alpha t 3.42로 강했으나 **2024+ OOS에서 무너짐**. lockbox-as-validation 주장 철회. 공간폐쇄/소거 verdict 아님 — 이 3-factor within-sector EW top-25 구성의 OOS 실측 결과.

## C1 (HIGH) — TOP_N=25 + TO 7.0/yr가 base mandate(20 names, TO<6) 위반
**분류: PARTIAL.** 본 WT mandate는 명시적으로 "25종 / TO≤11" (Q-Lead prompt + request.json universe max_names=null). 따라서 25/TO7.0은 **본 task 제약 내 위반 아님**. 단 Codex의 robustness 질문(20 names/엄격 TO에서 살아남는가)은 타당 → 실측:
- **top20: portfolio-alpha t = 3.200 (>2.95 hurdle 통과), net_sr=0.741, DSR(n=22)=0.906, TO=7.6**
- top15: portfolio-alpha t = 2.954 (≈hurdle), net_sr=0.702, TO=8.2
- **rebuttal 근거**: portfolio-alpha t는 20종에서도 hurdle 통과 (구성 자체는 names-robust). 단 **TO는 6-8/yr로 base 6.0 cap 초과** — implementation discipline 측면 borderline (task cap 11은 통과). in-sample 한정.

## C4 (HIGH) — single-sleeve long-only top-25, AX-007 예외 미충족
**분류: REBUTTAL (scoped).** 학술+L-code+정량 3축:
- 본 산출물은 **alpha-research (signal 생성)** 단계 — α̂ vector 제출이 본질. portfolio admission이 아님. AX-007은 single-sleeve top20 **portfolio**의 mechanism break를 다룸(L-160/165/166). alpha-stage에서 α̂를 측정·보고하는 것은 AX-007 적용 대상 아님.
- 정량: measurement-graduation §5 — 실패/약한 standalone alpha는 폐기 아닌 **DPL 입력 피처**. 본 sector-rel α̂는 DPL/multi-sleeve 연료로 제공 가능.
- **단, OOS reversal(C3)이 이 신호의 standalone 가치를 결정적으로 약화** — AX-007 예외 여부와 무관하게 standalone deployment 부적격.

## C5 (MEDIUM) — RF-A2 미해결: single-factor sector-rel baseline + monotonicity 부재
**분류: ACCEPT.** 타당. 실측 추가:
- single-factor sector-rel (top25, lockbox) portfolio-alpha t: V12_sr=2.117, Q01_sr=1.271, M01_sr=2.684. **COMPOSITE=3.424가 best single(M01 2.684) 대비 +27.6% 개선** → RF-A2 해소(composite 정당).
- monotonicity: spearman(decile, mean ret)=**0.636** (D1 0.62% → D10 1.32%, 중간 non-monotonic). **0.7 hurdle 미달 — 정직 보고**.

## C6 (MEDIUM) — Charter §8 closure 미완 (SECTOR_REL challenge_note/lineage 부재, risk/opt/weights/cov 부재)
**분류: PARTIAL.** 본 challenge_note_SECTOR_REL.md가 closure 1차 충족. risk/optimizer/weights/covariance 부재는 **정상** — 본 단계는 alpha-research 단독. Σ/weight는 명시적 역할 경계 외(agent_role_guard). artifact_lineage는 finalize 시 record_package_lineage 호출로 보강.

## C7 (MEDIUM) — references author-year only, KR applicability 동일 backtest로 추론
**분류: PARTIAL.** Asness-Porter-Stevens (2000, "Predicting Stock Returns Using Industry-Relative Firm Characteristics") + Cohen-Polk-Vuolteenaho (2003 JF, "The Value Spread") + Moskowitz-Grinblatt (1999 JF, "Do Industries Explain Momentum?") + Novy-Marx (2013 JFE, "The Other Side of Value: GPA"). KR applicability는 본 backtest로 검증 — 동일 harness 내 in-sample이며 **OOS는 reversal**, 정직 보고. 별도 KR cross-validation은 미수행(scoped).

## C8 (MEDIUM) — crowding: active cor 0.528 > 0.5 권고, port cor 0.852
**분류: REBUTTAL (scoped).** L-code+정량:
- measurement-graduation §6 확립 진실: KR long-only 수익률직교 구조적 불가. BAB(β-0.04)·VALUE(β-0.074) 시장중립인데 return_cor vs STR_1715 0.78/0.76. **active cor 0.528은 이 reference 대비 개선**(1st eigenmode 잔존은 long-only 본질).
- 단 0.528은 <0.5 권고 미달 → **완전 직교 아님 정직 인정**. port cor 0.852는 beta 0.965(시장 동행)에서 기인 — 구조적이나 saturation risk 잔존 인정.

---

## 합리화 자기검증 (rationalization auto-detect)
회피표현 grep: "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" — 본 note 내 **실질 사용 없음** (C8에서 "구조적"은 measurement-graduation §6 실증 인용, 합리화 아님). Codex의 META_ONLY 지적(draft의 grep self-check 언급)은 본 note에서 제거.

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? Codex HIGH=4 (C1-C4). escalate threshold 미달.
- AX hard FAIL ≥3? AX-007 1건 FAIL(rebuttal). 미달.
- PIT C1 lookahead? 없음 (C13/14/15 PASS, C2 leakage는 artifact 저장 문제로 fix 완료).
- **escalate 불요.** 단 C3 OOS reversal은 findings로 Q-Lead/도훈에 명시 보고 (verdict는 그들 권한).

## 최종 stance 반영
Codex REJECT를 **부분 수용**: C2 fix(clean parquet), C5 baseline+monotonicity 추가, C3 OOS 실측이 가장 중요 — **이 구성의 standalone alpha는 in-sample 강함(PORT_t 3.42, DSR 0.95) but OOS reversal(PORT_t -1.67)**. findings-only 보고, 공간폐쇄 금지.
