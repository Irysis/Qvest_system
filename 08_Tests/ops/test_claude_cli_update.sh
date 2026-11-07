#!/usr/bin/env bash
#==============================================================================
# test_claude_cli_update.sh — 무인 레인 npm CLI 자동 업데이트(claude_cli_update.sh) + 레인 쪽 배선(rf_llm_env.sh)
#   (2026-11-07 도훈 "무인레인이 쓰는 npm cli는 최신버전 나올때마다 자동 업데이트" · 방식 2 = 예약 작업)
# 재는 것:
#   U. 업데이터 — 가짜 npm(view · install) · 가짜 설치(package.json + bin/claude.exe) · 가짜 프로세스 목록으로
#      최신 · 업데이트 · 사용 중 · 조회 사망 · 조회 rc≠0 · 사용 중→유휴 · 잠금 직후 경합 · 설치 실패 재설치 ·
#      npm 자체 롤백(재설치 생략) · 복구 실패 · 설치 뒤 확인 실패 · 버전 확인 실패(오류 문구 속 숫자) ·
#      stderr 경고 · --check · --dry-run · 남의 잠금 · stale 잠금 · npm 잔여 폴더 · downgrade · 미설치 · stable · 인자 오류
#   T. 텔레그램 — 수동 실행은 안 보냄 · 무인 선언 + QVEST_TG_DRY_RUN=1 이면 R 경로(tg_agent_brief)가 끝까지 돈다 ·
#      연속 보류 경보는 3회째에만
#   L. 레인 쪽 — DISABLE_AUTOUPDATER · DISABLE_UPDATES 가 claude 에(1차 · 폴백) · 호출자 셸로 안 샘 · 잠금 있으면 대기 ·
#      stale 잠금 무시 · 대기 상한 · 잠금 없으면 즉시 · 레인과 업데이터가 같은 잠금 경로를 계산
#   M. 뮤테이션 테스트 — '#OK' 요구 제거 · 잠금 뒤 재확인 제거 · 재설치 제거 · 버전 앵커 제거 · 자체 롤백 판정 제거 ·
#      레인 lane_env 추가 줄 제거 · 레인 대기 호출 제거 → 각 뮤턴트를 위 검사가 잡는다(검사가 살아 있다는 증거)
#   P. 실물 — claude_cli_procs.ps1 이 npm 경로에서 도는 exe 를 그 PID 로 잡고(#OK) · 자기 자신은 빼고 ·
#      데스크톱 앱(WindowsApps · Claude-Data)은 안 잡는다(양성 대조)
# 격리: 쓰기는 mktemp 디렉터리뿐(상태 · 로그 · 잠금 · 설치 위치 전부 주입 · QVEST_HOST=ZZTEST).
#   실제 npm · claude · 텔레그램 발송은 없다(T 는 QVEST_TG_DRY_RUN=1 — 본문만 만든다).
#   밤 배터리가 QVEST_UNATTENDED=1 로 돌려도 업데이터 실행은 그 변수를 지우고 시작한다(오발송 차단).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
OPS="$ROOT/02_Infrastructure/ops"
UPD="$OPS/claude_cli_update.sh"
P=0; F=0
ok(){ P=$((P+1)); printf '  OK    %s\n' "$1"; }
ng(){ F=$((F+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
T="$(mktemp -d)"; BGPIDS=""
trap 'for p in $BGPIDS; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
echo "=== test_claude_cli_update (root: $ROOT) ==="
for f in "$UPD" "$OPS/claude_cli_procs.ps1" "$OPS/rf_llm_env.sh"; do
  [ -f "$f" ] || { echo "대상 없음: $f"; echo "{\"test\":\"claude_cli_update\",\"pass\":0,\"fail\":1,\"preflight\":\"missing $(basename "$f")\"}"; exit 1; }
done

# ── 가짜 npm · 가짜 프로세스 목록 ─────────────────────────────────────────────
cat > "$T/npm" <<'NPM'
#!/usr/bin/env bash
D="${FAKE_DIR:?}"
echo "npm $*" >> "$D/npm_calls.log"
pkg="$D/prefix/node_modules/@anthropic-ai/claude-code"
case "${1:-}" in
  view)   [ -f "$D/view_out" ] && cat "$D/view_out"; [ -f "$D/view_err" ] && cat "$D/view_err" >&2
          exit "$(cat "$D/view_rc" 2>/dev/null || echo 0)" ;;
  config) echo "$D/prefix"; exit 0 ;;
  install)
    spec=""; for a in "$@"; do case "$a" in @anthropic-ai/claude-code@*) spec="${a##*@}" ;; esac; done
    echo "install spec=$spec after_procs_calls=$(cat "$D/procs_calls" 2>/dev/null || echo 0) lock=$([ -d "${QVEST_CLI_UPDATE_LOCK:-/nonexistent_qv}" ] && echo held || echo none)" >> "$D/install.log"
    case "$(cat "$D/install_mode" 2>/dev/null || echo ok)" in
      fail_target) [ "$spec" = "$(cat "$D/target")" ] && { rm -f "$pkg/bin/claude.exe"; echo "npm ERR! code EBUSY"; echo "npm ERR! syscall unlink"; exit 1; } ;;
      fail_clean)  [ "$spec" = "$(cat "$D/target")" ] && { echo "npm ERR! code ETIMEDOUT"; exit 1; } ;;   # npm 이 스스로 롤백 — 파일 그대로
      fail_all)    rm -f "$pkg/bin/claude.exe"; echo "npm ERR! code EPERM"; exit 1 ;;
      stale_exe)   [ "$spec" = "$(cat "$D/target")" ] && { sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$spec\"/" "$pkg/package.json"; exit 0; } ;;
    esac
    mkdir -p "$pkg/bin"
    printf '{\n  "name": "@anthropic-ai/claude-code",\n  "version": "%s"\n}\n' "$spec" > "$pkg/package.json"
    printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$spec" > "$pkg/bin/claude.exe"; chmod +x "$pkg/bin/claude.exe"
    exit 0 ;;
