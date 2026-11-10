#!/usr/bin/env bash
#==============================================================================
# test_hook_backslash_paths.sh — 차단 훅이 역슬래시 경로를 보는가 (2026-11-10 전수점검)
#
# 지키는 것:
#   윈도우에서 Write · Edit 도구는 경로를 역슬래시로 준다(G:\…\파일). 경로 가지를 '/' 패턴으로만 가르는 훅은 그런 호출을
#   조용히 통과시킨다. 실측(수리 전): 종목 수 상한 훅(worktask_constraint_enforcer — 26종 패키지) · 졸업 관문
#   (discovery_graduation_gate — 참조 없는 졸업 요청) · 레거시 쓰기 차단(legacy_write_block) 셋 다
#   정슬래시 = block · 역슬래시 = allow 였다. 수리 = 경로 추출 직후 구분자 정규화.
#
# 축 (훅마다):
#   A  정슬래시 위반 → block                      (기준선 — 시험 입력이 실제로 차단되는 입력인지)
#   B  역슬래시 위반 → block                      (수리 대상)
#   C  섞인 구분자 위반 → block
#   D  [음성] 역슬래시 정상 입력 → allow          (정규화가 과차단을 만들지 않는다)
#   E  [위반 주입] 정규화 줄을 뺀 사본은 B 를 통과하지 못한다(= allow)
#   F  이미 양쪽을 보던 훅(safety_guard · book_write_guard)의 역슬래시 차단이 유지된다(회귀 감시)
#
# 격리: 훅은 판정 JSON 만 낸다(파일을 만들지 않는다). 돌연변이 사본은 임시 폴더.
#==============================================================================
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
command -v cygpath >/dev/null 2>&1 && ROOT="$(cygpath -m "$ROOT")"
H="$ROOT/02_Infrastructure/hooks"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS  $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL  $1 — $2"; }
finish() {
  echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
  printf '{"test":"hook_backslash_paths","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
  [ "$FAIL" = "0" ] || exit 1
  exit 0
}
QVEST_PARSE_TRAP=caller; QVEST_PARSE_RESOLVE_ONLY=1
# shellcheck source=/dev/null
source "$H/_shared_parse.sh" 2>/dev/null; unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
PY="${QVEST_PY_BIN:-python}"
for h in worktask_constraint_enforcer discovery_graduation_gate legacy_write_block safety_guard book_write_guard; do
  [ -f "$H/$h.sh" ] || { ng "0 훅 원본" "없음: $h.sh"; finish; }
done
T="$(mktemp -d 2>/dev/null || echo "/tmp/hookbs_$$")"; mkdir -p "$T"
command -v cygpath >/dev/null 2>&1 && T="$(cygpath -m "$T")"
trap 'rm -rf "$T" 2>/dev/null' EXIT

# payload <kind> <path> → 도구 호출 JSON (json.dumps 가 역슬래시를 이스케이프한다 — 실제 도구 호출과 같은 모양)
payload() {
  "$PY" -X utf8 -c 'import json,sys
kind,p=sys.argv[1],sys.argv[2]
if kind=="opt26":   c=json.dumps({"target_weights":{("T%03d"%i):1.0/26 for i in range(26)}})
elif kind=="opt10": c=json.dumps({"target_weights":{("T%03d"%i):0.1 for i in range(10)}})
elif kind=="req_bad": c=json.dumps({"wt_type":"deployment","discovery_of":"WT-D_NOT_EXISTING_PROBE"})
elif kind=="req_ok":  c=json.dumps({"wt_type":"discovery"})
else: c="x <- 1"
sys.stdout.write(json.dumps({"tool_name":"Write","tool_input":{"file_path":p,"content":c},"hook_event_name":"PreToolUse"},ensure_ascii=False))' "$@"
}
# verdict <hook-file> <kind> <path> → block | allow | ?
verdict() {
  local hook="$1"; shift
  (cd "$ROOT" && payload "$@" | CLAUDE_PROJECT_DIR="$ROOT" QM_ROOT="$ROOT" bash "$hook" 2>/dev/null) | "$PY" -X utf8 -c 'import json,sys
s=sys.stdin.buffer.read().decode("utf-8","replace").strip()
try: d=json.loads(s.splitlines()[-1]) if s else {}
except Exception: d={"_raw":1}
h=d.get("hookSpecificOutput") or {}
v=d.get("decision") or h.get("permissionDecision") or ("allow" if d=={} else "?")
print("block" if v in ("block","deny") else v)'
}
expect() {  # expect <want> <label> <hook-file> <kind> <path>
  local want="$1" label="$2"; shift 2
  local got; got="$(verdict "$@")"
  [ "$got" = "$want" ] && ok "$label → $got" || ng "$label" "기대 $want · 실제 $got"
}
# mutant <hook-name> → 정규화 줄을 뺀 사본 경로(치환이 정확히 1곳이어야 0)
mutant() {
  "$PY" -X utf8 -c 'import io,sys
s=io.open(sys.argv[1],encoding="utf-8",newline="").read()
line="FILE_PATH=\"${FILE_PATH//\\\\//}\"\n"
n=s.count(line)
io.open(sys.argv[2],"w",encoding="utf-8",newline="").write(s.replace(line,""))
sys.exit(0 if n==1 else 1)' "$H/$1.sh" "$T/$1_mut.sh"
}

