#!/usr/bin/env bash
#==============================================================================
# test_llm_single_entry.sh — 무인 LLM 단일 진입 + AutoMem 차단 (P0-M1 · 2026-09-24)
#
# 왜: 무인 `claude -p` 레인 519 세션 중 416 이 MEMORY.md(성과 수치 포함)를 주입받았고, 27 세션이
#   기억 디렉터리에 카드 19장 + MEMORY.md 를 썼다(D7-02). 차단 스위치(CLAUDE_CODE_DISABLE_AUTO_MEMORY=1)와
#   무인 표식(QVEST_UNATTENDED_LANE=1)은 rf_llm_env.sh::rf_llm_agent_run 한 곳에서만 실린다 —
#   그 밖에서 뜨는 claude 는 방어선 밖이다. "12곳 목록" 같은 열거는 낡는다(실제 27파일) → 전수 parse.
# 재는 것:
#   A. 전수 parse — 저장소 코드에서 rf_llm_agent_run 밖 헤드리스 호출 0 · 허용 지점 ≥2(1차·폴백 — 0 이면 검사기 사망)
#   B. 픽스처 주입 — 언어 6종(sh·R·py·ps1·bat·js)의 맨 호출이 정확히 검출되고 무해 언급(로그 문자열·주석·
#      인용 헤레독·--version)은 검출되지 않는다(양방향)
#   C. 실레인 주입 — 레인 사본에 맨 호출을 넣으면 잡힌다 · 허용은 파일이 아니라 **함수** 단위다
#   D. rf_llm_agent_run 이 두 표식을 claude 프로세스에 싣는다(1차·폴백 둘 다) · 호출자 셸로 새지 않는다 · 표식 삭제 돌연변이 red
#   E. `_run_claude` 레인 4종 — 함수 본문을 가짜 claude 로 태워 표식·stdin 프롬프트·모델·재지정 시 폴백 미탑재 확인
#   F. rf_llm_agent_run 을 부르는 파일은 호출 전에 rf_llm_env.sh 를 읽는다(명령 없음 = 조용한 무실행 방지)
#   G. (2차 09-25) 한도 폴백 배선 — 허용 목록(이관 전 호출자 3) 밖은 LLM_FALLBACK_MODEL="" (구판 동작 보존) · 돌연변이 red
#      (E5·E6 = `_run_claude` 기본 호출이 Fable 로 해석돼도 --fallback-model 미탑재 · 되살린 돌연변이 red)
# 격리: 쓰기는 mktemp 디렉터리뿐. 실 claude 는 부르지 않는다(가짜 실행 파일).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
SCAN_ROOT="${QVEST_LSE_ROOT:-$ROOT}"            # 전수 parse 의 파일 목록 원천(git 저장소)
OVERLAY="${QVEST_LSE_OVERLAY:-}"                  # 스테이징 검증: 같은 상대 경로 사본이 있으면 그 내용을 읽는다
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCANNER="$SELF_DIR/llm_single_entry_scan.py"
OPS="$ROOT/02_Infrastructure/ops"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY=python
P=0; F=0
ok(){ P=$((P+1)); printf '  OK    %s\n' "$1"; }
ng(){ F=$((F+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
winp(){ cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo "=== test_llm_single_entry (root: $SCAN_ROOT) ==="

echo "--- A. 전수 parse ---"
if [ -n "$OVERLAY" ]; then out="$("$PY" "$(winp "$SCANNER")" "$(winp "$SCAN_ROOT")" --overlay "$(winp "$OVERLAY")" 2>&1 | tr -d '\r')"
else out="$("$PY" "$(winp "$SCANNER")" "$(winp "$SCAN_ROOT")" 2>&1 | tr -d '\r')"; fi
js="$(printf '%s\n' "$out" | tail -1)"
nv=$(printf '%s' "$js" | "$PY" -c "import json,sys;print(json.loads(sys.stdin.read())['violations'])" 2>/dev/null)
na=$(printf '%s' "$js" | "$PY" -c "import json,sys;print(json.loads(sys.stdin.read())['allowed'])" 2>/dev/null)
nf=$(printf '%s' "$js" | "$PY" -c "import json,sys;print(json.loads(sys.stdin.read())['files_scanned'])" 2>/dev/null)
[ "${nv:-x}" = "0" ] && ok "A1 미경유 헤드리스 호출 0 (파일 ${nf:-?}개 parse)" || ng "A1 미경유 호출" "$(printf '%s\n' "$out" | grep '^VIOLATION' | head -8 | tr '\n' ' ')"
[ "${na:-0}" -ge 2 ] 2>/dev/null && ok "A2 허용 지점 ${na}곳(rf_llm_agent_run 1차·폴백) — 검사기가 호출을 본다" || ng "A2 허용 지점" "allowed=${na:-?} — 검사기가 아무것도 못 보면 A1 은 공허하다"

echo "--- B. 픽스처 주입(언어 6종 · 양방향) ---"
FX="$T/fx"; mkdir -p "$FX"
cat > "$FX/fx_bare.sh" <<'SH'
#!/usr/bin/env bash
timeout 60 claude -p < prompt.txt > out 2>&1   # @@V
CLAUDE_BIN="$(command -v claude || echo /c/x/npm/claude)"
"$CLAUDE_BIN" -p "hello" >> "$LOG" 2>&1   # @@V
OUT=$(claude --print "x")   # @@V
eval "claude -p hi"   # @@V
bash -c 'claude -p hi'   # @@V
QVEST_ARM_GEN=1 env FOO=1 nohup claude.exe -p x &   # @@V
run_it "$CLAUDE_BIN" -p "$PROMPT_TEXT" --dangerously-skip-permissions   # @@V
bin="${RF_CLAUDE_BIN:-claude}"
"$bin" --model opus \
  -p < "$PF"   # @@V
cat <<EOF
$(claude -p inside-heredoc) @@V
EOF
log "claude -p exit=$rc"
echo "run claude -p manually"
command -v claude >/dev/null 2>&1 || exit 0
[ -x "$CLAUDE_BIN" ] || exit 0
cat <<'PY'
claude -p not-code-in-quoted-heredoc
PY
claude --version
ls ~/.claude/projects
# timeout 1800 claude -p < "$PF"
SH
cat > "$FX/fx_bare.R" <<'RR'
system2("claude", c("-p", "hi"))   # @@V
system("claude -p hi")   # @@V
cl <- Sys.which("claude")
system2(cl, c("--print", "x"))   # @@V
message("claude -p exit")
# system2("claude", "-p")
root <- Sys.getenv("CLAUDE_PROJECT_DIR")
RR
cat > "$FX/fx_bare.py" <<'PYF'
import os, shutil, subprocess
subprocess.run(["claude", "-p", "x"])   # @@V
os.system("claude -p x")   # @@V
c = shutil.which("claude")
subprocess.Popen([c, "--print", "y"])   # @@V
print("claude -p exit=0")
# subprocess.run(["claude", "-p"])
root = os.environ.get("CLAUDE_PROJECT_DIR")
PYF
cat > "$FX/fx_bare.ps1" <<'PS'
& claude -p "x"   # @@V
claude.exe --print y   # @@V
# claude -p commented
Write-Host "claude -p is how lanes run"
PS
cat > "$FX/fx_bare.bat" <<'BAT'
claude -p hi & REM @@V
REM claude -p commented
echo done
BAT
cat > "$FX/fx_bare.js" <<'JS'
const { spawn } = require('child_process');
spawn('claude', ['-p', 'x']);   // @@V
// exec('claude -p commented')
console.log('claude -p');
JS
exp=""; for f in fx_bare.sh fx_bare.R fx_bare.py fx_bare.ps1 fx_bare.bat fx_bare.js; do
  for n in $(grep -n '@@V' "$FX/$f" | cut -d: -f1); do exp="$exp $f:$n"; done
done
# fx_bare.sh 의 줄 잇기 호출은 명령 시작 줄(11)에서 보고된다 — @@V 는 둘째 줄(12)에 있다
exp="$(printf '%s\n' $exp | sed 's/^fx_bare.sh:12$/fx_bare.sh:11/' | sort -u | tr '\n' ' ')"
got="$("$PY" "$(winp "$SCANNER")" "$(winp "$FX")" --paths fx_bare.sh fx_bare.R fx_bare.py fx_bare.ps1 fx_bare.bat fx_bare.js 2>&1 \
       | tr -d '\r' | sed -n 's/^VIOLATION \([^ ]*\) .*/\1/p' | sort -u | tr '\n' ' ')"
[ "$got" = "$exp" ] && ok "B1 맨 호출 $(printf '%s' "$exp" | wc -w)건 정확 검출 · 무해 언급 0건 오검출" \
  || ng "B1 검출 집합 불일치" "기대=[$exp] 실제=[$got]"
for lang in sh R py ps1 bat js; do
  e=$(printf '%s\n' $exp | grep -c "fx_bare.$lang:"); g=$(printf '%s\n' $got | grep -c "fx_bare.$lang:")
  [ "$e" -ge 1 ] && [ "$e" = "$g" ] && ok "B2 $lang 맨 호출 $g/$e" || ng "B2 $lang" "기대 $e · 실제 $g"
done

echo "--- C. 실레인 주입 · 함수 단위 허용 ---"
mkdir -p "$T/lane/02_Infrastructure/ops"
cp "$OPS/rf_b1_design.sh" "$T/lane/02_Infrastructure/ops/rf_b1_design.sh"
printf '\ntimeout 1800 claude -p < "$PF" --add-dir "$DDIR" >> "$LOG" 2>&1\n' >> "$T/lane/02_Infrastructure/ops/rf_b1_design.sh"
cp "$OPS/rf_llm_env.sh" "$T/lane/02_Infrastructure/ops/rf_llm_env.sh"
g1="$("$PY" "$(winp "$SCANNER")" "$(winp "$T/lane")" --paths 02_Infrastructure/ops/rf_b1_design.sh 02_Infrastructure/ops/rf_llm_env.sh 2>&1 | tr -d '\r')"
printf '%s\n' "$g1" | grep -q '^VIOLATION 02_Infrastructure/ops/rf_b1_design.sh:' && ok "C1 실레인 사본에 주입한 맨 호출 검출" || ng "C1 실레인 주입 미검출" "$(printf '%s' "$g1" | tail -1)"
printf '%s\n' "$g1" | grep -q '^VIOLATION 02_Infrastructure/ops/rf_llm_env.sh' && ng "C2 정본이 위반으로 잡혔다" "$g1" || ok "C2 정본 rf_llm_agent_run 본문은 허용"
sed -i 's/^rf_llm_agent_run() {/rf_llm_agent_run_shadow() {/' "$T/lane/02_Infrastructure/ops/rf_llm_env.sh"
g2="$("$PY" "$(winp "$SCANNER")" "$(winp "$T/lane")" --paths 02_Infrastructure/ops/rf_llm_env.sh 2>&1 | tr -d '\r')"
printf '%s\n' "$g2" | grep -q '^VIOLATION 02_Infrastructure/ops/rf_llm_env.sh' && ok "C3 허용은 함수 단위 — 같은 파일의 다른 함수 호출은 위반" || ng "C3 파일 단위 허용(구멍)" "$(printf '%s' "$g2" | tail -1)"

echo "--- D. rf_llm_agent_run 표식 전달(가짜 claude) ---"
cat > "$T/fake_claude" <<'FAKE'
#!/usr/bin/env bash
echo "ARGS:$*"
echo "AUTOMEM=${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-unset}"
echo "LANE=${QVEST_UNATTENDED_LANE:-unset}"
echo "ARMGEN=${QVEST_ARM_GEN:-unset}"
echo "STDIN=$(cat)"
if [ -n "${FAKE_LIMIT_ONCE:-}" ] && [ ! -e "$FAKE_LIMIT_ONCE" ]; then : > "$FAKE_LIMIT_ONCE"; echo "You've hit your session limit · resets 2am"; fi
FAKE
chmod +x "$T/fake_claude"
printf 'PROMPT-P0M1' > "$T/pf.txt"
drun(){ # $1 = rf_llm_env.sh 경로 · 나머지 = env 인자(-u 이름 · 이름=값) — 호출자 셸 표식은 늘 지우고 시작
  local envf="$1"; shift
  rm -f "$T/out.txt" "$T/out.txt.primary"
  env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY -u QVEST_UNATTENDED_LANE "$@" bash -c '. "$1"; LLM_MODEL=opus; LLM_EFFORT=max; LLM_FALLBACK_MODEL="${FB:-}"; LLM_FALLBACK_EFFORT=max
    RF_CLAUDE_BIN="$2" rf_llm_agent_run "$3" "$4" 30 --extra-flag
    echo "RC=$LLM_RC FELL=$LLM_FELL_BACK"
    echo "PARENT_AUTOMEM=${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-unset} PARENT_LANE=${QVEST_UNATTENDED_LANE:-unset}"' _ "$envf" "$T/fake_claude" "$T/pf.txt" "$T/out.txt"
}
o="$(drun "$OPS/rf_llm_env.sh")"; r="$(cat "$T/out.txt" 2>/dev/null)"
case "$r" in *AUTOMEM=1*) ok "D1 claude 에 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1" ;; *) ng "D1 AutoMem 스위치 미전달" "$r" ;; esac
case "$r" in *LANE=1*) ok "D2 claude 에 QVEST_UNATTENDED_LANE=1(훅 표식)" ;; *) ng "D2 무인 표식 미전달" "$r" ;; esac
case "$r" in *"STDIN=PROMPT-P0M1"*) ok "D3 프롬프트 = stdin 파일" ;; *) ng "D3 stdin" "$r" ;; esac
case "$r" in *"ARGS:-p --model opus --effort max --extra-flag"*) ok "D4 -p · 모델 · 노력 · 추가 인자 순서 보존" ;; *) ng "D4 인자" "$r" ;; esac
case "$o" in *"PARENT_AUTOMEM=unset PARENT_LANE=unset"*) ok "D5 표식이 호출자 셸로 새지 않는다(함수 지역)" ;; *) ng "D5 누출" "$o" ;; esac
rm -f "$T/limit_once"
o="$(drun "$OPS/rf_llm_env.sh" FB=opus FAKE_LIMIT_ONCE="$T/limit_once")"; r="$(cat "$T/out.txt" 2>/dev/null)"
case "$o|$r" in *"FELL=1"*"AUTOMEM=1"*"LANE=1"*) ok "D6 한도 폴백 재실행에도 두 표식" ;; *) ng "D6 폴백 표식" "o=$o r=$r" ;; esac
[ -f "$T/out.txt.primary" ] && grep -q "AUTOMEM=1" "$T/out.txt.primary" && ok "D7 1차 실행(한도)에도 표식" || ng "D7 1차 표식" "$(cat "$T/out.txt.primary" 2>/dev/null)"
sed 's/^  local lane_env=(CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 QVEST_UNATTENDED_LANE=1)$/  local lane_env=(QVEST_MUTANT=1)/' "$OPS/rf_llm_env.sh" > "$T/rf_llm_env_mut.sh"
if cmp -s "$OPS/rf_llm_env.sh" "$T/rf_llm_env_mut.sh"; then ng "D8 돌연변이" "sed 무변화(표식 줄 좌표 낡음)"; else
  drun "$T/rf_llm_env_mut.sh" >/dev/null
  r="$(cat "$T/out.txt" 2>/dev/null)"
  case "$r" in *AUTOMEM=unset*LANE=unset*) ok "D8 표식 줄을 지운 돌연변이 → 표식 소실(D1·D2 가 잡는다)" ;; *) ng "D8 돌연변이 판별력" "$r" ;; esac
