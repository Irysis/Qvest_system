#!/usr/bin/env bash
# test_suite_totals_anchor.sh — 배터리 총계 추출 앵커 위반 주입 (2026-08-20 신설)
#
# 무엇을 지키는가:
#   suite_totals_watch 는 "계측이 죽었는가"를 **총계 감소**로 감지하는 도구다.
#   그 도구 자신이 총계를 잘못 읽으면 감시망 전체가 무의미해진다.
#
# 실사고 2026-08-20: 러너 총계 1563 -> 기록 7. 원인은 러너 사망이 아니라 **파서**였다.
#   러너 총계(run_all_hooks.sh:1148)는 `FINAL: N pass / N fail / N skipped / N total`,
#   개별 테스트 일부는 `FINAL: N pass / N fail / N total`(skipped 없음)를 찍는다.
#   2026-08-03 수리가 skipped 를 **선택적**으로 만들어 양쪽을 받게 하자 개별 테스트 줄까지
#   매치됐고, `head -1` 이 **먼저 나온 테스트**를 집었다(실측: 4891행의 7).
#   fail=0 이라 초록으로 보였다 — 계측 사망이 '실패' 아닌 '총계 감소'로 오는 그 자리.
#
# ★검사는 정본 함수(st_pick_hooks_final)를 **직접 태운다**. 파싱을 여기에 복제하면
#   정본과 갈려서 "검사는 초록인데 운영은 틀린" 상태가 된다.
#
# 실행: bash 08_Tests/ops/test_suite_totals_anchor.sh

ROOT="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
# 경로 정규화는 하지 않는다 — QM_ROOT/CLAUDE_PROJECT_DIR 은 이 저장소 규약상 슬래시 형식이고,
# 역슬래시 치환 표현(${v//\//}, tr)은 bash 판본별로 슬래시를 삼키거나 경고를 낸다(2026-08-20 실측).
export QVEST_ST_LIB=1
# shellcheck disable=SC1090
. "$ROOT/02_Infrastructure/ops/suite_totals_watch.sh"

PASS=0; FAIL=0
chk() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS  $1"
  else FAIL=$((FAIL+1)); echo "  FAIL  $1 (기대='$2' 실제='$3')"; fi
}
tot() { printf '%s' "$1" | grep -oE '[0-9]+ total' | grep -oE '[0-9]+'; }

echo "=== 함수 존재 (정본을 실제로 태우는가) ==="
if command -v st_pick_hooks_final >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "  PASS  st_pick_hooks_final 로드됨"
else
  echo "  FAIL  st_pick_hooks_final 미로드 — 정본 경로가 아님"; echo "1 FAIL"; exit 1
fi

echo
echo "=== ★실사고 재현: 개별 테스트 줄이 러너 총계보다 **앞**에 온다 ==="
INCIDENT='─── Running: test_a ───
FINAL: 7 pass / 0 fail / 7 total
─── Running: test_b ───
FINAL: 29 pass / 0 fail / 29 total
─── Running: test_c ───
FINAL: 12 pass / 0 fail / 12 total
SKIPPED: (none)
FINAL: 1563 pass / 2 fail / 0 skipped / 1565 total
STATUS: ✅ ALL PASS'
got=$(st_pick_hooks_final "$INCIDENT")
chk "I1 러너 총계(1565)를 집는다 — 앞선 테스트 줄(7)이 아님" "1565" "$(tot "$got")"
chk "I2 fail 도 러너 것(2)" "2" "$(printf '%s' "$got" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+')"

echo
echo "=== ★현행 5-part 계약 (2026-08-24 러너가 unmeasured 구간 추가 — v10 2026-09-03 수리) ==="
#   구판 파서는 4-part 를 **정확히** 요구해 5-part 줄에 매치 0 → 3-part 폴백이 앞선 개별 테스트 줄을 집었다.
#   실측 결과 hooks=12(실제 3308) · fail=0(실제 6). 이 픽스처가 그 자리를 양성 대조로 고정한다.
# 실제 러너 출력 모양: 개별 테스트의 3-part 줄들 + 맨 끝 러너 5-part 총계(구 4-part 줄은 없다)
CURRENT='─── Running: test_a ───
FINAL: 7 pass / 0 fail / 7 total
─── Running: test_b ───
FINAL: 12 pass / 0 fail / 12 total
SKIPPED: (none)
FINAL: 3302 pass / 6 fail / 7 skipped / 9 unmeasured / 3308 total'
got5=$(st_pick_hooks_final "$CURRENT")
chk "C1 5-part 러너 총계(3308)를 집는다" "3308" "$(tot "$got5")"
chk "C2 fail 도 러너 것(6) — 앞선 개별 테스트의 0 이 아님" "6" "$(printf '%s' "$got5" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+')"
chk "C3 unmeasured 구간(9)이 보존된다" "9" "$(printf '%s' "$got5" | grep -oE '[0-9]+ unmeasured' | grep -oE '[0-9]+')"