esac
exit 0
NPM
cat > "$T/procs.sh" <<'PR'
#!/usr/bin/env bash
# 호출마다 procs_seq 의 다음 줄(끝 줄은 반복): idle | busy | dead(출력 없음 · rc 0) | err(#OK 0 을 찍고 rc 2)
D="${FAKE_DIR:?}"
n=$(( $(cat "$D/procs_calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/procs_calls"
st="$(sed -n "${n}p" "$D/procs_seq")"; [ -n "$st" ] || st="$(tail -1 "$D/procs_seq")"
case "$st" in
  idle) echo "#OK 0" ;;
  busy) printf '4242\tC:\\Users\\X\\AppData\\Roaming\\npm\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe\n#OK 1\n' ;;
  dead) : ;;
  err)  echo "#OK 0"; exit 2 ;;
esac
exit 0
PR
chmod +x "$T/npm" "$T/procs.sh"

NC=0; FD=""
setup(){ # $1 설치 버전(빈칸 = 미설치) · $2 npm view 출력 · $3 프로세스 순서(공백 구분)
  NC=$((NC + 1)); FD="$T/c$NC"; mkdir -p "$FD/prefix/node_modules/@anthropic-ai" "$FD/state"
  if [ -n "$1" ]; then
    local pkg="$FD/prefix/node_modules/@anthropic-ai/claude-code"; mkdir -p "$pkg/bin"
    printf '{\n  "name": "@anthropic-ai/claude-code",\n  "version": "%s"\n}\n' "$1" > "$pkg/package.json"
    printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$1" > "$pkg/bin/claude.exe"; chmod +x "$pkg/bin/claude.exe"
  fi
  printf '%s\n' "$2" > "$FD/view_out"; echo 0 > "$FD/view_rc"; printf '%s' "$2" > "$FD/target"
  printf '%s\n' $3 > "$FD/procs_seq"; echo ok > "$FD/install_mode"
  EXTRA_ENV=(); UPD_BIN="$UPD"
}
run_upd(){
  env -u QVEST_UNATTENDED -u QVEST_ALERT_FORCE -u QVEST_NO_ALERT -u QVEST_TG_DRY_RUN -u QVEST_CLI_CHANNEL \
    FAKE_DIR="$FD" QVEST_HOST=ZZTEST QVEST_CLI_NPM="$T/npm" QVEST_CLI_PREFIX="$FD/prefix" \
    QVEST_CLI_PROCS_CMD="bash '$T/procs.sh'" QVEST_CLI_STATE_DIR="$FD/state" QVEST_CLI_LOG="$FD/log.txt" \
    QVEST_CLI_UPDATE_LOCK="$FD/lock" QVEST_CLI_GRACE_SEC=0 QVEST_CLI_POLL_SEC=0 QVEST_CLI_MAX_WAIT_MIN=0 \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} bash "$UPD_BIN" --quiet "$@" >> "$FD/stdout.txt" 2>&1
}
pkgver(){ grep -m1 -oE '"version": "[^"]+"' "$FD/prefix/node_modules/@anthropic-ai/claude-code/package.json" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/'; }
exever(){ "$FD/prefix/node_modules/@anthropic-ai/claude-code/bin/claude.exe" --version 2>/dev/null | head -1 | cut -d' ' -f1; }
ninst(){ [ -f "$FD/install.log" ] && wc -l < "$FD/install.log" | tr -d ' ' || echo 0; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null; }
mutate(){ # $1 원본 $2 뮤턴트 $3 원문 $4 대체 — 리터럴 치환 · 0회면 rc 1(치환 좌표가 낡음 = 뮤테이션 실패로 보고)
  OLD="$3" NEW="$4" perl -0777 -pe 'BEGIN{$o=$ENV{OLD};$n=$ENV{NEW};$c=0} $c += s/\Q$o\E/$n/g; END{exit($c ? 0 : 1)}' "$1" > "$2" \
    && ! cmp -s "$1" "$2"
}
SJ(){ echo "$FD/state/claude_cli_ZZTEST.json"; }
HJ(){ echo "$FD/state/claude_cli_history_ZZTEST.jsonl"; }

echo "--- U. 업데이터 ---"
setup 2.1.319 2.1.319 "idle"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=up_to_date installed=2.1.319" && [ "$(ninst)" = 0 ] && has "$(SJ)" '"result":"up_to_date"'; } \
  && ok "U1 최신이면 설치 없음 · SUMMARY 1줄 · 상태 up_to_date" || ng "U1 최신" "rc=$rc $(tail -2 "$FD/log.txt")"

setup 2.1.261 2.1.319 "idle"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=updated before=2.1.261 after=2.1.319" && [ "$(pkgver)" = 2.1.319 ] && [ "$(exever)" = 2.1.319 ]; } \
  && ok "U2 유휴면 업데이트 — package.json · claude.exe --version 모두 2.1.319" || ng "U2 업데이트" "rc=$rc pkg=$(pkgver) exe=$(exever) $(tail -2 "$FD/log.txt")"
{ has "$FD/npm_calls.log" "npm install -g @anthropic-ai/claude-code@2.1.319" && [ "$(ninst)" = 1 ] && has "$FD/install.log" "lock=held"; } \
  && ok "U3 정확한 버전으로 한 번 설치 · 설치하는 동안 교체 잠금을 쥠" || ng "U3 설치 호출" "$(cat "$FD/npm_calls.log" "$FD/install.log" 2>/dev/null | tr '\n' '|')"
{ [ ! -e "$FD/lock" ] && has "$(HJ)" '"before":"2.1.261","target":"2.1.319","after":"2.1.319","result":"updated"' && has "$(SJ)" '"installed":"2.1.319"'; } \
  && ok "U4 끝나면 잠금 해제 · 이력 1줄(before/target/after) · 상태 갱신" || ng "U4 기록" "lock=$([ -e "$FD/lock" ] && echo 남음) hist=$(cat "$(HJ)" 2>/dev/null)"

setup 2.1.261 2.1.319 "busy"; run_upd; rc1=$?; run_upd; rc2=$?
{ [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && has "$FD/log.txt" "SUMMARY result=skip_busy" && [ "$(ninst)" = 0 ] && has "$(SJ)" '"streak":2' && [ ! -e "$FD/lock" ] && [ "$(pkgver)" = 2.1.261 ]; } \
  && ok "U5 레인 claude 가 계속 돌면 보류(rc 0) · 설치 0 · 연속 보류 2" || ng "U5 사용 중" "rc=$rc1/$rc2 inst=$(ninst) $(cat "$(SJ)" 2>/dev/null)"

setup 2.1.261 2.1.319 "dead"; run_upd; rc=$?
{ [ "$rc" = 0 ] && [ "$(ninst)" = 0 ] && has "$FD/log.txt" "result=skip_busy" && has "$FD/log.txt" "조회 실패"; } \
  && ok "U6 프로세스 조회가 죽으면(출력 없음) 사용 중 — 0개로 읽지 않는다" || ng "U6 조회 사망" "inst=$(ninst) $(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "err"; run_upd; rc=$?
{ [ "$rc" = 0 ] && [ "$(ninst)" = 0 ] && has "$FD/log.txt" "result=skip_busy"; } \
  && ok "U7 조회 rc≠0 이면 '#OK 0' 을 찍었어도 사용 중" || ng "U7 조회 rc" "inst=$(ninst) $(tail -1 "$FD/log.txt")"

setup 2.1.261 2.1.319 "busy busy idle"; EXTRA_ENV=(QVEST_CLI_MAX_WAIT_MIN=1); run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "result=updated" && has "$FD/log.txt" "polls=3" && has "$FD/install.log" "after_procs_calls=4"; } \
  && ok "U8 사용 중 → 유휴 구간을 기다렸다가 업데이트(조회 3회 + 잠금 뒤 재확인 1회)" || ng "U8 대기" "$(tail -1 "$FD/log.txt") | $(cat "$FD/install.log" 2>/dev/null)"

setup 2.1.261 2.1.319 "idle busy idle idle"; EXTRA_ENV=(QVEST_CLI_MAX_WAIT_MIN=1); run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "잠금 직후 레인 claude 감지" && has "$FD/install.log" "after_procs_calls=4" && [ "$(ninst)" = 1 ]; } \
  && ok "U9 잠금을 잡은 직후 레인이 뜨면 잠금을 풀고 다시 기다린다(경합)" || ng "U9 경합" "$(cat "$FD/install.log" 2>/dev/null) $(grep -c 감지 "$FD/log.txt")"

