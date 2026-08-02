#!/usr/bin/env bash
# test_prereq_skip_contract.sh — 전제 부재 제3상태(skipped) 계약 위반 주입 테스트
#
# 대상: 08_Tests/hooks/run_all_hooks.sh (집계·FINAL 표면)
#       08_Tests/portfolio/test_deployed_holdings_check.sh
#       08_Tests/factor_db/test_build_hash_provenance.R
#       08_Tests/factor_db/test_ic_frontier_check.R
#       08_Tests/data/test_contract_panel.R
#
# 왜 있나 (2026-08-02):
#   worktree 에서 배터리를 **자기 트리에 앵커해** 돌리면 17건이 붉었는데, 그중 어느 것도
#   코드 회귀가 아니었다 — 전부 이 트리에 없는 gitignore 산출물(.cache/*, venv)을
#   전제하는 축이었다. 종전 보고는 두 갈래뿐이라 둘 다 틀렸다:
#     · 실패로 계상 → "제약 위반 미검거"라는 **거짓 진단**
#       (실측: deployed_holdings_check 14건이 전부 exit 49 = 검사기 미실행인데
#        "위반 14건을 놓쳤다"로 읽혔다. 양성 대조 T0 까지 같은 49 였다.)
#     · 통과로 계상 → 이 저장소가 12회 수리한 "빈 결과 = 합격" 계통 재발
#   그래서 제3상태를 도입했고, **이 검사가 그 제3상태 자체의 차단 실효를 잰다**.
#
# 이 검사가 고정하는 3가지:
#   ① 전제가 **있을 때** 실제 검사가 돌고, 일부러 넣은 위반을 여전히 검거하는가
#   ② 전제가 **없을 때** 사유+경로와 함께 skipped 로 나오는가 (통과 아님·실패 아님)
#   ③ 러너가 skip 을 FINAL/결과JSON 에 드러내는가, 그리고 skip 이 종료코드를
#      물들이지 않으면서도 pass/fail 어느 쪽으로도 흡수되지 않는가
#
# ★ 전제 주입은 **실파일 생성/삭제**로 한다 — "skip 인 척하는 플래그"를 만들지 않는다.
#   그런 플래그가 있으면 전제가 실재해도 skip 을 만들어낼 수 있어 검사가 거짓말한다.
#   경로 치환(QVEST_TEST_CACHE_ROOT)은 게이트와 소비자가 **같은 경로**를 볼 때만 쓴다.
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
# 앵커는 self-first — env 우선이면 worktree 에서 돌린 검사가 main 을 잰다
# ([[project-test-runner-anchor-selffirst-20260802]]).
PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
if [ ! -f "$PROJ/08_Tests/hooks/run_all_hooks.sh" ]; then
  for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}"; do
    [ -n "$c" ] && [ -f "$c/08_Tests/hooks/run_all_hooks.sh" ] && PROJ="$(cd "$c" && pwd)" && break
  done
fi
PROJ="${PROJ//\\//}"

PY="${QVEST_PY_BIN:-${QVEST_PY:-}}"; PY="${PY//\\//}"
[ -x "$PY" ] || PY="$(command -v python.exe 2>/dev/null || true)"
if [ ! -x "$PY" ]; then
  # 이 검사기 자신의 계측이 죽는 경우 — 조용히 0건 통과로 끝내지 않는다.
  echo "  FAIL harness_python — 요약 JSON 파서를 돌릴 파이썬이 없음 (bare python3 는 스텁이라 제외)"
  echo '{"test":"prereq_skip_contract","pass":0,"fail":1,"skipped":0,"total":1}'
  exit 1
fi

PASS=0; FAIL=0
ok(){   PASS=$((PASS+1)); echo "  ok   $1${2:+ — $2}"; }
bad(){  FAIL=$((FAIL+1)); echo "  FAIL $1 — ${2:-}"; }
chk(){ local n="$1" exp="$2" got="$3"
  if [ "$exp" = "$got" ]; then ok "$n" "$exp"; else bad "$n" "기대=$exp 실제=$got"; fi; }

TD="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/pskip_$$")"; mkdir -p "$TD"
cleanup(){ rm -rf "$TD"; }
trap cleanup EXIT

