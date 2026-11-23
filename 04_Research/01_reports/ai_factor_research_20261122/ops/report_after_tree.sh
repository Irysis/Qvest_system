#!/usr/bin/env bash
# report_after_tree.sh — 트리 AutoML(측정까지)이 끝나기를 기다렸다가 종합 보고를 만들어 텔레그램으로 보낸다(도훈 11-23 "AutoML 끝나면 종합보고 텔레로 보내주고").
#   긴 대기열(run_queue_long.sh)은 건드리지 않는다 — 그 출력 파일에서 트리 묶음이 끝났다는 줄만 기다린다.
#   그 시각에는 수식 탐색 3판이 돌기 시작하므로, 종합 보고(R · 약 2분 · 가벼움)는 진행 상태 파일을 건드리지 않게 돌리고(07 을 --stage 없이),
#   발송은 알림 스크립트의 종합 보고 통(--event=report)으로 한다. 후속 연구 계획 요약(followup_plan.json)이 함께 실린다.
#   트리 AutoML 이 실패로 끝났으면 보내지 않고 1 로 끝낸다(실패 알림은 감시 셸이 따로 보낸다).
#   사용: bash ops/report_after_tree.sh <긴 대기열의 출력 파일>
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
[ $# -ge 1 ] || { echo "사용: report_after_tree.sh <긴 대기열의 출력 파일>"; exit 2; }
QOUT="$1"
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[report_after_tree] QM_ROOT 가 없다"; exit 2; }
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
# 긴 대기열 셸 · 감시 셸이 살아 있는 수(이 질의를 하는 파워셸 자신은 뺀다 — 명령줄에 같은 글자가 들어 있다)
alive() { powershell -NoProfile -Command "(Get-CimInstance Win32_Process | Where-Object { \$_.Name -match 'python|bash' -and \$_.CommandLine -match 'ops/run_queue_long\.sh|aif_run\.py' } | Measure-Object).Count" 2>/dev/null | tr -d '\r '; }

# 1. 트리 묶음의 끝(측정까지) · 실패 · 대기열 소멸 가운데 하나를 기다린다 — 출력 파일의 첫 생성기가 트리 AutoML 이다
rc=""; gone=0
while :; do
  if grep -qE '^\[run_generator\] 끝 rc=' "$QOUT" 2>/dev/null; then rc="$(grep -m1 -oE '^\[run_generator\] 끝 rc=[0-9]+' "$QOUT" | grep -oE '[0-9]+$')"; break; fi
  if grep -qE '^\[run_generator\] 생성 실패' "$QOUT" 2>/dev/null; then rc=99; break; fi
  n="$(alive)"; if [ "${n:-1}" = "0" ]; then gone=$((gone + 1)); else gone=0; fi
  if [ $gone -ge 3 ]; then rc=98; break; fi                       # 세 번 연속 대기열 · 감시 셸이 안 보이면 멈춘 것으로 본다
  sleep 60
done
echo "[report_after_tree] $(date '+%F %T') 트리 묶음 끝 신호 rc=$rc"
[ "$rc" = "0" ] || { echo "[report_after_tree] 트리 AutoML 이 정상으로 끝나지 않았다(rc=$rc · 99 = 생성 실패 · 98 = 대기열이 사라짐) — 종합 보고를 보내지 않는다"; exit 1; }

# 2. 종합 보고(진행 상태 파일 무접촉) → 3. 텔레그램 종합 보고 통
"$RS" --vanilla "$RD/run/07_final_report.R" || { echo "[report_after_tree] 종합 보고 생성 실패"; exit 3; }
"$RS" --vanilla "$RD/notify/aif_progress_notify.R" --send --force --event=report "--summary=$ROOT/.cache/aif_research/stage_summary_final.json"
r=$?; echo "[report_after_tree] $(date '+%F %T') 발송 rc=$r"; exit $r
}
main "$@"; exit $?