echo "--- 돌연변이: 5-part 앵커를 제거하면 오늘의 결함이 재현되는가(구판=개별 줄 12를 집음) ---"
mut5=$(printf '%s' "$CURRENT" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ skipped / [0-9]+ total' | tail -1)
[ -z "$mut5" ] && mut5=$(printf '%s' "$CURRENT" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ total' | tail -1)
chk "C4 돌연변이(구판 2단 앵커) → 개별 테스트 줄(12)로 뒤집힘 = 검출력 실증" "12" "$(tot "$mut5")"

echo
echo "=== 양성 대조: 러너 총계만 있는 정상 출력 ==="
CLEAN='SKIPPED: (none)
FINAL: 800 pass / 0 fail / 3 skipped / 800 total'
chk "P1 정상 출력에서 800" "800" "$(tot "$(st_pick_hooks_final "$CLEAN")")"

echo
echo "=== 폴백: 러너가 구 형식(skipped 없음)으로 되돌아간 경우 ==="
OLD='─── Running: test_a ───
FINAL: 7 pass / 0 fail / 7 total
FINAL: 900 pass / 1 fail / 901 total'
chk "F1 구 형식에서도 **마지막** 줄(901)" "901" "$(tot "$(st_pick_hooks_final "$OLD")")"

echo
echo "=== 결측: FINAL 줄이 아예 없으면 빈 문자열(수치 없음은 정상이 아니다 가드로 넘김) ==="
chk "M1 매치 없음 -> 빈 문자열" "" "$(st_pick_hooks_final '아무 출력도 없음')"

echo
echo "=== 돌연변이: head -1 로 되돌리면 이 검사가 빨개지는가 (검사 효력 실증) ==="
mut() { printf '%s' "$1" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail /( [0-9]+ skipped /)? [0-9]+ total' | head -1; }
mut_tot=$(tot "$(mut "$INCIDENT")")
chk "X1 구판(head -1)은 7 을 집는다 = 이 검사가 실제 결함을 구분한다" "7" "$mut_tot"

echo
echo "=== 같은 날 재수집 건너뛰기 (2026-11-10 — 아침 체인이 리프레시를 다시 돌릴 때 배터리 중복 실행) ==="
TD="$(mktemp -d 2>/dev/null || echo "/tmp/st_anchor_$$")"; mkdir -p "$TD"
mk_latest() { printf '{\n  "collected_at": "%sT03:34:33+09:00",\n  "tree_head": "abc1234",\n  "hooks": %s,\n  "regime": null\n}\n' "$1" "$2" > "$TD/latest.json"; }
yn() { if "$@"; then echo yes; else echo no; fi; }
mk_latest "2026-11-10" "10975"
chk "S1 오늘 수집 · 수치 있음 → 건너뜀"            "yes" "$(yn st_collected_today "$TD/latest.json" "2026-11-10")"
chk "S2 어제 수집 → 다시 수집"                     "no"  "$(yn st_collected_today "$TD/latest.json" "2026-11-11")"
mk_latest "2026-11-10" "null"
chk "S3 오늘 수집이지만 hooks=null(수집 실패) → 다시 수집" "no" "$(yn st_collected_today "$TD/latest.json" "2026-11-10")"
chk "S4 최근 수집 파일 없음 → 수집"                "no"  "$(yn st_collected_today "$TD/none.json" "2026-11-10")"
# 돌연변이: 수치 확인을 뺀 판은 수집 실패한 날에도 건너뛴다 — S3 이 그것을 잡는다
st_today_mut() { local d; d=$(grep -oE '"collected_at": *"[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1); [ "$d" = "$2" ]; }
chk "X2 수치 확인이 없으면 실패한 수집도 건너뛴다 = S3 이 실제 결함을 구분한다" "yes" "$(yn st_today_mut "$TD/latest.json" "2026-11-10")"

echo
echo "=== 폴더별 합계 — 러너 결과의 timings 에서(중복 러너 대체) ==="
cat > "$TD/res.json" <<'JSON'
{"timings":[{"suite":"08_Tests/regime/test_a.R","secs":3,"rc":0,"pass":10,"fail":1,"skipped":0},
            {"suite":"08_Tests/regime/test_b.R","secs":1,"rc":0,"pass":5,"fail":0,"skipped":0},
            {"suite":"08_Tests/ops/test_c.sh","secs":2,"rc":0,"pass":7,"fail":0,"skipped":0}]}
JSON
chk "T1 regime 몫만 더한다(총 16 · 실패 1)" "16 1" "$(st_folder_totals "$TD/res.json" "08_Tests/regime/" | tr -d '\r')"
cat > "$TD/res_null.json" <<'JSON'
{"timings":[{"suite":"08_Tests/regime/test_a.R","secs":3,"rc":1,"pass":null,"fail":null,"skipped":null},
            {"suite":"08_Tests/regime/test_b.R","secs":1,"rc":0,"pass":5,"fail":0,"skipped":0}]}
JSON
chk "T2 요약을 못 낸 스위트가 섞이면 빈 값(0 으로 접지 않는다 → null)" "" "$(st_folder_totals "$TD/res_null.json" "08_Tests/regime/" | tr -d '\r')"
echo '{"tests":[]}' > "$TD/res_old.json"
chk "T3 timings 가 없는 구판 결과 → 빈 값"         "" "$(st_folder_totals "$TD/res_old.json" "08_Tests/regime/" | tr -d '\r')"
echo
echo "=== 단계(tier) — 밤 목록 · 주 1회 전체 (2026-11-10) ==="
echo '{"schema":"suite_tiers_v1","full_weekday": 6}' > "$TD/tiers.json"
chk "R1 전체 요일(6)이면 full"                       "full"    "$(st_pick_tier "$TD/tiers.json" 6)"
chk "R2 그 밖의 요일이면 nightly"                    "nightly" "$(st_pick_tier "$TD/tiers.json" 2)"
chk "R3 설정 파일이 없으면 full(조용히 줄이지 않는다)" "full"   "$(st_pick_tier "$TD/none.json" 2)"
echo '{"full_weekday": "토"}' > "$TD/tiers_bad.json"
chk "R4 요일 값을 못 읽으면 full"                    "full"    "$(st_pick_tier "$TD/tiers_bad.json" 2)"
printf '# 주석\n08_Tests/ops/test_a.sh\n\n  # 들여쓴 주석\n08_Tests/hooks/test_b.R  \n' > "$TD/nightly.exclude"
RX="$(st_profile_regex "$TD/nightly.exclude")"
chk "R5 프로필 → 정규식(주석 · 빈 줄 제외 · 점 이스케이프)" '08_Tests/ops/test_a\.sh|08_Tests/hooks/test_b\.R' "$RX"
m1=no; [[ "08_Tests/ops/test_a.sh" =~ $RX ]] && m1=yes
m2=no; [[ "08_Tests/ops/test_axsh" =~ $RX ]] && m2=yes
chk "R6 정규식이 목록의 경로에 걸린다"               "yes" "$m1"
chk "R7 점이 임의 글자로 풀리지 않는다(test_axsh 는 안 걸림)" "no" "$m2"
chk "R8 프로필이 없으면 빈 값(아무것도 빼지 않는다)" "" "$(st_profile_regex "$TD/none.exclude")"
# 운영 프로필의 경로가 전부 실재 · 배터리 목록에 있다(없는 경로를 빼는 프로필은 조용히 무의미해진다)
PROF="$ROOT/08_Tests/hooks/profiles/nightly.exclude"; miss=0; n=0
if [ -f "$PROF" ]; then
  while IFS= read -r ln; do
    ln="${ln%$'\r'}"; case "$ln" in ''|'#'*) continue ;; esac; n=$((n+1))
    { [ -f "$ROOT/$ln" ] && grep -qF "\"$ln\"" "$ROOT/08_Tests/hooks/run_all_hooks.sh"; } || miss=$((miss+1))
  done < "$PROF"
fi
chk "R9 운영 밤 제외 목록 — 경로 전부 실재 · 배터리 목록에 있음(${n}종)" "0" "$miss"
# 단계가 다른 수집은 총계를 견주지 않는다 · 밤 수집은 기준선이 될 수 없다
BASELINE="$TD/base.json"; LATEST="$TD/latest.json"
printf '{"collected_at":"2026-08-03T09:56:04+09:00","tree_head":"x","hooks":1000,"regime":50,"hooks_fail":0}\n' > "$BASELINE"
printf '{"collected_at":"2026-11-10T03:00:00+09:00","tree_head":"x","tier":"nightly","hooks":870,"regime":50,"hooks_fail":0,"regime_fail":0}\n' > "$LATEST"
out_n="$(check 2>&1)"; rc_n=$?
chk "R10 밤 수집(870) vs 전체 기준선(1000) → '총계 감소' 아님(rc 0)" "0" "$rc_n"
chk "R11 생략 사실을 출력에 적는다"                 "yes" "$(printf '%s' "$out_n" | grep -q '총계 비교 생략' && echo yes || echo no)"
printf '{"collected_at":"2026-11-10T03:00:00+09:00","tree_head":"x","tier":"full","hooks":870,"regime":50,"hooks_fail":0,"regime_fail":0}\n' > "$LATEST"
check >/dev/null 2>&1; rc_f=$?
chk "R12 [대조] 전체 수집이 줄었으면 그대로 경보(rc 1)" "1" "$rc_f"
printf '{"collected_at":"2026-11-10T03:00:00+09:00","tree_head":"x","tier":"nightly","hooks":870,"regime":50,"hooks_fail":3,"regime_fail":0}\n' > "$LATEST"
check >/dev/null 2>&1; rc_ff=$?
chk "R13 밤 수집이어도 fail > 0 은 경보(rc 1)"       "1" "$rc_ff"
cp "$BASELINE" "$TD/base_before.json"
promote >/dev/null 2>&1; rc_p=$?
chk "R14 밤 수집은 기준선 승격 거부(rc 1 · 기준선 불변)" "1 same" "$rc_p $(cmp -s "$BASELINE" "$TD/base_before.json" && echo same || echo changed)"
rm -rf "$TD" 2>/dev/null

echo
echo "=== test_suite_totals_anchor: $PASS PASS / $FAIL FAIL ==="
echo "{\"test\":\"suite_totals_anchor\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":0,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
