# Qvest 3-Mode Architecture SOT — 각 모드가 각자 평가·자가발전

**버전**: v0.3 (도훈 vision 정합) · 2026-06-05
**상태**: 헌법개정. CLAUDE.md §8 적용 대상.
**핵심 전환 (v0.2→v0.3)**: v0.2는 Codex 비판을 따라 "세 모드를 *단일 권위로 통일*"하려 했으나, **도훈 mandate 2026-06-05: "각 모드가 각자의 평가 체계를 가지고 각자 발전. 팩터로테이션도 자가발전"** 에 따라 **per-mode 자율**로 전환. Codex는 조언자(veto 없음) — 유효 지적(정직 라벨·proxy 격리)만 §3에 흡수, *통일 처방은 폐기*.
**근거**: 도훈 mandate + footprint 매핑 + **axiom 엔진 v8.0(3-mode 2-tier, E2E 10/0 PASS — 본 vision의 작동 구현체)**.
**위반 = AX-002 동급.** Codex 토론 기록: `stage_artifacts/constitution_3mode/`.

---

## 0. 핵심 원칙 (한 문장)

> **Qvest는 독립된 리서치 모드 3개다. 각 모드는 (1) 자기 평가체계 + (2) 자기 자가발전을 가진다. 모드 간 공유는 *평가가 아니라 토대*뿐이다 (정직 라벨 · 자본 게이트 · 교차검증 global 공리). 평가체계는 통일하지 않는다.**

---

## 1. 3-Mode = 리서치 라이프사이클 (생산 → 소비)

Lane1(QEPM)·Lane2(alpha-search) = 모듈 *생산*. Lane3(factor-rotation) = 졸업 모듈 *소비*·조립. 서로 다른 입력·질문·산출을 갖는 별개 활동(병렬 rigor-tier 아님).

| 모드 | 질문 | 입력 → 산출 | **자기 평가체계** | **자기 자가발전** | 진입 |
|---|---|---|---|---|---|
| ① **QEPM** | 최적비중·편입 값어치? | 신호-only 알파 → 편입전략 | 6-게이트 graduation (PIT + portfolio-α t…) | `AX-QPM-*` axioms | `/qvest`·`/worktask` |
| ② **Alpha-Searching** | 이 논문 알파 먹히나? | 자기완결 논문 → screen + L-code | IC·hurdle 스크린 (proxy 라벨) | `AX-AS-*` axioms | `/alpha-search` |
| ③ **Factor-Rotation** | 국면 따라 어떻게 섞나? | frozen 졸업 모듈 → 합성 `FR_XXXX` | Track1 국면판별 + Track2 배분 OOS edge | `AX-FR-*` axioms | `/factor-rotation` |

**공통(불변)**: long-only·Σw=1·w∈[0,0.20]·max 25·LIQ 2e8·15bps·TO≤11/yr·PIT C1~C15.

---

## 2. 각자 자가발전 = Axiom 엔진 (3-mode 2-tier) — 이미 가동·검증

각 모드가 자기 L-code → 자기 **mode-local axiom**(`qepm/memory/axioms/active/modes/<mode>/AX-<MODE>-NNN.json`)으로 발전. SOT: **`02_Infrastructure/docs/rules/axiom-engine.md`** (v8.0, E2E 10/0 PASS, 2026-06-05 검증). r7 5축 hurdle(Independence/Rigor/Falsification/OOS/Mechanism). **검증된(backtested) 증거만 global `AX-NNN`으로 승격**(INV-1). negative=provisional failure-ledger(INV-7). 안전망: rollback + 주간 human-review.
→ **factor-rotation도 자기 트랙(`AX-FR`)으로 자가발전**(도훈 "이 또한 자가발전"). 현재 FR L-code 0건 — emit 시작 시 자동 합류.

---

## 3. 공유 = 평가가 아니라 *토대* (평가체계는 모드별 자율)

> **충돌 방지 (도훈 2026-06-05 지적)**: "평가 통일 금지"는 *모드의 산출물 채점*에만 적용. 아래 공유 토대(정직 라벨·자본 게이트·global 공리)는 *평가 통일이 아님* — 특히 global 공리는 "교차검증된 *사실*"의 공유지 "채점 방식"의 통일이 아니다(§3.3).

### 3.1 숫자 정직 라벨 (`metric_type`)
모든 숫자·모듈에 **`proxy`(대충 빠르게) / `backtested`(계약대로 실측) / `estimated`** 라벨 의무. **왜 이것만 공유하나**:
- ① **FR이 다른 모드 모듈을 소비**하니, 그게 "진짜 frozen·backtested 모듈"인지 알아야 안심하고 섞는다.
- ② **axiom INV-1**: proxy는 mode-local까지만, global은 backtested만 — 한 모드의 *대충 숫자*가 다른 데서 *진짜처럼* 쓰여 사고 나는 걸 차단.

