# Qvest Memory Layer (qepm/memory/)

**v7.2.1 Memory Knowledge Hardening Patch — Source of Truth + Authority + Lifecycle 정합화**

**발효**: 2026-05-02 / Session 76 / v7.2.1 PATCH
**상위**: `02_Infrastructure/docs/qvest_v6_4_sot.md` Active SOT

---

## 1. 지식 계층 정의

Qvest는 4-tier knowledge layer로 운용:

```
Lv0  Axiom   (constitutional / process / empirical / methodological)
Lv1  PIT     (C1~C15 — .claude/rules/pit.md)
Lv2  L-code  (lesson — methodology corpus, 269+ unique)
Lv3  Signal  (factor / strategy / hypothesis — runtime artifact)
```

- **Lv0 Axiom**: AX-code 명명. Hard-immutable + amendment 시 quarterly review. SOT는 `qepm/memory/axioms/active/*.json` + `.claude/rules/axioms.md`.
- **Lv1 PIT**: 미래참조 차단 15 check. SOT는 `.claude/rules/pit.md` + `02_Infrastructure/validation/pit_enforcement.R`.
- **Lv2 L-code**: 교훈/실패/calibration. 768+ id 범위, active corpus 269 unique. SOT는 `qepm/memory/methodology_memory*.md` + 외부 `methodology_active.md`.
- **Lv3 Signal**: factor / strategy. Runtime artifact — registry 회수.

위반 시 항상 상위 layer 우선 적용.

---

## 2. Authority + axiom_class 정합

### Authority enum (5값)

- `low` — lesson, calibration draft, candidate evidence
- `medium` — axiom_candidate (5축 검증 진행 중)
- `high` — axiom_active (5축 검증 PASS, hard-immutable 또는 quarterly review)
- `retired` — deprecated (superseded 또는 scope 재정의)
- `audit` — review_log, evidence_summary (감사 기록, 의사결정 영향 0)

### axiom_class enum (4값)

- `constitutional` — 시스템 헌법 (AX-000)
- `process` — 프로세스 우회 차단 (AX-002, AX-008)
- `empirical` — 실증 결과 (AX-003)
- `methodological` — 방법론 실패 (AX-001, AX-004, AX-005, AX-007)

### enforcement_mode enum (4값)

> **"문서상 권위가 아니라 실제 hook/action 강제 수준"**

- `documented` — 문서/JSON SOT 명시. Hook hard-block 없음. (AX-000, AX-007, AX-008)
- `advisory` — Hook warn + context, 실제 block 미보장. (AX-002, AX-003, AX-004, AX-005)
- `block` — Hook 일부 패턴 hard-block 실증. (AX-001)
- `none` — candidate / deprecated.

### review_policy enum (4값)

- `skip` — review 면제 (constitutional immutable)
- `q_lead_approval` — Q-Lead override 필요
- `quarterly` — 분기 자동 review (axiom_active 기본)
- `retired` — deprecated 처리

---

## 3. Lifecycle 흐름

```
[lesson L-code]
        │
        │  cluster (3+ supporting evidence)
        ▼
[CAND_*.json]   ─────── promote.R 5축 검증 ──────►   [AX-XXX.json active]
        │                  weighted_score ≥ 0.8                  │
        │                                                         │
        │  superseded                              quarterly review
        ▼                                                         ▼
[deprecated/CAND_superseded.json]           [review_log/AX-XXX_*.json]
                                                                  │
                                                  scope 변경 또는 폐기
                                                                  ▼
                                                  [deprecated/AX-XXX_*.json]
```

핵심 invariant:
- `qepm/memory/axioms/active/`만 실시간 권위 보유
- `candidates/` = pending 5축 검증 (status=`pending_5axis`)
- `deprecated/` = 폐기 또는 scope 재정의 (replace 명시 의무)
- `review_log/` = 감사 기록 (hard-block 권한 없음)

---

## 4. Review policy by axiom_class

