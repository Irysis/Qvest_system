#!/usr/bin/env bash
# test_paper_dispatch_backfill.sh — 논문 dispatch 백로그 선정 계약 (2026-08-13 신설)
#
# 왜: 소비자(paper_research_dispatch.R)가 생산자(라우터)보다 먼저 돌고 **오늘 큐만** 읽어
#   그날 큐가 영구 미소비로 남았다(실측 47편). 구동기가 그 날짜를 고르는 규칙이 본체다.
#
# ★이 검사의 핵심은 T2(음성 대조)와 T3(무음 절단 금지)다.
#   T1 만 있으면 "전부 고른다"도 통과한다 — 이미 소비한 날을 **다시 안 고르는지**가 같이 필요하고,
#   창 밖이라 뺀 날은 **목록으로 찍히는지**가 필요하다(조용히 자르면 '전부 처리'로 읽힌다).
#
# 방식: 임시 stage 디렉터리 + `--dry-run` 으로 **선정 규칙만** 검사한다(R 미호출).
#   실제 구동 경로는 QVEST_DISPATCH_RUNNER 로 갈아끼워 별도 축(T6)에서 확인.
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
[ -n "$PROJ" ] || { echo "PROJECT_ROOT 해석 실패" >&2
  echo '{"test":"paper_dispatch_backfill","pass":0,"fail":1,"total":1,"preflight":"no_root"}'; exit 1; }
SRC="$PROJ/02_Infrastructure/ops/paper_dispatch_backfill.sh"
[ -f "$SRC" ] || { echo "원본 없음: $SRC" >&2
  echo '{"test":"paper_dispatch_backfill","pass":0,"fail":1,"total":1,"preflight":"no_src"}'; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" 2>/dev/null' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
        else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); echo "  ok   $1"
        else FAIL=$((FAIL+1)); echo "  FAIL $1 — 출력에 '$3' 없음"; fi; }
hasnt() { if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); echo "  FAIL $1 — 출력에 '$3' 가 있으면 안 됨"
          else PASS=$((PASS+1)); echo "  ok   $1"; fi; }

R="$TMP/repo"; ST="$R/stage_artifacts/paper_recharge"
build() {
  rm -rf "$R"; mkdir -p "$ST" "$R/02_Infrastructure/hooks" "$R/02_Infrastructure/ops"
  touch "$R/$MARKER_REL"
  cp "$SRC" "$R/02_Infrastructure/ops/paper_dispatch_backfill.sh"
  q() { printf '{"date":"%s","optimizer":[{"title":"t"}],"risk":[],"regime":[]}\n' "$1" > "$ST/mode_queue_$1.json"; }
  s() { printf '{"date":"%s","actions":[]}\n' "$1" > "$ST/research_status_$1.json"; }
  q 20260810; s 20260810      # 소비 완료 — 재선정 금지
  q 20260812                  # 창 안 미소비 — 선정
  q 20260815                  # 기준일 이후(미래) — age 음수, 선정
  q 20260601                  # 창 밖(75일) — 기본 미선정 + **명시 보고**
  q 20260701                  # 창 밖(45일)
}
run() { ( cd "$R" && QM_ROOT="$R" CLAUDE_PROJECT_DIR="$R" QVEST_BACKFILL_TODAY=20260815 \
            bash "$R/02_Infrastructure/ops/paper_dispatch_backfill.sh" "$@" ) 2>&1; }

echo "== 논문 dispatch 백로그 선정 계약 =="
build
OUT="$(run --dry-run)"

# T1 양성 대조 — 큐 있고 소비 없는 날은 반드시 선정된다
has   "T1 창 안 미소비 날짜 선정(양성 대조)"        "$OUT" "20260812"
# T2 음성 대조 ★ — 이미 소비한 날은 다시 고르지 않는다 (T1 만으로는 '전부 선정'도 통과)
hasnt "T2 소비 완료 날짜는 미선정(음성 대조)"       "$OUT" "20260810"
# T3 ★무음 절단 금지 — 창 밖이라 뺀 날은 개수와 목록이 찍혀야 한다
has   "T3a 창밖 제외 개수 보고"                     "$OUT" "창밖 제외 2"
has   "T3b 창밖 제외 목록에 20260601 명시"          "$OUT" "20260601"
has   "T3c 창밖 제외 목록에 20260701 명시"          "$OUT" "20260701"
# T4 --all 이면 창 밖도 대상
OUT_ALL="$(run --dry-run --all)"
has   "T4a --all 이 창밖 날짜를 대상에 포함"        "$OUT_ALL" "대상 날짜: 20260601 20260701"
hasnt "T4b --all 에서도 소비 완료일은 여전히 제외"  "$OUT_ALL" "대상 날짜:.*20260810"
# T5 순서 = 오래된 것 먼저 (뒤집히면 최신 결과가 구판에 덮일 여지)
has   "T5 오래된 날짜 우선 정렬"                    "$OUT_ALL" "대상 날짜: 20260601 20260701 20260812 20260815"
# T6 dry-run 은 아무것도 실행/생성하지 않는다 (행동 검사 — 문구가 아니라 결과를 본다)
BEFORE="$(ls "$ST" | sort | md5sum)"
run --dry-run --all >/dev/null
AFTER="$(ls "$ST" | sort | md5sum)"
chk   "T6 dry-run 부작용 없음(디렉터리 불변)"       "$BEFORE" "$AFTER"

# T7 실제 구동 경로: RUNNER 를 갈아끼워 **선정된 날짜마다 1회씩** 호출되는지 확인
build
CNT="$TMP/calls.txt"; : > "$CNT"
( cd "$R" && QM_ROOT="$R" CLAUDE_PROJECT_DIR="$R" QVEST_BACKFILL_TODAY=20260815 \
    QVEST_DISPATCH_RUNNER="printf '%s\n' \"\$QVEST_DISPATCH_TODAY\" >> $CNT" \
    bash "$R/02_Infrastructure/ops/paper_dispatch_backfill.sh" --all ) >/dev/null 2>&1
chk   "T7a 선정 날짜 수만큼 dispatcher 호출"        "4" "$(wc -l < "$CNT" | tr -d ' ')"
chk   "T7b 호출 순서 = 오래된 것 먼저"              "20260601 20260701 20260812 20260815" "$(tr '\n' ' ' < "$CNT" | sed 's/ $//')"

# T8 ★검출력: 소비완료 판정을 없애면 T2 가 뒤집혀야 한다(그 조건이 실제로 일을 하는가).
MUT="$TMP/mut.sh"
sed 's|if \[ -f "\$STAGE/research_status_\${D}.json" \]; then N_DONE=\$((N_DONE + 1)); continue; fi|:|' \
    "$SRC" > "$MUT"
if cmp -s "$SRC" "$MUT"; then
  FAIL=$((FAIL+1)); echo "  FAIL T8 돌연변이 미적용(축이 공허)"
else
  cp "$MUT" "$R/02_Infrastructure/ops/paper_dispatch_backfill.sh"
  OUT_MUT="$(run --dry-run --all)"
  cp "$SRC" "$R/02_Infrastructure/ops/paper_dispatch_backfill.sh"
  has "T8 돌연변이(소비완료 판정 제거) → T2 가 뒤집힘" "$OUT_MUT" "20260810"
fi

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{"test":"paper_dispatch_backfill","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
