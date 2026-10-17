#!/usr/bin/env bash
#==============================================================================
# qw_updatefile_unattended.sh — 퀀티 Update_File 무인 수급(도훈 결정 QW-UPDATEFILE-UNATTENDED 안 A · 2026-10-16)
#
# 왜: consensus · investor_act · universe_support 패널의 원천 xlsx(03_Universe/Update_File/*_update.xlsx)를 갱신하는 것은
#   ops/qw_refresh.ps1 뿐인데, 08-29 계정 잠금 위험(저장 안 된 비밀번호로 로그인 클릭 40회)으로 무인 체인에서 뺐다
#   (run_nolayer4_monthly.sh:36-38). 그 뒤 세 자료는 사람이 손으로 돌린 날만 들어왔다(09-19 · 10-06 · Universe_Support 는 08-29 뒤 0회)
#   — 데이터 갱신 전담 Superfan 진단 2026-10-16 R4(04_Research/programs/_supervision/superfan/components/daily_refresh/20261016_2100_diagnosis.md).
# 무엇: daily_refresh.sh [1pre] 의 벤치 정본 수급이 **같은 실행에서 rc=0 으로 전진했을 때만**(= 퀀티 세션이 살아 있다는 양성 대조)
#   로그인 클릭 없이(-SkipLogin) Investor_Act · Consensus 를 받는다. 직전 월말이 Universe_Support 패널(us_k200) 최신일보다 뒤면
#   Universe_Support 도 받는다(월말 스냅샷 — 달에 한 번). -SkipLogin = 로그인 클릭 · 자격 점검 · 단말 재기동 없음 → 08-29 잠금 경로는 열리지 않는다.
# ★(2026-10-17 도훈 '이제 퀀티 실행 문제없이 되니까 주가관련 복잡한 규칙들 모두 없애고 Universe update 에 있는 파일들 매일 데이터 리프레시할 때
#   퀀티로 최신화시켜는걸로 Rawdata 관리하자' · 결정 RAWDATA-QW-ONLY-20261017) — RAWDATA 주가 원천 = 퀀티 단일(네이버 T+0 · KRX 갭필 · 아침 보충 퇴역).
#   Update_File 4종(OHLCVS → Universe_Support → Investor_Act → Consensus — 주가 · 위생 플래그 먼저)을 **매일** 받는다. 드라이버(qw_refresh.ps1)가
#   목표일(직전 거래일)에 이미 닿은 파일은 건너뛰므로 주말 · 휴일은 곧바로 끝난다. 월말 조건(Universe_Support 달 1회)은 퇴역 — 위생 플래그(거래정지 등)도 매일.
#   관문 = 벤치 수급 rc=3(전제 부재 — 단말 로그인 창 · 애드인 미등록 → 사람이 로그인해야 한다)일 때만 건너뛴다. rc=1(일시 오류 — 10-17 실측
#   'RPC 호출 실패 0x800706BE')·rc=2(벤치 변화 없음)여도 시도한다 — -SkipLogin 은 로그인 클릭 · 단말 재기동이 없어 08-29 계정 잠금 경로가 열리지 않는다.
#   보고 = 마지막 줄의 done=<완료>/<대상> · incomplete=0|1(드라이버 END 줄 판독 — 대상 중 목표일 미달이 있거나 rc≠0 이면 1). 호출부가 DR_FAILED 로 싣는다
#   (보충 원천이 없으니 미완료 = 그날 RAWDATA 정체 — 조용히 넘어가지 않는다).
# 계약: 리프레시를 멈추지 않는다 — 시간 상한(진행 인지) · 실패해도 경보 줄만. 종료 코드 0 = 어떤 파일이든 전진(호출부가 [0b] 적재를 한 번 더) ·
#   10 = 건너뜀 · 전진 없음. 마지막 줄 = 'QWUF<TAB>state=…<TAB>only=…<TAB>advanced=…<TAB>rc=…' · 기록 .cache/qw_updatefile_unattended.json
# 끄기: QVEST_QW_UPDATEFILE_UNATTENDED=0
# 사용: bash qw_updatefile_unattended.sh <벤치 정본 수급 rc> <python>
#   검사 주입(검사 전용): QWUF_REFRESH_CMD(수급 명령 — 기본 powershell.exe … qw_refresh.ps1) · QWUF_STATE · QWUF_US_PARQUET · QWUF_TIMEOUT · QWUF_LOG
#==============================================================================
set -u
QW_RC="${1:-1}"; PY="${2:-}"
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
STATE="${QWUF_STATE:-$BASE/.cache/qw_refresh_state.json}"
US_PARQUET="${QWUF_US_PARQUET:-$BASE/.cache/universe_support/us_k200.parquet}"
LOGJ="${QWUF_LOG:-$BASE/.cache/qw_updatefile_unattended.json}"
TMO="${QWUF_TIMEOUT:-2400}"
DONE="?"; INC=0   # 드라이버 END 줄의 완료/대상 · 미완료 표식(수급 뒤 채운다)
fin() {   # $1 state · $2 only · $3 advanced · $4 rc · $5 note — 기록 + 마지막 줄 + 종료
  printf 'QWUF\tstate=%s\tonly=%s\tadvanced=%s\trc=%s\tdone=%s\tincomplete=%s\n' "$1" "$2" "$3" "$4" "$DONE" "$INC"
  printf '{"at":"%s","state":"%s","only":"%s","advanced":"%s","rc":"%s","bench_rc":"%s","done":"%s","incomplete":"%s","note":"%s"}\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" "$3" "$4" "$QW_RC" "$DONE" "$INC" "${5:-}" > "$LOGJ" 2>/dev/null || true
  if [ "$1" = "advanced" ]; then exit 0; else exit 10; fi
}
[ "${QVEST_QW_UPDATEFILE_UNATTENDED:-1}" = "1" ] || fin disabled "-" 0 "-" "QVEST_QW_UPDATEFILE_UNATTENDED=0"
[ "$QW_RC" = "3" ] && fin skipped "-" 0 "-" "벤치 정본 수급 rc=3(전제 부재 — 단말 로그인 창 · 애드인 미등록) — 사람이 로그인해야 받는다"
[ -n "$PY" ] && [ -x "$PY" ] || fin skipped "-" 0 "-" "python 미발견"
ONLY="${QWUF_ONLY:-OHLCVS,Universe_Support,Investor_Act,Consensus}"   # 10-17 — 4종 매일(주가 · 위생 먼저)
## (퇴역 10-17) 구판은 Universe_Support 를 직전 월말이 us_k200 최신일보다 뒤일 때만(달 1회) 받았다 — 아래 판독은 기록(로그 줄)용으로만 남긴다
US_MAX=$("$PY" -c "import pyarrow.parquet as pq,pyarrow.compute as pc;print(pc.max(pq.read_table(r'$(cygpath -w "$US_PARQUET" 2>/dev/null || echo "$US_PARQUET")',columns=['Date']).column('Date')))" 2>/dev/null | tr -d '\r')
snap() { "$PY" -c "import json,sys;d=json.load(open(r'$(cygpath -w "$STATE" 2>/dev/null || echo "$STATE")',encoding='utf-8-sig'));print(';'.join('%s=%s'%(k,(d.get(k) or {}).get('ymd','')) for k in sys.argv[1].split(',')))" "$ONLY" 2>/dev/null | tr -d '\r'; }
before=$(snap)
echo "[qwuf] Update_File 무인 수급(퀀티 단일 · 10-17) $ONLY · 벤치 수급 rc=$QW_RC · us_k200 최신 ${US_MAX:-?} · 상한 ${TMO}초 · 전: ${before:-?}"
if [ -n "${QWUF_REFRESH_CMD:-}" ]; then
  read -r -a CMD <<< "$QWUF_REFRESH_CMD"