setup 2.1.261 2.1.319 "idle"; echo fail_target > "$FD/install_mode"; run_upd; rc=$?
{ [ "$rc" = 2 ] && has "$FD/log.txt" "SUMMARY result=failed_rolled_back" && [ "$(pkgver)" = 2.1.261 ] && [ "$(exever)" = 2.1.261 ] \
  && [ "$(sed -n 1p "$FD/install.log" | grep -o 'spec=[0-9.]*')" = "spec=2.1.319" ] && [ "$(sed -n 2p "$FD/install.log" | grep -o 'spec=[0-9.]*')" = "spec=2.1.261" ] \
  && has "$(HJ)" '"after":"2.1.261","result":"failed_rolled_back"' && has "$FD/log.txt" "이전 버전 재설치" && [ ! -e "$FD/lock" ]; } \
  && ok "U10 설치 실패(exe 삭제된 채) → 이전 버전 재설치 · 실행 확인 · rc 2" || ng "U10 재설치" "rc=$rc pkg=$(pkgver) exe=$(exever) $(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; echo fail_clean > "$FD/install_mode"; run_upd; rc=$?
{ [ "$rc" = 2 ] && has "$FD/log.txt" "SUMMARY result=failed_rolled_back" && [ "$(ninst)" = 1 ] && has "$FD/log.txt" "npm 자체 롤백" && [ "$(exever)" = 2.1.261 ]; } \
  && ok "U11 npm 이 스스로 롤백해 이전 버전이 온전하면 재설치하지 않는다(설치 1회)" || ng "U11 자체 롤백" "rc=$rc inst=$(ninst) $(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; echo fail_all > "$FD/install_mode"; run_upd; rc=$?
{ [ "$rc" = 3 ] && has "$FD/log.txt" "SUMMARY result=failed_broken" && has "$(SJ)" '"result":"failed_broken"' && [ ! -e "$FD/lock" ]; } \
  && ok "U12 복구까지 실패 → rc 3 · failed_broken(사람 조치) · 잠금은 해제" || ng "U12 복구 실패" "rc=$rc $(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; echo stale_exe > "$FD/install_mode"; run_upd; rc=$?
{ [ "$rc" = 2 ] && has "$FD/log.txt" "확인 실패" && [ "$(exever)" = 2.1.261 ] && [ "$(pkgver)" = 2.1.261 ]; } \
  && ok "U13 npm 은 성공인데 claude.exe 가 이전 버전이면 실패로 보고 되돌린다" || ng "U13 확인" "rc=$rc pkg=$(pkgver) exe=$(exever) $(grep -m1 실패 "$FD/log.txt")"

