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
echo "=== test_suite_totals_anchor: $PASS PASS / $FAIL FAIL ==="
echo "{\"test\":\"suite_totals_anchor\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":0,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