FWD="$ROOT"
BCK="$(printf '%s' "$ROOT" | tr '/' '\\')"
WT='qepm/mailbox/worktask/WT-P20990101_001'; WTB='qepm\mailbox\worktask\WT-P20990101_001'

echo "== 종목 수 상한 훅 (worktask_constraint_enforcer) =="
HK="$H/worktask_constraint_enforcer.sh"
expect block "A 정슬래시 26종"          "$HK" opt26 "$FWD/$WT/optimization_package.json"
expect block "B 역슬래시 26종"          "$HK" opt26 "$BCK\\$WTB\\optimization_package.json"
expect block "C 섞인 구분자 26종"       "$HK" opt26 "$FWD/$WTB\\optimization_package.json"
expect allow "D 역슬래시 10종(정상)"    "$HK" opt10 "$BCK\\$WTB\\optimization_package.json"
if mutant worktask_constraint_enforcer; then
  expect allow "E 정규화 줄을 뺀 사본은 역슬래시 26종을 통과시킨다 — B 가 이것을 잡는다" "$T/worktask_constraint_enforcer_mut.sh" opt26 "$BCK\\$WTB\\optimization_package.json"
else ng "E 돌연변이 치환" "정규화 줄이 정확히 1곳이 아님"; fi

echo "== 졸업 관문 (discovery_graduation_gate) =="
HK="$H/discovery_graduation_gate.sh"
expect block "A 정슬래시 참조 없는 졸업 요청"    "$HK" req_bad "$FWD/$WT/request.json"
expect block "B 역슬래시 참조 없는 졸업 요청"    "$HK" req_bad "$BCK\\$WTB\\request.json"
expect block "C 섞인 구분자"                     "$HK" req_bad "$FWD/$WTB\\request.json"
expect allow "D 역슬래시 발견형 요청(정상)"      "$HK" req_ok  "$BCK\\$WTB\\request.json"
if mutant discovery_graduation_gate; then
  expect allow "E 정규화 줄을 뺀 사본은 역슬래시 졸업 요청을 통과시킨다 — B 가 이것을 잡는다" "$T/discovery_graduation_gate_mut.sh" req_bad "$BCK\\$WTB\\request.json"
else ng "E 돌연변이 치환" "정규화 줄이 정확히 1곳이 아님"; fi

echo "== 레거시 쓰기 차단 (legacy_write_block) =="
HK="$H/legacy_write_block.sh"
expect block "A 정슬래시 _archive_v55"           "$HK" code "$FWD/04_Research/_archive_v55/zz_probe.R"
expect block "B 역슬래시 _archive_v55"           "$HK" code "$BCK\\04_Research\\_archive_v55\\zz_probe.R"
expect block "B 역슬래시 legacy\\v55"            "$HK" code "$BCK\\legacy\\v55\\zz_probe.R"
expect block "C 섞인 구분자 _archive_4_6"        "$HK" code "$FWD/04_Research\\_archive_4_6\\zz_probe.R"
expect allow "D 역슬래시 정상 경로"              "$HK" code "$BCK\\04_Research\\zz_probe.R"
if mutant legacy_write_block; then
  expect allow "E 정규화 줄을 뺀 사본은 역슬래시 레거시 경로를 통과시킨다 — B 가 이것을 잡는다" "$T/legacy_write_block_mut.sh" code "$BCK\\04_Research\\_archive_v55\\zz_probe.R"
else ng "E 돌연변이 치환" "정규화 줄이 정확히 1곳이 아님"; fi

echo "== 이미 양쪽을 보던 훅 (회귀 감시) =="
expect block "F safety_guard 역슬래시 05_Production"   "$H/safety_guard.sh" code "$BCK\\05_Production\\zz_probe.R"
expect block "F safety_guard 역슬래시 01_Literature"   "$H/safety_guard.sh" code "$BCK\\01_Literature\\zz_probe.md"
expect allow "F safety_guard 역슬래시 정상 경로"       "$H/safety_guard.sh" code "$BCK\\04_Research\\zz_probe.R"
expect block "F book_write_guard 역슬래시 BOOK 등록부" "$H/book_write_guard.sh" code "$BCK\\06_Registry\\book\\book_registry.json"

finish
