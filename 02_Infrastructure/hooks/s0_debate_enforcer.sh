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

# hypothesis_id 추출 (파일명에서 — H_1643_REVISED 같은 접미사도 포함)
HYP_ID=$(basename "$FILE_PATH" | python3 -c "
import sys, re
name = sys.stdin.read().strip()
# s0_debate_r1_risk_manager_H_1643_REVISED.json → H_1643_REVISED
# S0_VERDICT_H_1643.json → H_1643
# .json 확장자 제거 후 마지막 H_\d+... 패턴 추출
name_no_ext = name.rsplit('.', 1)[0]
m = re.search(r'(H_\d+(?:_[A-Za-z0-9]+)*)\s*$', name_no_ext)
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

  # content 검증: arguments 3건
  VALIDATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    args = d.get('arguments', d.get('key_arguments', []))
    role = d.get('role', 'unknown')
    score = d.get('score', d.get('total', 0))
    concern = d.get('concern', d.get('strongest_concern', ''))
    if len(args) != 3:
        print(f'FAIL|arguments {len(args)}건 (3건 필수)')
    elif 'score' not in d and 'total' not in d:
        print('FAIL|score 필드 누락')
    else:
        print(f'PASS|{role}|{score}|{\"|\".join(str(a) for a in args[:3])}|{concern}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK R1: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer] R1 검증 실패: %s"}' "$V_REASON"
    exit 0
  fi

  # 역할/점수 추출 (PASS|role|score 부분만)
  ROLE=$(echo "$VALIDATION" | cut -d'|' -f2)
  SCORE=$(echo "$VALIDATION" | cut -d'|' -f3)

  # 상태 전이
  if [ "$CUR_STATE" = "IDLE" ]; then
    write_state "R1_IN_PROGRESS"
  fi

  N_ROLES=$(add_role "r1" "$ROLE")

  # 텔레그램 중계 — 요약 메시지 (핵심만 전달, 줄바꿈 가독성)
  TG_MSG=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json

def summarize(txt, max_len=60):
    s = str(txt).strip()
    if len(s) <= max_len: return s
    # 첫 문장만 추출
    for sep in ['. ', '。', '; ', ' — ', ' - ']:
        idx = s.find(sep)
        if 0 < idx <= max_len:
            return s[:idx+1]
    return s[:max_len-3] + '...'

d = json.load(sys.stdin)
role = d.get('role', '?')
score = d.get('score', d.get('total', 0))
args = d.get('arguments', d.get('key_arguments', []))
concern = d.get('concern', d.get('strongest_concern', ''))

lines = []
lines.append(f'🎙 [S0] \$HYP_ID R1 — {role}: {score}/20')
lines.append('')
for i, a in enumerate(args[:3], 1):
    lines.append(f'  {i}. {summarize(a, 70)}')
lines.append('')
if concern:
    lines.append(f'  ⚠️ {summarize(concern, 80)}')
    lines.append('')
lines.append(f'[\$N_ROLES/5]')
print('\n'.join(lines))
" 2>/dev/null || echo "🎙 R1 $ROLE: $SCORE/20 [$N_ROLES/5]")

  tg_notify "$TG_MSG"

  echo "$(date +%H:%M:%S) ENFORCER R1: $ROLE ($SCORE/20) [$N_ROLES/5]" >> "$LOG"

  # 5/5 완료 시 R1_COMPLETE 전이
  if [ "$N_ROLES" = "5" ]; then
    write_state "R1_COMPLETE"

    # R1 합계 계산
    R1_TOTAL=$(python3 -c "
import json
with open('$STATE_FILE') as f: d = json.load(f)
print(d.get('r1_total', '?'))
" 2>/dev/null || echo "?")

    # R1 전원 의견 요약 발송
    R1_SUMMARY=$(python3 -c "
import json, glob, os
lines = []
lines.append('📋 [S0 Debate] $HYP_ID — R1 Complete')
lines.append('')
total = 0
artifacts_dir = os.path.dirname('$FILE_PATH') or 'stage_artifacts'
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r1_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        score = d.get('score', d.get('total', 0))
        total += score
        args = d.get('arguments', [])
        concern = d.get('concern', '')
        lines.append(f'━ {role}: {score}/20')
        for i, a in enumerate(args[:3], 1):
            lines.append(f'  {i}. {str(a)}')
        if concern:
            lines.append(f'  ⚠️ {str(concern)}')
        lines.append('')
    except: pass
lines.append(f'합계: {total}/100')
lines.append('')
lines.append('💬 R2 Rebuttal 시작...')
print('\n'.join(lines))
" 2>/dev/null || echo "📋 R1 Complete [$HYP_ID]")
    tg_notify "$R1_SUMMARY"

    echo "$(date +%H:%M:%S) ENFORCER: R1 COMPLETE → R2 시작 지시" >> "$LOG"

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
        # Transcript 미생성 시 R1 파일 5개 병합
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

    # Q-Lead에 R2 시작 지시 주입 (Codex R2 병행)
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R1 5/5 완료. 다음 단계:\\n1. 5개 R1 결과를 stage_artifacts/s0_debate_transcript_%s.json으로 컴파일\\n2. R2 Rebuttal: 5인 재스폰 (transcript 전문 프롬프트에 주입)\\n3. R2 필수: 동의 1건+ / 반박 1건+ / 점수수정시 이유 / 최강 반론 지목\\n\\n[S2.13] Codex R2 Verify는 background로 실행 중 — stage_artifacts/r2_codex_verdict_%s.json 생성 확인 후 VERDICT 작성 시 참고하세요."}}' "$HYP_ID" "$HYP_ID"
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

  # content 검증: rebuttals 1건+, agreements 1건+, r1_transcript_ref
  VALIDATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    errors = []
    role = d.get('role', 'unknown')
    r1_score = d.get('r1_score', 0)
    r2_score = d.get('r2_score', d.get('score', 0))
    score_changed = (r1_score != r2_score)

    rebuttals = d.get('rebuttals', [])
    agreements = d.get('agreements', [])

    if len(rebuttals) < 1:
        errors.append('반박(rebuttals) 0건 — 최소 1건 필수')
    if len(agreements) < 1:
        errors.append('동의(agreements) 0건 — 최소 1건 필수')
    if score_changed and not d.get('score_change_reason', ''):
        errors.append('점수 변경({0}→{1})인데 change_reason 누락'.format(r1_score, r2_score))

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        delta = r2_score - r1_score
        delta_str = f'+{delta}' if delta > 0 else str(delta)
        reb_summary = rebuttals[0].get('point', rebuttals[0]) if rebuttals else ''
        reb_target = rebuttals[0].get('against', '?') if isinstance(rebuttals[0], dict) else '?'
        agr_summary = agreements[0].get('point', agreements[0]) if agreements else ''
        agr_target = agreements[0].get('with', '?') if isinstance(agreements[0], dict) else '?'
        strongest = d.get('strongest_opposing_argument', '')
        print(f'PASS|{role}|{r1_score}|{r2_score}|{delta_str}|{reb_target}|{reb_summary[:80]}|{agr_target}|{agr_summary[:80]}|{strongest[:80]}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK R2: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer] R2 검증 실패: %s"}' "$V_REASON"
    exit 0
  fi

  # 역할/점수 추출 (PASS|role|r1|r2|delta 부분만)
  ROLE=$(echo "$VALIDATION" | cut -d'|' -f2)
  R1_SC=$(echo "$VALIDATION" | cut -d'|' -f3)
  R2_SC=$(echo "$VALIDATION" | cut -d'|' -f4)
  DELTA=$(echo "$VALIDATION" | cut -d'|' -f5)

  # 상태 전이
  if [ "$CUR_STATE" = "R1_COMPLETE" ]; then
    write_state "R2_IN_PROGRESS"
  fi

  N_ROLES=$(add_role "r2" "$ROLE")

  # 텔레그램 중계 — 요약 (핵심 반박/동의 1줄씩)
  TG_MSG=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json

def summarize(txt, max_len=70):
    s = str(txt).strip()
    if len(s) <= max_len: return s
    for sep in ['. ', '。', '; ', ' — ']:
        idx = s.find(sep)
        if 0 < idx <= max_len:
            return s[:idx+1]
    return s[:max_len-3] + '...'

d = json.load(sys.stdin)
role = d.get('role', '?')
r1 = d.get('r1_score', 0)
r2 = d.get('r2_score', d.get('score', 0))
delta = r2 - r1
ds = f'+{delta}' if delta > 0 else str(delta)
reason = d.get('score_change_reason', '') if d.get('score_changed') else ''

rebs = d.get('rebuttals', [])
agrs = d.get('agreements', [])

lines = []
lines.append(f'🔥 [S0] \$HYP_ID R2 — {role}: {r1}→{r2} ({ds})')
lines.append('')
if reason:
    lines.append(f'  이유: {summarize(reason, 80)}')
    lines.append('')
for rb in rebs[:2]:
    if isinstance(rb, dict):
        lines.append(f'  ↩️ vs {rb.get(\"against\",\"?\")}: {summarize(rb.get(\"point\",\"\"), 70)}')
lines.append('')
for ag in agrs[:1]:
    if isinstance(ag, dict):
        lines.append(f'  ✅ vs {ag.get(\"with\",\"?\")}: {summarize(ag.get(\"point\",\"\"), 70)}')
lines.append('')
lines.append(f'[\$N_ROLES/5]')
print('\n'.join(lines))
" 2>/dev/null || echo "🔥 R2 $ROLE: $R1_SC→$R2_SC ($DELTA) [$N_ROLES/5]")

  tg_notify "$TG_MSG"

  echo "$(date +%H:%M:%S) ENFORCER R2: $ROLE ($R1_SC→$R2_SC) [$N_ROLES/5]" >> "$LOG"

  # 5/5 완료 시 R2_COMPLETE 전이 + R3 필요 여부 판단
  if [ "$N_ROLES" = "5" ]; then
    # 점수 변동 > 4점인 에이전트 확인
    R3_CHECK=$(python3 -c "
import json, glob, os
state_dir = os.path.dirname('$FILE_PATH') or '.'
r3_needed = []
for f in glob.glob(os.path.join(state_dir, 's0_debate_r2_*_${HYP_ID}.json')):
    try:
        with open(f) as fh: d = json.load(fh)
        r1 = d.get('r1_score', 0)
        r2 = d.get('r2_score', d.get('score', 0))
        if abs(r2 - r1) > 4:
            r3_needed.append(d.get('role', '?'))
    except: pass
print(','.join(r3_needed) if r3_needed else 'NONE')
" 2>/dev/null || echo "NONE")

    if [ "$R3_CHECK" = "NONE" ]; then
      write_state "VERDICT_READY"

      # R2 전원 의견 변동 요약 발송
      R2_SUMMARY=$(python3 -c "
import json, glob, os
lines = []
lines.append('📊 [S0 Debate] $HYP_ID — R2 Complete')
lines.append('')
artifacts_dir = os.path.dirname('$FILE_PATH') or 'stage_artifacts'
r1_total = 0
r2_total = 0
for f in sorted(glob.glob(os.path.join(artifacts_dir, 's0_debate_r2_*_${HYP_ID}.json'))):
    try:
        with open(f) as fh: d = json.load(fh)
        role = d.get('role', '?')
        r1 = d.get('r1_score', 0)
        r2 = d.get('r2_score', 0)
        r1_total += r1
        r2_total += r2
        delta = r2 - r1
        ds = f'+{delta}' if delta > 0 else str(delta)
        reason = d.get('score_change_reason', '') if d.get('score_changed') else '변동 없음'
        rebs = d.get('rebuttals', [])
        agrs = d.get('agreements', [])

        lines.append(f'━ {role}: {r1} → {r2} ({ds})')
        if reason and reason != '변동 없음':
            lines.append(f'  이유: {str(reason)}')
        for rb in rebs[:1]:
            if isinstance(rb, dict):
                lines.append(f'  ↩️ vs {rb.get(\"against\",\"?\")}: {str(rb.get(\"point\",\"\"))}')
        for ag in agrs[:1]:
            if isinstance(ag, dict):
                lines.append(f'  ✅ vs {ag.get(\"with\",\"?\")}: {str(ag.get(\"point\",\"\"))}')
        lines.append('')
    except: pass
dt = r2_total - r1_total
ds = f'+{dt}' if dt > 0 else str(dt)
lines.append(f'합계: {r1_total} → {r2_total} ({ds})')
lines.append('')
lines.append('R3 대상: 없음 (전원 |delta| <= 4)')
lines.append('⚖️ VERDICT 작성 가능')
print('\n'.join(lines))
" 2>/dev/null || echo "📊 R2 Complete [$HYP_ID]")
      tg_notify "$R2_SUMMARY"

      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R2 5/5 완료. 점수 변동 ≤4점으로 R3 불필요.\\nVERDICT를 작성하세요. 필수 포함:\\n- transcript.rounds (R1, R2 최소 2라운드)\\n- final_scores (각 role별 r1/final/delta)\\n- consensus_points + unresolved_disputes\\n- debaters 배열 (5건, 기존 호환)"}}'
    else
      write_state "R3_NEEDED"
      tg_notify "$(printf '🔄 [S0 Debate] %s — R3 필요\n\n변동 >4점: %s\nR3 재소환 후 최종 확정.' "$HYP_ID" "$R3_CHECK")"

      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[S0 Debate Enforcer] R2 5/5 완료. 점수 변동 >4점 에이전트: %s\\nR3 Closing: 해당 에이전트만 재소환하여 최종 입장 확정하세요."}}' "$R3_CHECK"
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
    # r2 파일에서 |delta|>4인 에이전트 재계산
    artifacts_dir = os.path.dirname('$FILE_PATH') or '.'
    needed = []
    for f in glob.glob(os.path.join(artifacts_dir, 's0_debate_r2_*_${HYP_ID}.json')):
        try:
            with open(f) as fh: dd = json.load(fh)
            r1 = dd.get('r1_score', 0)
            r2 = dd.get('r2_score', dd.get('score', 0))
            if abs(r2 - r1) > 4:
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

  # VERDICT content 검증
  VALIDATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    errors = []

    # 1. transcript rounds 확인
    transcript = d.get('transcript', {})
    rounds = transcript.get('rounds', [])
    if len(rounds) < 2:
        errors.append(f'transcript.rounds {len(rounds)}개 (최소 2라운드: R1+R2 필수)')

    # 2. final_scores 확인
    fs = d.get('final_scores', {})
    required_roles = ['codex_critic', 'risk_manager', 'governor', 'quant', 'academic']
    for role in required_roles:
        if role not in fs:
            errors.append(f'final_scores에 {role} 누락')
        else:
            entry = fs[role]
            if 'r1' not in entry or 'final' not in entry:
                errors.append(f'final_scores.{role}에 r1/final 누락')
            if 'delta' not in entry:
                errors.append(f'final_scores.{role}에 delta 누락')

    # 3. debaters 배열 (기존 호환)
    debaters = d.get('debaters', [])
    if len(debaters) < 5:
        errors.append(f'debaters {len(debaters)}건 (5건 필수)')
    else:
        roles_found = set()
        for db in debaters:
            r = db.get('role', '').lower()
            if 'critic' in r: roles_found.add('codex_critic')
            elif 'risk' in r: roles_found.add('risk_manager')
            elif 'gov' in r: roles_found.add('governor')
            elif 'quant' in r: roles_found.add('quant')
            elif 'academic' in r: roles_found.add('academic')
        missing = set(required_roles) - roles_found
        if missing:
            errors.append(f'debaters 역할 누락: {missing}')

    # 4. consensus + disputes
    if not d.get('consensus_points'):
        errors.append('consensus_points 누락')
    if 'unresolved_disputes' not in d:
        errors.append('unresolved_disputes 누락')

    # 5. verdict
    verdict = d.get('verdict', '')
    total = d.get('total_score', d.get('total', {}).get('final', 0))

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        r1_total = sum(fs[r].get('r1', 0) for r in required_roles)
        final_total = sum(fs[r].get('final', 0) for r in required_roles)
        consensus = '; '.join(d.get('consensus_points', [])[:2])
        disputes = '; '.join(d.get('unresolved_disputes', [])[:2])
        print(f'PASS|{verdict}|{r1_total}|{final_total}|{consensus}|{disputes}')
except Exception as e:
    print(f'FAIL|JSON 파싱 실패: {e}')
" 2>/dev/null)

  V_STATUS=$(echo "$VALIDATION" | cut -d'|' -f1)
  if [ "$V_STATUS" = "FAIL" ]; then
    V_REASON=$(echo "$VALIDATION" | cut -d'|' -f2-)
    echo "$(date +%H:%M:%S) ENFORCER BLOCK VERDICT: $V_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[S0 Debate Enforcer] VERDICT 검증 실패: %s"}' "$V_REASON"
    exit 0
  fi

  VERDICT=$(echo "$VALIDATION" | cut -d'|' -f2)
  R1_TOTAL=$(echo "$VALIDATION" | cut -d'|' -f3)
  FINAL_TOTAL=$(echo "$VALIDATION" | cut -d'|' -f4)
  CONSENSUS=$(echo "$VALIDATION" | cut -d'|' -f5)
  DISPUTES=$(echo "$VALIDATION" | cut -d'|' -f6)

  write_state "DONE"

  # 텔레그램 최종 판정
  tg_notify "$(printf '⚖️ [S0 Debate] %s — VERDICT\n\n%s (%s/100)\nR1 %s → Final %s\n\n✅ 합의: %s\n❓ 미해결: %s' \
    "$HYP_ID" "$VERDICT" "$FINAL_TOTAL" "$R1_TOTAL" "$FINAL_TOTAL" "$CONSENSUS" "$DISPUTES")"

  echo "$(date +%H:%M:%S) ENFORCER VERDICT: $HYP_ID $VERDICT ($FINAL_TOTAL/100)" >> "$LOG"

  echo '{}'
  exit 0
fi

echo '{}'
exit 0