# suite 출력에서 마지막 유효 요약 JSON 을 뽑아 필드를 읽는다 (러너와 동일 규약 —
# 마지막 줄이 아니라 "뒤에서부터 첫 유효 요약". 경고가 끼면 tail -1 은 빗나간다).
fld(){ # fld <field> <suite-output-file>
  "$PY" -c '
import json,sys
pick=None
for line in open(sys.argv[2], encoding="utf-8", errors="replace").read().splitlines():
    s=line.strip()
    if not (s.startswith("{") and s.endswith("}")): continue
    try: d=json.loads(s)
    except Exception: continue
    if isinstance(d,dict) and "test" in d: pick=d
if pick is None: print("NOSUMMARY"); raise SystemExit(0)
f=sys.argv[1]
if f=="skips_missing":
    sk=pick.get("skips") or []
    print("|".join(str(s.get("missing","")) for s in sk) or "EMPTY")
elif f=="skips_reason":
    sk=pick.get("skips") or []
    print("|".join(str(s.get("reason","")) for s in sk) or "EMPTY")
elif f=="skips_axis":
    sk=pick.get("skips") or []
    print("|".join(str(s.get("axis","")) for s in sk) or "EMPTY")
else:
    print(pick.get(f, "MISSING"))
' "$1" "$2"
}

# 가짜 프로젝트 루트 — 표지 파일만 갖춘 빈 트리. 여기서 돌면 어떤 전제도 실재하지 않고,
# **소비자(빌더 등)도 같은 빈 루트를 보므로** skip 판정이 현실과 어긋나지 않는다.
mk_fake_root(){
  local r="$1"
  mkdir -p "$r/02_Infrastructure/hooks" "$r/02_Infrastructure/validation" "$r/08_Tests/hooks"
  : > "$r/02_Infrastructure/hooks/qvest_hook_router.py"
}

echo "══ A. deployed_holdings_check — 해석기 능력 판정 + 위반 검거 실효 ══════════"
DHC="$PROJ/08_Tests/portfolio/test_deployed_holdings_check.sh"
A_OUT="$TD/a_present.txt"
CLAUDE_PROJECT_DIR="$PROJ" bash "$DHC" > "$A_OUT" 2>&1
chk "A1_present_no_skip"  "0"  "$(fld skipped "$A_OUT")"
chk "A1b_present_no_fail" "0"  "$(fld fail "$A_OUT")"
chk "A1c_present_pass14"  "14" "$(fld pass "$A_OUT")"

# ★핵심: T1~T9 는 **일부러 넣은 제약/매니페스트 위반**이다. 이 축들이 실제로 검거되는지
#  확인하지 않으면 "14 pass"가 공허할 수 있다(구 상태에선 T0~T13 이 전부 exit 49 로
#  같은 값이었고, 그건 검거가 아니라 미실행이었다).
_miss=""
for t in T1 T2 T3 T4 T5 T6 T7 T8 T9; do
  grep -q "^  ok   $t " "$A_OUT" || _miss="$_miss $t"
done
if [ -z "$_miss" ]; then ok "A2_injected_violations_caught" "T1~T9 9종 전부 검거"
else bad "A2_injected_violations_caught" "미검거 축:$_miss"; fi
# 양성 대조와 음성 통제가 **서로 다른 값**을 내는지 — 같은 값이면 검사기 사망 지문
if grep -q "^  ok   T0 " "$A_OUT" && grep -q "^  ok   T13 " "$A_OUT"; then
  ok "A2b_controls_distinguish" "T0(정상=0)·T13(WARN=0) 통과 ∧ T1~T9(위반=1) 검거 — 값이 갈린다"
else
  bad "A2b_controls_distinguish" "양성 대조/음성 통제가 통과하지 않음 — 검사기가 무조건 실패를 뱉는 상태"
fi

# 전제 부재 주입: 어떤 후보도 pandas 를 못 쓰는 상태를 실제로 만든다.
# (venv 없는 빈 루트 + git 저장소 아님 + QVEST_PY* 비움. PATH 의 python3 는 스텁이므로
#  구현이 그걸 집으면 여기서 49 가 새어나와 이 축이 붉어진다 = 회귀 검출력.)
FAKE_A="$TD/fake_a"; mk_fake_root "$FAKE_A"
cp "$PROJ/02_Infrastructure/validation/deployed_holdings_check.py" \
   "$FAKE_A/02_Infrastructure/validation/" 2>/dev/null || true
