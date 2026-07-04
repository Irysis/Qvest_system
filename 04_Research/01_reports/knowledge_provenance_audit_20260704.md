# Qvest 지식 증거계보 감사 — 판정 및 적용 (2026-07-04)

**도훈 mandate**: "과거 아키텍처·설계미스로 인한 오류 적립 가능성 배제"
**감사 질문**: 주입·강제되는 지식 3층(active 공리 8건 · strategic_truths 확정진실 7건 · Distilled 17건)의 **증거가 결함 있는 측정기기로 측정된 것인가** — 지식 내용의 재해석이 아니라 *증거의 측정 신뢰성* 감사.
**audit_id**: `knowledge_provenance_audit_20260704`
**판정 원칙**: 증거 기반만. 추정 금지, 판정 불능은 UNKNOWN. 판정문은 감사 원장 원문 그대로 각 JSON `evidence_audit_20260704` 필드에 기록(재해석 없음).

---

## 1. 측정기기 결함 레지스트리 (판정문 인용 10종)

pre-fix 창(각 결함 수리 이전에 측정된 증거)이 감사 대상. 요약은 판정문·메모리 원사건 기준 — 상세는 각 참조 메모리.

| ID | 결함 | 수리 상태 | 편향 방향 (실측/판정) |
|---|---|---|---|
| DEF-01 | 벤치마크 IKS001 오염 — `.cache/benchmark.parquet`가 KOSPI200(IKS200) 아닌 KOSPI 전체(IKS001) 수록 (build_cache 지수컬럼 오선택) | **수리 2026-07-02** (`build_index_cache.py` 신설 + sanity 가드) | **스팟 S3 실측**: 구 벤치가 교정 벤치 대비 연 −1.32%p(2005+)·−2.13%p(2014+) 낮음(NW-t −1.60, cor 0.992) → pre-fix 벤치상대 성과(active/PORT_t)는 체계적 **관대(과대)**. negative 판정은 교정 시 강화만 됨 — 전복 불가. 위험군 = pre-fix **positive** 벤치상대 주장만 |
| DEF-02 | 비용모델 flat — per-rebalance 15bps 회전율 무관 과금 (TO>10x 과소, TO<3x 과대 — **양방향**) | **수리 2026-06-11** (v2.4 delta-based, 도훈 confirm) | 회전율 의존 양방향 — S3식 일괄 구제 불가. MDD·turnover 민감 결론은 개별 재검 필요 (→ DIST-QPM-002 RECHECK) |
| DEF-03 | 북↔벤치 realized_ym 1개월 오정렬 — lag0 merge 시 반대 표시 | **정렬규약 확립 2026-07-02** (anchor_date merge + shift(1) + β-스캔 offset 검증) | Book-상대 비교 클래스 오염 — 06-24 RAMP-Book 철회로 결론 전복 확정 사례 존재 |
| DEF-04 | faith 오버레이 동월누출 — Layer4 merge가 당월(concurrent) 신호 소비 = look-ahead | **적발·제거 2026-07-02** (lag1 스트레스 의무 + noLayer4 전환) | 오염 측정은 과대 성과. 수리-후 판정(T5)은 클린 |
| DEF-05 | batch_434 codegen 오염 — catalog ~124건 가설라벨≠실행신호(폴백 콤보) | **마킹 2026-06-13** + 07-04 distill서 authoritative 재실측 통합 | 수치는 실측이나 **라벨 오귀속** — 개별 가설 기각 증거 인용 금지 마킹 |
| DEF-06 | pre-winsorize 창 — 팩터 극단치 처리(winsorize, 2026-06-10) 도입 이전 측정 | 도입 완료 (이전 창만 해당) | 레거시 QEPM 창 구성요소 — 개별 수치 신뢰도 저하 |
| DEF-07 | pre-D000 창 — `hurdle_gate.R` D000 PIT 자동검증 도입 이전 레거시 측정 | 도입 완료 (이전 창만 해당) | 레거시 QEPM 창 구성요소 — PIT 자동검증 부재 창 |
| DEF-08 | 연율화 가드 부재 | **미수리** — 별도 트랙 (confirm 큐 ③) | — |
| DEF-09 | RAWDATA BM_Ret 컬럼 손상 (07-01자, 값 5.81) | **미수리** — 벤치는 `benchmark.parquet` 소비로 회피 중. 별도 트랙 | — |
| DEF-11 | score_eff 패널 1개월 지연 (RAMP) | **정정 2026-06-24** | Book-상대 비교 오염 (DEF-03과 결합 — 06-24 철회 클래스) |

