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
# ST_WATCH_SRC = 감시기 판본 바꿔 끼우기(수리 전 판으로 재현할 때 · 돌연변이 사본). 기본 = 정본.
WATCH="${ST_WATCH_SRC:-$ROOT/02_Infrastructure/ops/suite_totals_watch.sh}"
# shellcheck disable=SC1090
. "$WATCH"

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
# 단계가 다른 수집은 등록부 기준선과 총계를 견주지 않는다 · 대신 같은 층의 층별 기준과 견준다(2026-11-10 · U12) · 밤 수집은 등록부 기준선이 될 수 없다
BASELINE="$TD/base.json"; LATEST="$TD/latest.json"; TIER_REF="$TD/tier_ref.json"
yn2() { if grep -q -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
mkL() { printf '{"collected_at":"2026-11-10T03:00:00+09:00","tree_head":"x",%s}\n' "$1" > "$LATEST"; }
mkR() { printf '{"schema":"suite_totals_tier_baseline_v1","tiers":{%s}}\n' "$1" > "$TIER_REF"; }
printf '{"collected_at":"2026-08-03T09:56:04+09:00","tree_head":"x","hooks":1000,"regime":50,"hooks_fail":0}\n' > "$BASELINE"
rm -f "$TIER_REF"
mkL '"tier":"nightly","hooks":870,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
out_n="$(check 2>&1)"; rc_n=$?
chk "R10 밤 수집(870) · 같은 층 기준 없음 vs 전체 기준선(1000) → '총계 감소' 아님(rc 0)" "0" "$rc_n"
chk "R11 같은 층 기준 없음 → '미판정'을 적고 OK 로 끝내지 않는다" "yes no" "$(yn2 "$out_n" '총계 미판정') $(yn2 "$out_n" '\] OK ')"
mkR '"nightly":{"collected_at":"2026-11-09T03:00:00+09:00","hooks":1200,"regime":50,"hooks_unmeasured":0}'
mkL '"tier":"nightly","hooks":1000,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
out_w1="$(check 2>&1)"; rc_w1=$?
chk "W1 밤 수집 1200 → 1000(같은 층 직전 대비 감소) → 경보(rc 1 · '총계 감소')" "1 yes" "$rc_w1 $(yn2 "$out_w1" '총계 감소')"
mkL '"tier":"nightly","hooks":1210,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
out_w2="$(check 2>&1)"; rc_w2=$?
chk "W2 [대조] 밤 수집이 같은 층 직전 이상 → OK(rc 0 · hooks=1210 표시)" "0 yes" "$rc_w2 $(yn2 "$out_w2" 'OK .*hooks=1210')"
mkL '"tier":"nightly","hooks":1200,"regime":0,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
check >/dev/null 2>&1; rc_w3=$?
chk "W3 밤 수집 regime 50 → 0(계측 사망) → 경보(rc 1)" "1" "$rc_w3"
mkR '"full":{"collected_at":"2026-11-07T03:00:00+09:00","hooks":10975,"regime":50,"hooks_unmeasured":0}'
printf '{"collected_at":"2026-08-03T09:56:04+09:00","tree_head":"x","hooks":954,"regime":5,"hooks_fail":0}\n' > "$BASELINE"
mkL '"tier":"weekly","hooks":2000,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
out_w4="$(check 2>&1)"; rc_w4=$?
chk "W4 주간 10975 → 2000 — 낡은 등록부 기준선(954)보다 커도 같은 층 직전 대비 감소로 경보(rc 1)" "1 yes" "$rc_w4 $(yn2 "$out_w4" '총계 감소')"
chk "W5 등록부 기준선 낡음을 적는다"                 "yes" "$(yn2 "$out_w4" '기준선이 같은 층 직전 실측보다 작다')"
printf '{"collected_at":"2026-08-03T09:56:04+09:00","tree_head":"x","hooks":1000,"regime":50,"hooks_fail":0}\n' > "$BASELINE"
rm -f "$TIER_REF"
mkL '"tier":"nightly","hooks":1200,"regime":50,"hooks_fail":0,"hooks_unmeasured":40,"regime_fail":0'
out_u1="$(check 2>&1)"; rc_u1=$?
chk "U1 밤 수집 hooks_unmeasured 40 → 미측정 경보(rc 1)" "1 yes" "$rc_u1 $(yn2 "$out_u1" '미측정')"
mkL '"tier":"weekly","hooks":2000,"regime":50,"hooks_fail":0,"hooks_unmeasured":40,"regime_fail":0'
check >/dev/null 2>&1; rc_u2=$?
chk "U2 주간 수집 hooks_unmeasured 40 → 미측정 경보(rc 1)" "1" "$rc_u2"
mkL '"tier":"nightly","hooks":null,"regime":null,"hooks_fail":null,"hooks_unmeasured":null,"regime_fail":null'
out_u3="$(check 2>&1)"; rc_u3=$?
chk "U3 밤 수집 hooks null(결과 파일 없음 · 낡음) → 미측정 경보(rc 1 · 0 으로 접지 않음)" "1 yes" "$rc_u3 $(yn2 "$out_u3" '미측정')"
mkL '"tier":"full","hooks":1200,"regime":50,"hooks_fail":0,"regime_fail":0'
check >/dev/null 2>&1; rc_u4=$?
chk "U4 hooks_unmeasured 키 없음(미측정 여부 미상) → 경보(rc 1)" "1" "$rc_u4"
mkL '"tier":"full","hooks":870,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
check >/dev/null 2>&1; rc_f=$?
chk "R12 [대조] 전체 수집이 등록부 기준선보다 줄었으면 그대로 경보(rc 1)" "1" "$rc_f"
mkL '"tier":"nightly","hooks":870,"regime":50,"hooks_fail":3,"hooks_unmeasured":0,"regime_fail":0'
check >/dev/null 2>&1; rc_ff=$?
chk "R13 밤 수집이어도 fail > 0 은 경보(rc 1)"       "1" "$rc_ff"
cp "$BASELINE" "$TD/base_before.json"
promote >/dev/null 2>&1; rc_p=$?
chk "R14 밤 수집은 등록부 기준선 승격 거부(rc 1 · 기준선 불변)" "1 same" "$rc_p $(cmp -s "$BASELINE" "$TD/base_before.json" && echo same || echo changed)"

echo
echo "=== 층별 기준 흡수 (2026-11-10 · U12 — 수집이 덮어쓰기 직전 앞 수집을 그 층 칸에) ==="
refv() { "$PY" -c 'import io,json,sys; d=json.load(io.open(sys.argv[1],encoding="utf-8")); v=(d.get("tiers") or {}).get(sys.argv[2]) or {}; print(v.get(sys.argv[3]))' "$TIER_REF" "$1" "$2" 2>/dev/null | tr -d '\r'; }
rm -f "$TIER_REF"
mkL '"tier":"nightly","hooks":900,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
st_tier_ref_absorb "$LATEST" "$TIER_REF" >/dev/null; rc_a1=$?
chk "A1 건강한 밤 수집 → 밤 칸 흡수(rc 0 · hooks 900)" "0 900" "$rc_a1 $(refv nightly hooks)"
mkL '"tier":"nightly","hooks":950,"regime":50,"hooks_fail":0,"hooks_unmeasured":40,"regime_fail":0'
st_tier_ref_absorb "$LATEST" "$TIER_REF" >/dev/null; rc_a2=$?
chk "A2 미측정 40 인 수집은 기준이 되지 못함(rc 1 · 900 유지)" "1 900" "$rc_a2 $(refv nightly hooks)"
mkL '"tier":"nightly","hooks":800,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
st_tier_ref_absorb "$LATEST" "$TIER_REF" >/dev/null; rc_a3=$?
chk "A3 직전보다 줄어든 수집은 기준이 되지 못함(rc 1 · 900 유지 — 연이은 결손이 서로를 기준 삼지 않게)" "1 900" "$rc_a3 $(refv nightly hooks)"
st_tier_ref_absorb "$LATEST" "$TIER_REF" --force >/dev/null; rc_a4=$?
chk "A4 사람의 수용(--force · --accept-tier)은 감소를 받아들인다(rc 0 · 800)" "0 800" "$rc_a4 $(refv nightly hooks)"
mkL '"tier":"nightly","hooks":null,"regime":50,"hooks_fail":null,"hooks_unmeasured":null,"regime_fail":0'
st_tier_ref_absorb "$LATEST" "$TIER_REF" --force >/dev/null; rc_a5=$?
chk "A5 --force 여도 미측정 수집은 거부(rc 1 · 800 유지)" "1 800" "$rc_a5 $(refv nightly hooks)"
mkL '"tier":"weekly","hooks":10975,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0'
st_tier_ref_absorb "$LATEST" "$TIER_REF" >/dev/null
chk "A6 weekly 수집은 full 칸(check 와 같은 층 규칙) · 밤 칸 불변" "10975 800" "$(refv full hooks) $(refv nightly hooks)"
printf '{"tier":"nightly","timings":[]}\n' > "$TD/res_t.json"
chk "T4 러너 결과 파일의 층을 읽는다"               "nightly" "$(st_result_tier "$TD/res_t.json")"
printf '{"tier":"bogus"}\n' > "$TD/res_tb.json"
chk "T5 알 수 없는 층 값 → 빈 값(요청한 층으로 둔다)" "" "$(st_result_tier "$TD/res_tb.json")"

echo
echo "=== 돌연변이 (소스 텍스트 치환 · 치환 성사 단정) — 검출이 그 코드에서 오는가 ==="
mut_run() { # <치환 sed 식> <표식 grep> <LATEST 내용> <TIER_REF 내용 또는 빈 값> → "<치환 수> <rc>"
  local m="$TD/watch_mut.sh" n rc b="$BASELINE" l="$LATEST" t="$TIER_REF"
  sed -e "$1" "$WATCH" > "$m"; n="$(grep -c -- "$2" "$m")"
  mkL "$3"; if [ -n "$4" ]; then mkR "$4"; else rm -f "$TIER_REF"; fi
  # 사본을 source 하면 경로 변수가 운영 경로로 다시 잡힌다 — source 뒤에 시험 경로로 되돌린다(운영 파일을 읽지 않게)
  ( . "$m"; BASELINE="$b"; LATEST="$l"; TIER_REF="$t"; check >/dev/null 2>&1 ); rc=$?
  printf '%s %s' "$n" "$rc"
}
chk "X3 미측정 축(ST-UM-HITS) 끔 → U1 을 놓친다(rc 0) = 미측정 판정이 그 줄에서 온다" "1 0" \
  "$(mut_run 's/^um_hits = \[.*# ST-UM-HITS$/um_hits = []  # MUTATED-UM/' 'MUTATED-UM' '"tier":"nightly","hooks":1200,"regime":50,"hooks_fail":0,"hooks_unmeasured":40,"regime_fail":0' '')"
chk "X4 같은 층 비교(ST-TIER-REF) 끔 → W1 을 놓친다(rc 0) = 밤 층 감소 판정이 그 줄에서 온다" "1 0" \
  "$(mut_run 's/^if ref_t is not None:  # ST-TIER-REF$/if False:  # MUTATED-REF/' 'MUTATED-REF' '"tier":"nightly","hooks":1000,"regime":50,"hooks_fail":0,"hooks_unmeasured":0,"regime_fail":0' '"nightly":{"collected_at":"2026-11-09T03:00:00+09:00","hooks":1200,"regime":50,"hooks_unmeasured":0}')"
rm -rf "$TD" 2>/dev/null

echo
echo "=== test_suite_totals_anchor: $PASS PASS / $FAIL FAIL ==="
echo "{\"test\":\"suite_totals_anchor\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":0,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