setup 2.1.261 "x" "idle"; printf 'npm ERR! code ENOTFOUND\nnpm ERR! node v24.13.1\n' > "$FD/view_out"; echo 1 > "$FD/view_rc"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=check_failed" && [ "$(ninst)" = 0 ] && has "$(SJ)" '"streak":1'; } \
  && ok "U14 npm view 실패 → check_failed(rc 0 · 설치 없음 · 연속 1)" || ng "U14 확인 실패" "rc=$rc $(tail -1 "$FD/log.txt")"
setup 2.1.261 "x" "idle"; printf 'npm warn config node v24.13.1\n' > "$FD/view_out"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "result=check_failed" && [ "$(ninst)" = 0 ]; } \
  && ok "U15 rc 0 이어도 버전 문자열 하나가 아니면 믿지 않는다(오류 문구 속 24.13.1 을 버전으로 안 읽음)" || ng "U15 버전 앵커" "inst=$(ninst) $(cat "$FD/install.log" 2>/dev/null)"
setup 2.1.261 2.1.319 "idle"; printf 'npm warn deprecated something 9.9.9\n' > "$FD/view_err"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "result=updated" && [ "$(pkgver)" = 2.1.319 ]; } \
  && ok "U16 npm 경고(stderr)가 버전 줄 뒤에 와도 stdout 의 버전을 읽는다" || ng "U16 stderr" "$(tail -1 "$FD/log.txt")"

setup 2.1.261 2.1.319 "idle"; run_upd --check; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=update_available installed=2.1.261 target=2.1.319" && [ "$(ninst)" = 0 ] && [ ! -f "$FD/procs_calls" ]; } \
  && ok "U17 --check = 버전만 비교(프로세스 조회 · 설치 없음)" || ng "U17 --check" "$(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; run_upd --dry-run; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=dry_run" && [ "$(ninst)" = 0 ] && [ ! -e "$FD/lock" ]; } \
  && ok "U18 --dry-run = 유휴 판정까지 · 설치 없음 · 잠금 해제" || ng "U18 --dry-run" "$(tail -1 "$FD/log.txt")"

setup 2.1.261 2.1.319 "idle"; mkdir -p "$FD/lock"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "다른 업데이터가 잠금을 쥐고 있음" && [ "$(ninst)" = 0 ] && [ -d "$FD/lock" ]; } \
  && ok "U19 fresh 한 남의 잠금 = 다른 업데이터 실행 중 → 보류 · 그 잠금은 안 지움" || ng "U19 남의 잠금" "inst=$(ninst) $(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; mkdir -p "$FD/lock"; touch -d '2 hours ago' "$FD/lock"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "stale 잠금 회수" && has "$FD/log.txt" "result=updated" && [ ! -e "$FD/lock" ]; } \
  && ok "U20 stale 잠금(2시간) 회수 뒤 업데이트" || ng "U20 stale 잠금" "$(tail -2 "$FD/log.txt")"
setup 2.1.261 2.1.319 "idle"; mkdir -p "$FD/prefix/node_modules/@anthropic-ai/.claude-code-AbC123/bin"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "npm 잔여 폴더 정리: .claude-code-AbC123" && [ ! -e "$FD/prefix/node_modules/@anthropic-ai/.claude-code-AbC123" ] && has "$FD/log.txt" "result=updated"; } \
  && ok "U21 npm 잔여 폴더(.claude-code-*)를 설치 전에 지운다" || ng "U21 잔여 폴더" "$(grep 잔여 "$FD/log.txt")"
setup 2.1.319 2.1.311 "idle"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "downgrade" && [ "$(pkgver)" = 2.1.311 ]; } \
  && ok "U22 채널 버전이 더 낮으면(태그 되돌림) 그 버전을 따른다" || ng "U22 downgrade" "pkg=$(pkgver) $(tail -1 "$FD/log.txt")"