A2_OUT="$TD/a_absent.txt"
( cd "$FAKE_A" && CLAUDE_PROJECT_DIR="$FAKE_A" QM_ROOT="$FAKE_A" QVEST_PY="" QVEST_PY_BIN="" \
    bash "$DHC" ) > "$A2_OUT" 2>&1
A2_RC=$?
chk "A3_absent_skipped14" "14" "$(fld skipped "$A2_OUT")"
chk "A3b_absent_pass0"    "0"  "$(fld pass "$A2_OUT")"
chk "A3c_absent_fail0"    "0"  "$(fld fail "$A2_OUT")"
chk "A3d_absent_rc0"      "0"  "$A2_RC"
case "$(fld skips_missing "$A2_OUT")" in
  EMPTY|NOSUMMARY|"") bad "A3e_absent_names_path" "skips[].missing 가 비어 있음 — 조치 불가능한 보고" ;;
  *) ok "A3e_absent_names_path" "$(fld skips_missing "$A2_OUT")" ;;
esac

# 축 수 상수 드리프트 가드 — skip 이 "14건 미판정"이라 주장하는데 실제 축이 15개면 거짓말
_n_chk="$(grep -c '^chk "T' "$DHC")"
chk "A4_axis_count_constant" "$_n_chk" "$(grep -o 'N_AXES=[0-9]*' "$DHC" | head -1 | cut -d= -f2)"

echo ""
echo "══ B. build_hash_provenance — 전제 유/무 + 위반 주입 ═══════════════════════"
BHP="$PROJ/08_Tests/factor_db/test_build_hash_provenance.R"
# ① 전제 부재
B_ABS="$TD/bh_absent_root"; mkdir -p "$B_ABS"
B1_OUT="$TD/b1.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$B_ABS" Rscript "$BHP" > "$B1_OUT" 2>&1
chk "B1_absent_skipped1" "1" "$(fld skipped "$B1_OUT")"
chk "B1b_absent_fail0"   "0" "$(fld fail "$B1_OUT")"
chk "B1c_absent_axis"    "E2_canonical_state" "$(fld skips_axis "$B1_OUT")"

# ② 전제 존재 + 정상 내용 → 실제로 판정하고 통과
B_OK="$TD/bh_ok_root"; mkdir -p "$B_OK/.cache/factor_db"
echo "20260802211430_d34c9ee1" > "$B_OK/.cache/factor_db/build_hash.txt"
B2_OUT="$TD/b2.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$B_OK" Rscript "$BHP" > "$B2_OUT" 2>&1
chk "B2_present_skipped0" "0" "$(fld skipped "$B2_OUT")"
chk "B2b_present_fail0"   "0" "$(fld fail "$B2_OUT")"
grep -q "PASS: E2_canonical_state" "$B2_OUT" \
  && ok "B2c_present_axis_ran" "E2 가 실제로 판정" \
  || bad "B2c_present_axis_ran" "전제가 있는데 E2 판정 흔적이 없음"

# ③ 전제 존재 + **위반 주입**(provenance 소실 = _unknown) → 반드시 FAIL
#    전제 게이트가 진짜 고장을 삼키지 않는지의 결정적 축이다.
B_BAD="$TD/bh_bad_root"; mkdir -p "$B_BAD/.cache/factor_db"
echo "20260802211430_unknown" > "$B_BAD/.cache/factor_db/build_hash.txt"
B3_OUT="$TD/b3.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$B_BAD" Rscript "$BHP" > "$B3_OUT" 2>&1
chk "B3_injected_fail1"    "1" "$(fld fail "$B3_OUT")"
chk "B3b_injected_skipped0" "0" "$(fld skipped "$B3_OUT")"

