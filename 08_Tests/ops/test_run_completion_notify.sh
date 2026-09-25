#!/bin/bash
# test_run_completion_notify.sh — 완주 알림이 **실제로 배선됐는가** (2026-08-22 신설, 도훈 지시)
#
# 왜 있나:
#   도훈 지시는 "완주할 때마다 텔레그램" 이다. 그런데 이 세션에서 이미 두 번,
#   **모듈은 만들고 러너가 안 부르는** 상태를 발견했다(sched_token_fingerprint ·
#   knowledge_index_freshness 는 검출력 17/17 인데 소비자 0). 알림기는 특히 그 함정에
#   빠지기 쉽다 — 안 불려도 아무 에러가 안 나고, "조용하다" 가 "문제 없다" 로 읽힌다.
#
# ★그래서 이 검사의 1급 축은 알림기 내부가 아니라 **호출 배선**이다:
#   ① 세 러너 전부가 부르는가  ② rc 가 최종화된 **뒤**에 부르는가(폴백 성공을 실패로 알리지 않게)
#   ③ 조기 skip 경로에서는 안 부르는가(스팸 방지)  ④ 텔레그램 단일 진입점 규약을 지키는가
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
OPS="$ROOT/02_Infrastructure/ops"
NOTIFY="$OPS/research_run_notify.R"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$NOTIFY" ]; then
  echo "  SKIP  알림기 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; printf '{"test":"run_completion_notify","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"알림기 부재","missing":"%s"}]}\n' "$NOTIFY"; exit 0
fi

RUNNERS="mode_queue_research_run.sh alpha_search_queue_run.sh paper_router_run.sh"

echo "== 배선 축 1: 세 러너가 모두 알림기를 부르는가 (만들고 안 부르는 상태 아님) =="
for f in $RUNNERS; do
  if grep -q 'research_run_notify.R' "$OPS/$f" 2>/dev/null; then ok "$f 가 알림기를 호출"
  else ng "$f 호출" "알림기가 소비자 없이 존재 — 완주가 도훈에게 도달하지 않는다"; fi
done

echo "== 배선 축 2: rc 최종화(폴백 포함) **뒤**에 부르는가 =="
# spend_limit 폴백이 opus 로 재시도해 성공하면 rc 가 0 으로 바뀐다. 알림이 그 앞에 있으면
# 성공한 런을 "멈췄습니다" 로 알린 채로 남는다 — 잘못된 사실이 도달하는 경로.
for f in $RUNNERS; do
  v=$(awk '/if \[ "\$rc" -ne 0 \]; then/{last=NR} /research_run_notify/{nt=NR} END{print (nt>last)?"OK":"NG"}' "$OPS/$f")
  [ "$v" = "OK" ] && ok "$f — rc 확정 후 발송" \
    || ng "$f 발송 시점" "폴백 성공을 실패로 알린다"
done

echo "== 배선 축 3: 조기 skip 경로에서는 부르지 않는가 (스팸 방지) =="
# 라우터는 하루 여러 번 돌고 대개 skip 한다. skip 마다 알림이 가면 '학습된 무시'가 된다.
for f in $RUNNERS; do
  nt=$(grep -n 'research_run_notify' "$OPS/$f" | head -1 | cut -d: -f1)
  # claude 호출 줄보다 뒤에 있어야 = 실제로 일한 런만 알린다 (2026-08-22 시간제한 제거로 앵커가 timeout 3000 -> _run_claude 로 이동)
  #   (2026-09-24 P0-M1: 단일 진입 이관으로 호출이 `_run_claude ""` 가 됐다 — 두 형태 인정)
  cl=$(grep -nE '_run_claude "\$CLAUDE_BIN"|^_run_claude ""' "$OPS/$f" | head -1 | cut -d: -f1)
  if [ -n "$nt" ] && [ -n "$cl" ] && [ "$nt" -gt "$cl" ]; then ok "$f — claude 실행 뒤에만 발송"
  else ng "$f skip 경로" "일하지 않은 런도 알린다(nt=$nt cl=$cl)"; fi
done