setup "" 2.1.319 "idle"; run_upd; rc=$?
{ [ "$rc" = 0 ] && has "$FD/log.txt" "SUMMARY result=not_installed" && [ "$(ninst)" = 0 ]; } \
  && ok "U23 npm 전역 설치가 없으면 새로 설치하지 않는다(not_installed)" || ng "U23 미설치" "$(tail -1 "$FD/log.txt")"
setup 2.1.261 2.1.311 "idle"; run_upd --channel stable; rc=$?
{ [ "$rc" = 0 ] && has "$FD/npm_calls.log" "npm view @anthropic-ai/claude-code dist-tags.stable" && [ "$(pkgver)" = 2.1.311 ]; } \
  && ok "U24 --channel stable = dist-tags.stable 을 읽는다" || ng "U24 stable" "$(head -2 "$FD/npm_calls.log" | tr '\n' '|')"
setup 2.1.261 2.1.319 "idle"; run_upd --channel beta; rc=$?
{ [ "$rc" = 64 ] && [ "$(ninst)" = 0 ]; } && ok "U25 알 수 없는 채널 = rc 64 · 아무것도 안 함" || ng "U25 인자" "rc=$rc"

echo "--- T. 텔레그램 ---"
setup 2.1.261 2.1.319 "idle"; run_upd; rc=$?
has "$FD/log.txt" "tg skip(무인 선언 없음" && ok "T1 수동 실행(무인 선언 없음)은 보내지 않는다" || ng "T1 수동" "$(grep tg "$FD/log.txt")"
if command -v Rscript >/dev/null 2>&1 || [ -x "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" ]; then
  # 미리보기 본문의 이모지 수 — tg_send 의 검사 정규식([U+1F300–1F9FF · U+2600–27BF])과 같은 범위로 센다
  emo(){ perl -CSD -ne 'if (/=== dry_run output/) {$on=1; next} if (/tg sent:|tg fail:/) {$on=0} if ($on) { $c += () = /[\x{1F300}-\x{1F9FF}\x{2600}-\x{27BF}]/g } END { print $c+0 }' "$1"; }
  setup 2.1.261 2.1.319 "idle"; EXTRA_ENV=(QVEST_UNATTENDED=1 QVEST_TG_DRY_RUN=1); run_upd; rc=$?
  { has "$FD/log.txt" "tg sent: updated" && has "$FD/log.txt" "dry_run output" && has "$FD/log.txt" "Claude CLI 업데이트" && ! ls "$FD/state"/_tg_*.R >/dev/null 2>&1; } \
    && ok "T2 무인 + 미리보기 → tg_agent_brief 가 본문을 만든다(R 경로 생존 · 생성 스크립트 정리)" || ng "T2 R 경로" "$(grep -E 'tg |Error|오류' "$FD/log.txt" | head -3 | tr '\n' '|')"
  n2="$(emo "$FD/log.txt")"
  { [ "$n2" -ge 5 ] && has "$FD/log.txt" "쉬운 설명"; } && ok "T3 업데이트 알림 이모지 ${n2}개 ≥ 5(qvest-telegram EMOJI_MIN) · 쉬운 설명 섹션" || ng "T3 이모지" "n=$n2"
  setup 2.1.261 2.1.319 "busy"; EXTRA_ENV=(QVEST_UNATTENDED=1 QVEST_TG_DRY_RUN=1)
  run_upd; a1=$(grep -c "tg sent: stuck" "$FD/log.txt"); run_upd; a2=$(grep -c "tg sent: stuck" "$FD/log.txt"); run_upd; a3=$(grep -c "tg sent: stuck" "$FD/log.txt")
  { [ "$a1" = 0 ] && [ "$a2" = 0 ] && [ "$a3" = 1 ]; } && ok "T4 연속 보류 경보는 3회째에만(1 · 2회째 무음)" || ng "T4 연속" "a=$a1/$a2/$a3"
  n4="$(emo "$FD/log.txt")"
  [ "$n4" -ge 5 ] && ok "T5 연속 보류 알림 이모지 ${n4}개 ≥ 5" || ng "T5 이모지" "n=$n4"
else
  ng "T2·T3 Rscript 없음" "텔레그램 R 경로를 못 잰다"
fi

