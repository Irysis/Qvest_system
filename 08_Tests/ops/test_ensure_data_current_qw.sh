#!/usr/bin/env bash
#==============================================================================
# test_ensure_data_current_qw.sh — 부팅 규칙(퀀티 최신성 축) 양방향 검사 (2026-10-17 · 결정 BOOT-QW-LOGIN-REFRESH-20261017)
#
# 도훈 10-17 "복잡하게 가지말고 부팅시점에 최신화 안되어있으면 퀀티로그인해서 최신화시킨다로 정리해" · "공휴일정보 찾아서 붙여".
# 대상: 02_Infrastructure/ops/ensure_data_current.sh 의 2b) 퀀티 최신성 축 + 02_Infrastructure/data/krx_holidays.py expected.
#   벤치 최신일 < 직전 거래일(KRX 공식 휴장일) → 리프레시(= daily_refresh.sh · [1pre] 퀀티 수급이 로그인) · 같은 거래일 재실패는 재시도 안 함 ·
#   다음 거래일엔 다시 · 휴장일(대체공휴일) 다음 날은 '최신' · 휴장일 미수록 해는 이 축만 미측정.
#
# ★부작용 없음 — 실제 스크립트를 샌드박스 루트에 복사해 돌린다. 감사기(freshness_audit.R) · 리프레시(daily_refresh.sh) ·
#   Rscript 는 스텁이고, 운영 잠금 경로(/tmp/qm_daily_refresh.lock)는 사본에서만 샌드박스 경로로 치환한다(격리용 1줄).
#   휴장일 등록부는 운영 06_Registry/krx_holidays.json 사본. 네트워크 0(미수록 해 시험은 빈 등록부 + 오프라인).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PYV="$ROOT/.venv_qvest_ml/Scripts/python.exe"   # venv 고정(사용자 QVEST_PY = 시스템 Python312 · pandas 없음)
EDC="$ROOT/02_Infrastructure/ops/ensure_data_current.sh"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SB="$T/sb"; SBM=$(cygpath -m "$SB")

mk_sandbox(){ # $1 = ensure_data_current 사본 원본(기본 운영 파일)
  rm -rf "$SB"; mkdir -p "$SB/02_Infrastructure/ops/morning_steps" "$SB/02_Infrastructure/data" "$SB/02_Infrastructure/hooks" "$SB/06_Registry" "$SB/.cache"
  : > "$SB/02_Infrastructure/hooks/qvest_hook_router.py"
  printf 'PROJECT="%s"\n' "$SBM" > "$SB/02_Infrastructure/ops/resolve_project.sh"
  sed "s#^LOCKDIR=\"/tmp/qm_daily_refresh.lock\"#LOCKDIR=\"$SBM/refresh.lock\"#" "${1:-$EDC}" > "$SB/02_Infrastructure/ops/ensure_data_current.sh"
  : > "$SB/02_Infrastructure/ops/morning_steps/freshness_audit.R"
  cp 02_Infrastructure/data/krx_holidays.py "$SB/02_Infrastructure/data/"
  cp 06_Registry/krx_holidays.json "$SB/06_Registry/"
  # 리프레시 스텁: 호출을 센다 · STUB_ADVANCE 가 있으면 벤치 최신일을 그 날짜로 늘린다(= 퀀티 로그인 · 수급 성공)
  cat > "$SB/02_Infrastructure/data/daily_refresh.sh" <<EOF
echo called >> "$SBM/refresh_calls"
[ -n "\${STUB_ADVANCE:-}" ] && "$PYV" -c "import sys,pandas as pd; pd.DataFrame({'Date': pd.to_datetime(['2026-10-01', sys.argv[2]])}).to_parquet(sys.argv[1])" "$SBM/.cache/benchmark.parquet" "\$STUB_ADVANCE"
exit 0
EOF
  # Rscript 스텁: 감사기 대신 '감사 stale 0'(캘린더 기준 = 퀀티가 멈추면 같이 멈춘다)을 낸다
  printf '#!/usr/bin/env bash\necho "EDC_RESULT stale=0 as_of=2026-10-15 items=-"\n' > "$T/Rscript_stub"; chmod +x "$T/Rscript_stub"
  grep -q "^LOCKDIR=\"$SBM/refresh.lock\"" "$SB/02_Infrastructure/ops/ensure_data_current.sh" || ng "S0 잠금 경로 치환 실패(격리 불가)"
}
set_bench(){ "$PYV" -c "import sys,pandas as pd; pd.DataFrame({'Date': pd.to_datetime(['2026-09-30', sys.argv[2]])}).to_parquet(sys.argv[1])" "$SBM/.cache/benchmark.parquet" "$1"; }
run_edc(){ # $1 = 오늘(KRX 기준) · 출력 = "rc|refresh 호출 수|verdict|as_of|qw"
  rm -f "$SB/refresh_calls"
  QM_ROOT="$SBM" QVEST_PY="$PYV" RSCRIPT="$T/Rscript_stub" QVEST_KRX_TODAY="$1" bash "$SB/02_Infrastructure/ops/ensure_data_current.sh" > "$T/edc.log" 2>&1; local rc=$?
  local n; n=$(wc -l < "$SB/refresh_calls" 2>/dev/null || echo 0); n=$((n+0))
  local v a q
  v=$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$SB/.cache/data_currency_stamp.json" 2>/dev/null)
  a=$(sed -n 's/.*"as_of":"\([^"]*\)".*/\1/p' "$SB/.cache/data_currency_stamp.json" 2>/dev/null)
  q=$(sed -n 's/.*"qw":"\([^"]*\)".*/\1/p' "$SB/.cache/data_currency_stamp.json" 2>/dev/null)
  echo "$rc|$n|$v|$a|$q"
}

