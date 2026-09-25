#!/usr/bin/env bash
# test_scheduler_bat_locale.sh — 예약작업 .bat 의 로케일 환경에서 R 은 UTF-8 CTYPE 로 떠야 한다 (v10.4 2026-09-24)
#
# 왜: Qvest_MorningReboot.bat 이 `export LC_ALL=C.UTF-8` 을 걸었다(2026-07-10 — bash 한글 파싱 크래시 회피).
#   bash 는 그 값을 받지만 **Windows R 은 C.UTF-8 을 세우지 못하고 C 로 떨어진다**("Setting LC_CTYPE=C.UTF-8 failed").
#   그 결과 재부팅으로 아침 체인이 시작된 날마다: 텔레그램 제목 "Q-Lead Â·"(섞인 리터럴 이중 인코딩 · 9월 34건),
#   rf_director 캐시가 한글 중간에서 잘려 부팅 Director 줄이 '미실행'으로 오표시, B5 설계 프롬프트의 '침식형'이
#   제어문자로 마스킹. 호출부마다 LC_ALL='English_United States.utf8' 을 따로 붙이던 방식(v10.1 09-03)은 새 R 호출자
#   5곳에서 같은 결함이 재발했다 → 근본(= .bat 환경)을 고치고 이 검사가 그 환경을 지킨다.
#
# 판정 (운영 로그·작업 정의 무접촉 — .bat 은 읽기만, 실행은 명령을 프로브로 바꾼 사본만):
#   S  정적: 어떤 .bat 도 LC_ALL/LC_CTYPE 를 C 계열(C · C.UTF-8 · POSIX)로 export 하지 않는다
#   R  런타임: 각 .bat 의 export 집합 그대로 Rscript 를 띄우면 l10n_info()$UTF-8 == TRUE
#   P  MorningReboot 동치: R 의 LC_COLLATE/LC_TIME == C (종전 C 폴백과 정렬·날짜 불변) · bash CTYPE UTF-8(한글 3자=3)
#      · 그 환경에서 bash -n morning_run.sh 통과
#   X  cmd 실경로: MorningReboot.bat 사본(명령만 프로브로 교체)을 cmd.exe 로 실행 → R UTF-8 TRUE · COLLATE C
#   I  위반 주입: 사본에 `export LC_ALL=C.UTF-8;` 삽입 → S·R 둘 다 잡는다
#   M  돌연변이(export 추출 무력화) → I 의 런타임 주입을 놓친다 = 추출이 판정을 지탱함
set -uo pipefail
_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
T='"test":"scheduler_bat_locale"'
[ -n "$PROJ" ] || { echo "{$T,\"pass\":0,\"fail\":1,\"total\":1,\"preflight\":\"no_root\"}"; exit 1; }
BATDIR="$PROJ/02_Infrastructure/ops/scheduler"
REBOOT="$BATDIR/Qvest_MorningReboot.bat"
PY=""
for c in "${QVEST_PY_BIN:-}" "${QVEST_PY:-}" "$PROJ/.venv_qvest_ml/Scripts/python.exe" "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -c 'import re' >/dev/null 2>&1 && { PY="$c"; break; }
done
RS="$(command -v Rscript 2>/dev/null || true)"; [ -n "$RS" ] || RS="/c/Program Files/R/R-4.5.2/bin/Rscript.exe"
{ [ -n "$PY" ] && [ -x "$RS" ] && [ -f "$REBOOT" ]; } || { echo "{$T,\"pass\":0,\"fail\":1,\"total\":1,\"preflight\":\"no_python_or_rscript_or_bat\"}"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.Renviron"
printf 'cat(sprintf("utf8=%%s collate=%%s time=%%s\\n", isTRUE(l10n_info()[["UTF-8"]]), Sys.getlocale("LC_COLLATE"), Sys.getlocale("LC_TIME")))\n' > "$TMP/probe.R"
printf 'x="\xea\xb0\x80\xeb\x82\x98\xeb\x8b\xa4"; echo ${#x}\n' > "$TMP/probe_bash.sh"
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
CLEAN=(-u LANG -u LC_ALL -u LC_CTYPE -u LC_COLLATE -u LC_TIME -u LC_MESSAGES -u LC_NUMERIC -u LC_MONETARY -u LANGUAGE)

# exports <bat> → "VAR=VAL" 줄들 (bash.exe -c "..." 안의 LANG/LC_* export, 등장 순서). EXTRACT_OFF=1 = 돌연변이(추출 무력화)
exports() {
  # ★Windows python stdout 은 CRLF — CR 을 남기면 'C.UTF-8\r' 같은 무효 로케일이 되어 검사가 엉뚱한 이유로
  #   통과·실패한다(초판 실측: P2 가 CR 때문에 우연히 통과, R·P3 가 CR 때문에 거짓 실패). 여기서 한 번에 벗긴다.
  EXTRACT_OFF="${EXTRACT_OFF:-0}" "$PY" - "$1" <<'PY' | tr -d '\r'
import os, re, sys
if os.environ.get("EXTRACT_OFF") == "1": sys.exit(0)
t = open(sys.argv[1], "rb").read().decode("ascii", "replace")
for body in re.findall(r'bash\.exe"\s+-c\s+"(.*?)"\s*$', t, re.M):
    for m in re.finditer(r"export\s+(LANG|LC_[A-Z]+)=('([^']*)'|([^;\s]+))\s*;", body):
        print("%s=%s" % (m.group(1), m.group(3) if m.group(3) is not None else m.group(4)))
PY
}
# c_family <bat> → 위반 export 목록(없으면 NONE)
c_family() {
  local v out=""
  while IFS= read -r v; do
    case "$v" in LC_ALL=*|LC_CTYPE=*)
      local val="${v#*=}"; local lv="${val,,}"
      case "$lv" in c|posix|c.*) out="$out ${v}" ;; esac ;;
    esac
  done < <(exports "$1")
  [ -n "$out" ] && echo "${out# }" || echo NONE
}
# rprobe <bat> → "utf8=.. collate=.. time=.." (그 .bat 의 export 집합만으로 Rscript 기동)
rprobe() {
  local -a kv=(); local v
  while IFS= read -r v; do [ -n "$v" ] && kv+=("$v"); done < <(exports "$1")
  env "${CLEAN[@]}" "${kv[@]}" R_ENVIRON_USER="$TMP/empty.Renviron" "$RS" --no-save --no-restore "$TMP/probe.R" 2>/dev/null | tr -d '\r' | grep '^utf8=' | tail -1
}
bprobe() {  # $1=bat $2=script → bash 가 본 한글 3자 길이 ; $3(선택)=bash -n 대상
  local -a kv=(); local v
  while IFS= read -r v; do [ -n "$v" ] && kv+=("$v"); done < <(exports "$1")
  env "${CLEAN[@]}" "${kv[@]}" bash "$2" 2>/dev/null | tr -d '\r'
}

