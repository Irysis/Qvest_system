# Self-Adversarial Challenge — WT-D20260705_002 (Alpha Research)

**Agent**: QEPM Alpha Research (Opus 4.8 native adversarial reasoning, v8.2 — no external Codex).
**Verdict finalized**: CLEAN_NEGATIVE (0 capital-grade candidates; 0 JUDGE-eligible). No PIT violation.
**Date**: 2026-07-05. Measurement window Date ≤ 2026-06-30 (per mandate).

---

## A. hypothesis_index 조회 기록 (착수 전 의무)

| keyword | hit/miss | 핵심 히트 | 차별점 (INV-7) |
|---|---|---|---|
| earnings | HIT (30+) | DIST-QPM-002, STR_AS_PG2W2_earnings3m_refine, C21_FLOWCONF | earnings-revision @3M **이미 full-pipeline FAIL** (WT-D20260702_001, decay-pattern, recent PORT_t −0.32) → **회피** |
| flow | HIT (30+) | DIST-AR-003, C21/C22/C25 (FAIL/CLEAN_NEGATIVE) | raw flow composite/interaction/run-length **전부 negative** (INTERACTION_NOT_ADDITIVE/sector-driven) → **회피** |
| reversal | HIT | DIST-QPM-001(quarantined), DIST-AR-001 | behavioral reversal distilled negative → **회피** |
| accrual | HIT | DIST-QPM-006(L-135 sector-neutral accrual F), DIST-QPM-002 | **sector-neutral single accrual만 tested**. 차별점: multi-factor accrual-**quality/persistence/volatility** composite (AC18/22/23) = 미측정 축 → 시도 |
| crowding | HIT (3) | Anti-Crowding Grade B (**port_t NA**), CR07 alpha_search | crowding family **full-pipeline PORT_t 미측정** (Grade는 sharpe proxy) → 시도 |
| growth | HIT | DIST-QPM-003, NOA_Growth, Asset_Growth | quality_profitability escape 소진 → 회피 |
| horizon | MISS | — | (earnings-revision horizon은 earnings 히트로 커버) |

**결론**: 두 축(accrual-quality composite / crowding family)만이 genuine INV-7 차별점 보유 → 이 두 축을 실측 대상으로 확정.

---

## B. 실측 요약 (canonical_screen_bt, contract-grade, NW lag-3)

18 candidate × top25 EW long-only · 15bps delta · 2e8 liq · K200∪KQ150 · 205 months (2009-06~2026-04, Date≤2026-06-30).

- **전 candidate PORT_t < 2.95 (HARD FAIL)**. best full-period = CR09_MoneyFlow +0.461 (IR 0.125).
- Recent (2018+/2021+) 재측정: CR09 positive는 **pre-2015 아티팩트**(recent 전부 음). 유일 all-window 양수 = **CR11_IdioRet** (port_t 0.52~0.79, IR 0.14~0.25).
- **CR11 orthogonality (theme 핵심)**: active-cor vs book(blend_65_35_net) = **0.311 full / 0.55 recent** → <0.30 gate FAIL (recent 결정적). gross(net-level) 0.747 (시장성분 공유, §6 정합).
- **Sanity**: Q01_GPA(quality) 동일 harness = port_t −1.211 → harness 정상(AX-004/DIST-QPM-003 재현), 음수는 KR single-factor long-only 구조.
- **Decile mechanism**: CR11 rank_ic 0.0245·harvey_t 2.148인데 **decile 비단조·flat**(D10 active −0.0014 ≈ D1) → IC≠PORT_t, AX-007 translation break (신호가 top-decile에 미집중). CR09는 monotone이나 D10 소액+TO 7.0/yr로 net wash-out.

---

## C. 자기 비평 (devil's advocate) — ≥3건

### C1. "205개월 full-period가 죽인 게 아니라, recent-only면 살 수도?" (과대평가 방어)
- **자기비평**: full-period가 recent decay를 희석해 거짓-음수를 만들었을 가능성.
- **반증 실측**: recent window(2015/2018/2021) 별도 측정 → CR11 recent port_t 0.52~0.79 (여전히 ≪2.95), CR09 recent 전부 음(−1.1~−1.6). **recent가 오히려 더 나쁘거나 동급**. → **REBUTTAL 불성립, 음수 강화**. self-rationalization 회피(근거: `.cache/wt705_recent_results.csv`).