fi

echo "--- E. _run_claude 레인 4종 ---"
for lane in alpha_search_queue_run.sh factor_deep_recheck_run.sh mode_queue_research_run.sh paper_router_run.sh; do
  src="$OPS/$lane"
  body="$(sed -n '/^_run_claude(){/,/^}/p' "$src" | tr -d '\r')"
  if [ -z "$body" ]; then ng "E $lane" "_run_claude 정의 없음"; continue; fi
  if printf '%s' "$body" | grep -qE '"\$@"|claude[^_]* -p'; then ng "E0 $lane" "구판 형태(\"\$@\" 직행) 잔존"; continue; fi
  { printf '. "%s"\n' "$OPS/rf_llm_env.sh"; printf '%s\n' "$body"
    printf 'CLAUDE_BIN="%s"; LOG="%s"; PROMPT_TEXT="LANE-PROMPT %s"; LLM_MODEL=%s; LLM_EFFORT=max; LLM_FALLBACK_MODEL=%s\n' \
      "$T/fake_claude" "$T/lane.log" "$lane" "\${M:-opus}" "\${FBM:-}"
    printf '_run_claude "${ARG1:-}"; echo "RC=$?"\n'
  } > "$T/lane_h.sh"
  rm -f "$T/lane.log"
  o="$(env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY -u QVEST_UNATTENDED_LANE bash "$T/lane_h.sh" 2>&1)"; l="$(cat "$T/lane.log" 2>/dev/null)"
  case "$o|$l" in *RC=0*AUTOMEM=1*LANE=1*) ok "E1 $lane 표식 2종" ;; *) ng "E1 $lane 표식" "o=$o l=$l" ;; esac
  case "$l" in *"STDIN=LANE-PROMPT $lane"*) ok "E2 $lane 프롬프트 stdin" ;; *) ng "E2 $lane stdin" "$l" ;; esac
  case "$l" in *"--model opus --effort max --dangerously-skip-permissions"*) ok "E3 $lane 모델·노력·권한 인자" ;; *) ng "E3 $lane 인자" "$l" ;; esac
  rm -f "$T/lane.log"
  env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY M=fable FBM=opus ARG1=opus bash "$T/lane_h.sh" >/dev/null 2>&1; l="$(cat "$T/lane.log" 2>/dev/null)"
  case "$l" in *"--model opus"*) case "$l" in *fallback-model*) ng "E4 $lane" "재지정 호출에 --fallback-model 이 실렸다(같은 모델 폴백)" ;; *) ok "E4 $lane 폴백 재시도 = opus · CLI 폴백 미탑재" ;; esac ;;
    *) ng "E4 $lane 재지정" "$l" ;; esac
  # E5 (2차 · 2026-09-25) 기본 호출도 Fable 로 해석돼 있을 때 --fallback-model 을 싣지 않는다 — 구판 동작 보존.
  #   이 레인의 한도 폴백은 spend_limit → `_run_claude opus` 한 벌이다(두 벌이면 한도 한 번에 세 번 뜬다).
  rm -f "$T/lane.log"
  env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY M=fable FBM=opus bash "$T/lane_h.sh" >/dev/null 2>&1; l="$(cat "$T/lane.log" 2>/dev/null)"
  case "$l" in *"--model fable"*) case "$l" in *fallback-model*) ng "E5 $lane" "기본 호출에 --fallback-model 이 실렸다(자체 spend_limit 재시도와 이중 폴백)" ;; *) ok "E5 $lane 기본 호출(fable) = CLI 폴백 미탑재(구판 보존)" ;; esac ;;
    *) ng "E5 $lane 기본 호출" "$l" ;; esac