echo "--- L. 레인 쪽(rf_llm_env.sh) ---"
cat > "$T/fake_claude" <<'FAKE'
#!/usr/bin/env bash
echo "AU=${DISABLE_AUTOUPDATER:-unset} UP=${DISABLE_UPDATES:-unset} MEM=${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-unset}"
cat > /dev/null
if [ -n "${FAKE_LIMIT_ONCE:-}" ] && [ ! -e "$FAKE_LIMIT_ONCE" ]; then : > "$FAKE_LIMIT_ONCE"; echo "You've hit your session limit · resets 2am"; fi
FAKE
chmod +x "$T/fake_claude"; printf 'P' > "$T/pf.txt"
lrun(){ # $1 rf_llm_env.sh · 나머지 = NAME=VALUE → 출력 = 레인 stderr + PARENT 줄 · 걸린 초는 $T/lane_sec
  local envf="$1"; shift
  rm -f "$T/out.txt" "$T/out.txt.primary"
  local t0; t0=$(date +%s)
  # ★env 는 -u 를 NAME=VALUE 보다 앞에서만 옵션으로 읽는다 — 지울 이름은 여기 고정 목록에, 호출자는 NAME=VALUE 만 넘긴다.
  env -u DISABLE_AUTOUPDATER -u DISABLE_UPDATES -u QVEST_CLI_UPDATE_LOCK -u ROOT -u QVEST_CLI_LOCK_STALE_SEC \
    QVEST_HOST=ZZTEST QVEST_CLI_WAIT_STEP_SEC=1 "$@" bash -c '. "$1"; LLM_MODEL=opus; LLM_EFFORT=max; LLM_FALLBACK_MODEL="${FB:-}"; LLM_FALLBACK_EFFORT=max
    RF_CLAUDE_BIN="$2" rf_llm_agent_run "$3" "$4" 30
    echo "PARENT AU=${DISABLE_AUTOUPDATER:-unset} UP=${DISABLE_UPDATES:-unset} FELL=$LLM_FELL_BACK"' _ "$envf" "$T/fake_claude" "$T/pf.txt" "$T/out.txt" 2>&1
  echo $(( $(date +%s) - t0 )) > "$T/lane_sec"
}
o="$(lrun "$OPS/rf_llm_env.sh" QVEST_CLI_UPDATE_LOCK="$T/nolk")"; r="$(cat "$T/out.txt" 2>/dev/null)"
case "$r" in *"AU=1 UP=1 MEM=1"*) ok "L1 claude 에 DISABLE_AUTOUPDATER=1 · DISABLE_UPDATES=1 (기존 AutoMem 변수와 함께)" ;; *) ng "L1 업데이터 끄기 미전달" "$r" ;; esac
case "$o" in *"PARENT AU=unset UP=unset"*) ok "L2 호출자 셸로 새지 않는다(함수 지역)" ;; *) ng "L2 누출" "$o" ;; esac
{ [ "$(cat "$T/lane_sec")" -le 1 ] && ! printf '%s' "$o" | grep -q '\[rf_llm\]'; } && ok "L3 잠금 없으면 대기 없이 · 메시지 없이 시작" || ng "L3 즉시" "sec=$(cat "$T/lane_sec") $o"
rm -f "$T/limit_once"
o="$(lrun "$OPS/rf_llm_env.sh" QVEST_CLI_UPDATE_LOCK="$T/nolk" FB=opus FAKE_LIMIT_ONCE="$T/limit_once")"; r="$(cat "$T/out.txt" 2>/dev/null)"
{ printf '%s' "$o" | grep -q "FELL=1" && printf '%s' "$r" | grep -q "AU=1 UP=1" && grep -q "AU=1 UP=1" "$T/out.txt.primary" 2>/dev/null; } \
  && ok "L4 한도 폴백 재실행(2차)에도 · 1차에도 두 변수" || ng "L4 폴백" "o=$o r=$r"
mkdir -p "$T/lk1"; ( sleep 2; rmdir "$T/lk1" 2>/dev/null ) & BGPIDS="$BGPIDS $!"
o="$(lrun "$OPS/rf_llm_env.sh" QVEST_CLI_UPDATE_LOCK="$T/lk1")"; s="$(cat "$T/lane_sec")"
{ [ "$s" -ge 2 ] && printf '%s' "$o" | grep -q "Claude CLI 교체 중" && printf '%s' "$(cat "$T/out.txt" 2>/dev/null)" | grep -q "AU=1"; } \
  && ok "L5 교체 잠금이 있으면 새 claude 를 띄우지 않고 기다렸다가(${s}s) 시작" || ng "L5 대기" "sec=$s $o"
