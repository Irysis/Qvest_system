#!/bin/bash
# DEPRECATED 2026-05-29 v8.0 WS5-3 — settings.json 등록 해제. axiom 주입은 axiom_context_inject.sh로 이전. legacy Stage Guard(S0~S5/STR_XXX)는 v6.4 WT no-op. 파일 retain(legacy compat).

trap 'echo "{}"; exit 0' ERR  # Phase C3 전수 강제
#==============================================================================
# Unified Agent Guard — PreToolUse[Agent] Hook (v52 하네스)
# 3중 검증:
#   1. Stage Order: Agent name 기반 선행 artifact 존재 확인
#   2. S5 Spawn Order: Forge S5 전 RiskMgr 사전평가 필수
#   3. S0 Debate: s0_debate_guard.sh로 위임 (별도 Hook 유지)
#==============================================================================

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$DIR" ]; then echo '{}'; exit 0; fi

ARTS="$DIR/stage_artifacts"
TRACKER="$DIR/.cache/mutation_tracker.json"

# 전략 ID 추정 (name → prompt 순)
STRATEGY_ID=$(printf '%s' "$AGENT_NAME $AGENT_PROMPT" | grep -oE 'STR_[0-9]+[A-Za-z0-9_]*' | head -1)

# ─── 1. Stage Order Guard ────────────────────────────────────────────────────
# Agent name에서 stage 패턴 매칭 (name 기반만, 프롬프트 미검사)