done
# E6 돌연변이 — _run_claude 가 해석값 폴백을 다시 넘기면 E5 가 잡는다
body="$(sed -n '/^_run_claude(){/,/^}/p' "$OPS/paper_router_run.sh" | tr -d '\r')"
mbody="$(printf '%s\n' "$body" | sed 's/LLM_FALLBACK_MODEL="" \\/LLM_FALLBACK_MODEL="${LLM_FALLBACK_MODEL:-}" \\/')"
if [ "$mbody" = "$body" ]; then ng "E6 돌연변이" "sed 무변화(좌표 낡음)"; else
  { printf '. "%s"\n' "$OPS/rf_llm_env.sh"; printf '%s\n' "$mbody"
    printf 'CLAUDE_BIN="%s"; LOG="%s"; PROMPT_TEXT="MUT"; LLM_MODEL=fable; LLM_EFFORT=max; LLM_FALLBACK_MODEL=opus\n' "$T/fake_claude" "$T/lane_m.log"
    printf '_run_claude ""\n'; } > "$T/lane_m.sh"
  rm -f "$T/lane_m.log"; bash "$T/lane_m.sh" >/dev/null 2>&1
  grep -q -- '--fallback-model opus' "$T/lane_m.log" 2>/dev/null && ok "E6 폴백을 되살린 돌연변이 → --fallback-model 재출현(E5 판별력)" || ng "E6 돌연변이 판별력" "$(cat "$T/lane_m.log" 2>/dev/null | head -3)"