(DEF-10은 판정문 미인용 결번. DEF-06/07 정의 요약은 감사 판정문 "레거시 창(flat 비용·pre-winsorize·D000)" 기준.)

---

## 2. 스팟 재측정 3건 (판정의 핵심 축)

| # | 대상 | 방법 | 결과 |
|---|---|---|---|
| **S1** | T4 §6 직교 수치 (β≈0.99 · gross 0.789 · active 0.452) — 유일하게 '수치 자체'가 IKS001-창인 확정진실 | 보존 시계열 `04_Research/pg2_forensics/intermediate/variant_returns_xts.rds`(267m×9 변형)를 구 벤치(`.cache/benchmark.parquet.bak_naver_patch_20260701_000306`=IKS001)와 교정 벤치(IKS200) 양측에 재산출. β-스캔 offset −3..+3 정렬 확정(off=0), NW-t 계약 동일 공식 | 구 벤치 재현: β .993/.981/.987 · gross .789 · active .452 — **기록 수치 정확 일치(구-벤치 산물 확정)**. 교정 IKS200: **β core 0.921/def 0.906/blend 0.917 · gross 0.789 불변 · active cor 0.526**. 방향(gross≫active·시장성분 지배·직교≠수익) 불변 = 결론 보존. §6 수치 3곳 갱신 필요 (직교 여지 소폭 축소: 0.526>0.452) |
| **S2** | 자사주 buyback canonical PORT_t (T7③·DIST-AR-003 대표) — pre-fix negative가 교정 벤치로 뒤집히는지 정밀 검정 | `stage_artifacts/WT_D20260621_010/buyback_drift_results.rds` 보존 period_returns 137m을 forward-정렬 검증(cor 0.9954) 후 교정 벤치 delta-치환 + direct swap 이중 산출, contract 동일 NW lag-3 | OLD 재현: PORT_t −1.179/IR −0.428 → NEW 교정: **PORT_t −1.338/IR −0.502** (direct swap −1.306). **negative 강화 — kill verdict 보존 실증**. 부수: 자사주 벤치 소스가 `.cache/benchmark.parquet` 소비였음을 계보로 확정(T7③ UNKNOWN 해소) |
| **S3** | DEF-01 기기 오차 자체의 방향·크기 — pre-fix 벤치상대 지식 전체의 전복 개연 판가름 | 구 벤치(bak 20260701_000306) vs 교정본 월수익 delta 직접 산출, 창 2005-01~2026-06(n=258)·2014-01~2026-06(n=150), NW lag-3 | 구 IKS001이 교정 IKS200 대비 **연 −1.32%p(2005+)·−2.13%p(2014+) 낮음** = pre-fix active/PORT_t 체계적 '관대' 오염. 함의: ① negative/sub-threshold 판정 전복 불가(본 지식체계 태반) ② 위험군은 pre-fix **positive** 벤치상대 주장뿐(FLOW 절대값 2.35 · T2 병기 PORT_t 2.54 · AS-003 positive-conditional 일부) — 해당 항목에만 재검/라벨 |

산출 스크립트: 세션 scratchpad `spot_remeasure.R` · `spot_s2_fix.R` (프로젝트 무변경, 읽기 전용 재측정).

---

## 3. 판정 — 층 1: Active 공리 8건

의미론 무변경 — 각 `qepm/memory/axioms/active/AX-*.json`에 `evidence_audit_20260704` 메타 필드만 추가. 철회 후보 0건.