| axiom_class | review_policy | 사유 |
|---|---|---|
| constitutional | `skip` | AX-000 immutable, 변경 X |
| process | `q_lead_approval` | AX-002/008 — 프로세스 우회 방지, Q-Lead만 amend |
| empirical | `quarterly` | AX-003 — 분기 데이터로 재검증 |
| methodological | `quarterly` | AX-001/004/005/007 — 분기 retest |

`review.R --apply` 실행 시:
- `skip` → 변경 시도 차단
- `q_lead_approval` → Q-Lead 명시 결재 의무
- `quarterly` → 자동 dry-run, evidence drift 감지 시 candidate 재진입
- `retired` → 변경 0건

---

## 5. SOT reconciliation policy

### Primary SOT (authoritative)

- `qepm/memory/axioms/active/AX-*.json` — JSON 실시간 권위
- `.claude/rules/axioms.md` — documented summary (hook policy 부속)

### Documented set (Q-Lead 인지)

총 8 axiom (AX-000/001/002/003/004/005/007/008). AX-006는 candidate-only (active SOT 부재).

### Derived cache (NOT authoritative)

- `.cache/axiom_core.json` — bootstrap regenerate. SOT 아님.
- `.cache/lcode_corpus.json` — `lcode_corpus_rebuild.R`로 재생성.

### Sync status

`qepm/memory/axioms/axiom_sot_map.json`에 axiom별 sync_status 기록:
- `FULL` — active JSON ↔ `.claude/rules/axioms.md` ↔ derived cache 모두 일치
- `CANDIDATE_ONLY` — active JSON 부재 (AX-006)
- `STALE` — derived cache 갱신 필요

Hard fail 기준:
- active JSON ↔ `.claude/rules/axioms.md` 불일치 → memory_health hard fail
- derived cache STALE → WARN only (정상 reload로 해소)

### Memory layer 하위 dir

| dir | 용도 | authority |
|---|---|---|
| `axioms/active/` | live axiom JSON | high |
| `axioms/candidates/` | 5축 검증 pending | medium |
| `axioms/deprecated/` | superseded / scope 재정의 | retired |
| `axioms/review_log/` | quarterly review 산출 | audit |
| `axioms/review_log/dryrun/` | review.R dry-run report | audit |
| `lessons/` | L-code 교훈 (L-246~248 active) | low |
| `evidence_summary/` | factor evidence (233+) | audit |
| `regime_validation/` | regime gate validation | audit |
| `methodology_memory*.md` | L-code corpus source | low |

---

## 6. v7.2.1 변경 요약

- 8 documented active axiom 모두 JSON SOT 보유 (AX-007/008 신규 materialize, enforcement_mode=`documented`)
- AX-006 candidate-only 명시 (`axiom_sot_map.json::candidate_evidence_paths` 3건)
- `.cache/axiom_core.json` derived cache 격하 (NOT authoritative)
- 19 JSON metadata patch (`memory_id` / `axiom_class` / `authority` / `review_policy` / `enforcement_mode` / `canonical_statement` 추가)
- `lcode_corpus_rebuild.R` 38 → 269+ unique L-code 확장 (lcodes list-of-objects retain)
- `qvest_search` 5 type 추가 (lesson/candidate/deprecated/review/evidence_summary)
- `review.R --apply` flag 의무화 (default dry-run)
- `memory_knowledge_health.R` hard 6 + warning 6 gate
- v8 readiness gate 14 → 15 check

상세: `CHANGELOG.md` v7.2.1 entry.

---

## 참조

- `qepm/memory/axioms/axiom_sot_map.json` — SOT mapping 기준
- `qepm/observability/memory_inventory.json` — count snapshot
- `02_Infrastructure/memory/memory_metadata_normalize.R` — promote helper
- `02_Infrastructure/memory/memory_knowledge_health.R` — health gate
- `.claude/rules/axioms.md` — documented summary
- `02_Infrastructure/docs/qvest_v6_4_sot.md` — 상위 SOT
