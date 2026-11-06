#!/usr/bin/env bash
# run_daily_stress.sh — KR 자본시장 스트레스 일보 체인(같은 형태 · 내용만 갱신).
#   ① ECOS/FRED 직접 수급(fetch_research_inputs.py · ~60초) ② 지수 v1 재계산(KRSI_DAILY=1 → 부트스트랩 생략 · ~40초)
#   ③ 차트 v1 ④ PDF 일보 + 엑셀 대시보드(make_daily_report.py) → daily/<기준일>/ + daily/latest/
# 전제: 국내 시장 캐시(RAWDATA · investor_wide · benchmark · indices)는 데이터 리프레시가 최신화한다 — 이 스크립트는 리프레시를 띄우지 않는다.
# 실행: bash 04_Research/01_reports/kr_market_stress_index_20261106/run_daily_stress.sh [--skip-fetch] [--no-pdf]
#   예약(도훈 결정 뒤): 리프레시가 끝나는 시각 뒤(daily_refresh.sh 마지막 줄 또는 별도 예약 작업).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
LOG_DIR="$HERE/daily/logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"
export PYTHONUTF8=1 KRSI_DAILY=1
SKIP_FETCH=0; NO_PDF=""
for a in "$@"; do case "$a" in --skip-fetch) SKIP_FETCH=1;; --no-pdf) NO_PDF="--no-pdf";; esac; done
step() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
run() { "$@" >> "$LOG" 2>&1; local rc=$?; [ $rc -ne 0 ] && step "★FAILED rc=$rc: $*"; return $rc; }
cd "$HERE" || exit 2
step "start · root=$ROOT"
if [ "$SKIP_FETCH" = 0 ]; then step "① fetch_research_inputs.py"; run "$PY" fetch_research_inputs.py || exit 3; fi
step "② build_kr_stress_index_v1.py (KRSI_DAILY=1)"; run "$PY" build_kr_stress_index_v1.py || exit 4
step "③ make_charts.py v1";                           run "$PY" make_charts.py v1 || exit 5
# ③b 오늘의 해설(Sonnet · 숫자 출처 자동 검사) — ★기본 끔(도훈 11-06: 매일 일보 = 해설 없는 확정본 v1). 시험할 때만 KRSI_COMMENTARY=1(본문 삽입도 같은 변수)
if [ "${KRSI_COMMENTARY:-0}" = "1" ]; then step "③b make_commentary.py"; run "$PY" make_commentary.py || step "★해설 단계 실패(일보는 해설 없이 계속)"; fi
step "④ make_daily_report.py $NO_PDF";                run "$PY" make_daily_report.py $NO_PDF || exit 6
# 방법론 문서는 매일 만들지 않는다(도훈 11-06) — 필요할 때 손으로: make_methodology.py --pdf
# ⑤ 메일(PDF 일보 + 엑셀 대시보드 → ops/mail_config.json 수신자 · 기준일당 1통) — 발신 자격이 없거나 실패해도 일보는 유효(KRSI_NO_MAIL=1 이면 건너뜀)
if [ -z "$NO_PDF" ] && [ "${KRSI_NO_MAIL:-0}" != "1" ]; then step "⑤ ops/send_daily_mail.py"; run "$PY" ops/send_daily_mail.py || step "★메일 단계 실패(일보는 유효 · 로그 확인)"; fi
step "done → $(cat "$HERE/daily/latest/latest.json" 2>/dev/null | tr -d '\n' | cut -c1-200)"
