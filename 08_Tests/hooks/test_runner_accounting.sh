#!/usr/bin/env bash
#==============================================================================
# test_runner_accounting.sh — 배터리 러너(run_all_hooks.sh) 집계의 fail-closed 양성 대조 (2026-11-10 · 적대적 검토 U12)
#
# 결함(수리 전 재현): 스위트 요약 줄의 pass/fail/skipped 가 정수가 아니면(2.0 · [3] · null · true)
#   본 루프의 $((TOTAL_PASS + PASS)) 산술 오류가 for 루프 전체를 버리고, 남은 스위트는 실행조차 안 된 채
#   결과 JSON · FINAL 이 그때까지의 합계로 'ALL PASS' · 종료 코드 0 이 됐다(set -u 아래 null/true 는 러너 사망).
# 재는 것 (러너 사본 + 스텁 스위트로 집계를 실제로 실행해서 잰다 — grep 배선 확인 아님):
#   N. 비정수 요약 → 그 스위트 = 실패(미측정) 1건 · 뒤 스위트는 계속 돈다 · 종료 코드 ≠ 0 (직렬 · 병렬)
#   V. 값 모양별(목록 · null · true · 음수 · 문자열 · 실수 · fail 쪽 비정수) — 전부 같은 계상
#   K. 정상 실행의 결과 JSON n_expected = n_run(집계 루프 완주 대조 필드)
#   M. 돌연변이(소스 텍스트 치환 · 치환 성사 단정):
#      M1 수치 가드를 끄면 → 루프 완주 대조가 단독으로 잡는다(종료 코드 ≠ 0 · '집계 루프' 표시)
#      M2 가드 + 완주 대조를 함께 끄면 → 원 결함 재현(ALL PASS · rc 0 · 뒤 스위트 미실행) = 이 시험이 그 코드를 잰다
# 격리: mktemp 샌드박스만 쓴다(운영 등록부 · .cache 쓰기 0). 실제 시험 · 네트워크 · 텔레그램 없음.
#==============================================================================
set -uo pipefail
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
RUNNER_SRC="$PROJ/08_Tests/hooks/run_all_hooks.sh"
PY="${QVEST_PY:-}"; PY="${PY//\\//}"; [ -x "$PY" ] || PY="$(command -v python.exe 2>/dev/null || command -v python 2>/dev/null)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1${2:+ — $2}"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL  $1${2:+ — $2}"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1" "$3"; else bad "$1" "want='$2' got='$3'"; fi; }
yes_if(){ if eval "$2"; then ok "$1" "${3:-}"; else bad "$1" "${3:-}"; fi; }
TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT
unset QVEST_BATTERY_TIER QVEST_SUITES_EXCLUDE QVEST_SUITES_ONLY QVEST_SUITES_JOBS QVEST_RUNNER_NO_COPY QVEST_RUNNER_COPY QVEST_RUNNER_ORIG