| ID | 판정 | 핵심 근거 | 노출 결함 |
|---|---|---|---|
| AX-000 | **SOUND** | 규범 공리 — 시장 측정기기 비적용. 지지 실증 2건(earnings@3M, loser-penalty)은 전부 교정 기기 측정 | 없음 |
| AX-001 | **SOUND_REVERIFIED** | 07-03 방어팩터 DB 170종 전수(교정 기기)가 '전기간 PORT_t 기각 = AX-001 위반 프레이밍'을 실측 입증 — 강한 재확증. v2.1 amendment 원증거만 레거시 창(경미) — 레거시-창 라벨 부가 권고 | DEF-02/06/07 (v2.1 amendment 한정) |
| AX-002 | **SOUND_REVERIFIED** | proxy-vs-forge 비교는 기기 동일 델타라 유효 + 교정 시대 3중 재확증(census v3·faith 적발·oos 오산식 정정). 단 **FLOW 절대값 2.35는 pre-fix 창 — 인용 시 라벨** | DEF-01 (FLOW 절대값 한정) |
| AX-003 | **SOUND_REVERIFIED** | Grade F 근거가 벤치 비구속 절대지표 + S3상 negative 보수-안전. 재확증: value 24/24 감쇠(06-24) + KNS value-경로 실패(07-03) | DEF-02/06/07 (비전복) |
| AX-004 | **SOUND_REVERIFIED** | 클래스 재확증(16/16 universe-EW 자가벤치=DEF-01 비구속 + 07-03 방어DB + ML 증류 정합). 개별 construction 갭은 INV-7 provisional이 정직 커버 | DEF-02/06/07 (개별 한정, 방향 안전) |
| AX-005 | **SOUND_REVERIFIED** | 8공리 중 가장 직접적 재확증 — 07-03 방어 DB 전수 + BAB port_t −2.02(canonical) + book swap CLOSED | DEF-02/06/07 (재확증으로 해소) |
| AX-007 | **SOUND_REVERIFIED** | KNS +1.28 · superfactor 4방법 全 oos FAIL · SR 천장 · DPL settled — ML sizing 예외 오히려 축소 = 공리 강화 | DEF-02/06/07 (재확증으로 해소) |
| AX-008 | **SOUND** | 프로세스 공리 — 결함 기기 노출 자체 없음. 기기 결함 검출 사례 2건 실증 = 본 감사 리스크의 1차 방어선 | 없음 |

---

## 4. 판정 — 층 2: strategic_truths 확정진실 7건

전건 SOUND/SOUND_REVERIFIED → **`02_Infrastructure/prompts/strategic_truths.md` 무변경** (지시 ④: TAINTED/RECHECK만 병기 — 해당 없음).

| ID | 진실 (요약) | 판정 | 핵심 근거 / 조건 |
|---|---|---|---|
| T1 | post-2017 cohort 감쇠 | **SOUND_REVERIFIED** | 서브기간 '차분' 설계라 동일-벤치 오차 상쇄 + 07-03 클린 기기 3중 재확증 (KNS/superfactor/smartbeta) |
| T2 | SR 천장 ~1.1 | **SOUND** | SR은 벤치-독립 + v2.4·winsorize 이후 측정 + 교정 시대 반례 0. 단 **병기 PORT_t 2.54는 pre-fix — 인용 시 'IKS001-창' 라벨 의무** |
| T3 | 16/16 PORT_t FAIL | **SOUND** | 코드 계보 실측(`qepm/mailbox/worktask/WT-D20260529_001/qmj_alpha_build.R:154-168` — 본 감사서 라인 실확인): 벤치=universe EW 자가구축(DEF-01 비경유), 비용=turnover×15bps delta형(DEF-02 flat 비경유) — 구조적 비구속 |
| T4 | 직교 ≠ 수익 | **SOUND_REVERIFIED** | **스팟 S1 완료** — 방향·결론 불변, 수치만 구-벤치 산물. §6 갱신 필요: β 0.99→0.92 · active 0.45→0.53 (도훈 confirm 대기) |
| T5 | 시장타이밍 4중 부정 | **SOUND** | 3층 중 최클린 — 수리-후(lag1 의무 적용) + IKS200 교체 후 측정 + paired NW-t(벤치-독립). faith 단독 기각은 MDD 헌법제약 근거임만 구분 |
| T6 | settled-negative 5종 | **SOUND** | ①③⑤ 기기 무관/차분/수리-후, ② 데이터-메커니즘 무관. ④ 인버스 ETF만 pre-fix 창이나 핵심 3축 벤치 정체성 무관 + S3상 교정 시 현금 오버레이 우위 확대 방향 |
| T7 | SR 2.5 레버 3종 | **SOUND_REVERIFIED** | ① overlay 클린 강화(1.897) — 단 범위 'regime-cash층만'으로 축소 인용. ③ 자사주 **S2로 negative 강화**(−1.18→−1.34). ② 잔차-직교 sleeve는 기기 문제 아닌 **미실증** — RAMP 18후보 PORT_t 최초 실증 필요. line 8 재프레이밍 권고: 실증 위계 ①확증 > ③약화(재확증) > ②미실증 |

---

## 5. 판정 — 층 3: Distilled 17건 + CAND active 17건

각 `qepm/memory/axioms/distilled/DIST-*.json`에 `evidence_audit_20260704` 필드 기록 완료. **TAINTED 6건은 `status=quarantined_evidence` 전환**(구 status는 `status_before_audit` 보존, 정제·promote 대상 제외 — `distilled.R::refine_distilled`에 차단 가드 추가).

