# Weekly Digest — 2026-W27 (첫 주간 다이제스트)

**실행일**: 2026-07-05 · **생성**: /cleaner 세션 (Q-Lead Opus 4.8)
**소스**: `.cache/cleaner_pending.json` (week_of 2026-W27, sweep_deleted_n=3, stage_artifacts_new=391) + git log 7d(42 커밋 window) + 각 run 산출물 역추적
**규율**: 실측만(measurement-graduation §1). 수치는 기록 파일 인용 + metric_type 라벨. 추정·재구성 없음.

---

## 0. 한 줄 요약

이번 주는 **infra/거버넌스 중심**(axiom 엔진 v2 완결 + 아키텍처 강화 + negative 공리 Distilled 강등). **실측 백테 실험은 QEPM E2E 1건이 사실상 전부** — 다른 threads는 코드/문서/게이트 작업이라 성과수치 산출 없음.

---

## 1. 실측 실험 (성과수치 有)

### 1-1. QEPM Axiom-Engine E2E — DIST-QPM-003 frontier(b) 국면조건부 quality **FALSIFIED**
- **가설**: value/quality spread reversion 국면조건부 activation (CRISIS/CAUTION서 quality tilt) → 성장주 우위 밖에서 profitability 프리미엄 포착.
- **결론**: **FAIL (정직, AX-000)**. 전 변형 PORT_t ∈ [-2.65, -2.59] < 2.95 게이트 (vs cap-w KOSPI200).
- **수치** (`metric_type=canonical_screen`, 258m 2005-01~2026-06, top-25 long-only):
  - V0(naive quality) PORT_t **-2.6716** / V1(regime-cond, frontier b) **-2.6121** / V1b -2.590 / V2 -2.631
  - rank-IC qual +0.0362 (ICIR 1.355) 양이나 realized long-only active로 **미이전** (§6 재확인)
  - 국면별 realized active ann: CRISIS **-78.2%** / NEUTRAL -26.5% / RISK_ON -8.8% / **CAUTION +7.1%(n=13, sub-signal)**
  - era: pre2017 -8.2% → post2017 **-21.4%** (2017+ 성장주 우위 국면단절 재현)
- **출처**: `qepm/mailbox/worktask/WT-AXENGINE-E2E_20260705/alpha_validation.json`
- **L-code**: `L-QPM-20260705_102041` (2026-07-05 emit, DIST-QPM-003 실패-ledger) — frontier(b) 재시도 금지 표식 카드 반영.
- **후속(미탐색)**: frontier(a) multi-axis quality를 Q07 multi-sleeve 성분(← 본 세션 워크플로우 wf_585c31dc 착수) · frontier(c) DART 현금흐름 비-return(elestock BLOCKED).
- **E2E 메타 성과**: `knowledge_shaped_research=TRUE` — 주입된 Distilled 탐색지도가 나이브 실패경로(quality 단독) 재실행을 막고 차별화 frontier로 재지향. Self-Adversarial C2 자가포착(rank-IC를 realized로 오독).

### 1-2. §6 직교성 수치 벤치교정 재산출 (확정진실 정정, 성과-인접)
- **결론**: 방향·결론 불변, 수치만 교정. long-only 패밀리 β 하향, active 상관 소폭 상향.
- **수치** (`metric_type=gross/active`, `variant_returns_xts.rds` 267m, 교정벤치 IKS200):
  - 시장β: core **0.921** / def 0.906 / blend 0.917 (구 0.99x는 버그벤치 IKS001 산물)
  - gross 상관 0.789(불변) · **active(−BM) 상관 0.452→0.526** (직교 여지 소폭 축소, 결론 불변)
- **출처**: `04_Research/01_reports/knowledge_provenance_audit_20260704.md` S1 · measurement-graduation §6 changelog(2026-07-05)
- 부수: `.claude/rules/axioms.md` AX-005 L-165/166 오귀속(실제 AX-007 family) 정정.

---

## 2. Infra/거버넌스 (성과수치 無 — 코드·문서·게이트)

- **Axiom 엔진 v2 완결**: 3층 Ledger/Distilled/Law. **Law 4건**(000/001/002/008)만 잔존, negative 4건(003/004/005/007) **Distilled 강등**(INV-7, 도훈 지시). L-code 원장 599→220 증류. Distilled **10건 활성화**(도훈 승인, JG-001 제외). commit 계열 `532a4ebf`→`83201ccf`.
- **INV-7 부활 기구**: 산문 live_trigger → 기계 revival_spec 자동번역 브리지 DURABLE(`da055c90`). expiry+spread+regime 부활신호 실가동.
- **아키텍처 강화**: hook_e2e_battery **11/11 PASS**(수리 전 7/11) · factor_db 재빌드(M08 등 43팩터 복구)+값-무결성 가드 3축 · 게이트급 4훅 fail-closed(26/26) · auto-commit 부활.
- **증거계보 감사 33건**: 공리 8·확정진실 7 전건 SOUND/REVERIFIED. TAINTED 6건 DIST 격리. DEF-08 연율화 버그 수리.
- **대증류+Cleaner 체계**: 02_experiments 121.6MB + krx_options 198MB 삭제. Cleaner 스킬+스케줄러(토 09:00) 가동 — **본 다이제스트가 첫 산출**.

---

## 3. Axiom 후보 현황 (주간 사이클, 의무 절)

- **pending 18건 전량** — near-miss **0건**(1축만 미달인 후보 없음 → 이번 주 DIST 초안 승격 제안 없음).
- **실패 축 히스토그램**: falsification **17/18** (지배 병목) · external 16 · independence 14 · mechanism 10 · rigor 2.
- **진단**: 승격 병목 = **입력 결측**(falsification_attempts 생산자 미적립) — 축 설계·문턱 문제 아님(07-04 실측 확정). emit v2가 falsification을 채우기 시작하면 near-miss 발생 예상. 본 주 B1 emit(L-QPM-...102041)이 falsification_attempts 3건 포함 → 생산자 적립 첫 사례.
- **출처**: `.cache/cleaner_pending.json::axiom_candidates` (promote.R review_log 실기록 집계, dry-run).

---

## 4. 잔재 삭제 (§4, 참조0 검증)

기계 스윕이 hygiene 3건 선삭제(§0). 세션 판단 삭제는 **보수적으로 보류** — stage_artifacts 391 신규는 §6 불변 런 기록(삭제 금지), paper_recharge 스크래치는 morning 파이프라인 재소비 가능성으로 defer. distill_manifest 별도 삭제 0건.

---

## 5. 다음 주 시드

- frontier(a) quality Q07 multi-sleeve 실측 결과(wf_585c31dc) → DIST-QPM-003 ledger 갱신.
- falsification_attempts 생산자 적립 지속 → axiom 승격 near-miss 모니터.
- RAWDATA.parquet BM_Ret 신월 인제스트 재오염(2026-07-01 5.39) → 인제스트 파이프라인 근본 수리 필요(값-가드는 탐지만).
