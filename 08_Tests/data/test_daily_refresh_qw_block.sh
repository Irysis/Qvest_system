#!/usr/bin/env bash
#==============================================================================
# test_daily_refresh_qw_block.sh — daily_refresh.sh [1pre-qw] 블록(퀀티 Update_File 4종 매일 수급 · RAWDATA 퀀티 단일)
#   2026-10-17 도훈 '주가관련 복잡한 규칙들 모두 없애고 Universe update 에 있는 파일들 매일 데이터 리프레시할 때 퀀티로 최신화' ·
#   'Consensus_update, Investor_Act_update 이것도 매일해' · 결정 RAWDATA-QW-ONLY-20261017.
#   ① 실제 daily_refresh.sh 에서 [1pre-qw] 블록을 잘라 스텁(수급 스크립트 · run_r)으로 돌린다 — 수급 결과 줄(QWUF) → DR_FAILED · [0b'] 재적재
#      a 전진 4/4 → 실패 0 · 재적재 1 / b 전진 없음(주말 — 대상 모두 목표일) → 실패 0 · 재적재 0 / c 일부 전진 3/4 → 미완료 실패 · 재적재 1 /
#      d 건너뜀(로그인 창) → 건너뜀 실패 · 재적재 0 / e 전진 없음 + rc≠0 → 미완료 실패 · 재적재 0
#   ② 뮤테이션(소스 텍스트 치환 사본) — 미완료 DR_FAILED 줄을 지운 블록은 c 를 놓친다(검출력)
#   ③ 정적 — 밤 · 아침 체인 실행 코드(주석 제외)에 네이버 · KRX 주가 수집 호출 0 · 검사기 양성 대조
# 운영 퀀티 · .cache 무접촉(임시 디렉터리만). 실행: bash 08_Tests/data/test_daily_refresh_qw_block.sh
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
DR=02_Infrastructure/data/daily_refresh.sh
T="$(cygpath -m "$(mktemp -d)" 2>/dev/null)"; [ -n "$T" ] || T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

## 블록 = '# --- [1pre-qw]' 줄부터 다음 절('# --- BMG-01') 앞까지
awk '/^# --- \[1pre-qw\]/{f=1} /^# --- BMG-01/{f=0} f' "$DR" > "$T/block.sh"
[ -s "$T/block.sh" ] && grep -q 'qw_updatefile_unattended.sh' "$T/block.sh" && ok "0 [1pre-qw] 블록을 실제 daily_refresh.sh 에서 잘랐다($(wc -l < "$T/block.sh")줄)" || ng "0 블록 추출 실패"

## 스텁 수급 스크립트($INFRA/data/qw_updatefile_unattended.sh) — STUB_LINE 을 마지막 줄로 내고 STUB_RC 로 끝난다
mkdir -p "$T/infra/data"
cat > "$T/infra/data/qw_updatefile_unattended.sh" <<'STUB'
#!/usr/bin/env bash
echo "[qwuf] stub"
printf '%b\n' "$STUB_LINE"
exit "${STUB_RC:-0}"
STUB
run_case(){   # $1 = 블록 파일 · $2 = QWUF 줄 · $3 = 스텁 rc · $4 = 벤치 rc → "DRF=<목록>|RUNR=<횟수>"
  cat > "$T/harness.sh" <<HARN
set -uo pipefail
DR_FAILED=(); RUNR=0
run_r(){ RUNR=\$((RUNR + 1)); }
INFRA="$T/infra"; QVENV_PY="python"; _qw_rc="$4"
export STUB_LINE='$2' STUB_RC="$3"
. "$1" >/dev/null 2>&1
printf 'DRF=%s|RUNR=%s\n' "\${DR_FAILED[*]:-}" "\$RUNR"
HARN
  bash "$T/harness.sh" 2>/dev/null | tail -n 1
}
Q(){ printf 'QWUF\\tstate=%s\\tonly=OHLCVS,Universe_Support,Investor_Act,Consensus\\tadvanced=%s\\trc=%s\\tdone=%s\\tincomplete=%s' "$1" "$2" "$3" "$4" "$5"; }
ra=$(run_case "$T/block.sh" "$(Q advanced 4 0 4/4 0)" 0 0)
[ "$ra" = "DRF=|RUNR=1" ] && ok "a 전진 4/4 → 실패 0 · [0b'] 재적재 1회" || ng "a" "$ra"
rb=$(run_case "$T/block.sh" "$(Q no_advance 0 0 4/4 0)" 10 2)
[ "$rb" = "DRF=|RUNR=0" ] && ok "b 전진 없음 · 4/4(주말 — 모두 목표일) → 실패 0 · 재적재 없음" || ng "b" "$rb"
rc_=$(run_case "$T/block.sh" "$(Q advanced 2 0 3/4 1)" 0 0)
[ "$rc_" = "DRF=qw_updatefile_incomplete(done=3/4)|RUNR=1" ] && ok "c 일부 전진 3/4 → qw_updatefile_incomplete(done=3/4) · 재적재 1회(받은 것은 싣는다)" || ng "c" "$rc_"
rd=$(run_case "$T/block.sh" "$(Q skipped 0 - '?' 0)" 10 3)
[ "$rd" = "DRF=qw_updatefile_skipped(bench_rc=3)|RUNR=0" ] && ok "d 건너뜀(로그인 창 · 벤치 rc=3) → qw_updatefile_skipped · 재적재 없음" || ng "d" "$rd"
re=$(run_case "$T/block.sh" "$(Q no_advance 0 1 '?' 1)" 10 1)
[ "$re" = "DRF=qw_updatefile_incomplete(done=?)|RUNR=0" ] && ok "e 전진 없음 + rc≠0 → 미완료 실패 · 재적재 없음(오늘 RAWDATA 정체를 조용히 넘기지 않는다)" || ng "e" "$re"