mkdir -p "$T/lk2"; touch -d '2 hours ago' "$T/lk2"
o="$(lrun "$OPS/rf_llm_env.sh" QVEST_CLI_UPDATE_LOCK="$T/lk2")"; s="$(cat "$T/lane_sec")"
{ [ "$s" -le 1 ] && printf '%s' "$o" | grep -q "stale"; } && ok "L6 stale 잠금(2시간 · 죽은 업데이터)은 무시하고 바로 시작" || ng "L6 stale 잠금" "sec=$s $o"
mkdir -p "$T/lk3"; ( for i in 1 2 3 4 5 6 7 8 9 10; do touch "$T/lk3" 2>/dev/null; sleep 1; done ) & BGPIDS="$BGPIDS $!"
o="$(lrun "$OPS/rf_llm_env.sh" QVEST_CLI_UPDATE_LOCK="$T/lk3" QVEST_CLI_LOCK_STALE_SEC=3)"; s="$(cat "$T/lane_sec")"
{ [ "$s" -ge 3 ] && [ "$s" -le 7 ] && printf '%s' "$o" | grep -q "대기 상한"; } && ok "L7 잠금이 계속 갱신돼도 상한(${s}s)에서 진행 — 레인을 무기한 세우지 않는다" || ng "L7 상한" "sec=$s $o"
rm -rf "$T/lk3"
# 같은 잠금 경로: 레인(ROOT 기준 기본 경로)과 업데이터(QM_ROOT 기준 기본 경로)가 같은 디렉터리를 본다
LKD="$T/root/.cache/machine/claude_cli_update_ZZTEST.lock"
mkdir -p "$LKD"; ( sleep 2; rmdir "$LKD" 2>/dev/null ) & BGPIDS="$BGPIDS $!"
o="$(lrun "$OPS/rf_llm_env.sh" ROOT="$T/root")"; s="$(cat "$T/lane_sec")"
setup 2.1.261 2.1.319 "idle"; mkdir -p "$LKD"
env -u QVEST_UNATTENDED -u QVEST_CLI_UPDATE_LOCK -u QVEST_CLI_STATE_DIR -u QVEST_CLI_LOG -u CLAUDE_PROJECT_DIR \
  FAKE_DIR="$FD" QM_ROOT="$T/root" QVEST_HOST=ZZTEST QVEST_CLI_NPM="$T/npm" \
  QVEST_CLI_PREFIX="$FD/prefix" QVEST_CLI_PROCS_CMD="bash '$T/procs.sh'" QVEST_CLI_GRACE_SEC=0 QVEST_CLI_POLL_SEC=0 QVEST_CLI_MAX_WAIT_MIN=0 \
  bash "$UPD" --quiet --no-telegram >/dev/null 2>&1
{ [ "$s" -ge 2 ] && grep -qF "다른 업데이터가 잠금을 쥐고 있음($LKD)" "$T/root/.cache/scheduler_logs/claude_cli_update_ZZTEST.log" 2>/dev/null; } \
  && ok "L8 레인 기본 경로 = 업데이터 기본 경로(<root>/.cache/machine/claude_cli_update_<HOST>.lock)" || ng "L8 경로 일치" "lane_sec=$s $(tail -1 "$T/root/.cache/scheduler_logs/claude_cli_update_ZZTEST.log" 2>/dev/null)"
rm -rf "$LKD"

echo "--- M. 뮤테이션 테스트(검사가 살아 있다는 증거) ---"
# M1 흔한 오류 — 줄 수를 세고 '#OK' 를 요구하지 않으면 죽은 조회기가 '0개' 로 읽힌다 → U6 상황에서 설치해 버린다
if mutate "$UPD" "$T/m1a.sh" 'if [ "$rc" -ne 0 ] || [ -z "$okl" ]; then BUSY_N=-1' 'if [ "$rc" -ne 0 ]; then BUSY_N=-1' \
   && mutate "$T/m1a.sh" "$T/m1.sh" 'BUSY_N="${okl#\#OK }"' 'BUSY_N="$(printf "%s\n" "$out" | grep -vcE "^#|^$")"'; then
  setup 2.1.261 2.1.319 "dead"; UPD_BIN="$T/m1.sh"; run_upd
  [ "$(ninst)" -ge 1 ] && ok "M1 '#OK' 요구를 뺀 뮤턴트는 죽은 조회기에서 설치한다(U6 이 잡는다)" || ng "M1 판별력" "inst=$(ninst) $(tail -1 "$FD/log.txt")"
else ng "M1 뮤테이션" "치환 좌표가 낡음"; fi
# M2 잠금 뒤 재확인 제거 → 경합 상황(U9)에서 레인이 뜬 순간에 설치
if mutate "$UPD" "$T/m2.sh" '      sleep "$GRACE_SEC"
      busy_check
      if [ "$BUSY_N" = 0 ]; then GOT=1; break; fi' '      GOT=1; break'; then
  setup 2.1.261 2.1.319 "idle busy idle idle"; EXTRA_ENV=(QVEST_CLI_MAX_WAIT_MIN=1); UPD_BIN="$T/m2.sh"; run_upd
  has "$FD/install.log" "after_procs_calls=1" && ok "M2 재확인을 뺀 뮤턴트는 경합 순간에 설치한다(U9 가 잡는다)" || ng "M2 판별력" "$(cat "$FD/install.log" 2>/dev/null)"
else ng "M2 뮤테이션" "치환 좌표가 낡음"; fi
# M3 재설치 제거 → 설치 실패(U10)에서 exe 없이 끝남
if mutate "$UPD" "$T/m3.sh" '  npm_install "$BEFORE" || FAIL2="$INSTALL_ERR"' '  :'; then
  setup 2.1.261 2.1.319 "idle"; echo fail_target > "$FD/install_mode"; UPD_BIN="$T/m3.sh"; run_upd; rc=$?
  { [ "$rc" = 3 ] && [ -z "$(exever)" ]; } && ok "M3 재설치를 뺀 뮤턴트는 exe 없이 rc 3(U10 이 잡는다)" || ng "M3 판별력" "rc=$rc exe=$(exever)"
else ng "M3 뮤테이션" "치환 좌표가 낡음"; fi
# M4 버전 앵커 제거 → 오류 문구 속 숫자(U15)를 버전으로 읽고 설치 시도
if mutate "$UPD" "$T/m4.sh" "grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\$'; then REMOTE=\"\$last\"" "grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then REMOTE=\"\$(printf '%s' \"\$last\" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)\""; then
  setup 2.1.261 "x" "idle"; printf 'npm warn config node v24.13.1\n' > "$FD/view_out"; UPD_BIN="$T/m4.sh"; run_upd
  has "$FD/install.log" "spec=24.13.1" && ok "M4 앵커를 뺀 뮤턴트는 24.13.1 설치를 시도한다(U15 가 잡는다)" || ng "M4 판별력" "$(cat "$FD/install.log" 2>/dev/null) $(tail -1 "$FD/log.txt")"
