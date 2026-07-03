# Challenge Note — WT-S20260626_001 (Alpha role)

**WT type**: `sizing_only` · **discovery_of**: STR_1715_WT016_Iter31_GridBestProd · **as_of**: 2026-06-26

## codex_critic_skip_waiver — Alpha role (Codex Critic Round 면제)

**근거 (Charter v1.7 §10 Role Card + role_card_cert_inheritance.R line 35-37)**:
- `sizing_only` WT의 alpha role card: `alpha_discovery = "exempt"`. **alpha 0건이 정상 산출물**.
- 본 WT는 STR_1715 base sleeve의 alpha를 **inherit 참조만** 하며 **신규 알파/팩터/가설 발굴이 전혀 없음** (`new_discovery=false`, `alpha_inheritance_cor = 1.0`).
- 가설(`request.json::hypothesis_description`)이 변경하는 것은 **오버레이 결합 연산자**(곱셈 β_AR×β_R05 → max-cash min(β_AR,β_R05)) 뿐 — 이는 **risk/optimizer/forge 영역**이며 alpha 영역이 아님.
- 따라서 Codex Critic이 alpha role에서 비평할 신규 알파 산출물이 존재하지 않음 → full critic round 무의미.

**선례 정합**: WT-S20260504_001 (동일 `sizing_only` 패턴) — `codex_critic_response_alpha.json` = `status: SKIPPED_BY_WAIVER`, `reason: "sizing_only inherited alpha; ... alpha_discovery exempt"`. 본 WT는 그 선례를 그대로 따른다.

**역할 경계 준수 (strict)**:
- Σ/공분산/weight/오버레이 결합 연산자 **일절 건드리지 않음** — risk/optimizer/forge 몫.
- alpha role 산출 = inherit reference 2종 (`alpha_package_inherit_ref.json` + `alpha_package.json` thin stub)만.

**Codex round의 실질 비평 대상**: 본 WT의 신규 메커니즘(max-cash 오버레이 결합)은 **optimizer/forge role의 codex round**에서 비평되어야 한다 (alpha가 아님). 그 단계로 이관.

**PIT/측정 정직성**:
- 본 단계는 어떤 성과수치도 산출하지 않음 (실측은 forge 단계). 추측 성과수치 미기재.
- inherit reference는 parent alpha_package.json의 SHA256로 lineage 고정 (변조 감지 가능).

> `codex_critic_skip_waiver` 발효 (alpha role 한정). 사유: 위 Role Card exempt + 신규 알파 부재.