## ② 뮤테이션 — 미완료 DR_FAILED 줄을 지운 사본은 c 를 놓친다
grep -v 'DR_FAILED+=("qw_updatefile_incomplete' "$T/block.sh" > "$T/block_mut.sh"
if ! cmp -s "$T/block.sh" "$T/block_mut.sh"; then
  rm_=$(run_case "$T/block_mut.sh" "$(Q advanced 2 0 3/4 1)" 0 0)
  [ "$rm_" = "DRF=|RUNR=1" ] && ok "M 뮤테이션(미완료 경보 줄 삭제) → c 가 침묵 — c 는 그 줄의 발화다(검출력)" || ng "M 뮤테이션 판독" "$rm_"
else ng "M 뮤테이션 치환 실패" "블록에 미완료 경보 줄이 없다"; fi

## ③ 정적 — 밤 · 아침 체인 실행 코드(주석 제외)에 네이버 · KRX 주가 수집 호출 0
PRICE_RE='naver_run_pipeline|krx_run_pipeline|krx_detect_gap|krx_detect_interior_gaps|morning_steps/(krx_update|naver_supplement)\.R|data/naver_data_collector\.R|data/krx_build_rawdata\.R'
hits=$(for f in "$DR" 02_Infrastructure/ops/morning_briefing.sh 02_Infrastructure/ops/morning_steps/self_heal.R 02_Infrastructure/ops/ensure_data_current.sh; do sed 's/#.*$//' "$f" | grep -oE "$PRICE_RE"; done | sort -u | tr '\n' ' ')
[ -z "$hits" ] && ok "S1 밤 · 아침 · self_heal · ensure 실행 코드에 네이버 · KRX 주가 수집 호출 0" || ng "S1 주가 보충 호출 잔존" "$hits"
printf '  source("data/naver_data_collector.R")\n  tryCatch(naver_run_pipeline(), error = function(e) NULL)\n' > "$T/probe.R"
sed 's/#.*$//' "$T/probe.R" | grep -qE "$PRICE_RE" && ok "S2 검사기 양성 대조 — 주입한 호출은 잡힌다" || ng "S2 검사기 미발화"
[ ! -e 02_Infrastructure/ops/morning_steps/krx_update.R ] && [ ! -e 02_Infrastructure/ops/morning_steps/naver_supplement.R ] \
  && ok "S3 아침 보충 래퍼 2개 삭제(krx_update.R · naver_supplement.R)" || ng "S3 래퍼 잔존"
grep -q 'ONLY="${QWUF_ONLY:-OHLCVS,Universe_Support,Investor_Act,Consensus}"' 02_Infrastructure/data/qw_updatefile_unattended.sh \
  && ok "S4 수급 대상 = 4종 매일(OHLCVS → Universe_Support → Investor_Act → Consensus)" || ng "S4 수급 대상"

## ④ 벤치 퀀티 단일(BENCHMARK-QW-ONLY-20261017 · 도훈 '벤치마크도 퀀티 단일로 바꿔줘') — 밤 · 아침 실행 코드에 네이버 벤치 호출 0 · rc=3 = 실패
bh=$(for f in "$DR" 02_Infrastructure/ops/morning_briefing.sh; do sed 's/#.*$//' "$f" | grep -oE 'naver_benchmark_update\.py|QVEST_BENCH_NO_NAVER_FALLBACK|_BMV_RC'; done | sort -u | tr '\n' ' ')
[ -z "$bh" ] && ok "B1 밤 [1pre] · 아침 6_pre 실행 코드에 네이버 벤치 이어붙이기 · 검증 호출 0" || ng "B1 네이버 벤치 호출 잔존" "$bh"
awk '/^    3\) echo "  ※정본 수급 전제 부재/{f=1} f&&/;;/{print; exit} f' "$DR" | grep -q '_bm_rc=3' \
  && ok "B2 벤치 수급 rc=3(전제 부재)도 갱신기 실패로 센다(보충 원천 없음 → 그날 밤 축 A 신고)" || ng "B2 rc=3 실패 처리"

