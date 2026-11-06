#!/usr/bin/env bash
#==============================================================================
# test_qw_refresh_anchor.sh — test_qw_refresh_anchor.ps1(퀀티 드라이버 B5 앵커 F2 시험)의 bash 래퍼 (2026-11-06)
#
# 왜: 08_Tests/hooks/run_all_hooks.sh 는 확장자로 실행기를 고른다(.R → Rscript · .py → python · 그 밖 → bash).
#     .ps1 을 SUITES 에 그대로 넣으면 bash 가 PowerShell 문법을 돌려 깨진다 → 이 래퍼가 powershell 로 넘긴다(편입 자체는 원래 세션 몫).
# 하는 일:
#   ① 자기 점검 — 가짜 powershell 스텁으로 이 래퍼의 판정 규칙에 위반을 주입해 발화를 확인한다(아래 '판정 규칙' 전부 + 정상 통과 · 정상 실패).
#      하나라도 어긋나면 본 시험 결과를 내지 않고 preflight 로 끊는다(검사기가 죽은 채 통과로 읽히지 않게 · 사전 점검도 위반 주입으로 고정).
#   ② 카나리아 — 실제 powershell 이 기동해 토큰을 돌려주는가(-NoProfile -NonInteractive -Command).
#   ③ 본 시험 — powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <.ps1> → 출력을 그대로 보이고,
#      마지막 요약 JSON 을 검증해 **그 줄 그대로** 맨 끝에 한 번 낸다 · 종료 코드 = 시험의 종료 코드.
# 판정 규칙 — 죽은 실행이 성공으로 읽히지 않게(rc 0 · 0/N 위장 금지):
#   powershell 부재 · 카나리아 실패 · .ps1 부재 · 시간 상한 · 요약 JSON 없음 · 시험 이름 다름 · pass+fail=0 · rc≠0 인데 fail=0
#     → {"test":"test_qw_refresh_anchor","pass":0,"fail":1,"preflight":"<사유>"} + 종료 코드 1
#   rc=0 인데 fail>0 → 그 JSON 그대로 · 종료 코드 1(실패를 성공 종료 코드로 내지 않는다)
#   요약 JSON 형식 = .ps1 이 내는 그대로({"test":"…","pass":N,"fail":M} 또는 + ,"preflight":"…") — 형식이 바뀌면 여기서 '요약 없음'으로 막힌다.
# 검사 주입(환경변수 · 자기 점검이 쓴다): QW_ANCHOR_PS(powershell 경로) · QW_ANCHOR_PS1(.ps1 경로) · QW_ANCHOR_TIMEOUT(초) ·
#   QW_ANCHOR_SELFTEST=0(자기 점검 생략 — 자기 점검의 재귀 호출 전용)
# 사용: bash 08_Tests/data/test_qw_refresh_anchor.sh   · 마지막 줄: {"test":"test_qw_refresh_anchor","pass":N,"fail":M}
#==============================================================================
set -u
TEST=test_qw_refresh_anchor
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
PS1_PATH="${QW_ANCHOR_PS1:-$HERE/test_qw_refresh_anchor.ps1}"
# 시간 상한 = 멈춘 실행이 배터리를 붙잡지 않게 하는 멈춤 감지용. 근거: 실측 1회 68초(11-06 2차 판 · 1차 판 38~43초)의 약 13배 —
#   정상 실행을 끊지 않는 쪽으로 넉넉히 잡는다(느린 날 · 디스크 경합). timeout 명령이 없으면 상한 없이 돈다.
TMO="${QW_ANCHOR_TIMEOUT:-900}"
ST_DIR=""
trap '[ -n "$ST_DIR" ] && rm -rf "$ST_DIR"' EXIT

pre() {   # preflight 요약을 내고 끝낸다(사유의 \ " 는 / ' 로 — JSON 문자열을 깨지 않게)
  local why="$1"
  why="${why//\\//}"; why="${why//\"/\'}"; why="$(printf '%s' "$why" | tr '\n\t' '  ')"
  echo "  [PREFLIGHT] $1"
  printf '{"test":"%s","pass":0,"fail":1,"preflight":"%s"}\n' "$TEST" "$why"
  exit 1
}

find_ps() {
  if [ -n "${QW_ANCHOR_PS:-}" ]; then printf '%s\n' "$QW_ANCHOR_PS"; return; fi
  local c
  for c in "$(command -v powershell.exe 2>/dev/null)" "$(command -v powershell 2>/dev/null)" \
           /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
    if [ -n "$c" ] && [ -f "$c" ]; then printf '%s\n' "$c"; return; fi
  done
  printf '\n'
}