| ID | 판정 | 한줄 사유 | 노출 결함 |
|---|---|---|---|
| DIST-AR-001 | SOUND_REVERIFIED | 레거시 proxy 창이나 polarity는 07-03 방어DB가 독립 재확인 + S3상 방향 안전. promote 시 에피소드-lens 재작성 필수 | DEF-01/02 (방향 안전) |
| DIST-AR-003 | SOUND_REVERIFIED | 11/12 pre-fix 벤치이나 S3(관대 방향)+S2(대표 재벤치 실증)로 12/12 negative verdict 보존 | DEF-01 (방향 안전 입증) |
| DIST-AS-001 | **TAINTED_RETRACT** | 증거 계보 단절 + module_quarantine 기반 + 5축 3연속 FAIL — 증거 실체 부재 | 계보 단절 |
| DIST-AS-002 | **TAINTED_RETRACT** | supporting 72%가 DEF-05 b434 오염분 + '기각 증거 인용 금지' 마킹 충돌 + stale ID 380건. AS-003이 정정본 | DEF-05 (직접) |
| DIST-AS-003 | SOUND_REVERIFIED | AS-002 post-distill 정정판 — 조건: proxy 64건 라벨 + positive-방향 멤버 교정벤치 재검 라벨 | DEF-01/02 (조건부) |
| DIST-JG-001 | **RECHECK** | 측정기기(harvey_t rank-IC HARD·N>20) 자체가 현 헌법서 폐기/강등 — 거짓판정 실증 기기. S3 논리로 구제 불가 | 구 게이트 의미론 |
| DIST-QPM-001 | **TAINTED_RETRACT** | L-160 ID 재발급 오링크 — QPM-005가 정정본 | ID 오링크 |
| DIST-QPM-002 | **RECHECK** | 레거시 창 8건 재실측 0 + DEF-02 양방향(MDD·turnover 민감)이라 S3 일괄 구제 불가. protected 3건 byte 보존 | DEF-01/02/06/07 |
| DIST-QPM-003 | SOUND_REVERIFIED | AX-004 재확증 승계. 단 active 공리와 중복 재증류 — promote 실익 낮음 | DEF-02/06/07 (승계 해소) |
| DIST-QPM-005 | SOUND | QPM-001 정정판 — algebraic identity는 수리 명제(기기 비적용). L-131만 레거시-창 라벨 조건 | DEF-01/02 (L-131 한정) |
| DIST-QPM-006 | SOUND | 조건 2: L-161A는 v8.2 Codex 폐지로 전제 소멸(제외/스코프 명시) + estimated 5건 창 라벨 | 시효상실 (L-161A 한정) |
| DIST-RAMP-001 | **TAINTED_RETRACT** | supersession — bare 131316 stale ID. RAMP-005가 승계 (내용 자체는 신뢰) | stale ID |
| DIST-RAMP-002 | **TAINTED_RETRACT** | Book-상대 성분이 06-24 철회 클래스(DEF-03/11)와 혼재 — momentum-standalone 성분 분리 재정제 필요 | DEF-03/11 (직접) |
| DIST-RAMP-003 | SOUND | cap-w 자가구축(DEF-01 비경유). 조건: DSR 'PSR t-stat 오표기' 라벨 + MERGE ID 3건 재링크 | DSR 오표기 (라벨 해소) |
| DIST-RAMP-004 | **TAINTED_RETRACT** | supersession — RAMP-006이 정정본 (CAVEAT 문서화는 정직) | stale ID |
| DIST-RAMP-005 | SOUND | RAMP-001 정정판 — backtested + cap-w 자가구축 + 4축 적대감사 동시 검증 | 없음 |
| DIST-RAMP-006 | **RECHECK** | grade A 멤버 RAMP_03B의 'Book 초과' 주장이 06-24 철회 클래스 — 재실측 또는 drop 전 promote 금지 | DEF-03/11 (멤버 한정) |
| CAND-active-17 | **RECHECK** | 판정 상속. TAINTED 짝 6건 promote 큐 제외 선결. **promote.R 5축은 기기 결함을 자동 탐지 못함(AS-002 507건 통과가 실증)** — 본 감사 verdict를 promote 전 필터로 소비 | DEF-05 (필터 사각) |

**판정 분포 (33건)**: SOUND 10 · SOUND_REVERIFIED 13 · RECHECK_QUEUED 4 · TAINTED_RETRACT_CANDIDATE 6.

---

## 6. 도훈 confirm 큐

