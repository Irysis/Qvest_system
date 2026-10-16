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
# 계약: 리프레시를 멈추지 않는다 — 시간 상한(기본 40분) · 실패해도 경보 줄만. 종료 코드 0 = 어떤 파일이든 전진(호출부가 [0b] 적재를 한 번 더) ·
#   10 = 건너뜀 · 전진 없음. 마지막 줄 = 'QWUF<TAB>state=…<TAB>only=…<TAB>advanced=…<TAB>rc=…' · 기록 .cache/qw_updatefile_unattended.json
# 끄기: QVEST_QW_UPDATEFILE_UNATTENDED=0
# 사용: bash qw_updatefile_unattended.sh <벤치 정본 수급 rc> <python>
#   검사 주입(검사 전용): QWUF_REFRESH_CMD(수급 명령 — 기본 powershell.exe … qw_refresh.ps1) · QWUF_STATE · QWUF_US_PARQUET · QWUF_TODAY · QWUF_TIMEOUT · QWUF_LOG
#==============================================================================
set -u
QW_RC="${1:-1}"; PY="${2:-}"
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
STATE="${QWUF_STATE:-$BASE/.cache/qw_refresh_state.json}"
US_PARQUET="${QWUF_US_PARQUET:-$BASE/.cache/universe_support/us_k200.parquet}"
LOGJ="${QWUF_LOG:-$BASE/.cache/qw_updatefile_unattended.json}"
TODAY="${QWUF_TODAY:-$(date +%F)}"
TMO="${QWUF_TIMEOUT:-2400}"
fin() {   # $1 state · $2 only · $3 advanced · $4 rc · $5 note — 기록 + 마지막 줄 + 종료
  printf 'QWUF\tstate=%s\tonly=%s\tadvanced=%s\trc=%s\n' "$1" "$2" "$3" "$4"
  printf '{"at":"%s","state":"%s","only":"%s","advanced":"%s","rc":"%s","bench_rc":"%s","note":"%s"}\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" "$3" "$4" "$QW_RC" "${5:-}" > "$LOGJ" 2>/dev/null || true
  if [ "$1" = "advanced" ]; then exit 0; else exit 10; fi
}
[ "${QVEST_QW_UPDATEFILE_UNATTENDED:-1}" = "1" ] || fin disabled "-" 0 "-" "QVEST_QW_UPDATEFILE_UNATTENDED=0"
[ "$QW_RC" = "0" ] || fin skipped "-" 0 "-" "벤치 정본 수급 rc=$QW_RC — 세션 생존 미확인(무인 수급은 rc=0 인 밤에만)"
[ -n "$PY" ] && [ -x "$PY" ] || fin skipped "-" 0 "-" "python 미발견"
ONLY="Investor_Act,Consensus"
US_MAX=$("$PY" -c "import pyarrow.parquet as pq,pyarrow.compute as pc;print(pc.max(pq.read_table(r'$(cygpath -w "$US_PARQUET" 2>/dev/null || echo "$US_PARQUET")',columns=['Date']).column('Date')))" 2>/dev/null | tr -d '\r')
PME=$(date -d "$(date -d "$TODAY" +%Y-%m-01) -1 day" +%F)
if [ -z "$US_MAX" ] || [[ "$PME" > "$US_MAX" ]]; then ONLY="Universe_Support,$ONLY"; fi
snap() { "$PY" -c "import json,sys;d=json.load(open(r'$(cygpath -w "$STATE" 2>/dev/null || echo "$STATE")',encoding='utf-8-sig'));print(';'.join('%s=%s'%(k,(d.get(k) or {}).get('ymd','')) for k in sys.argv[1].split(',')))" "$ONLY" 2>/dev/null | tr -d '\r'; }
before=$(snap)
echo "[qwuf] 퀀티 세션 살아 있음(벤치 정본 전진) — Update_File 무인 수급 $ONLY · 직전 월말 $PME · us_k200 최신 ${US_MAX:-?} · 상한 ${TMO}초 · 전: ${before:-?}"
if [ -n "${QWUF_REFRESH_CMD:-}" ]; then
  read -r -a CMD <<< "$QWUF_REFRESH_CMD"
else
  CMD=(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$BASE/02_Infrastructure/ops/qw_refresh.ps1")")
fi
timeout "$TMO" "${CMD[@]}" -SkipLogin -Only "$ONLY" -MaxRounds 2 2>&1 | sed 's/^/  [qw] /'
rc=${PIPESTATUS[0]}
after=$(snap)
adv=0
IFS=';' read -r -a B <<< "$before"; IFS=';' read -r -a A <<< "$after"
for i in "${!A[@]}"; do [ "${A[$i]}" != "${B[$i]:-}" ] && adv=$((adv + 1)); done
echo "[qwuf] 수급 rc=$rc(124 = 시간 상한) · 후: ${after:-?} · 전진 $adv"
if [ "$adv" -gt 0 ]; then fin advanced "$ONLY" "$adv" "$rc" "전 $before → 후 $after"; fi
fin no_advance "$ONLY" 0 "$rc" "전 $before · 후 $after"