else
  CMD=(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$BASE/02_Infrastructure/ops/qw_refresh.ps1")")
fi
# ★진행 인지 상한(2026-10-17) — 기본 상한(TMO)이 지나도 이 실행이 띄운 수급 Excel 이 일하고 있으면(CPU 누적 증가) 기다리고,
#   STALL_N 번 연속 늘지 않으면(멈춤) 또는 절대 상한(HARD)에서 끝낸다. 끝낼 때는 지휘 셸과 **이 실행이 띄운** Excel(시작 시각 ≥ 이 실행)만 닫는다
#   — 고아 Excel 이 다음 수급을 막는다 · 사람이 연 Excel 은 건드리지 않는다.
#   10-17 실측: Universe_Support 49일치가 40분 고정 상한에 잘렸다(지휘만 죽고 Excel 은 조회를 계속 · 저장할 주체 없음) → 세션이 그 Excel 을 닫아
#   46분을 버렸다. 실측: 08-29 수동 1개월분 ≈ 60분(qw_refresh_state.json OHLCVS 18:00 → Universe_Support 18:59) · 10-17 재수급 49일치(33거래일)
#   = 64.5분(01:51:11 → 02:55:39 · 조회 자체는 1분 남짓 · 484MB 통합문서 저장 · 2회차 확인이 대부분). 절대 상한 기본 2시간 = 그 실측의 약 2배
#   (월초 하루만 리프레시를 늦춘다 · 06:00 아침 체인 전). 검사 주입: QWUF_PROGRESS_CMD · QWUF_CLEANUP_CMD · QWUF_POLL_S · QWUF_STALL_N · QWUF_HARD_TIMEOUT
#   (10-17 4종 매일) 절대 상한 = 4종 실측 합의 약 2배(같은 규약): OHLCVS 42.4분(10-17 · 03-30~10-16 전 구간) + Universe_Support 64.5분(10-17) +
#   Investor_Act 29.2분(09-19 00:21→00:50) + Consensus 83.9분(09-19 00:50→02:14) = 220분 → 440분(26400초). 조회 자체는 파일마다 1분 남짓이고
#   대부분 대용량 통합문서 처리다(484 · 273 · 654MB). 멈춤은 정체 감지(STALL_N 회 연속 CPU 무증가)가 따로 끊는다.
HARD="${QWUF_HARD_TIMEOUT:-26400}"; POLL="${QWUF_POLL_S:-60}"; STALL_N="${QWUF_STALL_N:-5}"
T0_ISO=$(date '+%Y-%m-%d %H:%M:%S')
progress() {
  if [ -n "${QWUF_PROGRESS_CMD:-}" ]; then bash -c "$QWUF_PROGRESS_CMD" 2>/dev/null | tr -d '\r'; return; fi
  powershell.exe -NoProfile -Command "\$t=[datetime]'$T0_ISO'; \$p=Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { \$_.StartTime -ge \$t }; if (\$p) { [int](\$p | Measure-Object -Property CPU -Sum).Sum }" 2>/dev/null | tr -d '\r'
}
cleanup() {
  if [ -n "${QWUF_CLEANUP_CMD:-}" ]; then bash -c "$QWUF_CLEANUP_CMD" 2>/dev/null; return; fi
  powershell.exe -NoProfile -Command "\$t=[datetime]'$T0_ISO'; Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { \$_.StartTime -ge \$t } | Stop-Process -Force" >/dev/null 2>&1
}
QW_OUT=$(mktemp)
"${CMD[@]}" -SkipLogin -Only "$ONLY" -MaxRounds 2 > "$QW_OUT" 2>&1 &
qpid=$!
t0=$(date +%s); last=-1; stall=0; cut=""
while kill -0 "$qpid" 2>/dev/null; do
  w=0; while [ "$w" -lt "$POLL" ] && kill -0 "$qpid" 2>/dev/null; do sleep 1; w=$((w + 1)); done
  kill -0 "$qpid" 2>/dev/null || break
  el=$(( $(date +%s) - t0 )); [ "$el" -lt "$TMO" ] && continue
  cpu=$(progress)
  if [[ "$cpu" =~ ^[0-9]+$ ]] && [ "$cpu" -gt "$last" ]; then
    stall=0; last=$cpu; echo "[qwuf] 기본 상한 ${TMO}초 경과(${el}초) — 수급 Excel 일하는 중(CPU ${cpu}초) · 기다린다(절대 상한 ${HARD}초)"
  else stall=$((stall + 1)); fi
  if [ "$el" -ge "$HARD" ] || [ "$stall" -ge "$STALL_N" ]; then
    cut=$([ "$el" -ge "$HARD" ] && echo hard || echo stall)
    echo "[qwuf] ★수급 종료($cut · ${el}초) — 지휘 셸과 이 실행이 띄운 수급 Excel 을 닫는다"
    wp=$(cat "/proc/$qpid/winpid" 2>/dev/null); kill "$qpid" 2>/dev/null
    [ -n "$wp" ] && taskkill //PID "$wp" //T //F >/dev/null 2>&1
    cleanup; break
  fi