echo "== 규약 축: 텔레그램 단일 진입점(tg_agent_brief) 만 쓰는가 =="
if grep -q 'tg_agent_brief(' "$NOTIFY"; then ok "tg_agent_brief() 경유"
else ng "진입점" "SOT 규약 위반"; fi
if grep -Eq '(^|[^_a-zA-Z])tg_send[a-z_]*\(' "$NOTIFY"; then
  ng "직접 발송 우회" "tg_send* 직접 호출 — 약어 풀이·비전공자 3장치를 건너뛴다"
else ok "tg_send* 직접 호출 없음"
fi

echo "== ★인사이트 축: L-code 를 실제로 나르는가 (v2 핵심) =="
# ★도훈 지적(2026-08-22): "리서치에서 얻을 수 있는 인사이트는 없고, 그저 완료했다는 얘기만
#   장황하게 온다." v1 은 런 상태만 날랐다 — 완주 사실은 그 자체로 정보가 아니다.
#   v2 는 L-code 의 lesson_text·mechanism_hypothesis·falsification_attempts 를 나른다.
if command -v Rscript >/dev/null 2>&1; then
  _FIX=$(mktemp -d)
  mkdir -p "$_FIX/stage_artifacts/l_code/alpha_research"
  cat > "$_FIX/stage_artifacts/l_code/alpha_research/l_code_TEST_probe.json" <<'JEOF'
{"l_code":"L-TEST-0001","strategy_id":"WT-TEST","family":"methodology_power",
 "grade":"C","research_mode":"alpha_research","metric_type":"estimated",
 "lesson_text":"순열 기반 최소검출효과는 추정기 자체의 추정오차 분산을 누락한다. 실측 사전 0.00290 대 실현 0.02998 로 10.3배 과소.",
 "mechanism_hypothesis":"순열 귀무분포는 라벨 교환 하의 통계량 분포이지 추정기 분산을 포함한 효과크기 분포가 아니다.",
 "falsification_attempts":"실현 값을 실측 재표집으로 재산출해 사전값과 직접 대조했다."}
JEOF
  _T2=$(mktemp)
  QVEST_RUN_NOTIFY_DRYRUN=1 QVEST_NOTIFY_ROOT="$_FIX" Rscript --no-save "$NOTIFY" alpha 5 1 CHANGED 0 "" 0 > "$_T2" 2>&1
  grep -q "배운 것" "$_T2" && ok "L-code lesson 이 본문에 실린다" \
    || ng "인사이트 부재" "완주 사실만 나른다 — v1 회귀: $(tail -2 "$_T2" | tr '\n' ' ')"
  grep -q "추정오차 분산을 누락" "$_T2" && ok "lesson 원문이 실제로 전달된다" \
    || ng "lesson 유실" "제목만 있고 내용이 없다"
  grep -q "기전" "$_T2" && ok "기전(mechanism)이 별도 섹션으로" || ng "기전 누락" "왜 그런지가 빠진다"
  grep -q "반증 시도" "$_T2" && ok "반증 시도가 전달된다" || ng "반증 누락" "어떻게 확인했나가 빠진다"
  grep -q "런 상태" "$_T2" && ok "런 상태는 꼬리 블록으로 접힘" || ng "런 상태" "위치 계약 위반"
  # 헤더가 발견이어야 한다 — 완주 문구가 헤더면 v1 회귀
  grep -qE "^.{0,4}<b>Q-Lead" "$_T2" && ok "제목 렌더" || true
  grep -q "한 건이 끝났습니다" "$_T2" && ng "v1 회귀" "헤더가 여전히 완주 문구다" \
    || ok "헤더가 완주 문구가 아님"
  rm -rf "$_FIX" "$_T2"

  echo "== ★포장 금지 축: 산출이 없으면 없다고 말하는가 =="
  _FIX2=$(mktemp -d); mkdir -p "$_FIX2/stage_artifacts/l_code"
  _T3=$(mktemp)
  QVEST_RUN_NOTIFY_DRYRUN=1 QVEST_NOTIFY_ROOT="$_FIX2" Rscript --no-save "$NOTIFY" alpha 5 0 SAME 0 "" 0 > "$_T3" 2>&1
  grep -q "적립 없음" "$_T3" && ok "L-code 0건 → '적립 없음' 명시" \
    || ng "포장" "산출 없는 런을 성과처럼 알린다"
  grep -q "적립된 지식 없음" "$_T3" && ok "헤더도 없음을 말한다" || ng "헤더 포장" "$(grep -m1 gsub "$_T3")"
  rm -rf "$_FIX2" "$_T3"

  echo "== 중단 축: rc!=0 을 구분하는가 =="
  _FIX3=$(mktemp -d); mkdir -p "$_FIX3/stage_artifacts/l_code"
  _T4=$(mktemp)
  QVEST_RUN_NOTIFY_DRYRUN=1 QVEST_NOTIFY_ROOT="$_FIX3" Rscript --no-save "$NOTIFY" alpha 5 0 CHANGED 124 "" 0 > "$_T4" 2>&1
  grep -q "중단 —" "$_T4" && ok "rc=124 → 중단 표기" || ng "중단 표기" "timeout 을 정상으로 알린다"
  grep -q "중단 시점까지의 산출은 보존됨" "$_T4" && ok "중단+진척 → 산출 잔존 명시" || ng "잔존 표기" "다시 돌릴지 판단 불가"
  rm -rf "$_FIX3" "$_T4"
  echo "== 미등록 레인 대조: 모르는 레인도 죽지 않고 그대로 쓰는가 =="
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        brand_new_lane 3 1 CHANGED 0 2>/dev/null)
  echo "$OUT" | grep -q "brand_new_lane" && ok "미등록 레인 fallback 동작" \
    || ng "미등록 레인" "새 레인을 추가하면 알림이 죽는다"