# Forge S1: S0_VERDICT APPROVE 필요
if echo "$AGENT_NAME_LC" | grep -qE "forge.*(s1|cbpq|atyp|factor)"; then
  APPROVED=$(ls "$ARTS"/S0_VERDICT_*.json 2>/dev/null | head -1)
  if [ -z "$APPROVED" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Forge S1 차단: S0_VERDICT APPROVE artifact 없음. S0 Debate 먼저 완료하세요."}'
    exit 0
  fi
fi

# ─── v53 Sprint 3 P0-B: Stage Gate S2/S3/S4 전이 확장 ────────────────────────
# Forge S2 (profile): s1_construction artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "forge.*s2|s2.*forge|profile.*forge|forge.*profile"; then
  if [ -n "$STRATEGY_ID" ]; then
    S1_DONE=$(ls "$ARTS"/s1_construction_*"$STRATEGY_ID"*.json 2>/dev/null | head -1)
    if [ -z "$S1_DONE" ]; then
      printf '{"decision":"block","reason":"[P0-B Stage Gate] Forge S2 차단 (%s): s1_construction artifact 없음. S1 팩터 구축 완료 후 재스폰하세요."}' "$STRATEGY_ID"
      exit 0
    fi
  fi
fi

# Scout S3 (orthogonality): s2_profile artifact 필요 + ICIR >= 0.20 확인
if echo "$AGENT_NAME_LC" | grep -qE "scout.*s3|s3.*scout|orthogonality"; then
  if [ -n "$STRATEGY_ID" ]; then
    S2_DONE=$(ls "$ARTS"/s2_profile_*"$STRATEGY_ID"*.json 2>/dev/null | head -1)
    if [ -z "$S2_DONE" ]; then
      printf '{"decision":"block","reason":"[P0-B Stage Gate] Scout S3 차단 (%s): s2_profile artifact 없음. S2 프로파일링(ICIR 측정) 완료 후 재스폰하세요."}' "$STRATEGY_ID"
      exit 0
    fi
  fi
fi

# Forge S4 (integration/marginal): s3_orthogonality artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "forge.*s4|s4.*forge|integration.*forge|marginal.*forge"; then
  if [ -n "$STRATEGY_ID" ]; then
    S3_DONE=$(ls "$ARTS"/s3_orthogonality_*"$STRATEGY_ID"*.json 2>/dev/null | head -1)
    if [ -z "$S3_DONE" ]; then
      printf '{"decision":"block","reason":"[P0-B Stage Gate] Forge S4 차단 (%s): s3_orthogonality artifact 없음. Scout S3 직교성 검증 완료 후 재스폰하세요."}' "$STRATEGY_ID"
      exit 0
    fi
  fi
fi

# Scout S5 (research slate 설계): s4_marginal 또는 s4_integration artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "scout.*s5|s5.*scout|slate.*scout"; then
  if [ -n "$STRATEGY_ID" ]; then
    S4_DONE=$(ls "$ARTS"/s4_marginal_*"$STRATEGY_ID"*.json "$ARTS"/s4_integration_*"$STRATEGY_ID"*.json 2>/dev/null | head -1)
    if [ -z "$S4_DONE" ]; then
      printf '{"decision":"block","reason":"[P0-B Stage Gate] Scout S5 차단 (%s): s4_marginal/s4_integration artifact 없음. Forge S4 한계기여 검증 완료 후 재스폰하세요."}' "$STRATEGY_ID"
      exit 0
    fi
  fi
fi

# Judge S6: S2 + S4 + S5 artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "judge.*s6"; then
  MISSING=""
  ls "$ARTS"/s2_profile_*.json     >/dev/null 2>&1 || MISSING="${MISSING}s2_profile "
  ls "$ARTS"/s4_marginal_*.json    >/dev/null 2>&1 || MISSING="${MISSING}s4_marginal "
  ls "$ARTS"/s5_research_slate_*.json >/dev/null 2>&1 || MISSING="${MISSING}s5_research_slate "
  if [ -n "$MISSING" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Judge S6 차단: 선행 artifact 누락 [%s]. S2~S5 완료 후 스폰하세요."}' "$MISSING"
    exit 0
  fi

  # ─── v53 S2.6: Fast-Track 차단 — mutation_tracker.json 기반 S5 Rule 검증 ───
  if [ -f "$TRACKER" ] && [ -n "$STRATEGY_ID" ]; then
    FT_CHECK=$(python3 -c "
import json
try:
    t = json.load(open('$TRACKER'))
    strats = t.get('strategies', {})
    sid = '$STRATEGY_ID'
    # prefix match (STR_1662a, STR_1662_synth 등)
    matches = [k for k in strats.keys() if k.startswith(sid) or sid.startswith(k)]
    if not matches:
        print('NO_ENTRY')
    else:
        best = max(matches, key=lambda k: strats[k]['mutations_attempted'])
        e = strats[best]
        if e['passes_s5_rule']:
            print('PASS')
        else:
            msg = 'mutations=%d(>=9필요); categories=%d(>=2필요); synthesis_tested=%s' % (
                e['mutations_attempted'], e['f_category_count'], str(e['synthesis_tested']))
            print('FAIL|'+msg)
except Exception as ex:
    print(f'ERR|{ex}')
" 2>/dev/null)

    FT_STATUS=$(echo "$FT_CHECK" | cut -d'|' -f1)
    FT_MSG=$(echo "$FT_CHECK" | cut -d'|' -f2-)
    case "$FT_STATUS" in
      FAIL)
        printf '{"decision":"block","reason":"[S2.6 Fast-Track Guard] Judge S6 차단 (%s): S5 Rule 미충족 — %s. S5 Mutation Lab 완료 후 재스폰하세요."}' "$STRATEGY_ID" "$FT_MSG"
        exit 0
        ;;
      NO_ENTRY)
        printf '{"decision":"block","reason":"[S2.6 Fast-Track Guard] Judge S6 차단 (%s): mutation_tracker에 S5 산출물이 없습니다. S5 Mutation Lab을 먼저 실행하세요."}' "$STRATEGY_ID"
        exit 0
        ;;
    esac
  fi
fi

# ─── v53 Sprint 3 P1-B: Governor PG0→PG1→PG2→PG3 전이 gate ────────────────
# PG0 (Gap Diagnosis): S6 Judge Grade A artifact 필요 (최소 1건)
if echo "$AGENT_NAME_LC" | grep -qE "governor.*pg0|pg0.*governor|gap.*diag"; then
  GRADE_A=$(grep -rl '"grade".*"A' "$ARTS"/s6_judge_*.json 2>/dev/null | head -1)
  if [ -z "$GRADE_A" ]; then
    printf '{"decision":"block","reason":"[P1-B PG0] Governor PG0 차단: S6 Judge Grade A artifact 없음. S6 검증 먼저 완료."}'
    exit 0
  fi
fi

# PG1 (Admission): pg0_gap_diagnosis artifact 필요 + 해당 STR의 s7_disposition 필요
if echo "$AGENT_NAME_LC" | grep -qE "governor.*pg1|pg1.*governor|admission"; then
  PG0_DONE=$(ls "$ARTS"/pg0_gap_*.json "$ARTS"/pg0_diagnosis_*.json 2>/dev/null | head -1)
  if [ -z "$PG0_DONE" ]; then
    # .cache/portfolio_gap_vector.json 도 대안 허용
    if [ ! -f "$DIR/.cache/portfolio_gap_vector.json" ]; then
      printf '{"decision":"block","reason":"[P1-B PG1] Governor PG1 차단: pg0_gap/pg0_diagnosis artifact 없음 (또는 .cache/portfolio_gap_vector.json). PG0 Gap Diagnosis 선행."}'
      exit 0
    fi
  fi
  if [ -n "$STRATEGY_ID" ]; then
    S7_DONE=$(ls "$ARTS"/s7_disposition_*"$STRATEGY_ID"*.json "$ARTS"/s7_*"$STRATEGY_ID"*.json 2>/dev/null | head -1)
    if [ -z "$S7_DONE" ]; then
      printf '{"decision":"block","reason":"[P1-B PG1] Governor PG1 차단 (%s): s7_disposition artifact 없음. Judge S7 판정 선행."}' "$STRATEGY_ID"
      exit 0
    fi
  fi
fi

# PG2 (Allocation): pg1_admission artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "governor.*pg2|pg2.*governor|allocation"; then
  PG1_DONE=$(ls "$ARTS"/pg1_admission_*.json 2>/dev/null | head -1)
  if [ -z "$PG1_DONE" ]; then
    printf '{"decision":"block","reason":"[P1-B PG2] Governor PG2 차단: pg1_admission artifact 없음. PG1 Admission 선행."}'
    exit 0
  fi
fi

# PG3 (Validation): pg2_allocation artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "governor.*pg3|pg3.*governor|pg_validation"; then
  PG2_DONE=$(ls "$ARTS"/pg2_allocation_*.json 2>/dev/null | head -1)
  if [ -z "$PG2_DONE" ]; then
    printf '{"decision":"block","reason":"[P1-B PG3] Governor PG3 차단: pg2_allocation artifact 없음. PG2 Allocation 선행."}'
    exit 0
  fi
fi

# Generic governor (PG stage 미지정 시 fallback): S6 Grade A 필요
if echo "$AGENT_NAME_LC" | grep -qE "governor" \
   && ! echo "$AGENT_NAME_LC" | grep -qE "pg[0-3]|admission|allocation|gap.*diag|pg_validation"; then
  GRADE_A=$(grep -rl '"grade".*"A' "$ARTS"/s6_judge_*.json 2>/dev/null | head -1)
  if [ -z "$GRADE_A" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Governor 차단: S6 Judge Grade A artifact 없음. Agent name에 pg0/pg1/pg2/pg3 명시 권장."}'
    exit 0
  fi
fi

# ─── 2. S5 Spawn Order (기존 s5_spawn_order.sh 통합) ─────────────────────────
# Forge S5 스폰 시 RiskMgr 사전평가 필수

IS_FORGE_S5=0
if echo "$AGENT_NAME_LC" | grep -qE "forge.*s5|s5.*forge"; then
  IS_FORGE_S5=1
fi

if [ "$IS_FORGE_S5" -eq 1 ]; then
  RISK_FILES=$(ls "$ARTS"/s5_risk_assessment_*.json 2>/dev/null | wc -l)
  if [ "$RISK_FILES" -eq 0 ]; then
    printf '{"decision":"block","reason":"[S5 Hook] Forge S5 차단: Risk Manager 사전 평가(s5_risk_assessment_*.json) 미완료. RiskMgr을 먼저 스폰하세요."}'
    exit 0
  fi

  # ─── v53 S2.6: Research Slate A/B/C/D 완성도 검증 ───
  if [ -n "$STRATEGY_ID" ] && [ -f "$TRACKER" ]; then
    SLATE_CHECK=$(python3 -c "
import json
try:
    t = json.load(open('$TRACKER'))
    strats = t.get('strategies', {})
    sid = '$STRATEGY_ID'
    matches = [k for k in strats.keys() if k.startswith(sid) or sid.startswith(k)]
    if not matches:
        print('NO_SLATE')
    else:
        e = strats[matches[0]]
        if e['slate_complete']:
            print('OK')
        else:
            got = ','.join(e['slate_slots']) or 'none'
            print(f'INCOMPLETE|{got}')
except Exception as ex:
    print(f'ERR|{ex}')
" 2>/dev/null)
    SL_STATUS=$(echo "$SLATE_CHECK" | cut -d'|' -f1)
    SL_GOT=$(echo "$SLATE_CHECK" | cut -d'|' -f2-)
    case "$SL_STATUS" in
      INCOMPLETE)
        printf '{"decision":"block","reason":"[S2.6 Fast-Track Guard] Forge S5 차단 (%s): Research Slate A/B/C/D 미완성 — 현재 [%s]. Scout이 s5_research_slate_*.json에 A/B/C/D 4슬롯 모두 설계 후 재스폰하세요."}' "$STRATEGY_ID" "$SL_GOT"
        exit 0
        ;;
      NO_SLATE)
        printf '{"decision":"block","reason":"[S2.6 Fast-Track Guard] Forge S5 차단 (%s): s5_research_slate artifact 없음. Scout이 Research Slate 설계 후 재스폰하세요."}' "$STRATEGY_ID"
        exit 0
        ;;
    esac
  fi
fi

# ─── v53 Sprint 4 AX-P2 + Block C v1.0 토큰 절감: Axiom 캐시 기반 주입 ────────
# AX-* JSON 파일들의 내용을 .cache/axiom_inject_body.md에 pre-render.
# 소스 mtime 대비 캐시 mtime이 최신이면 cat만, 아니면 재생성.
# Agent 스폰 시마다 발생하던 python3 spawn + json parse + string serialize 제거.
AXIOM_CONTEXT=""
ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
CACHE_BODY="$DIR/.cache/axiom_inject_body.md"
mkdir -p "$DIR/.cache" 2>/dev/null

if [ -d "$ACTIVE_DIR" ]; then
  # 캐시 유효성 검사: 소스 폴더의 최신 mtime > 캐시 mtime 이면 재생성
  NEED_REGEN=1
  if [ -f "$CACHE_BODY" ]; then
    NEWEST_SRC=$(find "$ACTIVE_DIR" -name 'AX-*.json' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
    CACHE_TS=$(stat -c '%Y' "$CACHE_BODY" 2>/dev/null || echo 0)
    # bash 산술 비교 (float → int)
    NEWEST_SRC_INT=${NEWEST_SRC%.*}
    [ -z "$NEWEST_SRC_INT" ] && NEWEST_SRC_INT=0
    if [ "$NEWEST_SRC_INT" -le "$CACHE_TS" ]; then
      NEED_REGEN=0
    fi
  fi

  if [ "$NEED_REGEN" -eq 1 ]; then
    python3 -c "
import json, os, glob
lines = []
for f in sorted(glob.glob(os.path.join('$ACTIVE_DIR', 'AX-*.json'))):
    try:
        ax = json.load(open(f))
        ax_id = ax.get('axiom_id') or ax.get('id') or os.path.basename(f).replace('.json','')
        stmt = (ax.get('statement') or ax.get('text') or ax.get('name') or '')[:75]
        tag_type = ax.get('type') or ax.get('grade') or 'IMMUTABLE'
        tag_pol = ax.get('polarity') or ('axiom' if ax.get('grade')=='IMMUTABLE' else '?')
        lines.append(f'  - {ax_id} [{tag_type}/{tag_pol}]: {stmt}')
    except Exception: pass
# [v8.0 WS5-4] 경량화: statement 75자 요약 + 전문 pointer (매 spawn ~600→~180 tok). 전문은 agent가 필요시 Read.
lines.append('  → 전문: .claude/rules/axioms.md / qepm/memory/axioms/active/AX-*.json (active 8)')
open('$CACHE_BODY', 'w').write(chr(10).join(lines))
" 2>/dev/null
  fi

  # 캐시된 body 읽기 + role-specific header 조합
  if [ -s "$CACHE_BODY" ]; then
    case "$AGENT_NAME_LC" in
      *scout*)    HEADER='[AX 전제 — Scout] 이미 확립된 영역은 재탐색 금지. 새 construction/regime/미확립 영역에 집중.' ;;
      *forge*)    HEADER='[AX 전제 — Forge] AX 범위 내 실험이면 AX 인용 + 경계 조건 명시.' ;;
      *judge*)    HEADER='[AX 전제 — Judge] AX 범위인데 반대 결과면 결과가 아닌 실험을 먼저 의심 (auditor).' ;;
      *governor*) HEADER='[AX 전제 — Governor] AX covered 전략은 core 배정 confidence 상승.' ;;
      *blender*)  HEADER='[AX 전제 — Blender] AX 인증 전략만 앙상블 후보 base weight 상향.' ;;
      *)          HEADER='[AX 전제] 아래 공리는 qvest 모든 행위의 대전제.' ;;
    esac
    AXIOM_CONTEXT="$HEADER