평가를 통일하는 게 아니라 **숫자의 출처·품질만 정직하게 붙이는 것**(PIT·측정정직 = 기존 도훈 원칙). Codex 유효지적 흡수.

### 3.2 단일 자본 게이트
어느 모드 결과든 **실제 자본 편입(`book_state`)은 governor 수동 + 도훈 confirm 한 곳**으로 수렴. 돈은 한 군데서만 막는다. (이미 도훈 장치 — governor 정지.)

### 3.3 교차검증 global 공리 (axiom 엔진 2-tier)
각 모드가 자가발전으로 얻은 *교훈* 중 **backtested + r7 5축 + AX-008(2/3 verification) + 도훈 confirm**을 통과한 것만 mode-local `AX-<MODE>-*` → global `AX-NNN`으로 승격(INV-1). **이건 평가 통일이 아니라 *교차검증된 사실*의 공유** — 법칙을 공유해도 모드별 채점 기준은 안 통일되는 것과 같다. 안전: proxy·한 모드 loose 평가는 global 차단(INV-1) / negative=provisional+재도전(INV-7) → 모드 자율 불침해 / global 승격=비가역이라 도훈 수동. 즉 **각자 평가하되, 공유 *사실*은 가장 엄격한 공통 falsification 통과분만.** SOT: `02_Infrastructure/docs/rules/axiom-engine.md`.

---

## 4. 모드별 평가체계 = 각자 (통일 금지)

- 세 모드는 *평가 대상이 다르다*: 알파신호(alpha-search) / 포트폴리오·편입(QEPM) / 국면배분정책(factor-rotation). 단일 5지표로 통일 부적합.
- **mode-local 평가·게이트·등급 정의 허용**(v0.2의 "mode-local 금지" 조항 폐기). 각 모드가 자기 기준으로 "좋다"를 정의.
- 단 §3.1 정직 라벨은 의무 — 자기 평가 숫자가 proxy면 proxy라 표시(그래야 자율이 안전).

---

## 5. 분리 불변식 (namespace)
- ID prefix: QEPM `WT_*` / alpha-search `STR_AS_*` / factor-rotation `FR_*`. 교차·`WT_WT_` 금지.
- 모드별 artifact root `stage_artifacts/<mode>/`. 공유 레지스트리에 `mode` 필드. alpha-search backlog를 `qepm/registry/` 밖으로(후속).

---

## 6. FR 입력(소비) 규칙
- **floor = `contract_pass`(계약 실측) + frozen + `source_contract_id`/`module_hash`/`build_version` 검증.** RCMA가 그 위에서 국면조건부 **grade-무관** 선정(walk-forward asof — 2026-06-05 fix).
- **RCMA = pool 선정 ≠ 자본편입.** 출력 `strategy_type=composite_allocator`·`eligible_for_alpha_registry=false`·별도 `factor_rotation_registry.json`.

---

## 7. Codex 토론 기록 + 도훈 override (정직)
- **R1** `MAJOR_REVISION`("3모드→2-lane 축소") → synthesis → **R2** `APPROVE_WITH_CHANGES`(단일 권위 통일 조건).
- **흡수(유효)**: 정직 라벨 + proxy 격리 → §3. namespace 분리 → §5.
- **Override(폐기)**: "단일 권위로 *통일*" 처방은 도훈 vision(각자 평가·발전)과 정면 배치 → **폐기**. Codex=조언자(veto 없음), 결정=도훈. axiom 엔진(E2E 통과)이 per-mode 자율의 작동 증거.

---

## 8. CLAUDE.md 개정안 (적용 대상)
- `## Active Path` → **`## Active Modes (3-Mode — 각자 평가·자가발전)`**: 3-모드 표 + "각 모드 자기 평가체계+자가발전(axiom mode-local) / 공유 2가지(정직 라벨 + 자본 게이트) / 평가 통일 안 함" + SOT·axiom-engine.md 포인터.
- `## Active Entrypoints`: `/alpha-search`·`/factor-rotation` 추가.

---

## 9. 후속
skill §11 / `axiom_sot_map.json` 헤더 stale 정정 · FR L-code emit 개시(AX-FR 채움) · alpha-search backlog 이전 · 8 axiom provisional human-confirm.

## Change log
- 2026-06-05 v0.3: **도훈 vision 전환** — 단일 권위 spine 폐기 → **per-mode 자율(각자 평가+자가발전)**. 공유=정직라벨+자본게이트 2개. axiom 엔진 v8.0(검증)을 자가발전 백본으로 명시. Codex 통일 처방 override(유효지적만 흡수).
- 2026-06-05 v0.2: Codex R2 반영 단일 권위 spine — 도훈 vision과 배치 → v0.3 폐기.
- 2026-06-05 v0.1: 초안(3-mode 정의). Codex R1 MAJOR_REVISION.