fi


echo "== 실행 축: 알림 블록이 러너와 같은 셸 옵션에서 **완주**하는가 =="
# ★존재·위치 검사만으로는 부족하다 — 러너는 `set -uo pipefail` 로 돌고,
#   미설정 변수 하나면 런이 할 일을 다 한 **뒤** 마지막 줄에서 죽는다.
#   그 죽음은 알림 실패로 보이지 않고 **러너 실패**로 보여 오진을 부른다.
EXTRACT="$ROOT/08_Tests/ops/lib/_extract_notify_block.py"
for f in $RUNNERS; do
  if [ ! -f "$EXTRACT" ]; then ng "$f 블록 추출" "추출기 부재"; continue; fi
  blk=$("${QVEST_PY:-python}" "$EXTRACT" "$ROOT/02_Infrastructure/ops/$f" 2>/dev/null)
  if [ -z "$blk" ]; then ng "$f 블록 추출" "알림 블록을 못 찾음"; continue; fi
  out=$(bash -c "set -uo pipefail
BASE='$ROOT'; LOG=/dev/null; rc=0; N=7; _n_done=1; _EFFECT_CMP=CHANGED
_EFFECT_BEFORE=''; _EFFECT_SIG='$ROOT/02_Infrastructure/ops/research_effect_signature.py'
_ROUTE_DIR='$ROOT/stage_artifacts/paper_recharge'; _ROUTE_BEFORE=0
BACKLOG_DATES=''; QVEST_MODE_QUEUE_LANE=alpha; PYBIN='${QVEST_PY:-python}'
log(){ :; }; export QVEST_RUN_NOTIFY_DRYRUN=1
$blk
echo __BLOCK_OK__" 2>&1)
  if echo "$out" | grep -q "__BLOCK_OK__"; then ok "$f — 알림 블록이 set -u 아래 완주"
  else ng "$f 블록 실행" "미설정 변수 등으로 중단: $(echo "$out" | tail -1)"; fi
done

echo "== 발화 축: 블록 완주 != 알림 발화 (|| log 가 실패를 삼킨다) =="
# 비치명 처리는 옳지만, 그 때문에 알림기가 죽어도 러너는 초록이다.
# 러너가 실제로 넘기는 인자 패턴으로 알림기가 끝까지 도는지 따로 확인한다.
if command -v Rscript >/dev/null 2>&1; then
  _T=$(mktemp)
  QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" alpha_search 7 1 CHANGED 0 > "$_T" 2>&1
  if grep -q "notify. lane=alpha_search" "$_T"; then ok "러너 인자 패턴으로 알림기 발화"
  else ng "발화" "블록은 완주해도 알림기가 안 돈다: $(tail -1 "$_T")"; fi
  rm -f "$_T"
fi

echo "== 귀속 축: 런이 무엇을 겨눴는지 로그에 남는가 =="
# ★2026-08-22 18:13 실사고: 런은 WT-D20260822_005 를 SPEC_APPROVED → ALPHA_DONE 으로
#   올리고 alpha_package(15KB)·certificate·validation 까지 냈다(성공). 그런데 로그에
#   WT id 가 한 줄도 없어서, 같은 시각 **병렬 세션**이 만지던 WT-007 의 산출을 이 런의
#   것으로 오귀속했고 텔레그램으로 틀린 사실이 나갔다.
#   ★기전: 원장 지문은 **전역**이다 — 저장소에 동시 세션이 있으면 남의 진척도 CHANGED 다.
#   08-16 연속성 마커 사고("남의 mtime 이 내 턴의 계약을 충족")와 같은 계통.
#   전역 지문은 "무언가 바뀌었다" 는 답해도 "내가 바꿨다" 는 답하지 못한다.
#   ⇒ 디스패치 **전에** 대상을 남긴다. 귀속은 사후에 복원되지 않는다.
MQ="$OPS/mode_queue_research_run.sh"
if grep -q "_queue_top_ids.py" "$MQ" && grep -q "디스패치 후보" "$MQ"; then
  ok "mode_queue — 디스패치 대상 기록 존재"
else
  ng "디스패치 기록" "런이 무엇을 겨눴는지 남지 않아 성공/실패를 남의 산출로 오귀속한다"
fi
HELP="$OPS/_queue_top_ids.py"
if [ -f "$HELP" ] && command -v "${QVEST_PY:-python}" >/dev/null 2>&1; then
  _TQ=$(mktemp)
  printf '{"items":[{"wt_id":"WT-A"},{"wt_id":"WT-B"},{"id":"X-1"},{"wt_id":"WT-D"}]}' > "$_TQ"
  got=$("${QVEST_PY:-python}" "$HELP" "$_TQ" 3 2>/dev/null)
  [ "$got" = "WT-A,WT-B,X-1" ] && ok "상위 N 추출 정확 (wt_id 우선, id 폴백)" || ng "추출" "got=$got"
  printf 'not json' > "$_TQ"
  got=$("${QVEST_PY:-python}" "$HELP" "$_TQ" 3 2>/dev/null)
  [ "$got" = "?" ] && ok "손상 큐 → ? (조용히 빈 문자열로 접지 않음)" || ng "손상 큐" "got=$got"
  rm -f "$_TQ"
fi

echo "== 시간제한 축: 기본이 무제한이고 env 로만 켜지는가 (도훈 지시 2026-08-22) =="
# ★근거: 18:13 실측에서 상한이 자른 것은 폭주가 아니라 **끝난 일의 뒷정리**였다.
#   런은 18:10 에 WT-005 를 ALPHA_DONE 으로 올리고 alpha_package(15KB)까지 냈는데
#   18:13 에 죽어 MODEQ_DONE 자기보고와 원장 append 를 잃었다.
#   되돌리기는 코드 수정이 아니라 QVEST_RUN_TIMEOUT 환경변수여야 한다.
for f in $RUNNERS factor_deep_recheck_run.sh; do
  [ -f "$OPS/$f" ] || continue
  if grep -q 'timeout 3000 "\$CLAUDE_BIN"' "$OPS/$f"; then
    ng "$f 시간제한" "하드코딩 timeout 3000 잔존 — 끝난 일의 뒷정리를 계속 자른다"
  else ok "$f — 하드코딩 상한 없음"; fi
  if grep -q "QVEST_RUN_TIMEOUT" "$OPS/$f"; then ok "$f — env 로 상한 복원 가능"
  else ng "$f 상한 복원" "필요할 때 켤 수단이 없다(코드 수정만 남는다)"; fi
done
# 실동작: 기본은 제한 없이, 값을 주면 상한이 걸린다.
#   ★2026-09-24(P0-M1): _run_claude 가 rf_llm_env.sh::rf_llm_agent_run 단일 진입을 거친다 — 상한은
#   "${QVEST_RUN_TIMEOUT:-0}" 로 넘어가고(timeout 0 = GNU 규약상 무제한) 실행 파일은 CLAUDE_BIN 이다.
#   그래서 가짜 claude(CLAUDE_BIN)로 실제 함수 본문을 태운다 — 가짜는 FAKE_SLEEP 초 뒤 RAN 을 낸다.
_RC_D=$(mktemp -d)
cat > "$_RC_D/fake_claude" <<'FAKE'
#!/usr/bin/env bash
cat > /dev/null
sleep "${FAKE_SLEEP:-0}"
echo RAN
FAKE
chmod +x "$_RC_D/fake_claude"
{ printf '. "%s"\n' "$OPS/rf_llm_env.sh"
  sed -n "/^_run_claude(){/,/^}/p" "$OPS/mode_queue_research_run.sh"
  printf 'CLAUDE_BIN="%s"; LOG="%s"; PROMPT_TEXT=hi; LLM_MODEL=opus; LLM_EFFORT=max; LLM_FALLBACK_MODEL=""\n' "$_RC_D/fake_claude" "$_RC_D/log"
  printf '_run_claude ""; echo "rc=$?"; cat "$LOG"\n'
} > "$_RC_D/h.sh"
out=$(bash "$_RC_D/h.sh" 2>&1); case "$out" in *rc=0*RAN*) ok "기본 = 제한 없이 실행" ;; *) ng "기본 동작" "got=$out" ;; esac
out=$(FAKE_SLEEP=2 bash "$_RC_D/h.sh" 2>&1); case "$out" in *rc=0*RAN*) ok "기본(무제한) = 2초 걸리는 런도 끝까지(timeout 0)" ;; *) ng "기본 무제한" "got=$out" ;; esac
out=$(QVEST_RUN_TIMEOUT=5 bash "$_RC_D/h.sh" 2>&1); case "$out" in *rc=0*RAN*) ok "env 지정 시에도 정상 실행" ;; *) ng "env 경로" "got=$out" ;; esac
out=$(QVEST_RUN_TIMEOUT=1 FAKE_SLEEP=4 bash "$_RC_D/h.sh" 2>&1)
echo "$out" | grep -q "rc=124" && ok "env 지정 시 실제로 상한이 걸린다(위반 주입)" || ng "상한 실효" "got=$out"
rm -rf "$_RC_D"

