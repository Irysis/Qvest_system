# Axioms (Level 0 공리)

**모든 에이전트는 아래 공리를 전제로 작동. AX-code 위반 = 즉시 중단.**

**SOT (v7.2.1+)**:
- Primary (authoritative): `qepm/memory/axioms/active/AX-*.json` (**active Law 4건: 000/001/002/008**. negative 4건 003/004/005/007 = 2026-07-05 **Distilled 강등**, `deprecated/` 아카이브 — INV-7)
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

mode-local `AX-<MODE>-NNN` (`active/modes/<mode>/`, MODE=AS/QPM/FR) + global `AX-NNN` (`active/`). negative 공리 = **Distilled 탐색지도**(INV-7, 재도전 대상 — Law 아님. 2026-07-05 AX-003/004/005/007 active→Distilled 강등, DIST 카드/Ledger 이관). Law 잔존 = process 규칙(polarity 없음, AX-000/001/002/008). 엔진 SOT: `02_Infrastructure/docs/rules/axiom-engine.md` (원전 r7 복원 + INV-1~7).

## Active Law (4) — AX-000/001/002/008

- **AX-000** [IMMUTABLE]: 한계는 대개 법칙이 아니라 방법의 한계다. 모든 목표는 충분한 엄밀함·창의성·반복으로 달성 가능하다는 전제로 임한다. 소수(3~4회)의 실험 실패를 '구조적 한계'나 'dead-end'로 단정하는 것을 금지하며, 탐색은 가용한 모든 수단(개념 발산·다른 데이터원·다른 구조·ML·수리·물리)을 소진하거나 도훈이 중단을 지시할 때까지 계속한다. 실증·PIT·수리로 얻은 결과는 정직히 보고하되(성공 위장·추측 금지), 그 자체가 탐색 중단의 근거가 되지 않는다. (2026-06-21 개정 — 도훈 mandate: '포기 정당' 라이선스 절 삭제 + 조기-한계-단정 금지 명문화)
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터는 조건부 성과로 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio). 전기간 SR 기준 적용 금지. **(process 규칙 — polarity 없음, INV-7 Law 잔존)**
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조 = C1 위반 동급.
- **AX-008** [process]: Verification Triangulation — Forge + Self-Adversarial(메인 Opus 4.8 자체 적대검증) + Architect 3-source 중 최소 2-source PASS 필수. (v8.2: Codex Round 제거 → Codex source를 self-adversarial로 치환, 3-source 2/3 불변) L-159/167/168.

## Demoted → Distilled (2026-07-05, INV-7 — 도훈 지시)

**negative 공리는 Law가 아니라 Distilled 탐색지도**(INV-7). 아래 4건은 active Law에서 강등 — active/에서 제거, `deprecated/AX-*_demoted_to_distilled_20260705.json` 아카이브. **지식은 손실 아님**: Ledger(L-code, `hypothesis_index` 검색) + deprecated 아카이브 + DIST 등가물 + 부활신호로 보존, **재도전 대상**(부활 조건 충족 시 시스템이 먼저 un-bury). 방향(family) 판결 아닌 경로(구성)-scoped 실패로만 소비.

- **AX-003** [empirical, DEMOTED→Distilled]: market=KR, family=value, EP_STANDALONE+LOW_TURNOVER 실패. L-132/135. → Ledger + 부활신호 `value_quality_spread`(V02_EP 분산 백분위, 극단 시 재도전). DIST 카드 authoring 후속.
- **AX-004** [methodological, DEMOTED→Distilled]: market=KR, family=quality_profitability, single-signal long-only 구조적 실패. EXCLUSION: multi-axis quality composite + multi-sleeve 내 Q07. L-133/134/139. → **DIST-QPM-003**.
- **AX-005 v1.2** [methodological, DEMOTED→Distilled]: market=KR, family=defense, universe=top20_long_only, low-beta/Q07+D25/4-axis composite 실패. EXCLUSION은 necessary not sufficient. L-136/140 (구 문서의 L-165/166 병기는 **오귀속 — 실제 AX-007 signal-portfolio translation family**, 2026-07-05 정정). → **DIST-AR-001**.
- **AX-007** [methodological, DEMOTED→Distilled]: roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing). L-160/165/166. → **DIST-AR-003**(AX-007 명시).

## Hook 강제 (v7.2.1+ enforcement_mode 기준)

`02_Infrastructure/hooks/axiom_enforcement_hook.sh` (PreToolUse[W/E]):
- AX-000 documented (immutable, hard-block 없음)
- AX-001 block (일부 패턴 hard-block 실증)
- AX-002 advisory (warn + context, v7.3에서 block 검토)
- AX-008 documented (hook hard-block 미도입)
- ~~AX-003/004/005/007~~ **2026-07-05 Distilled 강등 — active enforcement 대상 아님** (지식은 Distilled 탐색지도/검색으로 소비, 강제 아님)

## 참조

- `_shared_prefix.md` (full body)
- `qepm/memory/axioms/active/AX-*.json` (active Law 4건: 000/001/002/008) + `deprecated/AX-*_demoted_to_distilled_20260705.json` (강등 4건)
- `qepm/memory/axioms/candidates/CAND_*.json` (pending — AX-006 candidate-only)
- `qepm/memory/axioms/axiom_sot_map.json` (Documented ↔ JSON 매핑)
- `02_Infrastructure/axiom/lcode_harvester.py` (L-code → AX-code 승격 파이프라인)
- `02_Infrastructure/memory/memory_knowledge_health.R` (health gate hard 6 + warning 6)