$(cat "$CACHE_BODY")"
  fi
fi

# ─── 3. v53 Fix #5 (legacy): Scout 스폰 시 Axiom Signal 힌트 (실패 패턴 회피) ──
if echo "$AGENT_NAME_LC" | grep -q "scout"; then
  SIG="$DIR/.cache/axiom_signals.json"
  if [ -f "$SIG" ]; then
    HINT=$(python3 -c "
import json
try:
    d = json.load(open('$SIG'))
    rp = [e.get('pattern','') for e in d.get('reuse_penalty',{}).get('entries',[])[:3] if e.get('pattern')]
    fc = [e.get('cluster','') for e in d.get('failure_cluster',{}).get('entries',[])[:3] if e.get('cluster')]
    parts = []
    if rp: parts.append('reuse_penalty: ' + '; '.join(rp))
    if fc: parts.append('failure_cluster: ' + '; '.join(fc))
    if parts: print('[Axiom Guard] 최근 실패 패턴 회피 권고 — ' + ' | '.join(parts))
except Exception:
    pass
" 2>/dev/null)
    if [ -n "$HINT" ]; then
      # Axiom + reuse_penalty 결합 주입
      COMBINED="${HINT}"
      if [ -n "$AXIOM_CONTEXT" ]; then
        COMBINED="${AXIOM_CONTEXT}

${HINT}"
      fi
      HINT_ESC=$(printf '%s' "$COMBINED" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
      exit 0
    fi
  fi
fi

# ─── 4. Axiom 단독 주입 (Scout 이외 에이전트) ────────────────────────
if [ -n "$AXIOM_CONTEXT" ]; then
  HINT_ESC=$(printf '%s' "$AXIOM_CONTEXT" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
  exit 0
fi

# ─── 5. 기타 (Explore, general-purpose 등) → 무조건 허용 ─────────────────────
echo '{}'
exit 0