echo ""
echo "══ C. ic_frontier_check — 부재는 skip, **0행은 fail** ═════════════════════"
ICF="$PROJ/08_Tests/factor_db/test_ic_frontier_check.R"
# ① 전제 부재
C_ABS="$TD/ic_absent_root"; mkdir -p "$C_ABS"
C1_OUT="$TD/c1.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$C_ABS" Rscript "$ICF" > "$C1_OUT" 2>&1
chk "C1_absent_skipped1" "1" "$(fld skipped "$C1_OUT")"
chk "C1b_absent_fail0"   "0" "$(fld fail "$C1_OUT")"
chk "C1c_absent_axis"    "B7_live_lag_recompute" "$(fld skips_axis "$C1_OUT")"

# 라이브 전제는 **둘**이다(IC parquet + RAWDATA) — 기대 프론티어는 RAWDATA 거래일에서
# 나오므로 IC 만 놔두면 월 필드가 안 채워진다. 초판이 IC 만 합성해 present-arm 을 붉혔다.
MK_CACHE="$TD/mk_cache.R"
cat > "$MK_CACHE" <<'REOF'
suppressPackageStartupMessages(library(arrow))
a <- commandArgs(TRUE); root <- a[1]; ic_mode <- a[2]
dir.create(file.path(root, ".cache/factor_db"), recursive = TRUE, showWarnings = FALSE)
d <- seq(as.Date("2024-01-01"), as.Date("2026-07-31"), by = "day")
d <- d[!(format(d, "%u") %in% c("6", "7"))]          # 주말 제외 = 거래일 근사
write_parquet(data.frame(Date = d), file.path(root, ".cache/RAWDATA.parquet"))
ic <- if (identical(ic_mode, "empty")) as.Date(character(0)) else
        seq(as.Date("2024-01-31"), as.Date("2026-06-30"), by = "month")
write_parquet(data.frame(Date = ic), file.path(root, ".cache/factor_db/factor_ic_monthly.parquet"))
REOF

# ② 전제 존재(유효 IC + RAWDATA) → B7 이 실제로 재계산 대조를 수행
C_OK="$TD/ic_ok_root"
Rscript "$MK_CACHE" "$C_OK" full >/dev/null 2>&1
C2_OUT="$TD/c2.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$C_OK" Rscript "$ICF" > "$C2_OUT" 2>&1
chk "C2_present_skipped0" "0" "$(fld skipped "$C2_OUT")"
grep -q "PASS: B7_live_lag_recompute" "$C2_OUT" \
  && ok "C2b_present_axis_ran" "B7 이 실제로 재계산 대조" \
  || bad "C2b_present_axis_ran" "전제가 있는데 B7 판정 흔적이 없음: $(grep -o 'B7_live_lag_recompute.*' "$C2_OUT" | head -1)"

# ③ **위반 주입**: 전제 파일은 둘 다 있는데 IC 가 0행 → 월 필드가 안 채워진다.
#    이건 상류 고장이므로 skip 이 아니라 FAIL 이어야 한다("비었으니 건너뛴다"로 새면
#    빈 결과=합격 재발). 부재와 0행을 가르는 것이 이 제3상태 설계의 전부다.
C_EMPTY="$TD/ic_empty_root"
Rscript "$MK_CACHE" "$C_EMPTY" empty >/dev/null 2>&1
C3_OUT="$TD/c3.txt"
CLAUDE_PROJECT_DIR="$PROJ" QVEST_TEST_CACHE_ROOT="$C_EMPTY" Rscript "$ICF" > "$C3_OUT" 2>&1
chk "C3_zero_rows_skipped0" "0" "$(fld skipped "$C3_OUT")"
chk "C3b_zero_rows_fail1"   "1" "$(fld fail "$C3_OUT")"