fi

echo "--- F. 호출 전 rf_llm_env.sh 적재 ---"
for f in "$OPS"/*.sh; do
  b="$(basename "$f")"; [ "$b" = rf_llm_env.sh ] && continue
  c=$(grep -nE '^[^#]*\brf_llm_agent_run [^(]' "$f" | grep -v 'rf_llm_agent_run()' | head -1 | cut -d: -f1)
  [ -n "$c" ] || continue
  s=$(grep -nE '^[^#]*rf_llm_env\.sh' "$f" | head -1 | cut -d: -f1)
  d=$(grep -nE '^\s*(\.|source)\s+"?\$?\{?(_RFLE|[^ ]*rf_llm_env\.sh)' "$f" | head -1 | cut -d: -f1)
  if [ -n "$s" ] && [ -n "$d" ] && [ "$s" -lt "$c" ] && [ "$d" -lt "$c" ]; then ok "F $b (적재 $d < 호출 $c)"
  else ng "F $b" "적재=${d:-없음} 호출=$c — 함수가 없으면 호출이 '명령 없음' 으로 조용히 죽는다"; fi
done

echo "--- G. 한도 폴백 배선 — 허용 목록 밖 호출자는 LLM_FALLBACK_MODEL=\"\" (2차 · 2026-09-25) ---"
# 폴백을 싣는 호출자 = 이관 전부터 이 함수를 쓰던 셋(반쪽 산출물 청소 훅 rf_llm_before_fallback 또는 감사 레인).
# P0-M1 이관 레인은 구판처럼 폴백 없이 뜬다 — 새 호출자는 둘 중 하나를 명시적으로 골라야 한다.
FB_ALLOW="rf_replication_auto.sh,rf_b5_design.sh,rf_overlay_audit.sh"
cat > "$T/g_scan.py" <<'PYG'
import io, os, re, sys
ops = sys.argv[1]; allow = set(sys.argv[2].split(','))
bad = []; seen = 0
for fn in sorted(os.listdir(ops)):
    if not fn.endswith('.sh') or fn == 'rf_llm_env.sh':
        continue
    t = io.open(os.path.join(ops, fn), 'rb').read().decode('utf-8', 'replace').replace('\r\n', '\n')
    logical = []; buf = ''; start = None
    for i, l in enumerate(t.split('\n'), 1):
        if start is None:
            start = i
        if l.rstrip().endswith('\\'):
            buf += l.rstrip()[:-1] + ' '
            continue
        buf += l; logical.append((start, buf)); buf = ''; start = None
    code = [(n, s) for n, s in logical if s.strip() and not s.lstrip().startswith('#')]
    for k, (n, s) in enumerate(code):
        if not re.search(r'(^|[\s;&|(])rf_llm_agent_run\s+[^\s(]', s) or re.search(r'rf_llm_agent_run\s*\(\)', s):
            continue
        seen += 1
        if fn in allow:
            continue
        ctx = ' '.join(x for _, x in code[max(0, k - 3):k + 1])
        if 'LLM_FALLBACK_MODEL=""' not in ctx:
            bad.append('%s:%d' % (fn, n))
print('SEEN=%d' % seen)
print('BAD=' + ' '.join(bad))
PYG
g="$("$PY" "$(winp "$T/g_scan.py")" "$(winp "$OPS")" "$FB_ALLOW" 2>&1 | tr -d '\r')"
gs="$(printf '%s\n' "$g" | sed -n 's/^SEEN=//p')"; gb="$(printf '%s\n' "$g" | sed -n 's/^BAD=//p')"
[ "${gs:-0}" -ge 4 ] 2>/dev/null && ok "G1 호출 지점 ${gs}곳을 본다(검사기 생존)" || ng "G1 호출 지점" "seen=${gs:-?} — $g"
[ -z "$gb" ] && [ -n "$gs" ] && ok "G2 허용 목록 밖 호출자 전부 폴백 미탑재" || ng "G2 폴백 배선" "위반=[$gb]"
mkdir -p "$T/gops"
cp "$OPS/rf_b1_design.sh" "$OPS/paper_router_run.sh" "$T/gops/"
sed -i 's/LLM_FALLBACK_MODEL="" rf_llm_agent_run/rf_llm_agent_run/; s/LLM_MODEL="\$_model" LLM_FALLBACK_MODEL="" \\/LLM_MODEL="$_model" \\/' "$T/gops/rf_b1_design.sh" "$T/gops/paper_router_run.sh"
if cmp -s "$OPS/rf_b1_design.sh" "$T/gops/rf_b1_design.sh" || cmp -s "$OPS/paper_router_run.sh" "$T/gops/paper_router_run.sh"; then ng "G3 돌연변이" "sed 무변화(좌표 낡음)"; else
  g3="$("$PY" "$(winp "$T/g_scan.py")" "$(winp "$T/gops")" "$FB_ALLOW" 2>&1 | tr -d '\r' | sed -n 's/^BAD=//p')"
  case "$g3" in *rf_b1_design.sh:*paper_router_run.sh:*|*paper_router_run.sh:*rf_b1_design.sh:*) ok "G3 비움을 지운 돌연변이 2종(직접 레인·_run_claude) 검출" ;; *) ng "G3 판별력" "검출=[$g3]" ;; esac
fi

echo
echo "합계: 통과 $P · 실패 $F"
echo "{\"test\":\"llm_single_entry\",\"pass\":$P,\"fail\":$F,\"total\":$((P+F))}"
[ "$F" -eq 0 ]