jget(){ "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); v=d.get(sys.argv[2]); print(len(v) if isinstance(v,list) else v)' "$1" "$2" 2>/dev/null; }

# mk_sb <dir> <runner 소스> <stub...> — SUITES 블록만 스텁 목록으로 교체(test_runner_parallel_tiers.sh 와 같은 방식)
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
run_sb(){ # run_sb <dir> <out> [env...] --
  local r="$1" o="$2"; shift 2
  local -a ev=(); while [ $# -gt 0 ] && [ "$1" != "--" ]; do ev+=("$1"); shift; done; [ "${1:-}" = "--" ] && shift
  env CLAUDE_PROJECT_DIR="$r" QM_ROOT="$r" "${ev[@]}" bash "$r/08_Tests/hooks/run_all_hooks.sh" "$@" > "$o" 2>&1
}
final(){ grep -m1 '^FINAL:' "$1"; }
nfail(){ final "$1" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+'; }
RES(){ printf '%s' "$1/.cache/test_results/hook_dryrun_results.json"; }

# 표준 묶음: a(3 통과) · bad(비정수 요약) · zfail(5 실패 · exit 1). 기대 = pass 3 · fail 5 + 1 = 6 · 종료 코드 ≠ 0 · zfail 실행.
mk_std(){ # <dir> <runner 소스> <bad 요약 JSON>
  local r="$1"; mk_sb "$r" "$2" a bad zfail
  stub "$r" a     "echo '{\"test\":\"a\",\"pass\":3,\"fail\":0,\"total\":3}'"
  stub "$r" bad   "echo '$3'"
  stub "$r" zfail "echo ZFAIL_RAN; echo '{\"test\":\"zfail\",\"pass\":0,\"fail\":5,\"total\":5}'; exit 1"
}

echo "══ N. 비정수 요약(pass 2.0) — 직렬 · 병렬 ══"
RN="$TD/n"; mk_std "$RN" "$RUNNER_SRC" '{"test":"bad","pass":2.0,"fail":0,"total":2}'
run_sb "$RN" "$TD/n1.txt" QVEST_SUITES_JOBS=1 --; RCN1=$?
yes_if "N1 뒤 스위트(zfail)가 실행된다 — 루프가 끊기지 않음" 'grep -q "^ZFAIL_RAN" "$TD/n1.txt"'
chk "N2 FINAL = 3 pass · 6 fail(zfail 5 + 비정수 1)" "FINAL: 3 pass / 6 fail / 0 skipped / 0 unmeasured / 9 total" "$(final "$TD/n1.txt")"
[ "$RCN1" -ne 0 ] && ok "N3 종료 코드 ≠ 0" "rc=$RCN1" || bad "N3 종료 코드 ≠ 0" "rc=$RCN1"
chk "N4 결과 JSON status = FAIL" "FAIL" "$(jget "$(RES "$RN")" status)"
uf_has(){ "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); sys.exit(0 if any(sys.argv[2] in x and sys.argv[3] in x for x in d.get("unmeasured_failing",[])) else 1)' "$1" "$2" "$3" 2>/dev/null; }
yes_if "N5 비정수 사유가 이름과 함께 남는다(unmeasured_failing)" 'uf_has "$(RES "$RN")" "bad.sh" "비정수"'
yes_if "N6 STATUS 가 ALL PASS 가 아니다" '! grep -q "STATUS: ✅ ALL PASS" "$TD/n1.txt"'
printf '08_Tests/stub/%s.sh\tnightly\tparallel\tt\n' a bad zfail | tiers "$RN"
run_sb "$RN" "$TD/n4.txt" QVEST_SUITES_JOBS=4 --; RCN4=$?
chk "N7 병렬 구간에서도 같은 FINAL" "$(final "$TD/n1.txt")" "$(final "$TD/n4.txt")"
chk "N8 병렬 종료 코드 = 직렬" "$RCN1" "$RCN4"
chk "N9 병렬 구간이 실제로 돌았다(n_parallel)" "3" "$(jget "$(RES "$RN")" n_parallel)"

echo "══ V. 값 모양별 — 전부 실패 1건 + 뒤 스위트 계속 ══"
i=0
for J in '{"test":"bad","pass":[3],"fail":0,"total":3}' \
         '{"test":"bad","pass":null,"fail":0,"total":0}' \
         '{"test":"bad","pass":true,"fail":0,"total":1}' \
         '{"test":"bad","pass":-1,"fail":0,"total":-1}' \
         '{"test":"bad","pass":"3","fail":0,"total":3}' \
         '{"test":"bad","pass":2.5,"fail":0,"total":2}' \
         '{"test":"bad","pass":1,"fail":0.0,"skipped":null,"total":1}'; do
  i=$((i+1)); RV="$TD/v$i"; mk_std "$RV" "$RUNNER_SRC" "$J"
  run_sb "$RV" "$TD/v$i.txt" QVEST_SUITES_JOBS=1 --; RCV=$?
  got="$(nfail "$TD/v$i.txt")|$(grep -c '^ZFAIL_RAN' "$TD/v$i.txt")|$([ "$RCV" -ne 0 ] && echo rc_nz || echo rc0)"
  chk "V$i $J → fail 6 · zfail 실행 · rc≠0" "6|1|rc_nz" "$got"
done

echo "══ K. 정상 실행 — 루프 완주 대조 필드 ══"
RK="$TD/k"; mk_sb "$RK" "$RUNNER_SRC" a b c
for s in a b c; do stub "$RK" "$s" "echo '{\"test\":\"$s\",\"pass\":2,\"fail\":0,\"total\":2}'"; done
run_sb "$RK" "$TD/k.txt" QVEST_SUITES_JOBS=1 --; RCK=$?
chk "K1 정상 묶음 ALL PASS · rc 0(가드가 정상 값을 막지 않음)" "FINAL: 6 pass / 0 fail / 0 skipped / 0 unmeasured / 6 total|0" "$(final "$TD/k.txt")|$RCK"
chk "K2 결과 JSON n_expected = n_run = 3" "3 3" "$(jget "$(RES "$RK")" n_expected) $(jget "$(RES "$RK")" n_run)"
RKO="$TD/ko"; mk_sb "$RKO" "$RUNNER_SRC" a b c
for s in a b c; do stub "$RKO" "$s" "echo '{\"test\":\"$s\",\"pass\":2,\"fail\":0,\"total\":2}'"; done
run_sb "$RKO" "$TD/ko.txt" QVEST_SUITES_JOBS=1 QVEST_SUITES_ONLY='/(a|c)\.sh$' --; RCKO=$?
chk "K3 필터(QVEST_SUITES_ONLY)로 뺀 스위트는 기대 수에서도 빠진다(2 = 2 · rc 0)" "2 2 0" "$(jget "$(RES "$RKO")" n_expected) $(jget "$(RES "$RKO")" n_run) $RCKO"

echo "══ M. 돌연변이 ══"
# M1: 수치 가드(파이썬 · 셸) 끔 — 파이썬은 원판처럼 %s 로 그대로 찍는다
M1="$TD/runner_m1.sh"
sed -e 's/^    if all(_qv_n(v) for v in vals):  # QV-NUM-GUARD$/    if True:  # mutated/' \
    -e 's/^        print("ok %d %d %d" % tuple(vals))$/        print("ok %s %s %s" % tuple(vals))/' \
    -e '/# QV-NUM-GUARD-SH$/d' "$RUNNER_SRC" > "$M1"
n_g="$(grep -c '^    if True:  # mutated$' "$M1")"; n_p="$(grep -c 'print("ok %s %s %s" % tuple(vals))' "$M1")"
n_s="$(grep -c 'QV-NUM-GUARD-SH' "$RUNNER_SRC")"; n_s1="$(grep -c 'QV-NUM-GUARD-SH' "$M1")"
if [ "$n_g" = "1" ] && [ "$n_p" = "1" ] && [ "$n_s" -ge 1 ] && [ "$n_s1" = "0" ]; then
  ok "M0 돌연변이 M1 치환 성사" "가드 1 · 출력 1 · 셸 가드 $n_s → 0"
  RM1="$TD/m1"; mk_std "$RM1" "$M1" '{"test":"bad","pass":2.0,"fail":0,"total":2}'
  run_sb "$RM1" "$TD/m1.txt" QVEST_SUITES_JOBS=1 --; RCM1=$?
  yes_if "M1a 가드를 꺼도(산술 오류로 루프 이탈) 완주 대조가 잡는다 — rc≠0" '[ "$RCM1" -ne 0 ]' "rc=$RCM1"
  yes_if "M1b STATUS 가 ALL PASS 가 아니다" '! grep -q "STATUS: ✅ ALL PASS" "$TD/m1.txt"'
  yes_if "M1c 루프 이탈이 이름으로 보인다('집계 루프')" 'grep -q "집계 루프" "$TD/m1.txt"'
  yes_if "M1d [대조] 이 돌연변이에서는 실제로 루프가 끊겼다(zfail 미실행)" '! grep -q "^ZFAIL_RAN" "$TD/m1.txt"'
  # M2: M1 + 완주 대조 끔 → 원 결함 재현
  M2="$TD/runner_m2.sh"
  sed -e 's/^if (( _QV_N_DONE != _QV_N_EXPECT )); then$/if false; then/' "$M1" > "$M2"
  if [ "$(grep -c '^if false; then$' "$M2")" = "1" ]; then
    ok "M0b 돌연변이 M2 치환 성사"
    RM2="$TD/m2"; mk_std "$RM2" "$M2" '{"test":"bad","pass":2.0,"fail":0,"total":2}'
    run_sb "$RM2" "$TD/m2.txt" QVEST_SUITES_JOBS=1 --; RCM2=$?
    chk "M2 가드 + 완주 대조 끔 → 원 결함 재현(ALL PASS · rc 0 · zfail 미실행)" "1|0|0" \
        "$(grep -c 'STATUS: ✅ ALL PASS' "$TD/m2.txt")|$RCM2|$(grep -c '^ZFAIL_RAN' "$TD/m2.txt")"
  else
    bad "M0b 돌연변이 M2 치환 미성사" "패턴 0곳"
  fi
else
  bad "M0 돌연변이 M1 치환 미성사" "가드 $n_g · 출력 $n_p · 셸 가드 $n_s → $n_s1"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"runner_accounting\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