winpath() {   # powershell -File 은 Windows 경로가 필요하다
  cygpath -w "$1" 2>/dev/null && return
  (cd "$(dirname "$1")" && printf '%s\\%s\n' "$(pwd -W | tr '/' '\\')" "$(basename "$1")")
}

selftest() {
  ST_DIR="$(mktemp -d 2>/dev/null)" || ST_DIR=""
  [ -n "$ST_DIR" ] && [ -d "$ST_DIR" ] || pre "wrapper_selftest_failed(mktemp)"
  # 가짜 powershell — QWST_MODE 로 행동을 고른다(인수에 -Command 가 있으면 카나리아 호출)
  cat > "$ST_DIR/fakeps" <<'EOS'
#!/usr/bin/env bash
case " $* " in
  *" -Command "*) [ "${QWST_MODE:-}" = canary_dead ] && exit 0; echo QW_PS_CANARY_OK; exit 0 ;;
esac
case "${QWST_MODE:-}" in
  silent)      exit 0 ;;
  wrongname)   echo '{"test":"other_test","pass":3,"fail":0}'; exit 0 ;;
  rc_mismatch) echo '{"test":"test_qw_refresh_anchor","pass":5,"fail":0}'; exit 1 ;;
  zero)        echo '{"test":"test_qw_refresh_anchor","pass":0,"fail":0}'; exit 0 ;;
  ok)          echo 'body line'; echo '{"test":"test_qw_refresh_anchor","pass":5,"fail":0}'; exit 0 ;;
  fail)        echo '{"test":"test_qw_refresh_anchor","pass":4,"fail":2}'; exit 1 ;;
  fail_rc0)    echo '{"test":"test_qw_refresh_anchor","pass":4,"fail":2}'; exit 0 ;;
  inner_pre)   echo '{"test":"test_qw_refresh_anchor","pass":0,"fail":1,"preflight":"python_probe_failed"}'; exit 1 ;;
  hang)        exec sleep 30 ;;
esac
exit 3
EOS
  chmod +x "$ST_DIR/fakeps" 2>/dev/null
  : > "$ST_DIR/fake.ps1"
  local P='{"test":"test_qw_refresh_anchor","pass":0,"fail":1,"preflight":"'
  # 사례: 모드 | powershell 경로(nope = 없는 경로) | 기대 rc | 기대 마지막 줄 접두(또는 정확히)
  local cases=(
    "absent|nope|1|${P}powershell_absent"
    "canary_dead|fake|1|${P}powershell_canary_failed"
    "silent|fake|1|${P}no_summary_json"
    "wrongname|fake|1|${P}summary_name_mismatch"
    "rc_mismatch|fake|1|${P}rc_json_mismatch"
    "zero|fake|1|${P}zero_checks"
    "ok|fake|0|={\"test\":\"test_qw_refresh_anchor\",\"pass\":5,\"fail\":0}"
    "fail|fake|1|={\"test\":\"test_qw_refresh_anchor\",\"pass\":4,\"fail\":2}"
    "fail_rc0|fake|1|={\"test\":\"test_qw_refresh_anchor\",\"pass\":4,\"fail\":2}"
    "inner_pre|fake|1|={\"test\":\"test_qw_refresh_anchor\",\"pass\":0,\"fail\":1,\"preflight\":\"python_probe_failed\"}"
  )
  if command -v timeout >/dev/null 2>&1; then cases+=("hang|fake|1|${P}timeout"); fi
  local i c mode psel erc exp ps out rc last ok bad=""
  # 사례는 서로 독립이라 함께 띄운다(Windows bash 기동이 사례당 약 1초 — 차례로 돌면 배터리에 10초 넘게 얹힌다)
  for i in "${!cases[@]}"; do
    IFS='|' read -r mode psel erc exp <<< "${cases[$i]}"
    ps="$ST_DIR/fakeps"; [ "$psel" = nope ] && ps="$ST_DIR/no_such_powershell.exe"
    ( QWST_MODE="$mode" QW_ANCHOR_PS="$ps" QW_ANCHOR_PS1="$ST_DIR/fake.ps1" QW_ANCHOR_SELFTEST=0 QW_ANCHOR_TIMEOUT=2 \
        bash "$SELF" > "$ST_DIR/out_$i" 2>&1; echo $? > "$ST_DIR/rc_$i" ) &
  done
  wait
  for i in "${!cases[@]}"; do
    IFS='|' read -r mode psel erc exp <<< "${cases[$i]}"
    out="$(cat "$ST_DIR/out_$i" 2>/dev/null)"; rc="$(tr -d '\r\n ' < "$ST_DIR/rc_$i" 2>/dev/null)"
    last=$(printf '%s\n' "$out" | tr -d '\r' | tail -n 1)
    ok=1
    [ "$rc" = "$erc" ] || ok=0
    if [ "${exp:0:1}" = "=" ]; then [ "$last" = "${exp:1}" ] || ok=0
    else case "$last" in "$exp"*) ;; *) ok=0 ;; esac; fi
    # 정상 사례는 요약 JSON 이 출력에 정확히 한 번(본문 중복 없음)
    if [ "$mode" = ok ] && [ "$(printf '%s\n' "$out" | grep -c '"test":"test_qw_refresh_anchor"')" != 1 ]; then ok=0; fi
    [ "$ok" = 1 ] || bad="$bad $mode(rc=$rc last=${last:0:90})"
  done
  # ★자기 점검 실패는 점검 대상인 pre() 를 거치지 않고 직접 끝낸다(11-06 2차 검증 W8 — pre 의 exit 이 빠지면 본시험으로 흘러 rc 0)
  if [ -n "$bad" ]; then
    rm -rf "$ST_DIR"; ST_DIR=""
    printf '{"test":"test_qw_refresh_anchor","pass":0,"fail":1,"preflight":"wrapper_selftest_failed:%s"}\n' "$(printf '%s' "$bad" | tr -d '"\\' | head -c 300)"
    exit 1
  fi
  echo "   wrapper selftest OK - 위반 주입 ${#cases[@]}종(부재 · 카나리아 · 요약 없음 · 이름 · rc 불일치 · 0건 · 실패 · 상한 …) 발화 확인"
  rm -rf "$ST_DIR"; ST_DIR=""
}

