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

  echo "== 위반 주입 3: rc!=0 은 중단으로 알리는가 =="
  OUT=$(QVEST_RUN_NOTIFY_DRYRUN=1 QM_ROOT="$ROOT" Rscript --no-save "$NOTIFY" \
        method_measure 11 0 SAME 124 2>/dev/null)
  echo "$OUT" | grep -q "중간에 멈췄습니다" && ok "rc=124 → 중단 문구" \
    || ng "실패 문구" "timeout 을 정상 완주로 알린다"

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

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
