# Axioms (Level 0 공리)

**모든 에이전트는 아래 공리를 전제로 작동. AX-code 위반 = 즉시 중단.**

**SOT (v7.2.1+)**:
- Primary (authoritative): `qepm/memory/axioms/active/AX-*.json` (8건: 000~005, 007, 008)
- Documented (Q-Lead 인지): `.claude/rules/axioms.md` (본 파일)
- Mapping: `qepm/memory/axioms/axiom_sot_map.json`
- Health: `02_Infrastructure/memory/memory_knowledge_health.R` (hard 6 + warning 6)

**Derived cache (NOT authoritative)**:
- `.cache/axiom_core.json` — bootstrap regenerate. 권위 X. 동기화 STALE 시 WARN (hard fail X).
- `02_Infrastructure/prompts/_shared_prefix.md` — agent prefix injection.

**Hard fail 기준**: `qepm/memory/axioms/active/*.json` ↔ `.claude/rules/axioms.md` 불일치만. derived cache는 WARN.

## 계층

```
AX-code (Lv0) > PIT C1-C15 (Lv1) > L-code (Lv2) > Signals (Lv3)
```

## 2-Tier (v8.0)

mode-local `AX-<MODE>-NNN` (`active/modes/<mode>/`, MODE=AS/QPM/FR) + global `AX-NNN` (`active/`). negative 공리 = **provisional failure-ledger**(INV-7, 재도전 대상 — 불변 법칙 아님). 엔진 SOT: `02_Infrastructure/docs/rules/axiom-engine.md` (원전 r7 복원 + INV-1~7).

## AX-000 ~ AX-008

- **AX-000** [IMMUTABLE]: 한계는 대개 법칙이 아니라 방법의 한계다. 모든 목표는 충분한 엄밀함·창의성·반복으로 달성 가능하다는 전제로 임한다. 단, 실증·PIT·수리로 입증된 한계는 부정할 대상이 아니라 정직히 보고할 발견이며, 포기는 가용한 모든 방법을 소진한 뒤에만 정당하다. (v8.0 reframe — 4.8 정직성 정합)
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터는 조건부 성과로 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio). 전기간 SR 기준 적용 금지.
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조 = C1 위반 동급.
- **AX-003** [empirical]: market=KR, family=value, EP_STANDALONE+LOW_TURNOVER 실패. L-132/135.
- **AX-004** [methodological]: market=KR, family=quality_profitability, single-signal long-only 구조적 실패. EXCLUSION: multi-axis quality composite + multi-sleeve 내 Q07. L-133/134/139.
- **AX-005 v1.2** [methodological]: market=KR, family=defense, universe=top20_long_only, low-beta/Q07+D25/4-axis composite 실패. EXCLUSION은 necessary not sufficient (Gate13 PASS 동시). L-136/140/165/166.
- **AX-007** [methodological]: roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing). L-160/165/166.
- **AX-008** [process]: Verification Triangulation — Forge + Codex + Architect 3-source 중 최소 2-source PASS 필수. L-159/167/168.

## Hook 강제 (v7.2.1+ enforcement_mode 기준)

`02_Infrastructure/hooks/axiom_enforcement_hook.sh` (PreToolUse[W/E]):
- AX-000 documented (immutable, hard-block 없음)
- AX-001 block (일부 패턴 hard-block 실증)
- AX-002 advisory (warn + context, v7.3에서 block 검토)
- AX-003/004/005 advisory (warn, v7.3에서 block 강화)
- AX-007/008 documented (v7.2.1 신규, hook hard-block 미도입, v7.3 검토)

## 참조

- `_shared_prefix.md` (full body)
- `qepm/memory/axioms/active/AX-*.json` (active 8건 — v7.2.1 AX-007/008 materialize)
- `qepm/memory/axioms/candidates/CAND_*.json` (pending — AX-006 candidate-only)
- `qepm/memory/axioms/axiom_sot_map.json` (Documented ↔ JSON 매핑)
- `02_Infrastructure/axiom/lcode_harvester.py` (L-code → AX-code 승격 파이프라인)
- `02_Infrastructure/memory/memory_knowledge_health.R` (health gate hard 6 + warning 6)