echo "=== A. krx_holidays.py expected — KRX 직전 거래일 ==="
for c in "2026-10-17:2026-10-16" "2026-10-20:2026-10-19" "2026-10-06:2026-10-02" "2026-10-10:2026-10-08" "2026-12-28:2026-12-24" "2027-01-04:2026-12-30"; do
  t=${c%%:*}; w=${c#*:}; g=$(QM_ROOT="$ROOT" "$PYV" 02_Infrastructure/data/krx_holidays.py expected --today "$t" --no-fetch | tr -d '\r')
  [ "$g" = "$w" ] && ok "A ${t} → ${w}" || ng "A ${t}" "got=$g want=$w"
done

echo "=== B. ensure_data_current.sh 퀀티 최신성 축(실제 스크립트 · 샌드박스) ==="
mk_sandbox
set_bench 2026-10-16; r=$(run_edc 2026-10-17)
[ "$r" = "0|0|already_current|2026-10-16|0|2026-10-16|2026-10-16" ] && ok "B1 [양성] 벤치 10-16 = 직전 거래일 → 이미 최신 · 리프레시 0" || ng "B1" "$r"
set_bench 2026-10-15; r=$(STUB_ADVANCE=2026-10-16 run_edc 2026-10-17)
[ "$r" = "0|1|refreshed_current|2026-10-16|0|2026-10-16|2026-10-16" ] && ok "B2 [주입] 벤치 10-15 < 10-16(감사는 stale 0) → 리프레시 1회 → 퀀티 최신 확보 rc=0" || ng "B2" "$r"
set_bench 2026-10-15; r=$(run_edc 2026-10-17)
[ "$r" = "3|1|stale_after_refresh|2026-10-16|1|2026-10-15|2026-10-16" ] && ok "B3 리프레시해도 안 늘면(퀀티 로그인 실패) → rc=3 stale_after_refresh · 키 = KRX 직전 거래일" || ng "B3" "$r"
r=$(run_edc 2026-10-17)
[ "$r" = "3|0|stale_unfixable_by_refresh|2026-10-16|1|2026-10-15|2026-10-16" ] && ok "B4 같은 거래일 두 번째 부팅 → 재시도 안 함(47분 헛리프레시 방지) · rc=3 보고" || ng "B4" "$r"
grep -q "단말 로그인 확인" "$T/edc.log" && ok "B4b 재시도 생략 로그가 퀀티 로그인 확인을 안내" || ng "B4b 안내 문구"
r=$(STUB_ADVANCE=2026-10-19 run_edc 2026-10-20)
[ "$r" = "0|1|refreshed_current|2026-10-19|0|2026-10-19|2026-10-19" ] && ok "B5 다음 거래일(10-20 · 직전 10-19) → 키가 바뀌어 다시 시도 → 최신 확보" || ng "B5" "$r"
set_bench 2026-10-02; r=$(run_edc 2026-10-06)
[ "$r" = "0|0|already_current|2026-10-02|0|2026-10-02|2026-10-02" ] && ok "B6 대체공휴일(10-05) 다음 날 10-06 · 벤치 10-02 → 최신(평일 규칙이면 헛리프레시 했을 자리)" || ng "B6" "$r"

echo "=== C. 휴장일 미수록 해 = 이 축만 미측정(위 감사 판정 그대로) ==="
"$PYV" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); d['years']=[y for y in d['years'] if y<2026]; d['holidays']={k:v for k,v in d['holidays'].items() if k<'2026'}; json.dump(d,open(sys.argv[1],'w',encoding='utf-8'),ensure_ascii=False)" "$SBM/06_Registry/krx_holidays.json"
set_bench 2026-10-15
rm -f "$SB/refresh_calls"
QM_ROOT="$SBM" QVEST_PY="$PYV" RSCRIPT="$T/Rscript_stub" QVEST_KRX_TODAY=2026-10-17 bash -c '
  # 네트워크 차단: krx_holidays.py 의 자동 수급이 실패하도록 프록시를 죽은 주소로
  export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
  bash "$0"' "$SB/02_Infrastructure/ops/ensure_data_current.sh" > "$T/edc.log" 2>&1; rc=$?
