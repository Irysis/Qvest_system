---
name: kr-inverse-pattern-miner
description: "실측 negative 지식(Distilled 카드·L-code)을 입력받아 역전 가설을 제안하고 alpha_frontier_queue 등재까지 연결. KR 실패 패턴의 반대 방향 alpha 탐색 (INV-7 재도전 규약 준수)."
---

# KR Inverse Pattern Miner (v8.3 재작성 — 2026-07-24 도훈 승인 C4)

실측 negative로 확정된 지식의 **실패 기전을 역전**하여 새 가설 후보를 생성한다. AX-000(한계는 방법의 한계) + INV-7(negative = 판결 아닌 탐색지도) 정합. (구 v54판은 methodology_memory.md·Scout/S0 핸드오프 등 사멸 경로 의존으로 실행 불가 — 본판이 대체. 역사 = git.)

## 호출

Q-Lead가 L-code ID / DIST ID / family 키워드로 호출. 인수 없으면 Distilled negative 전량 스캔 후 미탐색 역전 후보 목록 제시.

## 실행 절차

### Step 1: 실패 지식 로드 (현행 정본 3원천)

```bash
Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <keyword>   # FAIL/KILL 이력 + in-flight 확인 (중복실행 방지 의무)
```
- `06_Registry/distilled_knowledge.json` — DIST 카드 (polarity=negative/conditional, `statement_refined` + `revival_spec` 부활조건)
- `stage_artifacts/l_code/<mode>/*.json` — mode별 L-code (기전 진단·next_probe)
- `qepm/memory/axioms/deprecated/` — 강등 4건 (구 AX-003/004/005/007 → DIST-QPM-006/QPM-003/AR-001/AR-003)

### Step 2: 역전 유형 3종 검토

| 역전 유형 | 설명 | 예시 |
|---|---|---|
| **Direction Flip** | 동일 factor, 반대 방향 | 12M momentum 음의 IC → short-horizon reversal |
| **Conditional Gate** | 동일 factor, 특정 국면에서만 | defense → CRISIS-only 노출 (AX-001 v2 조건부 평가 정합) |
| **Synthesis Pivot** | 실패 factor를 타 family와 결합 | low-beta 단독 실패 → low-beta + quality composite |

### Step 3: INV-7 재도전 규약 (필수 — 미충족 시 제안 금지)

1. **차별점 명시**: 원 실패의 config(구성·기간·유니버스·측정 기준)와 무엇이 다른지 1줄 — 동일 config 재시도는 제안 불가.
2. **revival_spec 대조**: 해당 DIST 카드에 부활조건이 정의돼 있으면 발화 여부 확인 (미발화 시 "조건부 대기" 라벨).
3. **선례 조회 의무(금지 목록 아님)**: DPL(§5 G-5 2026-08-24 settled-negative **철회**) · uncertainty sizing(§6 ④ — 새 각도·새 통제·새 표적이면 재시도 정당) · regime-conditional 교차결합 · conjunctive AND-gate 등 config-scoped negative 는 `hypothesis_index.R lookup <kw>` 로 선례를 1줄 대조하고 **차별점을 명시하면 재도전 정당**(AX-000 · INV-7 · CLAUDE.md v10). 동일 config 재시도만 금지(1항). revival_spec 발화 여부는 2항으로 병기.
4. **제약 비귀속** (AX-000 따름정리): "long-only/25종이라서 실패"식 역전(제약 완화 제안) 금지 — 조건-안 레버만.

### Step 4: 출력 — frontier 큐 등재 제안 (v8.3 M5)

가설을 `06_Registry/alpha_frontier_queue.json` FQ 항목 형식으로 제안 (mechanism·차별점·소비면·owner 표기). 등재 후 착수는 진입점 경유: 논문-검증형 → `/alpha-search`(v10 충실구현 `run_paper_replication`) · 강화 축(멀티팩터·비중방법론·리스크오버레이) → `Skill(reinforce)` 원장 등재 · 정밀 편입 → `/worktask create`(WT-R). 착수 전 큐 `status=open` 확인 + `hypothesis_index lookup` 의무 — CLAUDE.md v10 · lean-loop.md.

## 사용 제한

- Q-Lead 전용 (agent 내 자동 호출 금지 — selection pressure 방지).
- 동일 원천 지식에서 역전 가설 최대 2건 (조합 폭발 방지).
- 모든 제안에 metric_type 라벨 원칙 적용 — 역전 근거의 IC/성과 수치는 실측 출처 명시.

## 참조

- `.claude/rules/axioms.md` (AX-000·INV-7) · `02_Infrastructure/docs/rules/axiom-engine.md` (Distilled/revival 엔진)
- `06_Registry/alpha_frontier_queue.json` (등재 대상, schema 2.0 — 신규 항목은 `status="open"` enum 으로 등재. 자유서술 금지, 서술은 `status_raw`)
  - ★구 참조 `06_Registry/layer_bottleneck_map.md`(병목 계층 우선순위)는 **폐지**됐다 — 2026-08-23 v9 Lean Loop §3.4(f)/도훈 승인 D-h 로 `06_Registry/_archive/layer_bottleneck_map_20260822.md` 아카이브, 갱신 의무 없음. 우선순위는 지도가 아니라 `alpha_frontier_queue.json` 의 `status=open` 항목에서 고른다.
