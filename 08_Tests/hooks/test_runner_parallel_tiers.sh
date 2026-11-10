#!/usr/bin/env bash
#==============================================================================
# test_runner_parallel_tiers.sh — 배터리 러너(run_all_hooks.sh) 2026-11-10 개편의 양성 대조 (v10.2 시험 정리 · H1)
#
# 재는 것 (러너 사본 + 스텁 스위트로 집계를 실제로 실행해서 잰다 — grep 배선 확인 아님):
#   A. 병렬 = 직렬 — 같은 스텁 묶음(통과 · 실패 · skip · 요약 없음 exit0 · 요약 없음 exit1)을 슬롯 1 과 4 로 돌려
#      FINAL 줄 · 종료 코드 · 결과 JSON 합계가 같다 · 실패가 있으면 종료 코드 ≠ 0
#   B. 병렬 구간 등록부 쓰기 검출 — 병렬 스텁이 샌드박스 06_Registry/method_registry.json 을 쓰면 registry_dirty 에 오르고
#      종료 코드 ≠ 0 · 돌연변이(구간 지문 비교 끄기 — 소스 텍스트 치환)에서는 안 잡힌다(검출이 그 코드에서 온다)
#   C. 자기 사본 실행 — 실행 도중 스텁이 러너 원본을 통째로 덮어써도 결과 JSON · FINAL 이 나온다 ·
#      사본을 끄면(QVEST_RUNNER_NO_COPY=1) FINAL 이 사라진다(11-10 hooks=9 사고 재현)
#   D. 층 — suite_tiers.tsv 배정대로 fast ⊂ nightly ⊂ weekly · 미배정 = nightly · --tier > QVEST_BATTERY_TIER > full ·
#      결과 JSON tier 필드 · 알 수 없는 층 = 종료 코드 2
#   E. 자동 편입 — 08_Tests/scenarios/test_scn_* 는 SUITES 에 없어도 돈다 · 편입 검사기도 센다 ·
#      돌연변이(AUTO_ENROLL_GLOBS 줄 제거)에서는 검사기가 미편입으로 잡는다
# 격리: mktemp 샌드박스만 쓴다(운영 등록부 · .cache 쓰기 0). 실제 시험 · 네트워크 · 텔레그램 없음.
#==============================================================================
set -uo pipefail
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
RUNNER_SRC="$PROJ/08_Tests/hooks/run_all_hooks.sh"
CHECKER_SRC="$PROJ/02_Infrastructure/ops/suite_enrollment_check.sh"
PY="${QVEST_PY:-}"; PY="${PY//\\//}"; [ -x "$PY" ] || PY="$(command -v python.exe 2>/dev/null || command -v python 2>/dev/null)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1${2:+ — $2}"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL  $1${2:+ — $2}"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1" "$3"; else bad "$1" "want='$2' got='$3'"; fi; }
TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT
unset QVEST_BATTERY_TIER QVEST_SUITES_EXCLUDE QVEST_SUITES_ONLY QVEST_SUITES_JOBS QVEST_RUNNER_NO_COPY QVEST_RUNNER_COPY QVEST_RUNNER_ORIG