echo ""
echo "══ D. contract_panel — 매핑 부재는 9축 skip, 존재하면 실제 판정 ═══════════"
CTP="$PROJ/08_Tests/data/test_contract_panel.R"
FAKE_D="$TD/fake_d"; mk_fake_root "$FAKE_D"
D1_OUT="$TD/d1.txt"
( cd "$FAKE_D" && CLAUDE_PROJECT_DIR="$FAKE_D" QM_ROOT="$FAKE_D" Rscript "$CTP" ) > "$D1_OUT" 2>&1
D1_RC=$?
chk "D1_absent_skipped9" "9" "$(fld skipped "$D1_OUT")"
chk "D1b_absent_pass0"   "0" "$(fld pass "$D1_OUT")"
chk "D1c_absent_fail0"   "0" "$(fld fail "$D1_OUT")"
chk "D1d_absent_rc0"     "0" "$D1_RC"
# 축 수 상수 드리프트 가드
_n_ax="$(grep -cE '^\s*(ok|bad)\("' "$CTP")"
if [ "$(grep -o 'N_AXES <- [0-9]*' "$CTP" | head -1 | grep -o '[0-9]*')" -le "$_n_ax" ]; then
  ok "D2_axis_count_sane" "N_AXES ≤ 실제 ok/bad 호출 수($_n_ax)"
else
  bad "D2_axis_count_sane" "N_AXES 가 실제 축 수($_n_ax)보다 큼 — skip 건수가 과대보고된다"
fi