echo "== 창 축: 런 시작 시각을 알림기에 넘기는가 (남의 산출 귀속 방지) =="
# v2 알림기는 since 로 인사이트 수집 창을 자른다. 러너가 안 넘기면 기본 4시간 창이 쓰여
#   런이 30분이어도 직전 3.5시간의 남의 산출까지 자기 것으로 보고한다.
#   오늘 여섯 번 겪은 "범위를 안 정하고 센다" 의 알림 판본 — 배선 당일 실제로 빠져 있었다.
for f in $RUNNERS; do
  p="$OPS/$f"
  a=$(grep -n "_NOTIFY_SINCE=" "$p" | head -1 | cut -d: -f1)
  # 함수 **정의**(_run_claude(){ ) 가 아니라 **호출**을 잡는다 — 정의가 앞서므로
  #   그대로 쓰면 순서 판정이 뒤집힌다(도입 당일 실제로 오탐).
  b=$(grep -nE '_run_claude .*-p |^_run_claude ""' "$p" | head -1 | cut -d: -f1)
  c=$(grep -n "research_run_notify" "$p" | head -1 | cut -d: -f1)
  if [ -z "$a" ]; then
    ng "$f 창 미전달" "since 미기록 — 기본 4시간 창이 남의 산출을 삼킨다"
    continue
  fi
  if grep -q "_NOTIFY_SINCE:-" "$p"; then ok "$f — since 를 알림기에 전달"
  else ng "$f 인자 누락" "기록만 하고 안 넘긴다"; fi
  if [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]; then
    ok "$f — 기록 < claude < 알림 순서"
  else
    ng "$f 순서" "claude 뒤에 찍으면 그 런의 산출이 창 밖으로 나간다 (a=$a b=$b c=$c)"
  fi
done

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"run_completion_notify","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