## ⑤ 퀀티 드라이버 목표일 = 벤치 최신일(10-17 순환 결함 수리) — 구판 RAWDATA 최신일이면 퀀티 단일에서 새 날짜를 영영 안 받는다
PYV="$ROOT/.venv_qvest_ml/Scripts/python.exe"; PS1=02_Infrastructure/ops/qw_refresh.ps1
fn_of(){ awk '/^function Get-Target \{/{f=1} f{print} f&&/^\}/{exit}'; }
fn_of < "$PS1" > "$T/gt_fn.ps1"
mkdir -p "$T/root/.cache"
"$PYV" -c "
import sys, pandas as pd
d = sys.argv[1]
pd.DataFrame({'Date': pd.to_datetime(['2026-10-15', '2026-10-16', '2026-10-19']), 'BM_Close': [1.0, 2.0, 3.0]}).to_parquet(d + '/benchmark.parquet')
pd.DataFrame({'Date': pd.to_datetime(['2026-10-15', '2026-10-16']), 'Ticker': ['A', 'A']}).to_parquet(d + '/RAWDATA.parquet')
" "$(cygpath -w "$T/root/.cache")"
run_gt(){ { printf '$ROOT = "%s"\n$PY = "%s"\n' "$(cygpath -w "$T/root")" "$(cygpath -w "$PYV")"; cat "$1"; printf 'Get-Target\n'; } > "$T/gt_run.ps1"
          powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$T/gt_run.ps1")" 2>/dev/null | tr -d '\r' | tail -n 1; }
[ -s "$T/gt_fn.ps1" ] || ng "T0 Get-Target 함수 추출 실패"
g1=$(run_gt "$T/gt_fn.ps1")
[ "$g1" = "20261019" ] && ok "T1 Get-Target = 벤치 최신일 20261019(RAWDATA 최신일 20261016 이 아니다)" || ng "T1 목표일" "$g1"
mv "$T/root/.cache/benchmark.parquet" "$T/root/.cache/benchmark.bak"; g2=$(run_gt "$T/gt_fn.ps1"); mv "$T/root/.cache/benchmark.bak" "$T/root/.cache/benchmark.parquet"
[ "$g2" = "20261016" ] && ok "T2 벤치 부재 = 구판(RAWDATA 최신일) 폴백" || ng "T2 폴백" "$g2"
cp "$T/root/.cache/benchmark.parquet" "$T/root/.cache/benchmark.bak"; printf 'not a parquet' > "$T/root/.cache/benchmark.parquet"
g4=$(run_gt "$T/gt_fn.ps1"); mv -f "$T/root/.cache/benchmark.bak" "$T/root/.cache/benchmark.parquet"
[ "$g4" = "20261016" ] && ok "T3 벤치 판독 불능(깨진 파일) = RAWDATA 최신일 폴백(빈 문자열 · 오류문을 목표일로 넘기지 않는다)" || ng "T3 판독 불능 폴백" "$g4"
mkdir -p "$T/root/.hide"; mv "$T/root/.cache/"*.parquet "$T/root/.hide/"; g5=$(run_gt "$T/gt_fn.ps1"); mv "$T/root/.hide/"*.parquet "$T/root/.cache/"
y5=$(powershell.exe -NoProfile -Command '(Get-Date).AddDays(-1).ToString("yyyyMMdd")' 2>/dev/null | tr -d '\r')
[ -n "$g5" ] && [ "$g5" = "$y5" ] && ok "T4 두 파일 모두 부재 = 어제($y5)" || ng "T4 둘 다 부재" "$g5 vs $y5"
if git show pre-rawdata-qw-only-20261017:"$PS1" 2>/dev/null | fn_of > "$T/gt_old.ps1" && [ -s "$T/gt_old.ps1" ]; then
  g3=$(run_gt "$T/gt_old.ps1")
  [ "$g3" = "20261016" ] && ok "TM 뮤테이션(구판 RAWDATA 기준 함수) → 20261016 — T1 은 수리의 발화다(검출력)" || ng "TM 뮤테이션 판독" "$g3"
else ng "TM 구판 함수 판독 실패(태그 pre-rawdata-qw-only-20261017)"; fi

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
printf '{"test":"daily_refresh_qw_block","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
