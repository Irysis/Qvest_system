#!/usr/bin/env bash
#==============================================================================
# s0_debate_enforcer.sh — PostToolUse[Write] Hook
#
# S0 3-Round Debate 상태 머신. 토론 프로세스를 기계적으로 강제.
#
# 통합 대체:
#   - s0_verdict_validator.sh (debaters 검증 → transcript rounds 검증)
#   - s0_debate_chain.sh (SubagentStop → 상태 전이 additionalContext)
#
# 상태 전이:
#   IDLE → R1_IN_PROGRESS → R1_COMPLETE → R2_IN_PROGRESS → R2_COMPLETE
#   → VERDICT_READY → DONE  (R3_NEEDED는 R2_COMPLETE에서 분기)
#
# 텔레그램 실시간 중계: 상태 전이마다 tg_send() 호출
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# 파일 경로 추출
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

# debate 관련 파일이 아니면 즉시 통과
case "$FILE_PATH" in
  *s0_debate_r1_*.json) DTYPE="R1" ;;
  *s0_debate_r2_*.json) DTYPE="R2" ;;
  *s0_debate_r3_*.json) DTYPE="R3" ;;
  *S0_VERDICT*.json)    DTYPE="VERDICT" ;;
  *s0_debate_transcript*.json) DTYPE="TRANSCRIPT" ;;
  *) echo '{}'; exit 0 ;;
esac

LOG="/tmp/s0_debate_enforcer.log"
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")

# Write의 content 추출
CONTENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('content', ''))
" 2>/dev/null || echo "")

# hypothesis_id 추출 (파일명에서 — H_1643_REVISED, H_SMOKE_v55 같은 형태 모두 포함)
HYP_ID=$(basename "$FILE_PATH" | python3 -c "
import sys, re
name = sys.stdin.read().strip()
# s0_debate_r1_risk_manager_H_1643_REVISED.json → H_1643_REVISED
# s0_debate_r2_academic_H_SMOKE_v55.json → H_SMOKE_v55
# S0_VERDICT_H_1643.json → H_1643
# .json 확장자 제거 후 마지막 H_[A-Za-z0-9]+... 패턴 추출 (숫자/문자 모두 허용)
name_no_ext = name.rsplit('.', 1)[0]
m = re.search(r'(H_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*)\s*$', name_no_ext)
print(m.group(1) if m else 'unknown')
" 2>/dev/null || echo "unknown")

STATE_FILE="/tmp/s0_debate_state_${HYP_ID}.json"

# ─── 상태 읽기 ───
read_state() {
  if [ -f "$STATE_FILE" ]; then
    python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
print(d.get('state', 'IDLE'))
" 2>/dev/null || echo "IDLE"
  else
    echo "IDLE"
  fi
}

# ─── 상태 쓰기 ───
write_state() {
  local new_state="$1"
  local extra="${2:-}"
  python3 -c "
import json, os
state_file = '$STATE_FILE'
if os.path.exists(state_file):
    with open(state_file) as f: d = json.load(f)
else:
    d = {'hypothesis_id': '$HYP_ID', 'r1_roles': [], 'r2_roles': [], 'r3_roles': []}
d['state'] = '$new_state'
if '$extra':
    import ast
    try: d.update(ast.literal_eval('$extra'))
    except: pass
with open(state_file, 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null
}

# ─── 역할 추적 ───
add_role() {
  local round="$1"
  local role="$2"
  python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
key = '${round}_roles'
if key not in d: d[key] = []
if '$role' not in d[key]:
    d[key].append('$role')
with open('$STATE_FILE', 'w') as f: json.dump(d, f, indent=2)
print(len(d[key]))
" 2>/dev/null
}

# ─── 텔레그램 발송 (백그라운드, non-blocking, 4096자 분할) ───
# .env에서 토큰/chat_id 로드 (hardcoded 금지 — 2026-04-17 rotation 이후)
if [ -f "$DIR/.env" ]; then
  set -a; source "$DIR/.env" 2>/dev/null; set +a
fi
: "${TG_BOT_TOKEN:=}"
: "${TG_CHAT_ID:=}"

tg_notify() {
  local msg="$1"
  [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
  (
    # 4096자 제한: 길면 분할
    local len=${#msg}
    if [ "$len" -le 4000 ]; then
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=" \
        --data-urlencode "text=$msg" > /dev/null 2>&1
    else
      # 앞 3900자 + "...(계속)" / 나머지
      local part1="${msg:0:3900}
...(계속)"
      local part2="(이어서)
${msg:3900}"
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=" \
        --data-urlencode "text=$part1" > /dev/null 2>&1
      sleep 1
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=" \
        --data-urlencode "text=$part2" > /dev/null 2>&1
    fi
  ) &
}

# ─── 텔레그램 가독성 helper (B안+이모지) ───
role_icon() {
  case "$1" in
    risk_manager) printf "🎯" ;;
    governor)     printf "🏛️" ;;
    quant)        printf "📐" ;;
    academic)     printf "📖" ;;
    codex_critic) printf "🤖" ;;
    *)            printf "👤" ;;
  esac
}

delta_icon() {
  local d="$1"
  if [ -z "$d" ] || ! [ "$d" -eq "$d" ] 2>/dev/null; then
    printf "•"
  elif [ "$d" -gt 0 ] 2>/dev/null; then
    printf "⬆️"
  elif [ "$d" -lt 0 ] 2>/dev/null; then
    printf "⬇️"
  else
    printf "➡️"
  fi
}

progress_bar() {
  local n="$1"
  local total=5
  local bar=""
  local i=1
  while [ "$i" -le "$total" ]; do
    if [ "$i" -le "$n" ]; then
      bar="${bar}▰"
    else
      bar="${bar}░"
    fi
    i=$((i+1))
  done
  printf "%s" "$bar"
}

verdict_icon() {
  case "$1" in
    APPROVE)             printf "✅" ;;
    APPROVE_CONDITIONAL) printf "🟡" ;;
    REVISE)              printf "🔄" ;;
    REJECT)              printf "❌" ;;
    *)                   printf "⚖️" ;;
  esac
}

# v55: stance 아이콘 (R1/R2/Verdict 텔레그램용)
stance_icon() {
  case "$1" in
    APPROVE)             printf "✅" ;;
    APPROVE_CONDITIONAL) printf "🟡" ;;
    REVISE)              printf "🔄" ;;
    REJECT)              printf "❌" ;;
    *)                   printf "❔" ;;
  esac
}