jget(){ "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); v=d.get(sys.argv[2]); print(len(v) if isinstance(v,list) else v)' "$1" "$2" 2>/dev/null; }

# mk_sb <dir> <runner 소스> <stub...> — SUITES 블록만 스텁 목록으로 교체(test_prereq_skip_contract.sh 와 같은 방식)
mk_sb(){
  local r="$1" src="$2"; shift 2
  mkdir -p "$r/08_Tests/hooks/profiles" "$r/08_Tests/stub" "$r/06_Registry" "$r/02_Infrastructure/ops"
  local body="" s
  for s in "$@"; do body="$body  \"08_Tests/stub/$s.sh\"\n"; done
  awk -v repl="$body" '
    /^SUITES=\(/ { print; printf "%s", repl; inarr=1; next }
    inarr && /^\)/ { print; inarr=0; next }
    !inarr { print }' "$src" > "$r/08_Tests/hooks/run_all_hooks.sh"
  printf '{"items":[]}\n' > "$r/06_Registry/method_registry.json"
}
stub(){ printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/08_Tests/stub/$2.sh"; }
tiers(){ { printf 'suite\ttier\tlane\treason\n'; cat; } > "$1/08_Tests/hooks/profiles/suite_tiers.tsv"; }
run_sb(){ # run_sb <dir> <out> [env...] -- [args...]
  local r="$1" o="$2"; shift 2
  local -a ev=(); while [ $# -gt 0 ] && [ "$1" != "--" ]; do ev+=("$1"); shift; done; [ "${1:-}" = "--" ] && shift
  env CLAUDE_PROJECT_DIR="$r" QM_ROOT="$r" "${ev[@]}" bash "$r/08_Tests/hooks/run_all_hooks.sh" "$@" > "$o" 2>&1
}
final(){ grep -m1 '^FINAL:' "$1"; }

STUBS=(p3 f1 sk ns0 ns1)
mk_std(){
  local r="$1"; mk_sb "$r" "$RUNNER_SRC" "${STUBS[@]}"
  stub "$r" p3  "echo '{\"test\":\"p3\",\"pass\":3,\"fail\":0,\"total\":3}'"
  stub "$r" f1  "echo '{\"test\":\"f1\",\"pass\":2,\"fail\":1,\"total\":3}'; exit 1"
  stub "$r" sk  "echo '{\"test\":\"sk\",\"pass\":1,\"fail\":0,\"skipped\":2,\"total\":1,\"skips\":[{\"axis\":\"X\",\"reason\":\"r\",\"missing\":\"/nope\"}]}'"
  stub "$r" ns0 "echo 'no summary'"
  stub "$r" ns1 "echo 'crash'; exit 3"
}

echo "══ A. 병렬 = 직렬 ══"
RA="$TD/a"; mk_std "$RA"
printf '08_Tests/stub/%s.sh\tnightly\tparallel\tt\n' "${STUBS[@]}" | tiers "$RA"
run_sb "$RA" "$TD/a1.txt" QVEST_SUITES_JOBS=1 --; RC1=$?; cp "$RA/.cache/test_results/hook_dryrun_results.json" "$TD/a1.json" 2>/dev/null
run_sb "$RA" "$TD/a4.txt" QVEST_SUITES_JOBS=4 --; RC4=$?; cp "$RA/.cache/test_results/hook_dryrun_results.json" "$TD/a4.json" 2>/dev/null
chk "A1 FINAL 직렬 = 병렬" "$(final "$TD/a1.txt")" "$(final "$TD/a4.txt")"
chk "A2 FINAL 값(5 스텁 계상 규칙 불변)" "FINAL: 6 pass / 2 fail / 2 skipped / 1 unmeasured / 8 total" "$(final "$TD/a4.txt")"
chk "A3 종료 코드 직렬 = 병렬" "$RC1" "$RC4"
[ "$RC4" -ne 0 ] && ok "A4 병렬에서 실패 → 종료 코드 ≠ 0" "rc=$RC4" || bad "A4 병렬에서 실패 → 종료 코드 ≠ 0" "rc=$RC4"
chk "A5 결과 JSON n_parallel(병렬 구간이 실제로 돌았다)" "5" "$(jget "$TD/a4.json" n_parallel)"
chk "A6 결과 JSON total_fail 직렬 = 병렬" "$(jget "$TD/a1.json" total_fail)" "$(jget "$TD/a4.json" total_fail)"
chk "A7 결과 JSON timings 수(스위트마다 1)" "5" "$(jget "$TD/a4.json" timings)"

echo "══ B. 병렬 구간 등록부 쓰기 검출 ══"
RB="$TD/b"; mk_sb "$RB" "$RUNNER_SRC" p3 dirty
stub "$RB" p3 "echo '{\"test\":\"p3\",\"pass\":3,\"fail\":0,\"total\":3}'"
stub "$RB" dirty 'printf "{\"items\":[1]}\n" > "$CLAUDE_PROJECT_DIR/06_Registry/method_registry.json"; echo "{\"test\":\"dirty\",\"pass\":1,\"fail\":0,\"total\":1}"'
printf '08_Tests/stub/%s.sh\tnightly\tparallel\tt\n' p3 dirty | tiers "$RB"
run_sb "$RB" "$TD/b.txt" QVEST_SUITES_JOBS=4 --; RCB=$?
NB="$(jget "$RB/.cache/test_results/hook_dryrun_results.json" registry_dirty)"
[ "${NB:-0}" -ge 1 ] && ok "B1 병렬 쓰기 → registry_dirty" "$NB건" || bad "B1 병렬 쓰기 → registry_dirty" "got=$NB"
[ "$RCB" -ne 0 ] && ok "B2 등록부 쓰기 → 종료 코드 ≠ 0" "rc=$RCB" || bad "B2 등록부 쓰기 → 종료 코드 ≠ 0" "rc=$RCB"
MUT="$TD/runner_mutB.sh"
sed 's/^    if \[\[ "\$_pg0" != "\$_pg1" \]\]; then$/    if false; then/' "$RUNNER_SRC" > "$MUT"
if [ "$(grep -c '^    if false; then$' "$MUT")" -ge 1 ]; then
  RBM="$TD/bm"; mk_sb "$RBM" "$MUT" p3 dirty
  cp "$RB/08_Tests/stub/"*.sh "$RBM/08_Tests/stub/"; cp "$RB/08_Tests/hooks/profiles/suite_tiers.tsv" "$RBM/08_Tests/hooks/profiles/"
  run_sb "$RBM" "$TD/bm.txt" QVEST_SUITES_JOBS=4 --
  chk "B3 돌연변이(구간 지문 비교 끔) → 놓침(검출이 그 코드에서 온다)" "0" "$(jget "$RBM/.cache/test_results/hook_dryrun_results.json" registry_dirty)"
else
  bad "B3 돌연변이 치환 미성사" "패턴 0곳"
fi

echo "══ C. 자기 사본 실행 ══"
mk_c(){ local r="$1"; mk_sb "$r" "$RUNNER_SRC" p3 edit p3b
  stub "$r" p3 "echo '{\"test\":\"p3\",\"pass\":3,\"fail\":0,\"total\":3}'"
  stub "$r" p3b "echo '{\"test\":\"p3b\",\"pass\":2,\"fail\":0,\"total\":2}'"
  stub "$r" edit 'printf "echo CLOBBERED\n" > "$CLAUDE_PROJECT_DIR/08_Tests/hooks/run_all_hooks.sh"; echo "{\"test\":\"edit\",\"pass\":1,\"fail\":0,\"total\":1}"'; }
RC_="$TD/c"; mk_c "$RC_"
run_sb "$RC_" "$TD/c.txt" QVEST_SUITES_JOBS=1 --
chk "C1 실행 중 원본 덮어써도 FINAL 그대로" "FINAL: 6 pass / 0 fail / 0 skipped / 0 unmeasured / 6 total" "$(final "$TD/c.txt")"
[ -f "$RC_/.cache/test_results/hook_dryrun_results.json" ] && ok "C2 결과 JSON 작성" || bad "C2 결과 JSON 작성" "없음"
RCN="$TD/cn"; mk_c "$RCN"
run_sb "$RCN" "$TD/cn.txt" QVEST_SUITES_JOBS=1 QVEST_RUNNER_NO_COPY=1 --
if [ -z "$(final "$TD/cn.txt")" ] || [ ! -f "$RCN/.cache/test_results/hook_dryrun_results.json" ]; then
  ok "C3 사본 끔(QVEST_RUNNER_NO_COPY=1) → FINAL/결과 소실(사고 재현 — 사본이 막는 것)"
else
  bad "C3 사본 끔 → 사고 재현 실패(이 축이 공허)" "$(final "$TD/cn.txt")"
fi

echo "══ D. 층 ══"
RD="$TD/d"; mk_sb "$RD" "$RUNNER_SRC" tf tn tw tu
for s in tf tn tw tu; do stub "$RD" "$s" "echo '{\"test\":\"$s\",\"pass\":1,\"fail\":0,\"total\":1}'"; done
printf '08_Tests/stub/tf.sh\tfast\tserial\tt\n08_Tests/stub/tn.sh\tnightly\tparallel\tt\n08_Tests/stub/tw.sh\tweekly\tserial\tt\n' | tiers "$RD"
tot(){ grep -m1 '^FINAL:' "$1" | grep -oE '[0-9]+ total' | grep -oE '[0-9]+'; }
RJ="$RD/.cache/test_results/hook_dryrun_results.json"
run_sb "$RD" "$TD/d_f.txt" -- --tier fast;        chk "D1 --tier fast = fast 만" "1" "$(tot "$TD/d_f.txt")"; chk "D1b 결과 tier 필드" "fast" "$(jget "$RJ" tier)"
run_sb "$RD" "$TD/d_n.txt" -- --tier nightly;     chk "D2 --tier nightly = fast+nightly+미배정" "3" "$(tot "$TD/d_n.txt")"
grep -q '층 미배정 1 → nightly' "$TD/d_n.txt" && ok "D3 미배정 수를 찍는다(조용히 빠지지 않음)" || bad "D3 미배정 수 표시" "$(grep -m1 '^층 =' "$TD/d_n.txt")"
run_sb "$RD" "$TD/d_w.txt" -- --tier weekly;      chk "D4 --tier weekly = 전부" "4" "$(tot "$TD/d_w.txt")"
run_sb "$RD" "$TD/d_0.txt" --;                    chk "D5 인자 없음 = 전부" "4" "$(tot "$TD/d_0.txt")"; chk "D5b 결과 tier = full" "full" "$(jget "$RJ" tier)"
run_sb "$RD" "$TD/d_e.txt" QVEST_BATTERY_TIER=fast --;        chk "D6 QVEST_BATTERY_TIER=fast" "1" "$(tot "$TD/d_e.txt")"
run_sb "$RD" "$TD/d_x.txt" QVEST_BATTERY_TIER=fast -- --tier weekly; chk "D7 인자 > 환경변수" "4" "$(tot "$TD/d_x.txt")"
run_sb "$RD" "$TD/d_bad.txt" -- --tier bogus; chk "D8 알 수 없는 층 → 종료 코드 2" "2" "$?"

echo "══ E. 자동 편입(scenarios) ══"
RE_="$TD/e"; mk_sb "$RE_" "$RUNNER_SRC" p3
stub "$RE_" p3 "echo '{\"test\":\"p3\",\"pass\":3,\"fail\":0,\"total\":3}'"
mkdir -p "$RE_/08_Tests/scenarios"
printf '#!/usr/bin/env bash\necho %s\n' "'{\"test\":\"scn\",\"pass\":2,\"fail\":0,\"total\":2}'" > "$RE_/08_Tests/scenarios/test_scn_demo.sh"
mv "$RE_/08_Tests/stub/p3.sh" "$RE_/08_Tests/stub/test_p3.sh"; sed -i 's#08_Tests/stub/p3.sh#08_Tests/stub/test_p3.sh#' "$RE_/08_Tests/hooks/run_all_hooks.sh"
run_sb "$RE_" "$TD/e.txt" --
chk "E1 scenarios 자동 편입 — SUITES 밖 시나리오가 돈다" "5" "$(tot "$TD/e.txt")"
cp "$CHECKER_SRC" "$RE_/02_Infrastructure/ops/suite_enrollment_check.sh"
E2O="$(CLAUDE_PROJECT_DIR="$RE_" QM_ROOT="$RE_" bash "$RE_/02_Infrastructure/ops/suite_enrollment_check.sh" 2>&1)"
printf '%s\n' "$E2O" | grep -q 'PASS  E2' && ok "E2 편입 검사기가 자동 편입분을 센다" || bad "E2 편입 검사기" "$(printf '%s' "$E2O" | grep -m1 'E2')"
sed -i '/^AUTO_ENROLL_GLOBS=(/d' "$RE_/08_Tests/hooks/run_all_hooks.sh"
E3O="$(CLAUDE_PROJECT_DIR="$RE_" QM_ROOT="$RE_" bash "$RE_/02_Infrastructure/ops/suite_enrollment_check.sh" 2>&1)"
printf '%s\n' "$E3O" | grep -q 'test_scn_demo.sh' && ok "E3 돌연변이(글롭 줄 제거) → 미편입으로 잡힘" || bad "E3 돌연변이 미검출" "$(printf '%s' "$E3O" | tail -2 | tr '\n' ' ')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"runner_parallel_tiers\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