else ng "M4 뮤테이션" "치환 좌표가 낡음"; fi
# M5 자체 롤백 판정 제거 → npm 이 이미 되돌린 경우(U11)에도 재설치(설치 2회)
if mutate "$UPD" "$T/m5.sh" 'if healthy_at "$BEFORE"; then
  HOW="npm 자체 롤백' 'if false; then
  HOW="npm 자체 롤백'; then
  setup 2.1.261 2.1.319 "idle"; echo fail_clean > "$FD/install_mode"; UPD_BIN="$T/m5.sh"; run_upd
  [ "$(ninst)" = 2 ] && ok "M5 자체 롤백 판정을 뺀 뮤턴트는 불필요하게 재설치한다(U11 이 잡는다)" || ng "M5 판별력" "inst=$(ninst)"
else ng "M5 뮤테이션" "치환 좌표가 낡음"; fi
# M6 레인 lane_env 추가 줄 제거 → L1 이 잡는다
if mutate "$OPS/rf_llm_env.sh" "$T/rf_m6.sh" '  lane_env+=(DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1)' '  :'; then
  lrun "$T/rf_m6.sh" QVEST_CLI_UPDATE_LOCK="$T/nolk" >/dev/null; r="$(cat "$T/out.txt" 2>/dev/null)"
  case "$r" in *"AU=unset UP=unset"*) ok "M6 추가 줄을 지운 뮤턴트 → 두 변수 소실(L1 이 잡는다)" ;; *) ng "M6 판별력" "$r" ;; esac
else ng "M6 뮤테이션" "치환 좌표가 낡음"; fi
# M7 레인 대기 호출 제거(1차) → L5 가 잡는다
if mutate "$OPS/rf_llm_env.sh" "$T/rf_m7.sh" '  rf_llm_wait_cli_update
  env "${lane_env[@]}"' '  env "${lane_env[@]}"'; then
  mkdir -p "$T/lk7"; ( sleep 3; rmdir "$T/lk7" 2>/dev/null ) & BGPIDS="$BGPIDS $!"
  lrun "$T/rf_m7.sh" QVEST_CLI_UPDATE_LOCK="$T/lk7" >/dev/null; s="$(cat "$T/lane_sec")"
  [ "$s" -le 1 ] && ok "M7 대기 호출을 지운 뮤턴트는 교체 중에도 바로 띄운다(L5 가 잡는다)" || ng "M7 판별력" "sec=$s"
  rm -rf "$T/lk7"
else ng "M7 뮤테이션" "치환 좌표가 낡음"; fi

echo "--- P. 실물 프로세스 조회(claude_cli_procs.ps1) ---"
PSW="$(cygpath -w "$OPS/claude_cli_procs.ps1" 2>/dev/null || echo "$OPS/claude_cli_procs.ps1")"
psl(){ powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PSW" "$@" 2>&1 | tr -d '\r'; }
if command -v powershell.exe >/dev/null 2>&1; then
  o="$(psl)"
  { printf '%s\n' "$o" | tail -1 | grep -qE '^#OK [0-9]+$' && ! printf '%s\n' "$o" | grep -qiE 'WindowsApps|Claude-Data'; } \
    && ok "P1 조회 생존(#OK 줄) · 데스크톱 앱(WindowsApps · Claude-Data) 프로세스는 안 잡는다" || ng "P1 조회" "$o"
  FX="$T/fx/npm/node_modules/@anthropic-ai/claude-code/bin"; mkdir -p "$FX"
  if cp /usr/bin/sleep.exe "$FX/claude.exe" 2>/dev/null; then
    "$FX/claude.exe" 20 & spid=$!; BGPIDS="$BGPIDS $spid"; sleep 1
    wpid="$(cat "/proc/$spid/winpid" 2>/dev/null)"
    o="$(psl)"
    { [ -n "$wpid" ] && printf '%s\n' "$o" | grep -qE "^${wpid}"$'\t'".*claude-code.bin.claude.exe" && printf '%s\n' "$o" | tail -1 | grep -qE '^#OK [1-9][0-9]*$'; } \
      && ok "P2 npm 경로에서 도는 claude.exe 를 그 PID($wpid)로 잡는다(양성 대조)" || ng "P2 양성 대조" "wpid=$wpid $o"
    kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  else ng "P2 양성 대조" "sleep.exe 복사 실패"; fi
  o="$(psl -Marker 'claude_cli_procs')"
  [ "$(printf '%s\n' "$o" | tail -1)" = "#OK 0" ] && ok "P3 자기 자신(명령줄에 스크립트 이름)은 빼고 센다" || ng "P3 자기 제외" "$o"
else
  ng "P1~P3 powershell.exe 없음" "실물 조회를 못 잰다"
fi

echo
echo "합계: 통과 $P · 실패 $F"
echo "{\"test\":\"claude_cli_update\",\"pass\":$P,\"fail\":$F,\"total\":$((P+F))}"
[ "$F" -eq 0 ]