echo "== 예약작업 .bat 로케일 → R UTF-8 =="
shopt -s nullglob
BATS=("$BATDIR"/*.bat)
chk "B .bat 목록 비어있지 않음" YES "$([ "${#BATS[@]}" -gt 0 ] && echo YES || echo NO)"
bad_s=""; bad_r=""
declare -A seen_env=()
for b in "${BATS[@]}"; do
  n="$(basename "$b")"
  cf="$(c_family "$b")"; [ "$cf" = NONE ] || bad_s="$bad_s $n[$cf]"
  key="k:$(exports "$b" | tr '\n' ' ')"
  grep -q 'bash\.exe" -c' "$b" || continue
  if [ -z "${seen_env[$key]+x}" ]; then seen_env[$key]="$(rprobe "$b")"; fi
  case "${seen_env[$key]}" in utf8=TRUE*) : ;; *) bad_r="$bad_r $n{${seen_env[$key]:-no_output}}" ;; esac
done
chk "S 정적: LC_ALL/LC_CTYPE 를 C 계열로 export 하는 .bat 없음" "" "${bad_s# }"
chk "R 런타임: 전 .bat export 집합에서 R l10n_info()\$UTF-8 == TRUE (환경 ${#seen_env[@]}종)" "" "${bad_r# }"

rp="$(rprobe "$REBOOT")"
chk "P1 MorningReboot: R CTYPE UTF-8" "utf8=TRUE" "${rp%% *}"
chk "P2 MorningReboot: R LC_COLLATE/LC_TIME = C (종전과 정렬·날짜 동치)" "collate=C time=C" "${rp#* }"
chk "P3 MorningReboot: bash CTYPE UTF-8 (한글 3자 = 길이 3 · 07-10 수리 유지)" "3" "$(bprobe "$REBOOT" "$TMP/probe_bash.sh")"
MR="$PROJ/02_Infrastructure/ops/morning_run.sh"
printf 'bash -n "%s" && echo PARSE_OK\n' "$MR" > "$TMP/probe_parse.sh"
chk "P4 MorningReboot 환경에서 bash -n morning_run.sh 통과" "PARSE_OK" "$(bprobe "$REBOOT" "$TMP/probe_parse.sh" | tail -1)"

# X — cmd.exe 실경로: 명령 줄의 `bash …/morning_run.sh reboot >> … 2>&1` 만 R 프로브로 바꾼 사본을 실행(작업 정의 무접촉)
if command -v cmd.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  OUTF="$TMP/cmd_probe.out"
  "$PY" - "$REBOOT" "$TMP/xprobe.bat" "$TMP/probe.R" "$OUTF" "$TMP/empty.Renviron" <<'PY'
import re, sys
src, dst, probe, outf, renv = sys.argv[1:6]
b = open(src, "rb").read()
new = ("export R_ENVIRON_USER=%s; Rscript --no-save --no-restore %s > %s 2>&1" % (renv, probe, outf)).encode()
b2, n = re.subn(rb"bash /c/[^ ]*/morning_run\.sh reboot >> [^\"]*2>&1", new, b)
open(dst, "wb").write(b2 if n == 1 else b"@echo off\r\nexit /b 9\r\n")
PY
  env "${CLEAN[@]}" cmd.exe //c "$(cygpath -w "$TMP/xprobe.bat")" >/dev/null 2>&1
  xr="$(tr -d '\r' < "$OUTF" 2>/dev/null | grep '^utf8=' | tail -1)"
  chk "X cmd.exe 로 실행한 MorningReboot 사본: R UTF-8 · COLLATE C" "utf8=TRUE collate=C" "${xr% time=*}"
else
  chk "X cmd.exe 실경로 프로브(전제: cmd.exe·cygpath)" YES NO
fi

# I — 위반 주입(사본): 종전 결함 형태 `export LC_ALL=C.UTF-8;` 를 LANG 뒤에 되살린다
INJ="$TMP/inj.bat"
"$PY" -c "
import sys
b=open(sys.argv[1],'rb').read(); o=b'export LANG=C.UTF-8; '
open(sys.argv[2],'wb').write(b.replace(o, o+b'export LC_ALL=C.UTF-8; ', 1))" "$REBOOT" "$INJ"
chk "I1 주입 사본 → 정적 검사가 잡는다" "LC_ALL=C.UTF-8" "$(c_family "$INJ")"
ir="$(rprobe "$INJ")"
chk "I2 주입 사본 → 런타임 R UTF-8 FALSE 로 잡힌다(결함 재현)" "utf8=FALSE" "${ir%% *}"
# M — 돌연변이: export 추출을 끄면 같은 주입을 놓친다(= 통과가 추출 덕임을 실증)
mr="$(EXTRACT_OFF=1 rprobe "$INJ")"
chk "M 돌연변이(export 추출 무력화) → I2 를 놓침" "utf8=TRUE" "${mr%% *}"

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{%s,"pass":%d,"fail":%d,"total":%d}\n' "$T" "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
