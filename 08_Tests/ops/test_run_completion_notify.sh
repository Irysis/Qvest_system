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
  echo "  SKIP  알림기 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0
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
  # claude 호출 줄보다 뒤에 있어야 = 실제로 일한 런만 알린다
  cl=$(grep -n 'timeout 3000' "$OPS/$f" | head -1 | cut -d: -f1)
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

echo "== 양성 대조: 진척 있음 → '끝났습니다' 로 알리는가 =="
if command -v Rscript >/dev/null 2>&1; then
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        qepm_dossier 68 1 CHANGED 0 2>/dev/null)
  echo "$OUT" | grep -q "끝났습니다" && ok "진척 → 완주 문구" || ng "진척 문구" "got=$(echo "$OUT" | head -3)"

  echo "== 위반 주입 1: 마커 0 인데 원장이 바뀌면 진척으로 읽는가 (오경보 방지) =="
  # 16:31 실사고의 재현 — 에이전트가 일은 했는데 MODEQ_DONE 을 안 냈다.
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        qepm_dossier 68 0 CHANGED 0 2>/dev/null)
  if echo "$OUT" | grep -q "끝났습니다" && echo "$OUT" | grep -q "완료 표시는 없었지만"; then
    ok "마커 0 + 원장변화 → 진척 + 사유 명시"
  else ng "자기보고 누락 처리" "자기보고만 보고 무진척으로 읽는다"; fi

  echo "== 위반 주입 2: 진짜 무진척은 그렇게 알리는가 (검출력 유지) =="
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        alpha 7 0 SAME 0 2>/dev/null)
  echo "$OUT" | grep -q "바뀐 것이 없습니다" && ok "무진척 → 확인 필요 문구" \
    || ng "무진척 판정" "아무 일도 없었는데 완주로 알린다"

  echo "== 위반 주입 3: rc x 효과 4갈래를 정확히 가르는가 =="
  # ★2026-08-22 18:13 실사고: 구판은 rc!=0 이면 무조건 "멈췄습니다" + 효과 "미측정" 이었다.
  #   그런데 그 런은 WT-007 에 18개 파일(alpha_scores.parquet · alpha_vector_live.parquet ·
  #   p4_verdict · p5_adversarial)을 남기고 50분 벽에 죽었다. 이 레인의 **지배적** 실패가
  #   timeout 이므로 "중단됐지만 산출 잔존" 칸이 제일 중요한데 구판엔 그 칸이 없었다.
  #   ★"측정 안 함" 과 "효과 없음" 을 같은 자리에 놓으면 다시 돌릴지 판단할 수 없다.
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" method_measure 11 0 SAME 124 2>/dev/null)
  echo "$OUT" | grep -q "남은 산출이 없습니다" && ok "rc=124 + SAME → 중단+무산출" || ng "중단/무산출 문구" "timeout 을 정상 완주로 알린다"
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" method_measure 11 0 CHANGED 124 2>/dev/null)
  echo "$OUT" | grep -q "산출은 남아 있습니다" && ok "rc=124 + CHANGED → 중단+산출잔존" || ng "중단/산출잔존 문구" "타임아웃 런의 산출을 버린 것처럼 알린다"
  echo "$OUT" | grep -q "이어받을 수 있습니다" && ok "이어받기 안내 포함" || ng "이어받기 안내" "다시 돌려도 되는지 알 수 없다"
  echo "== 계약 축: 효과 측정이 rc 분기 밖에 있는가 (러너) =="
  # 측정이 rc==0 분기 안에 갇히면 timeout 런은 영원히 "미측정" 이다 — 18:13 의 기전.
  if grep -q 'if \[ -z "${_EFFECT_CMP:-}" \]' "$OPS/mode_queue_research_run.sh"; then
    ok "mode_queue — rc 무관 효과 측정 존재"
  else
    ng "rc 무관 측정" "효과가 rc==0 분기 안에만 있어 timeout 런은 미측정으로 남는다"
  fi

  echo "== 가독 축: 비전공자 3장치 중 '쉬운 설명' 섹션이 있는가 (원칙 8-②) =="
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        risk 37 1 CHANGED 0 2>/dev/null)
  echo "$OUT" | grep -q "쉬운 설명" && ok "쉬운 설명 섹션 존재" || ng "가독 장치" "코드 라벨만 나간다"

  echo "== 라벨 축: 레인 코드가 평문 이름으로 바뀌는가 =="
  echo "$OUT" | grep -q "위험모델 방법 검토" && ok "risk → 평문 이름" \
    || ng "레인 라벨" "raw 코드가 그대로 나간다"

  echo "== 미등록 레인 대조: 모르는 레인도 죽지 않고 그대로 쓰는가 =="
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        brand_new_lane 3 1 CHANGED 0 2>/dev/null)
  echo "$OUT" | grep -q "brand_new_lane" && ok "미등록 레인 fallback 동작" \
    || ng "미등록 레인" "새 레인을 추가하면 알림이 죽는다"
else
  echo "  SKIP  Rscript 없음 — 배선 축만 검사"
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

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