1. **철회 후보 6건 큐 제외 confirm** — DIST-AS-001/AS-002/QPM-001/RAMP-001/RAMP-002/RAMP-004 (status=quarantined_evidence 적용 완료). confirm 시 expire 전환, RAMP-002는 momentum-standalone 성분 분리 재정제.
2. **measurement-graduation.md §6 수치 3곳 교정 갱신** — β≈0.99→0.92(교정 벤치) · active cor 0.45→0.53 · gross 0.789 불변 (스팟 S1 근거. 결론 불변, 수치만).
3. **잔여 미수리 기기 2점 수리 트랙** — DEF-08(연율화 가드) · DEF-09(RAWDATA BM_Ret 07-01 손상).
4. (advisory) pre-fix positive 벤치상대 수치 인용 라벨 — FLOW 2.35 · T2 병기 PORT_t 2.54는 'IKS001-창' 라벨 의무.

RECHECK 큐(재측정 계획 포함): `06_Registry/knowledge_recheck_queue.json`

---

## 7. 적용 내역 (본 세션, 임무 W)

| 파일 | 변경 |
|---|---|
| `qepm/memory/axioms/distilled/DIST-*.json` (17) | `evidence_audit_20260704` 필드 추가. TAINTED 6건 `status→quarantined_evidence` (+`status_before_audit`/`quarantined_at`/`quarantine_reason`) |
| `qepm/memory/axioms/active/AX-*.json` (8) | `evidence_audit_20260704` **메타 필드만** 추가 — text/canonical_statement/grade/enforcement 의미론 무변경 (스크립트 내 assert 가드로 확인) |
| `06_Registry/distilled_knowledge.json` | `distilled.R rebuild` 재생성 — quarantined_evidence 6건 전파 확인 |
| `06_Registry/knowledge_recheck_queue.json` | 신규 — RECHECK 4 entries + 제외 CAND 6건 + non-blocking followup 3건 |
| `02_Infrastructure/axiom/distilled.R` | `refine_distilled()`에 quarantined_evidence 정제 차단 가드 추가 (지시 ② '정제 대상 제외' 강제) |
| `02_Infrastructure/prompts/strategic_truths.md` | **무변경** — TAINTED/RECHECK 해당 truths 0건 (지시 ④ 조건 미충족) |
| `06_Registry/hypothesis_index.json` | `hypothesis_index.R build` 재생성 (회귀 확인) |

## 8. 검증 결과 (지시 ⑥)

- **JSON 파싱 전수**: DIST 17 + AX 8 + queue + distilled_knowledge + hypothesis_index + CAND 17 = 45 files, **fail 0**. `evidence_audit_20260704` 필드 25/25 존재.
- **inject 회귀**: `axiom_context_inject.sh` SessionStart — valid JSON, ctx 2034자, AX-000·truths 주입 정상, **quarantined/초안 텍스트 누출 0** (INV-6 유지).
- **hypothesis_index 회귀**: build 694 entries (distilled 17/17 indexed, parse_fail 0), lookup 정상 (quarantined 항목은 `distilled_status` 필드로 상태 표출).
- **hook_e2e_battery**: **11/11 PASS** (axiom_inject.context 포함).
- **memory_knowledge_health**: **Hard fails 0** (warnings 3 = 미커밋 git 상태 + 기존 WARN 2건, 본 변경과 무관).
- **보고서 링크 유효성**: 본문 참조 경로 전수 존재 확인 (variant_returns_xts.rds / buyback_drift_results.rds / benchmark.parquet + bak / strategic_truths.md / measurement-graduation.md / recheck_queue.json / essence_score.R / hurdle_gate.R / promote.R).

## 9. 참조

- 판정 기록: `qepm/memory/axioms/active/AX-*.json` · `qepm/memory/axioms/distilled/DIST-*.json` (각 `evidence_audit_20260704`)
- RECHECK 큐: `06_Registry/knowledge_recheck_queue.json`
- 룰: `.claude/rules/measurement-graduation.md` (§3/§6) · `.claude/rules/axioms.md` · `02_Infrastructure/docs/rules/axiom-engine.md` (INV-1~7)
- 원사건 메모리: reference-benchmark-iks200-bug-fix (DEF-01) · 백테 비용모델 진실 B0 (DEF-02) · reference-book-benchmark-alignment-realized-ym (DEF-03) · project-pg2-offense-overlay-settled (DEF-04) · project-batch434-codegen-contamination (DEF-05) · project-ramp-panel-score-lag-correction (DEF-11) · reference-orthogonality-gross-vs-active (T4)
