---
name: s5-mutation-lab
description: "S5 mutation 설계/실행 시 적용 — 3축, Research Slate, 9건+ 필수, Risk Engine 연동"
hooks:
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: "agent"
          if: "Bash(Rscript*source*run_all*)"
          prompt: "S5 mutation 백테스트 완료. output에서 tail_risk_result.json 확인. 없으면 {\"ok\":false, \"reason\":\"S5 mutation에 tail_risk 미측정. compute_tail_risk_suite() 필수.\"}, 있으면 {\"ok\":true}."
          timeout: 60
---
## S5 Mutation Lab

### 3축 병렬 탐색
1. **Factor Weight** (팩터 가중): 멀티팩터 조합 3건+ 최우선
2. **Stock Weight** (종목 가중): EW/RP/MinVar/Score-weighted
3. **Overlay** (오버레이): DD Brake, Regime tilt (S5에서만 허용)

### Research Slate 4슬롯
- A: same-family repair (기존 팩터 개선)
- B: cross-family complement (다른 family 조합)
- C: defensive/counter-cyclical
- D: method-only mutation (가중 방식만 변경)

### 필수 조건 (v53 Sprint 2 Fast-Track 강제)
- **최소 9건** mutation 실행
- **f_category_count ≥ 2**
- `synthesis_tested = TRUE` (Phase 5 Cross-Combination 완료)
- Research Slate A/B/C/D 4슬롯 모두 채움
- 멀티팩터 조합 3건+ 최우선, 파라미터 튜닝 최소

### Mutation Tracker (S2.7 자동 집계)
`artifact_validator.sh`가 `s5_mutation_*.json` / `s5_research_slate_*.json` / `s5_synthesis_slate_*.json` Write 시
`02_Infrastructure/validation/mutation_tracker.py`를 백그라운드 실행하여
`.cache/mutation_tracker.json`을 갱신한다.

**스키마**:
```json
{
  "last_updated": "...",
  "strategies": {
    "STR_XXX": {
      "mutations_attempted": 9,
      "f_category_count": 5,
      "categories": ["A_NHold", "B_Rebal", "C_Weight", ...],
      "synthesis_tested": true,
      "slate_slots": ["A", "B", "C", "D"],
      "slate_complete": true,
      "sources": [...],
      "passes_s5_rule": true   // 9건+2카테고리+synthesis 모두 충족 시 TRUE
    }
  }
}
```

**수동 갱신**:
```bash
python3 02_Infrastructure/validation/mutation_tracker.py
```

### Fast-Track 차단 (S2.6)
`unified_agent_guard.sh`가 Agent 스폰 시 mutation_tracker 조회:

- **Forge S5 스폰**: Research Slate A/B/C/D 미완성 → **block**
- **Judge S6 스폰**: `passes_s5_rule=false` 또는 entry 없음 → **block**
  ```
  "[S2.6 Fast-Track Guard] Judge S6 차단 (STR_XXX): S5 Rule 미충족 — 
   mutations=3(>=9필요); categories=1(>=2필요); synthesis_tested=False"
  ```

따라서 Scout은 설계 단계에서 A/B/C/D 4슬롯을 명시적으로 작성해야 한다 (빈 슬롯 허용 X).

### Scout이 설계 → Codex가 비평 → Scout이 수정 → Forge가 실행

### Scout이 설계 → Codex가 비평 → Scout이 수정 → Forge가 실행

**Phase A: Scout 설계**
- Scout → `s5_mutation_design_{n}.json` × 9건+ (instructions_for_forge 포함)

**Phase B: Codex Mutation Review (GPT-5.5) — 신규**
- Scout 설계 완료 후, Q-Lead가 Codex task를 호출하여 mutation slate 전체를 비판적 평가
- 프롬프트: `02_Infrastructure/prompts/codex_s5_review_prompt.md`
- Placeholder 치환: `{{MUTATION_SLATE}}`, `{{BASE_STRATEGY}}`, `{{RESEARCH_SLATE_SLOTS}}`
- 호출:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs" task --wait --effort xhigh "$(cat /tmp/codex_s5_filled.md)"
```
- Codex 평가 축:
  1. **다양성**: 독립 축 개수 + 슬롯(A/B/C/D) 커버리지 + 3축(Factor/Stock/Overlay) 커버리지
  2. **구조 vs 파라미터**: 각 mutation이 structural/parameter/hybrid 중 어디인지 판별
  3. **경제적 메커니즘**: alpha source 논리성
  4. **설계 PIT**: overlay/regime/weight 방식의 실시간 구현 가능성
     - **MRS t-1 lag 주의**: `regime_engine_daily.R` Step 5에서 `shift(MRS_raw, 1, "lag")` 적용됨. overlay 코드에서 추가 shift 금지 (이중 lag → t-2 오류). PIT 주석 필수.
  5. **누락 탐지**: 빈 슬롯·빈 축·편중 탐지
  6. **예상 실패 모드**: mutation별 리스크
- Codex verdict가 `"needs-revision"`이면:
  - Codex의 `missing_explorations` + `recommendations`를 Scout에 피드백
  - Scout이 slate 수정 → Phase B 재실행 (최대 1회)
- Codex verdict가 `"approve"`이면 Phase C로 진행

**Phase C: Forge 실행**
- Forge → 설계대로만 실행. 자체 DD/VT 삽입 금지.

### DD/VT 규칙 (S5에서만)
- DD: `c(0, dd_pct[-n])` (t-1 lag, C9)
- VT: `c(vol[1], head(vol, -1))` (t-1 lag, C9)