done
wait "$qpid" 2>/dev/null; rc=$?
[ -n "$cut" ] && rc=124
sed 's/^/  [qw] /' "$QW_OUT"
## 완료 수 = 드라이버 END 줄('===== END hh:mm:ss / done D/N (target T) =====') — 없으면(시간 상한으로 끊김 등) '?' · rc≠0 또는 D<N 이면 미완료
_dn=$(grep -oE 'done [0-9]+/[0-9]+' "$QW_OUT" | tail -n 1 | sed 's/^done //'); rm -f "$QW_OUT"
[ -n "$_dn" ] && DONE="$_dn"
if [ "$rc" != "0" ]; then INC=1
elif [ -n "$_dn" ] && [ "${_dn%%/*}" -lt "${_dn##*/}" ]; then INC=1; fi
after=$(snap)
adv=0
IFS=';' read -r -a B <<< "$before"; IFS=';' read -r -a A <<< "$after"
for i in "${!A[@]}"; do [ "${A[$i]}" != "${B[$i]:-}" ] && adv=$((adv + 1)); done
echo "[qwuf] 수급 rc=$rc(124 = 시간 상한) · 후: ${after:-?} · 전진 $adv"
if [ "$adv" -gt 0 ]; then fin advanced "$ONLY" "$adv" "$rc" "전 $before → 후 $after"; fi
fin no_advance "$ONLY" 0 "$rc" "전 $before · 후 $after"