n=$(wc -l < "$SB/refresh_calls" 2>/dev/null || echo 0); n=$((n+0))
grep -q "퀀티 최신성 미측정" "$T/edc.log" && [ "$rc" = 0 ] && [ "$n" = 0 ] && ok "C1 2026 미수록 + 수급 실패 → 미측정 로그 · 감사(stale 0) 판정 그대로 rc=0" || ng "C1" "rc=$rc calls=$n"

echo "=== M. 뮤테이션 — 축을 지우면 B2 가 침묵 ==="
"$PYV" - "$EDC" "$T/edc_mut.sh" <<'PYM'
import io, sys
s = io.open(sys.argv[1], encoding='utf-8').read()
a = s.index('QW="$(_qw_state)"; QW_BEHIND=')
b = s.index('esac', a) + len('esac')
io.open(sys.argv[2], 'w', encoding='utf-8', newline='').write(s[:a] + 'QW_BEHIND=0; QW_EXP=NA; QW=NA' + s[b:])
PYM
grep -q "QW_BEHIND=0; QW_EXP=NA; QW=NA" "$T/edc_mut.sh" && ok "M0 뮤테이션 치환 성사" || ng "M0 치환 실패"
mk_sandbox "$T/edc_mut.sh"; set_bench 2026-10-15; r=$(STUB_ADVANCE=2026-10-16 run_edc 2026-10-17)
case "$r" in 0\|0\|already_current*) ok "M1 축 삭제 사본 → 벤치가 밀려도 '이미 최신'(리프레시 0) — B2 는 이 축의 발화다(검출력)" ;; *) ng "M1 뮤테이션 판독" "$r" ;; esac

echo "=== D. /qvest 부팅 Data 줄의 퀀티 칸(boot_lean.sh _qwcur — 실제 함수 텍스트를 잘라 실행) ==="
mk_sandbox
"$PYV" - "$ROOT/02_Infrastructure/ops/boot_lean.sh" "$SBM" <<'PYD' > "$T/qwcur.out" 2>&1
import datetime, io, os, re, sys, types
src = io.open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^def _qwcur\(\):\n(?:    .*\n)+', src, re.M)
if not m:
    print('NOFUNC'); sys.exit(0)
SB = sys.argv[2]; os.environ['QM_ROOT'] = SB
import pandas as pd
def run(today, bench):
    pd.DataFrame({'Date': pd.to_datetime(['2026-09-30', bench])}).to_parquet(os.path.join(SB, '.cache', 'benchmark.parquet'))
    class _D(datetime.date):
        @classmethod
        def today(cls): return datetime.date.fromisoformat(today)
    ns = {'R': lambda *a: os.path.join(SB, *a), 'dt': types.SimpleNamespace(date=_D)}
    exec(m.group(0), ns)
    return ns['_qwcur']()
for t, b in (('2026-10-20', '2026-10-16'), ('2026-10-20', '2026-10-19'), ('2026-10-06', '2026-10-02'), ('2028-01-04', '2027-12-30')):
    s, f = run(t, b); print(f'{t}|{b}|{s}|{f}')
PYD
grep -q NOFUNC "$T/qwcur.out" && ng "D0 _qwcur 함수 추출 실패"
grep -qx "2026-10-20|2026-10-16|★퀀티 미최신 10-16<10-19|True" "$T/qwcur.out" && ok "D1 벤치 10-16 · 직전 거래일 10-19 → ★퀀티 미최신(부팅 규칙 조치 줄)" || ng "D1" "$(head -3 "$T/qwcur.out" | tr '\n' ' ')"
grep -qx "2026-10-20|2026-10-19|퀀티 10-19 ✓|False" "$T/qwcur.out" && ok "D2 [양성] 벤치 = 직전 거래일 → 퀀티 ✓" || ng "D2" "$(sed -n 2p "$T/qwcur.out")"
grep -qx "2026-10-06|2026-10-02|퀀티 10-02 ✓|False" "$T/qwcur.out" && ok "D3 대체공휴일 다음 날 → ✓(헛경보 없음)" || ng "D3" "$(sed -n 3p "$T/qwcur.out")"
grep -q "^2028-01-04|2027-12-30|퀀티 ?(year_not_covered:2028)|False" "$T/qwcur.out" && ok "D4 휴장일 미수록 해 → '퀀티 ?(year_not_covered)' — 0 으로 접지 않는다 · 부팅은 수급하지 않는다(오프라인)" || ng "D4" "$(sed -n 4p "$T/qwcur.out")"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
printf '{"test":"ensure_data_current_qw","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