# ③ 전제 **존재** arm — 이 검사는 게이트/소비자가 같은 실경로를 봐야 해서 env 치환을
#    쓸 수 없다(위 CTP 주석). 그래서 전제를 **실제로 놓고** 돌린 뒤, 우리가 만든 것만
#    지운다. 이미 있으면 건드리지 않는다(실데이터 보호).
CTP_MAP="$PROJ/.cache/dart/universe_corpcodes.csv"
_created_map=0
if [ ! -f "$CTP_MAP" ]; then
  _src=""
  if _gcd="$(git -C "$PROJ" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$_gcd" ]; then
    case "$_gcd" in /*|[A-Za-z]:*) : ;; *) _gcd="$PROJ/$_gcd" ;; esac
    [ -d "$_gcd" ] && _src="$(dirname "$(cd "$_gcd" && pwd)")/.cache/dart/universe_corpcodes.csv"
  fi
  if [ -n "$_src" ] && [ -f "$_src" ]; then
    mkdir -p "$(dirname "$CTP_MAP")" && cp "$_src" "$CTP_MAP" && _created_map=1
  fi
fi
if [ -f "$CTP_MAP" ]; then
  D3_OUT="$TD/d3.txt"
  CLAUDE_PROJECT_DIR="$PROJ" Rscript "$CTP" > "$D3_OUT" 2>&1
  chk "D3_present_skipped0" "0" "$(fld skipped "$D3_OUT")"
  chk "D3b_present_fail0"   "0" "$(fld fail "$D3_OUT")"
  chk "D3c_present_pass9"   "9" "$(fld pass "$D3_OUT")"
  # 전제가 있을 때 **일부러 넣은 위반**을 여전히 검거하는가 (패널 (ym,Ticker) 중복 주입)
  grep -q "PASS: engine_dup_injection_blocked" "$D3_OUT" \
    && ok "D3d_injection_still_caught" "중복 주입 → 엔진 stop 검거" \
    || bad "D3d_injection_still_caught" "전제가 있는데 위반 주입이 검거되지 않음"
else
  bad "D3_present_arm" "전제 arm 을 구성할 소스가 없음 — main 체크아웃에도 매핑이 없다(이 검사가 반쪽이 된다)"
fi
[ "$_created_map" -eq 1 ] && rm -f "$CTP_MAP"

echo ""
echo "══ E. 러너 — skip 이 FINAL/결과JSON 에 드러나고 종료코드를 물들이지 않는가 ══"
# 러너 사본 + 스텁 3종으로 **집계 자체를 실행해서** 잰다 (grep 배선 확인은 dead code 를
# 배선완료로 위장한다 — 실행 결과로 잰다).
mk_runner_sandbox(){ # mk_runner_sandbox <dir> <stub...>
  local r="$1"; shift
  mkdir -p "$r/08_Tests/hooks" "$r/08_Tests/stub"
  local body="" s
  for s in "$@"; do body="$body  \"08_Tests/stub/$s.sh\"\n"; done
  # SUITES=( ... ) 블록만 스텁 목록으로 교체 (배열 경계는 여는 줄과 단독 ')' 로 판정)
  awk -v repl="$body" '
    /^SUITES=\(/ { print; printf "%s", repl; inarr=1; next }
    inarr && /^\)/ { print; inarr=0; next }
    !inarr { print }
  ' "$PROJ/08_Tests/hooks/run_all_hooks.sh" > "$r/08_Tests/hooks/run_all_hooks.sh"
  chmod +x "$r/08_Tests/hooks/run_all_hooks.sh"
}
stub(){ # stub <dir> <name> <json>
  printf '#!/usr/bin/env bash\necho %s\n' "'$3'" > "$1/08_Tests/stub/$2.sh"; chmod +x "$1/08_Tests/stub/$2.sh"
}

R1="$TD/run1"; mk_runner_sandbox "$R1" s_pass s_skip
stub "$R1" s_pass '{"test":"s_pass","pass":3,"fail":0,"skipped":0,"total":3}'
stub "$R1" s_skip '{"test":"s_skip","pass":1,"fail":0,"skipped":2,"total":1,"skips":[{"axis":"AX_demo","reason":"전제 산출물 부재","missing":"/nope/thing.parquet"}]}'
E1_OUT="$TD/e1.txt"
CLAUDE_PROJECT_DIR="$R1" QM_ROOT="$R1" bash "$R1/08_Tests/hooks/run_all_hooks.sh" > "$E1_OUT" 2>&1
E1_RC=$?
if grep -qE '^FINAL: 4 pass / 0 fail / 2 skipped / 4 total' "$E1_OUT"; then
  ok "E1_final_line_has_skipped" "FINAL 에 skipped 계상"
else
  bad "E1_final_line_has_skipped" "FINAL='$(grep -m1 '^FINAL:' "$E1_OUT")'"
fi
chk "E2_skip_does_not_redden" "0" "$E1_RC"
grep -q "/nope/thing.parquet" "$E1_OUT" \
  && ok "E3_skip_reason_surfaced" "사유+없는 경로가 출력에 노출" \
  || bad "E3_skip_reason_surfaced" "skip 사유/경로가 러너 출력에 없음 — 숫자만 남으면 무시된다"
RES="$R1/.cache/test_results/hook_dryrun_results.json"
if [ -f "$RES" ]; then
  chk "E4_results_json_total_skipped" "2" "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("total_skipped","MISSING"))' "$RES")"
  chk "E4b_results_json_pass" "4" "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("total_pass","MISSING"))' "$RES")"
else
  bad "E4_results_json_total_skipped" "결과 JSON 미생성: $RES"
  bad "E4b_results_json_pass" "결과 JSON 미생성"
fi

# 통제: skip 만으로는 안 붉어지지만 **진짜 실패는 여전히 붉어진다**.
# 이게 없으면 E2 는 "러너가 아무것도 안 붉힌다"와 구분되지 않는다(공허한 통과).
R2="$TD/run2"; mk_runner_sandbox "$R2" s_pass s_skip s_fail
stub "$R2" s_pass '{"test":"s_pass","pass":3,"fail":0,"skipped":0,"total":3}'
stub "$R2" s_skip '{"test":"s_skip","pass":1,"fail":0,"skipped":2,"total":1,"skips":[{"axis":"AX_demo","reason":"전제 산출물 부재","missing":"/nope/thing.parquet"}]}'
stub "$R2" s_fail '{"test":"s_fail","pass":0,"fail":1,"skipped":0,"total":1}'
E2_OUT="$TD/e2.txt"
CLAUDE_PROJECT_DIR="$R2" QM_ROOT="$R2" bash "$R2/08_Tests/hooks/run_all_hooks.sh" > "$E2_OUT" 2>&1
E2_RC=$?
if [ "$E2_RC" -ne 0 ]; then ok "E5_real_fail_still_reddens" "rc=$E2_RC"
else bad "E5_real_fail_still_reddens" "실패 1건인데 rc=0 — 러너가 붉히지 못한다"; fi
grep -qE '^FINAL: 4 pass / 1 fail / 2 skipped' "$E2_OUT" \
  && ok "E5b_three_states_coexist" "pass/fail/skipped 3상태 동시 계상" \
  || bad "E5b_three_states_coexist" "FINAL='$(grep -m1 '^FINAL:' "$E2_OUT")'"

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIPPED=0"
echo "{\"test\":\"prereq_skip_contract\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":0,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