[ "${QW_ANCHOR_SELFTEST:-1}" = 0 ] || selftest

PS="$(find_ps)"
[ -n "$PS" ] || pre "powershell_absent(not on PATH, not in System32)"
[ -e "$PS" ] || pre "powershell_absent($PS)"
CAN=$("$PS" -NoProfile -NonInteractive -Command "[Console]::Out.WriteLine('QW_PS_CANARY_OK')" 2>&1); RC=$?
CAN="$(printf '%s\n' "$CAN" | tr -d '\r')"
if [ "$RC" -ne 0 ] || ! printf '%s\n' "$CAN" | grep -qx 'QW_PS_CANARY_OK'; then
  pre "powershell_canary_failed(rc=$RC out=$(printf '%s' "$CAN" | head -c 120))"
fi
[ -f "$PS1_PATH" ] || pre "ps1_absent($PS1_PATH)"
W="$(winpath "$PS1_PATH")"
if command -v timeout >/dev/null 2>&1; then
  OUT=$(timeout "$TMO" "$PS" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$W" 2>&1); RC=$?
else
  OUT=$("$PS" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$W" 2>&1); RC=$?
fi
OUT="$(printf '%s\n' "$OUT" | tr -d '\r')"
JS=$(printf '%s\n' "$OUT" | grep -E '^\{"test":"[^"]*","pass":[0-9]+,"fail":[0-9]+(,"preflight":"[^"]*")?\}$' | tail -n 1)
# 본문을 그대로 보인다(요약 줄은 검증 뒤 맨 끝에 한 번만)
if [ -n "$JS" ]; then printf '%s\n' "$OUT" | grep -vxF -- "$JS"; else printf '%s\n' "$OUT"; fi
if [ -z "$JS" ]; then
  if [ "$RC" -eq 124 ]; then pre "timeout(${TMO}s, no summary json)"; fi
  pre "no_summary_json(rc=$RC)"
fi
NAME=$(printf '%s' "$JS" | sed -E 's/^\{"test":"([^"]*)".*$/\1/')
NP=$(printf '%s' "$JS" | sed -E 's/^.*"pass":([0-9]+).*$/\1/')
NF=$(printf '%s' "$JS" | sed -E 's/^.*"fail":([0-9]+).*$/\1/')
[ "$NAME" = "$TEST" ] || pre "summary_name_mismatch($NAME)"
[ $((NP + NF)) -gt 0 ] || pre "zero_checks(rc=$RC)"
if [ "$RC" -ne 0 ] && [ "$NF" -eq 0 ]; then pre "rc_json_mismatch(rc=$RC, summary says fail=0)"; fi
printf '%s\n' "$JS"
[ "$NF" -eq 0 ] || exit 1
exit 0