### C2. "rank-IC를 realized로 오독?" (Cycle 2 교훈)
- **자기비평**: CR11 harvey_t 2.148이 그럴듯 → rank-IC t를 PORT_t로 오독하면 "borderline pass"로 위장 가능.
- **반증**: harvey_t(rank-IC) 2.148 ≠ portfolio-alpha t 0.52~0.79. **명시 구분 보고**(alpha_package diagnostics에 둘 다 기록). decile flat이 IC-PORT_t 괴리 원인. Judge authoritative = PORT_t. → **ACCEPT (구분 준수)**.

### C3. "active-cor 0.311이 <0.30에 근접 — '거의 직교'로 봐줄 수 있나?" (합리화 탐지)
- **자기비평**: "0.311은 0.30에 거의 근접 → 실무적으로 직교"라고 쓰고 싶은 유혹.
- **auto RE-VIEW** (금지어 "거의/근접/실무적" 감지): **기각**. (a) recent 0.55는 근접조차 아님. (b) 애초에 PORT_t 0.52 < 2.95라 orthogonality 논쟁 무의미 — measurement-graduation §6은 '직교 ∧ PORT_t≥2.95 **동시**' 요구. 한쪽만 논해도 book 기여 불가. → **ACCEPT (음수, 합리화 폐기)**.

### C4. "top25 대신 top50/multi-sleeve였으면?" (envelope 우회 유혹)
- **자기비평**: box를 넓히면 CR11 mid-decile 신호를 담을 수 있음.
- **반증**: top50/공매도/50+분산은 **out-of-envelope**(종목수≤25는 문제의 고정 축, AX-000 따름정리·INV-7 제약 방화벽). → **REBUTTAL 불성립(제약 완화 금지)**. 단 **frontier로 정직 라우팅**: CR11의 diffuse mid-decile 신호 = DPL_FEATURE 후보(long-only 박스가 비매매하는 신호를 end-to-end weight 학습이 소비, DIST-AR-003 frontier 정합).

### C5. "look-ahead?" (PIT)
- **자기비평**: score_eom(T) → fwd_ym(T+1) 정렬이 same-month 누출?
- **반증**: sig factors known at eom(T), return realized in **T+1** (strict forward). load_month_factors = C13/C14/C15 PIT-safe(direction IC-inferred expanding window, min_months=36). liquidity adv20 = t-1 rolling. → **ACCEPT (PIT clean)**.

### C6. 소표본?
- 205 months full / 100 months recent — 소표본 아님. CR11 harvey_t는 204 months. → 비이슈.

---

## D. 분류 종합
- ACCEPT: C2, C3, C5 (구분준수·합리화폐기·PIT clean)
- REBUTTAL 불성립(음수 강화): C1, C4 (recent 더 나쁨·제약완화 금지)
- 비이슈: C6

**Q-Lead escalate trigger 점검**: HIGH severity concern ≥5? NO (전부 음수-강화 또는 준수). AX axiom hard FAIL ≥3? N/A(음수 보고). PIT C1 위반? NO. → **자동 escalate 없음**. 정직 CLEAN_NEGATIVE 보고.

## E. Frontier (미탐색 인접, AX-000 — dead-end 단정 금지)
1. **CR11_IdioRet → DPL_FEATURE**: diffuse mid-decile 신호를 direct portfolio learning 입력 피처로 (long-only 박스 비매매분 소비).
2. **CR09_MoneyFlow monotone but TO-killed**: turnover-aware / banded-rebalance 재구성 시 net 재검 (현재 TO 7.0/yr가 D10 edge 소각).
3. **accrual-quality × regime-conditional**: full-period flat이나 특정 국면(고변동)에서 accrual-quality가 crash-defense specialist 가능성 — FR-RCMA screen-route (본 WT 범위 밖, factor-rotation 모드).
4. **비-return 신규 데이터원** (DART insider 등, 현재 BLOCKED): factor DB 가용분 내 orthogonal PORT_t-통과 후보 부재 확정 → 새 원천 필요.