# v55: stance 변동 아이콘
stance_change_icon() {
  case "$1" in
    UPGRADED)   printf "⬆️" ;;
    DOWNGRADED) printf "⬇️" ;;
    UNCHANGED)  printf "➡️" ;;
    *)          printf "•" ;;
  esac
}

# ─── R1 제출 처리 ───
if [ "$DTYPE" = "R1" ]; then
  CUR_STATE=$(read_state)

  # R1은 IDLE 또는 R1_IN_PROGRESS에서만 허용
  case "$CUR_STATE" in
    IDLE|R1_IN_PROGRESS) ;;
    *)
      echo "$(date +%H:%M:%S) ENFORCER BLOCK: R1 Write in state $CUR_STATE" >> "$LOG"
      printf '{"decision":"block","reason":"[S0 Debate Enforcer] 현재 상태 %s에서 R1 Write 불가. 새 토론은 기존 토론 완료 후 시작하세요."}' "$CUR_STATE"
      exit 0
      ;;
  esac

  # content 검증 (v55 strict): stance 필수, supporting+critical 합산 1건+, veto_flag 키 존재
  VALIDATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    role = d.get('role', 'unknown')
    stance = str(d.get('stance', '')).upper()
    veto = d.get('veto_flag', 'MISSING')  # 명시적 null과 키 누락 구분
    crit = d.get('critical_concerns', []) or []
    sup = d.get('supporting_arguments', []) or []
    valid_stances = {'APPROVE','APPROVE_CONDITIONAL','REVISE','REJECT'}

    errors = []
    if stance not in valid_stances:
        errors.append(f\"stance='{stance}' 누락/비정상 (APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT 중 하나 필수)\")
    if veto == 'MISSING':
        errors.append('veto_flag 키 누락 (null이라도 명시 필수)')
    if len(crit) + len(sup) < 1:
        errors.append('critical_concerns + supporting_arguments 합산 0건 (1건+ 필수)')

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        veto_disp = 'null' if veto in (None, 'null', '') else str(veto)
        print(f'PASS|{role}|{stance}|{veto_disp}|{len(crit)}|{len(sup)}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK R1: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer v55] R1 검증 실패: %s\\n\\nv55 R1 스키마: {role, stance, critical_concerns[], supporting_arguments[], veto_flag, s1_gate_items[]}\\n점수제(score) 폐기됨. SKILL.md Round 1 출력 스키마 참조."}' "$V_REASON"
    exit 0
  fi

  # 역할/stance/veto 추출 (PASS|role|stance|veto|n_crit|n_sup)
  ROLE=$(echo "$VALIDATION" | cut -d'|' -f2)
  STANCE=$(echo "$VALIDATION" | cut -d'|' -f3)
  VETO=$(echo "$VALIDATION" | cut -d'|' -f4)

  # 상태 전이
  if [ "$CUR_STATE" = "IDLE" ]; then
    write_state "R1_IN_PROGRESS"
  fi

  N_ROLES=$(add_role "r1" "$ROLE")

  # 텔레그램 중계 (v55) — 역할 아이콘 + stance + veto + 진행률 bar
  DEBATE_MODE="${QVEST_DEBATE_MODE:-full}"
  if [ "$DEBATE_MODE" = "compact" ]; then R1_TOTAL_EXPECTED=3; else R1_TOTAL_EXPECTED=5; fi
  RICON=$(role_icon "$ROLE")
  SICON=$(stance_icon "$STANCE")
  PBAR=$(progress_bar "$N_ROLES")
  VETO_DISP=""
  [ "$VETO" != "null" ] && [ -n "$VETO" ] && VETO_DISP="  🚫${VETO}"
  tg_notify "🎙 [S0 · $HYP_ID · R1]  ${RICON} ${ROLE}  ${SICON} ${STANCE}${VETO_DISP}   ${PBAR} (${N_ROLES}/${R1_TOTAL_EXPECTED})"

  echo "$(date +%H:%M:%S) ENFORCER R1: $ROLE [$STANCE veto=$VETO] [$N_ROLES/${R1_TOTAL_EXPECTED}]" >> "$LOG"

  # ─── Compact mode 감지 ───
  DEBATE_MODE="${QVEST_DEBATE_MODE:-full}"
  if [ "$DEBATE_MODE" = "compact" ]; then
    R1_THRESHOLD=3
  else
    R1_THRESHOLD=5
  fi

  # N/N 완료 시 R1_COMPLETE 전이 (compact=3, full=5)
  if [ "$N_ROLES" = "$R1_THRESHOLD" ]; then
    write_state "R1_COMPLETE"

    # ─── Block E (2026-04-19, v55): R1 요약본 생성 (R2 토큰 절감) ───────────
    # R2 에이전트가 R1 전체 transcript 대신 요약본(~500T)만 읽음.
    # 원본 transcript는 stage_artifacts/s0_debate_transcript_{HYP_ID}.json에 보존.
    R1_SUMMARY_FILE="/tmp/s0_debate_r1_summary_${HYP_ID}.md"
    python3 -c "
import json, glob, os
def clip(s, n=120):
    s = str(s).strip().replace('\n',' ')
    return s if len(s)<=n else s[:n-3]+'...'
artifacts_dir = os.path.dirname('$FILE_PATH') or 'stage_artifacts'
lines = ['# R1 요약본 — ${HYP_ID} (R2 Rebuttal용, v55)',
         '',
         '> Full transcript: stage_artifacts/s0_debate_transcript_${HYP_ID}.json',
         '> 토큰 절감을 위해 stance/veto/핵심 논거만 압축. 점수 없음 (v55).',
         '']
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r1_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        stance = str(d.get('stance', '?')).upper()
        veto = d.get('veto_flag', None)
        veto_disp = 'null' if veto in (None,'null','') else str(veto)
        concerns = d.get('critical_concerns', []) or []
        supports = d.get('supporting_arguments', []) or []
        gate_items = d.get('s1_gate_items', []) or []
        lines.append(f'## {role}  [stance={stance}, veto={veto_disp}]')
        if concerns:
            lines.append('**critical_concerns:**')
            for c in concerns[:2]:
                lines.append(f'- {clip(c)}')
        if supports:
            lines.append('**supporting_arguments:**')
            for s in supports[:2]:
                lines.append(f'- {clip(s)}')
        if gate_items:
            lines.append('**s1_gate_items:**')
            for g in gate_items[:2]:
                lines.append(f'- {clip(g)}')
        lines.append('')
    except Exception as e: pass
open('$R1_SUMMARY_FILE','w').write('\n'.join(lines))
" 2>/dev/null || echo "R1 summary 생성 실패" > "$R1_SUMMARY_FILE"

    # R1 전원 의견 요약 발송 (v55) — 역할 아이콘 + stance + veto + critical_concerns
    R1_SUMMARY=$(python3 -c "
import json, glob, os
def clip(s, n=110):
    s = str(s).strip().replace('\n',' ')
    return s if len(s)<=n else s[:n-3]+'...'
ICONS = {'risk_manager':'🎯','governor':'🏛️','quant':'📐','academic':'📖','codex_critic':'🤖','judge':'⚖️'}
SICONS = {'APPROVE':'✅','APPROVE_CONDITIONAL':'🟡','REVISE':'🔄','REJECT':'❌'}
lines = ['📋 [S0 Debate · $HYP_ID] R1 Opening Complete',
         '━━━━━━━━━━━━━━━━━━━━━━━━']
tally = {'APPROVE':0,'APPROVE_CONDITIONAL':0,'REVISE':0,'REJECT':0}
veto_count = 0
artifacts_dir = os.path.dirname('$FILE_PATH') or 'stage_artifacts'
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r1_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        ricon = ICONS.get(role, '👤')
        stance = str(d.get('stance', '?')).upper()
        sicon = SICONS.get(stance, '❔')
        veto = d.get('veto_flag')
        tally[stance] = tally.get(stance, 0) + 1
        # codex veto는 집계 제외 (권한 없음)
        if veto and str(veto).lower() not in ('null','none','') and 'codex' not in role.lower():
            veto_count += 1
        veto_disp = f'  🚫{veto}' if veto and str(veto).lower() not in ('null','none','') else ''
        crit = (d.get('critical_concerns') or [])
        lines.append(f'{ricon} {role}  {sicon} {stance}{veto_disp}')
        if crit:
            lines.append(f'   💭 {clip(crit[0])}')
    except: pass
lines.append('━━━━━━━━━━━━━━━━━━━━━━━━')
lines.append(f\"📊 R1 tally: ✅{tally['APPROVE']} 🟡{tally['APPROVE_CONDITIONAL']} 🔄{tally['REVISE']} ❌{tally['REJECT']}  veto={veto_count}\")
lines.append('💬 R2 Rebuttal 시작...')
print('\n'.join(lines))
" 2>/dev/null || echo "📋 R1 Complete [$HYP_ID]")
    tg_notify "$R1_SUMMARY"

    echo "$(date +%H:%M:%S) ENFORCER: R1 COMPLETE → R2 시작 지시 (mode=${DEBATE_MODE})" >> "$LOG"

    # ─── Compact mode: academic_factcheck + quant_factcheck 자동 트리거 ───
    if [ "$DEBATE_MODE" = "compact" ]; then
      # s0_record에서 scout plan 찾기
      ARTIFACTS_DIR=$(dirname "$FILE_PATH" 2>/dev/null || echo "$DIR/stage_artifacts")
      S0_RECORD=$(ls "$ARTIFACTS_DIR"/s0_record_*${HYP_ID}*.json 2>/dev/null | head -1)
      if [ -n "$S0_RECORD" ] && [ -f "$S0_RECORD" ]; then
        (
          HYP_ID="$HYP_ID" nohup bash "$DIR/02_Infrastructure/hooks/academic_factcheck.sh" \
            "$S0_RECORD" > /dev/null 2>>/tmp/academic_factcheck_${HYP_ID}.log
        ) &
        (
          HYP_ID="$HYP_ID" FC_CONTENT="$(cat "$S0_RECORD")" \
            nohup bash "$DIR/02_Infrastructure/hooks/quant_factcheck.sh" \
            "$S0_RECORD" > /dev/null 2>>/tmp/quant_factcheck_${HYP_ID}.log
        ) &
        echo "$(date +%H:%M:%S) ENFORCER: Compact factcheck hooks triggered for $HYP_ID" >> "$LOG"
      else
        echo "$(date +%H:%M:%S) ENFORCER WARN: s0_record not found for $HYP_ID factcheck" >> "$LOG"
      fi
    fi

    # ─── v53 S2.13: Codex R2 Verify 자동 트리거 ───────────────────────────
    # Codex R2 결과가 이미 있으면 skip. 없으면 background 스폰.
    CODEX_R2_OUT="$DIR/stage_artifacts/r2_codex_verdict_${HYP_ID}.json"
    if [ ! -f "$CODEX_R2_OUT" ]; then
      ARTIFACTS_DIR=$(dirname "$FILE_PATH" 2>/dev/null || echo "$DIR/stage_artifacts")
      CODEX_R1_FILE=$(ls "$ARTIFACTS_DIR"/s0_debate_r1_codex_critic_${HYP_ID}.json 2>/dev/null | head -1)
      TRANSCRIPT_FILE="$ARTIFACTS_DIR/s0_debate_transcript_${HYP_ID}.json"
      CODEX_R1_JSON="$([ -f "$CODEX_R1_FILE" ] && cat "$CODEX_R1_FILE" || echo 'NO_R1')"
      TRANSCRIPT_JSON=""
      if [ -f "$TRANSCRIPT_FILE" ]; then
        TRANSCRIPT_JSON=$(cat "$TRANSCRIPT_FILE")
      else
        # Transcript 미생성 시 R1 파일 병합
        TRANSCRIPT_JSON=$(python3 -c "
import json, glob, os
out = {'hypothesis_id': '$HYP_ID', 'round': 'R1', 'debaters': []}
for f in sorted(glob.glob(os.path.join('$ARTIFACTS_DIR', 's0_debate_r1_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: out['debaters'].append(json.load(fh))
    except: pass
print(json.dumps(out, ensure_ascii=False))
" 2>/dev/null)
      fi

      (
        R1_TRANSCRIPT="$TRANSCRIPT_JSON" \
        CODEX_R1_RESULT="$CODEX_R1_JSON" \
        HYP_ID="$HYP_ID" \
        bash "$DIR/02_Infrastructure/hooks/run_codex_critic_r2.sh" \
          > "$CODEX_R2_OUT.tmp" 2>>"$LOG"
        if [ -s "$CODEX_R2_OUT.tmp" ]; then
          mv "$CODEX_R2_OUT.tmp" "$CODEX_R2_OUT"
          echo "$(date +%H:%M:%S) CODEX_R2: ${HYP_ID} → $CODEX_R2_OUT" >> "$LOG"
        else
          rm -f "$CODEX_R2_OUT.tmp"
        fi
      ) &
    fi

    # Q-Lead에 R2 시작 지시 주입
    if [ "$DEBATE_MODE" = "compact" ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R1 3/3 Compact 완료. 다음 단계:\\n1. 3개 R1 결과를 stage_artifacts/s0_debate_transcript_%s.json으로 컴파일\\n2. R2 Rebuttal: 3인 재스폰 (R1 요약본 프롬프트에 주입)\\n3. R2 필수: 동의 1건+ / 반박 1건+ / 점수수정시 이유\\n4. academic_factcheck + quant_factcheck → background 실행 중\\n\\n[S2.13] Codex R2 Verify background 실행 중."}}' "$HYP_ID"
    else
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R1 5/5 완료. 다음 단계:\\n1. 5개 R1 결과를 stage_artifacts/s0_debate_transcript_%s.json으로 컴파일\\n2. R2 Rebuttal: 5인 재스폰 (transcript 전문 프롬프트에 주입)\\n3. R2 필수: 동의 1건+ / 반박 1건+ / 점수수정시 이유 / 최강 반론 지목\\n\\n[S2.13] Codex R2 Verify는 background로 실행 중 — stage_artifacts/r2_codex_verdict_%s.json 생성 확인 후 VERDICT 작성 시 참고하세요."}}' "$HYP_ID" "$HYP_ID"
    fi
    exit 0
  fi

  echo '{}'
  exit 0
fi

# ─── Transcript 허용 (검증 없이 통과) ───
if [ "$DTYPE" = "TRANSCRIPT" ]; then
  echo '{}'
  exit 0
fi

# ─── R2 제출 처리 ───
if [ "$DTYPE" = "R2" ]; then
  CUR_STATE=$(read_state)

  # R2는 R1_COMPLETE 또는 R2_IN_PROGRESS에서만 허용
  case "$CUR_STATE" in
    R1_COMPLETE|R2_IN_PROGRESS) ;;
    *)
      echo "$(date +%H:%M:%S) ENFORCER BLOCK: R2 Write in state $CUR_STATE" >> "$LOG"
      GUIDE=""
      [ "$CUR_STATE" = "IDLE" ] || [ "$CUR_STATE" = "R1_IN_PROGRESS" ] && GUIDE=" R1이 아직 5/5 완료되지 않았습니다."
      printf '{"decision":"block","reason":"[S0 Debate Enforcer] R1 미완료 상태(%s)에서 R2 Write 불가.%s"}' "$CUR_STATE" "$GUIDE"
      exit 0
      ;;
  esac

  # content 검증 (v55 strict): stance_change/new_stance/unresolved/veto_flag
  VALIDATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    errors = []
    role = d.get('role', 'unknown')
    r1_stance = str(d.get('r1_stance', '')).upper()
    stance_change = str(d.get('stance_change', '')).upper()
    new_stance = str(d.get('new_stance', '')).upper()
    veto_flag = d.get('veto_flag', 'MISSING')
    r1_veto = d.get('r1_veto_flag', d.get('veto_flag_r1'))
    unresolved = d.get('unresolved', [])
    addressed = d.get('addressed_concerns', [])
    reason = d.get('stance_change_reason', '') or ''

    valid_changes = {'UNCHANGED','UPGRADED','DOWNGRADED'}
    valid_stances = {'APPROVE','APPROVE_CONDITIONAL','REVISE','REJECT'}

    if stance_change not in valid_changes:
        errors.append(f\"stance_change='{stance_change}' 누락/비정상 (UNCHANGED/UPGRADED/DOWNGRADED 필수)\")
    if new_stance not in valid_stances:
        errors.append(f\"new_stance='{new_stance}' 누락/비정상 (APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT 필수)\")
    if veto_flag == 'MISSING':
        errors.append('veto_flag 키 누락 (null이라도 명시 필수)')
    if len(unresolved) < 1:
        errors.append('unresolved 0건 — 최소 1건 필수 (토론 없는 R2 = 반복)')
    if stance_change != 'UNCHANGED' and len(reason) < 50:
        errors.append(f'stance_change={stance_change}인데 stance_change_reason 50자 미만 ({len(reason)}자)')

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        # veto 변동 여부
        r1v = str(r1_veto).lower() not in ('','none','null','false','missing')
        r2v = str(veto_flag).lower() not in ('','none','null','false','missing')
        veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(veto_flag).lower())
        veto_disp = 'null' if veto_flag in (None,'null','') else str(veto_flag)
        un_summary = unresolved[0].get('point', unresolved[0]) if unresolved else ''
        if isinstance(un_summary, dict):
            un_summary = str(un_summary)
        print(f'PASS|{role}|{r1_stance}|{new_stance}|{stance_change}|{veto_disp}|{int(veto_changed)}|{str(un_summary)[:80]}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK R2: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer v55] R2 검증 실패: %s\\n\\nv55 R2 스키마: {role, r1_stance, stance_change, new_stance, stance_change_reason, veto_flag, r1_veto_flag, addressed_concerns[], unresolved[]}\\n점수제(r1_score/r2_score) 폐기. SKILL.md Round 2 출력 스키마 참조."}' "$V_REASON"
    exit 0
  fi

  # 역할/stance 변동 추출 (PASS|role|r1_stance|new_stance|stance_change|veto|veto_changed|unresolved)
  ROLE=$(echo "$VALIDATION" | cut -d'|' -f2)
  R1_ST=$(echo "$VALIDATION" | cut -d'|' -f3)
  R2_ST=$(echo "$VALIDATION" | cut -d'|' -f4)
  STANCE_CHANGE=$(echo "$VALIDATION" | cut -d'|' -f5)
  VETO=$(echo "$VALIDATION" | cut -d'|' -f6)
  VETO_CHANGED=$(echo "$VALIDATION" | cut -d'|' -f7)

  # 상태 전이
  if [ "$CUR_STATE" = "R1_COMPLETE" ]; then
    write_state "R2_IN_PROGRESS"
  fi

  N_ROLES=$(add_role "r2" "$ROLE")

  # ─── Compact mode 감지 (R2) ───
  DEBATE_MODE="${QVEST_DEBATE_MODE:-full}"
  if [ "$DEBATE_MODE" = "compact" ]; then R2_THRESHOLD=3; else R2_THRESHOLD=5; fi

  # 텔레그램 중계 (v55) — 역할 + stance 변동 화살표 + new_stance + veto + 진행률
  RICON=$(role_icon "$ROLE")
  CICON=$(stance_change_icon "$STANCE_CHANGE")
  R1_SI=$(stance_icon "$R1_ST")
  R2_SI=$(stance_icon "$R2_ST")
  PBAR=$(progress_bar "$N_ROLES")
  VETO_DISP=""
  [ "$VETO" != "null" ] && [ -n "$VETO" ] && VETO_DISP="  🚫${VETO}"
  [ "$VETO_CHANGED" = "1" ] && VETO_DISP="${VETO_DISP} ⚠️veto변동"
  tg_notify "🔥 [S0 · $HYP_ID · R2]  ${RICON} ${ROLE}  ${R1_SI}${R1_ST} ${CICON} ${R2_SI}${R2_ST}${VETO_DISP}   ${PBAR} (${N_ROLES}/${R2_THRESHOLD})"

  echo "$(date +%H:%M:%S) ENFORCER R2: $ROLE [$R1_ST→$R2_ST $STANCE_CHANGE veto=$VETO veto_changed=$VETO_CHANGED] [$N_ROLES/${R2_THRESHOLD}] mode=$DEBATE_MODE" >> "$LOG"

  # N/N 완료 시 R2_COMPLETE 전이 + R3 필요 여부 판단
  if [ "$N_ROLES" = "$R2_THRESHOLD" ]; then

    # ─── v55 R3 트리거: stance_change != UNCHANGED OR veto 변동 ───
    # Compact mode: stance 만장일치 + veto 변동 0 → SKIP_R3 (consensus_tier=strong)
    # Full mode: stance_change != UNCHANGED 또는 veto 변동 있는 role 재소환
    R3_DECISION=$(python3 -c "
import json, glob, os
artifacts_dir = os.path.dirname('$FILE_PATH') or '.'
mode = '$DEBATE_MODE'
new_stances = []
need_r3_roles = []
any_veto_change = False
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r2_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        stance_change = str(d.get('stance_change', '')).upper()
        new_stance = str(d.get('new_stance', d.get('stance', ''))).upper()
        r1_veto = d.get('r1_veto_flag') or d.get('veto_flag_r1')
        r2_veto = d.get('veto_flag')
        r1v = str(r1_veto).lower() not in ('','none','null','false')
        r2v = str(r2_veto).lower() not in ('','none','null','false')
        veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(r2_veto).lower())
        new_stances.append(new_stance)
        if veto_changed:
            any_veto_change = True
        # 재소환 대상: stance 변동 OR veto 변동
        if stance_change != 'UNCHANGED' or veto_changed:
            need_r3_roles.append(role)
    except: pass

unique_stances = set(s for s in new_stances if s)
# Compact mode SKIP 조건: stance 만장일치 + veto 변동 0 + 3인 모두 응답
if mode == 'compact' and len(unique_stances) == 1 and not any_veto_change and len(new_stances) >= 3:
    print(f'SKIP_R3|{list(unique_stances)[0]}|strong|')
elif not need_r3_roles:
    # 전원 UNCHANGED + veto 변동 0 (Full mode 포함)
    tier = 'strong' if len(unique_stances) == 1 else 'mixed'
    one = list(unique_stances)[0] if len(unique_stances) == 1 else 'mixed'
    print(f'SKIP_R3|{one}|{tier}|')
else:
    print(f'NEED_R3|mixed|mixed|{\",\".join(need_r3_roles)}')
" 2>/dev/null || echo "NEED_R3|unknown|error|")

    R3_DECISION_TAG=$(echo "$R3_DECISION" | cut -d'|' -f1)
    COMPACT_STANCE=$(echo "$R3_DECISION" | cut -d'|' -f2)
    COMPACT_TIER=$(echo "$R3_DECISION" | cut -d'|' -f3)
    R3_NEEDED_ROLES=$(echo "$R3_DECISION" | cut -d'|' -f4)
    R3_CHECK="${R3_NEEDED_ROLES:-NONE}"
    [ -z "$R3_CHECK" ] && R3_CHECK="NONE"

    SKIP_R3=0
    if [ "$R3_DECISION_TAG" = "SKIP_R3" ]; then
      SKIP_R3=1
      echo "$(date +%H:%M:%S) ENFORCER v55: R3 SKIP (mode=$DEBATE_MODE, stance=$COMPACT_STANCE, tier=$COMPACT_TIER)" >> "$LOG"
    else
      echo "$(date +%H:%M:%S) ENFORCER v55: R3 NEEDED roles=$R3_NEEDED_ROLES" >> "$LOG"
    fi

    if [ "$SKIP_R3" -eq 1 ]; then
      write_state "VERDICT_READY"

      # R2 전원 의견 변동 요약 발송 (v55) — stance 변동 + veto + unresolved
      R2_SUMMARY=$(python3 -c "
import json, glob, os
def clip(s, n=100):
    s = str(s).strip().replace('\n',' ')
    return s if len(s)<=n else s[:n-3]+'...'
ICONS = {'risk_manager':'🎯','governor':'🏛️','quant':'📐','academic':'📖','codex_critic':'🤖','judge':'⚖️'}
SICONS = {'APPROVE':'✅','APPROVE_CONDITIONAL':'🟡','REVISE':'🔄','REJECT':'❌'}
CICONS = {'UPGRADED':'⬆️','DOWNGRADED':'⬇️','UNCHANGED':'➡️'}
lines = ['📊 [S0 Debate · $HYP_ID] R2 Rebuttal Complete',
         '━━━━━━━━━━━━━━━━━━━━━━━━']
artifacts_dir = os.path.dirname('$FILE_PATH') or 'stage_artifacts'
tally = {'APPROVE':0,'APPROVE_CONDITIONAL':0,'REVISE':0,'REJECT':0}
veto_count = 0
veto_list = []
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r2_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        ricon = ICONS.get(role, '👤')
        r1_st = str(d.get('r1_stance','')).upper()
        new_st = str(d.get('new_stance', d.get('stance',''))).upper()
        sc = str(d.get('stance_change','UNCHANGED')).upper()
        cicon = CICONS.get(sc, '•')
        r1_si = SICONS.get(r1_st, '❔')
        new_si = SICONS.get(new_st, '❔')
        tally[new_st] = tally.get(new_st, 0) + 1
        veto = d.get('veto_flag')
        if veto and str(veto).lower() not in ('null','none','') and 'codex' not in role.lower():
            veto_count += 1
            veto_list.append(f'{role}={veto}')
        veto_disp = f'  🚫{veto}' if veto and str(veto).lower() not in ('null','none','') else ''
        unr = (d.get('unresolved') or [])
        unr_txt = ''
        if unr:
            first = unr[0]
            if isinstance(first, dict):
                unr_txt = clip(first.get('point',''))
            else:
                unr_txt = clip(str(first))
        lines.append(f'{ricon} {role}  {r1_si}{r1_st} {cicon} {new_si}{new_st}{veto_disp}')
        if unr_txt:
            lines.append(f'   ❓ {unr_txt}')
    except: pass
lines.append('━━━━━━━━━━━━━━━━━━━━━━━━')
lines.append(f\"📊 R2 tally: ✅{tally['APPROVE']} 🟡{tally['APPROVE_CONDITIONAL']} 🔄{tally['REVISE']} ❌{tally['REJECT']}  veto={veto_count}\")
if veto_list:
    lines.append('🚫 ' + '; '.join(veto_list[:3]))
lines.append('⚖️ VERDICT 작성 가능')
print('\n'.join(lines))
" 2>/dev/null || echo "📊 R2 Complete [$HYP_ID]")
      tg_notify "$R2_SUMMARY"

      if [ "$DEBATE_MODE" = "compact" ]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer v55] R2 3/3 Compact 완료. stance 만장일치(%s) + veto 무변동 → R3 생략 (consensus_tier: %s).\\nVERDICT를 v55 스키마로 작성하세요:\\n- transcript.rounds (R1, R2 2라운드+)\\n- final_stances (각 role별 r1/final/stance_change/veto_flag)\\n- consensus_tally (approve/approve_conditional/revise/reject/veto_count, 합 = 3)\\n- consensus_tier (UNANIMOUS/MAJORITY/MINORITY/DEADLOCK)\\n- consensus_points + unresolved_disputes\\n- debaters 배열 (3건)\\n- 점수(total_score/final_scores) 폐기"}}' "$COMPACT_STANCE" "$COMPACT_TIER"
      else
        printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer v55] R2 %s/%s 완료. 전원 stance UNCHANGED + veto 변동 0 → R3 불필요.\\nVERDICT를 v55 스키마로 작성하세요:\\n- transcript.rounds (R1, R2 2라운드+)\\n- final_stances (각 role별 r1/final/stance_change/veto_flag)\\n- consensus_tally (합 = %s)\\n- consensus_tier\\n- consensus_points + unresolved_disputes\\n- debaters 배열 (%s건)\\n- 점수제 폐기"}}' "$R2_THRESHOLD" "$R2_THRESHOLD" "$R2_THRESHOLD" "$R2_THRESHOLD"
      fi
    else
      write_state "R3_NEEDED"
      tg_notify "$(printf '🔄 [S0 Debate v55] %s — R3 필요\n\nstance/veto 변동 role: %s\nR3 Closing 재소환 후 최종 확정.' "$HYP_ID" "$R3_CHECK")"

      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer v55] R2 %s/%s 완료. stance_change != UNCHANGED 또는 veto 변동 발생 role: %s\\nR3 Closing: 해당 role만 재소환하여 final_stance + final_veto_flag + closing_statement(150자+) 확정.\\n출력: stage_artifacts/s0_debate_r3_{role}_%s.json"}}' "$R2_THRESHOLD" "$R2_THRESHOLD" "$R3_CHECK" "$HYP_ID"
    fi
    exit 0
  fi

  echo '{}'
  exit 0
fi

# ─── R3 제출 처리 ───
if [ "$DTYPE" = "R3" ]; then
  CUR_STATE=$(read_state)
  if [ "$CUR_STATE" != "R3_NEEDED" ]; then
    printf '{"decision":"block","reason":"[S0 Debate Enforcer] R3는 R3_NEEDED 상태에서만 허용. 현재: %s"}' "$CUR_STATE"
    exit 0
  fi

  ROLE=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('role', 'unknown'))
" 2>/dev/null || echo "unknown")

  add_role "r3" "$ROLE" > /dev/null 2>&1

  # R3 필요 에이전트 모두 완료 시 VERDICT_READY
  R3_DONE=$(python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
print(len(d.get('r3_roles', [])))
" 2>/dev/null || echo "0")

  tg_notify "$(printf '🔄 [S0 Debate] %s — R3 %s 최종 확정' "$HYP_ID" "$ROLE")"

  # R3 대상 에이전트: R2에서 |delta|>4인 에이전트 목록을 상태 파일에서 읽음
  # r3_needed_roles가 없으면 r2 파일에서 재계산
  R3_NEEDED_COUNT=$(python3 -c "
import json, glob, os
state_file = '$STATE_FILE'
with open(state_file) as f: d = json.load(f)

# r3_needed_roles가 이미 저장된 경우
if 'r3_needed_roles' in d:
    needed = d['r3_needed_roles']
    r3_done = d.get('r3_roles', [])
    # 남은 대상 수 출력
    remaining = [r for r in needed if r not in r3_done]
    print(len(remaining))
else:
    # v55: r2 파일에서 stance_change != UNCHANGED OR veto 변동인 에이전트 재계산
    artifacts_dir = os.path.dirname('$FILE_PATH') or '.'
    needed = []
    for f in glob.glob(os.path.join(artifacts_dir, 's0_debate_r2_*_${HYP_ID}.json')):
        try:
            with open(f) as fh: dd = json.load(fh)
            stance_change = str(dd.get('stance_change','')).upper()
            r1_veto = dd.get('r1_veto_flag') or dd.get('veto_flag_r1')
            r2_veto = dd.get('veto_flag')
            r1v = str(r1_veto).lower() not in ('','none','null','false')
            r2v = str(r2_veto).lower() not in ('','none','null','false')
            veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(r2_veto).lower())
            if stance_change != 'UNCHANGED' or veto_changed:
                needed.append(dd.get('role', '?'))
        except: pass
    d['r3_needed_roles'] = needed
    r3_done = d.get('r3_roles', [])
    remaining = [r for r in needed if r not in r3_done]
    with open(state_file, 'w') as fw: json.dump(d, fw, indent=2)
    print(len(remaining))
" 2>/dev/null || echo "1")

  echo "$(date +%H:%M:%S) ENFORCER R3: $ROLE 제출, 남은 대상 수=$R3_NEEDED_COUNT" >> "$LOG"

  # 아직 R3 미제출 대상이 있으면 R3_NEEDED 유지
  if [ "$R3_NEEDED_COUNT" -gt "0" ] 2>/dev/null; then
    write_state "R3_NEEDED"
    echo "$(date +%H:%M:%S) ENFORCER R3: R3_NEEDED 유지 (남은 $R3_NEEDED_COUNT 인)" >> "$LOG"
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R3 %s 완료. 아직 %s명 R3 미제출. R3_NEEDED 상태 유지."}}' "$ROLE" "$R3_NEEDED_COUNT"
  else
    # 전원 완료 시 VERDICT_READY
    write_state "VERDICT_READY"
    echo "$(date +%H:%M:%S) ENFORCER R3: 전원 완료 → VERDICT_READY" >> "$LOG"
    tg_notify "$(printf '✅ [S0 Debate] %s — R3 전원 완료\n⚖️ VERDICT 작성 가능' "$HYP_ID")"
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R3 전원 완료. VERDICT 작성하세요."}}'
  fi
  exit 0
fi

# ─── VERDICT 처리 ───
if [ "$DTYPE" = "VERDICT" ]; then
  CUR_STATE=$(read_state)

  # VERDICT는 VERDICT_READY에서만 허용
  if [ "$CUR_STATE" != "VERDICT_READY" ] && [ "$CUR_STATE" != "DONE" ]; then
    echo "$(date +%H:%M:%S) ENFORCER BLOCK VERDICT: state=$CUR_STATE" >> "$LOG"

    GUIDE="R2까지 완료해야 VERDICT 작성 가능합니다."
    [ "$CUR_STATE" = "IDLE" ] && GUIDE="토론이 시작되지 않았습니다. /s0-debate로 R1부터 시작하세요."
    [ "$CUR_STATE" = "R1_IN_PROGRESS" ] && GUIDE="R1이 아직 진행 중입니다 (5/5 미완료)."
    [ "$CUR_STATE" = "R1_COMPLETE" ] && GUIDE="R2 Rebuttal이 아직 실행되지 않았습니다."
    [ "$CUR_STATE" = "R2_IN_PROGRESS" ] && GUIDE="R2가 아직 진행 중입니다 (5/5 미완료)."
    [ "$CUR_STATE" = "R3_NEEDED" ] && GUIDE="R3 Closing이 필요한 에이전트가 있습니다."

    printf '{"decision":"block","reason":"[S0 Debate Enforcer] 토론 미완료 상태(%s)에서 VERDICT 작성 불가. %s"}' "$CUR_STATE" "$GUIDE"
    exit 0
  fi

  # ─── v53 S2.13: Codex R2 Verify 산출물 필수 (skip 허용: QVEST_SKIP_CODEX_R2=1) ───
  CODEX_R2_PATH="$DIR/stage_artifacts/r2_codex_verdict_${HYP_ID}.json"
  if [ ! -f "$CODEX_R2_PATH" ] && [ "${QVEST_SKIP_CODEX_R2:-0}" != "1" ]; then
    echo "$(date +%H:%M:%S) ENFORCER BLOCK VERDICT: codex R2 verdict missing ($HYP_ID)" >> "$LOG"
    printf '{"decision":"block","reason":"[S2.13 Codex R2 Guard] VERDICT 작성 차단 (%s): stage_artifacts/r2_codex_verdict_%s.json 미생성. Codex R2 Verify가 아직 진행 중이거나 실패했습니다. /tmp/codex_critic_r2_stderr.log 확인 후 재시도하거나 QVEST_SKIP_CODEX_R2=1로 우회하세요."}' "$HYP_ID" "$HYP_ID"
    exit 0
  fi

  # VERDICT content 검증 (v55 strict, compact 3인 / full 5인 동적 분기)
  DEBATE_MODE="${QVEST_DEBATE_MODE:-full}"
  VALIDATION=$(printf '%s' "$CONTENT" | DEBATE_MODE_PY="$DEBATE_MODE" python3 -c "
import sys, json, os
try:
    d = json.load(sys.stdin)
    errors = []
    mode = os.environ.get('DEBATE_MODE_PY', 'full')
    valid_stances = {'APPROVE','APPROVE_CONDITIONAL','REVISE','REJECT'}
    valid_changes = {'UNCHANGED','UPGRADED','DOWNGRADED'}
    valid_tiers = {'UNANIMOUS','MAJORITY','MINORITY','DEADLOCK'}

    # 1. transcript rounds 확인
    transcript = d.get('transcript', {})
    rounds = transcript.get('rounds', [])
    if len(rounds) < 2:
        errors.append(f'transcript.rounds {len(rounds)}개 (최소 2라운드: R1+R2 필수)')

    # 2. final_stances (v55) 확인 — final_scores는 무시
    fst = d.get('final_stances', {})
    if not isinstance(fst, dict) or not fst:
        errors.append('final_stances 누락 또는 빈 객체 (v55 필수, final_scores는 무시됨)')

    if mode == 'compact':
        compact_core = {'codex_critic', 'risk_manager'}
        compact_flex = {'judge', 'governor'}
        fs_keys = set(fst.keys())
        if not compact_core.issubset(fs_keys):
            errors.append(f'final_stances에 compact 필수 역할 누락: {compact_core - fs_keys}')
        if not fs_keys.intersection(compact_flex):
            errors.append('final_stances에 judge 또는 governor 중 하나 필수')
        required_roles = list(fs_keys.intersection(compact_core | compact_flex))
        expected_n = 3
    else:
        required_roles = ['codex_critic', 'risk_manager', 'governor', 'quant', 'academic']
        expected_n = 5

    for role in required_roles:
        if role not in fst:
            errors.append(f'final_stances에 {role} 누락')
            continue
        entry = fst[role]
        if 'r1' not in entry or 'final' not in entry:
            errors.append(f'final_stances.{role}에 r1/final 누락')
            continue
        if str(entry.get('r1','')).upper() not in valid_stances:
            errors.append(f\"final_stances.{role}.r1 '{entry.get('r1')}' 비정상\")
        if str(entry.get('final','')).upper() not in valid_stances:
            errors.append(f\"final_stances.{role}.final '{entry.get('final')}' 비정상\")
        if 'stance_change' not in entry or str(entry.get('stance_change','')).upper() not in valid_changes:
            errors.append(f'final_stances.{role}.stance_change 누락/비정상')
        if 'veto_flag' not in entry:
            errors.append(f'final_stances.{role}.veto_flag 키 누락 (null이라도 명시)')

    # 3. consensus_tally (v55 신규)
    tally = d.get('consensus_tally', {})
    if not isinstance(tally, dict):
        errors.append('consensus_tally 누락 (v55 필수)')
    else:
        for k in ('approve','approve_conditional','revise','reject','veto_count'):
            if k not in tally:
                errors.append(f'consensus_tally.{k} 누락')
        try:
            stance_sum = int(tally.get('approve',0)) + int(tally.get('approve_conditional',0)) + int(tally.get('revise',0)) + int(tally.get('reject',0))
            if stance_sum != expected_n:
                errors.append(f'consensus_tally stance 합 {stance_sum} != {expected_n} (mode={mode})')
        except: errors.append('consensus_tally 숫자 변환 실패')

    # 4. consensus_tier (v55 신규)
    tier = str(d.get('consensus_tier','')).upper()
    if tier not in valid_tiers:
        errors.append(f\"consensus_tier '{tier}' 비정상 (UNANIMOUS/MAJORITY/MINORITY/DEADLOCK)\")

    # 5. debaters 배열 — compact 3건 / full 5건
    debaters = d.get('debaters', [])
    min_debaters = 3 if mode == 'compact' else 5
    if len(debaters) < min_debaters:
        errors.append(f'debaters {len(debaters)}건 ({min_debaters}건 필수, mode={mode})')
    else:
        roles_found = set()
        for db in debaters:
            r = db.get('role', '').lower()
            if 'critic' in r: roles_found.add('codex_critic')
            elif 'risk' in r: roles_found.add('risk_manager')
            elif 'gov' in r: roles_found.add('governor')
            elif 'judge' in r: roles_found.add('judge')
            elif 'quant' in r: roles_found.add('quant')
            elif 'academic' in r: roles_found.add('academic')
        if mode == 'compact':
            if 'codex_critic' not in roles_found:
                errors.append('debaters에 codex_critic 누락')
            if 'risk_manager' not in roles_found:
                errors.append('debaters에 risk_manager 누락')
            if not roles_found.intersection({'judge', 'governor'}):
                errors.append('debaters에 judge 또는 governor 중 하나 필수')
        else:
            required_set = {'codex_critic', 'risk_manager', 'governor', 'quant', 'academic'}
            missing = required_set - roles_found
            if missing:
                errors.append(f'debaters 역할 누락: {missing}')
        # debaters 항목별 stance/veto 검증
        for i, db in enumerate(debaters):
            if 'stance' not in db:
                errors.append(f'debaters[{i}].stance 누락')
            elif str(db.get('stance','')).upper() not in valid_stances:
                errors.append(f\"debaters[{i}].stance '{db.get('stance')}' 비정상\")
            if 'veto_flag' not in db:
                errors.append(f'debaters[{i}].veto_flag 키 누락')

    # 6. consensus_points + unresolved_disputes
    if not d.get('consensus_points'):
        errors.append('consensus_points 누락 또는 빈 배열 (1건+ 필수)')
    if 'unresolved_disputes' not in d:
        errors.append('unresolved_disputes 키 누락')

    # 7. verdict
    verdict = str(d.get('verdict','')).upper()
    if verdict not in valid_stances:
        errors.append(f\"verdict '{verdict}' 비정상\")

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        consensus = '; '.join(d.get('consensus_points', [])[:2])
        disputes_list = d.get('unresolved_disputes', []) or []
        disputes = '; '.join([str(x) for x in disputes_list[:2]]) if disputes_list else '(없음)'
        veto_n = int(tally.get('veto_count', 0))
        a_n = int(tally.get('approve',0))
        c_n = int(tally.get('approve_conditional',0))
        rv_n = int(tally.get('revise',0))
        rj_n = int(tally.get('reject',0))
        print(f'PASS|{verdict}|{tier}|{a_n}|{c_n}|{rv_n}|{rj_n}|{veto_n}|{consensus}|{disputes}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK VERDICT: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer v55] VERDICT 검증 실패: %s\\n\\nv55 VERDICT 필수 필드: hypothesis_id, verdict, consensus_tier, consensus_tally{approve, approve_conditional, revise, reject, veto_count}, transcript.rounds, final_stances{role: {r1, final, stance_change, veto_flag}}, debaters[{role, stance, veto_flag}], consensus_points[], unresolved_disputes[]\\n점수제(total_score/final_scores) 폐기. SKILL.md Verdict 섹션 참조."}' "$V_REASON"
    exit 0
  fi

  VERDICT=$(echo "$VALIDATION" | cut -d'|' -f2)
  CTIER=$(echo "$VALIDATION" | cut -d'|' -f3)
  A_N=$(echo "$VALIDATION" | cut -d'|' -f4)
  C_N=$(echo "$VALIDATION" | cut -d'|' -f5)
  RV_N=$(echo "$VALIDATION" | cut -d'|' -f6)
  RJ_N=$(echo "$VALIDATION" | cut -d'|' -f7)
  VETO_N=$(echo "$VALIDATION" | cut -d'|' -f8)
  CONSENSUS=$(echo "$VALIDATION" | cut -d'|' -f9)
  DISPUTES=$(echo "$VALIDATION" | cut -d'|' -f10)

  write_state "DONE"

  # 텔레그램 최종 판정 (v55) — verdict 아이콘 + consensus_tier + tally + veto
  VICON=$(verdict_icon "$VERDICT")
  tg_notify "$(printf '⚖️ [S0 Debate · %s] VERDICT (v55)\n━━━━━━━━━━━━━━━━━━━━━━━━\n%s %s   (tier: %s)\n📊 tally  ✅%s  🟡%s  🔄%s  ❌%s   🚫veto=%s\n\n✅ 합의점\n%s\n\n❓ 미해결\n%s\n━━━━━━━━━━━━━━━━━━━━━━━━' \
    "$HYP_ID" "$VICON" "$VERDICT" "$CTIER" "$A_N" "$C_N" "$RV_N" "$RJ_N" "$VETO_N" "$CONSENSUS" "$DISPUTES")"

  echo "$(date +%H:%M:%S) ENFORCER VERDICT v55: $HYP_ID $VERDICT tier=$CTIER tally=A${A_N}/C${C_N}/Rv${RV_N}/Rj${RJ_N} veto=$VETO_N" >> "$LOG"

  echo '{}'
  exit 0
fi

echo '{}'
exit 0
