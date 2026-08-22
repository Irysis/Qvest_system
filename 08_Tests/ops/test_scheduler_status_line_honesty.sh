#!/bin/bash
# test_scheduler_status_line_honesty.sh — 부팅 상태라인이 **모름을 안다로 바꾸지 않는가** (2026-08-22)
#
# 왜 있나 (실사고 2026-08-22, 26일 은폐):
#   `SchedAlerts: 미해소 18건 (전부 자동복구 대상) · 최고령 25d`
#   실제 분류는 scheduled_task_unhealthy(14건)=unknown · exit_1=unknown ·
#   lock_owner_unknown=unknown · timeout_kill=partial — **yes 는 0건**이었다.
#   그 14건의 정체가 Qvest_MorningReboot PT3H 벽 + Qvest_AuditWatch 실패였고,
#   26일간 이 한 줄 뒤에 숨어 있었다.
#
# ★기전: 분류기는 옳았다(yes/no/partial/unknown 정확히 구분, 주석까지 "partial 을 yes 로
#   뭉개면 학습된 무시" 라고 경고). 틀린 건 **소비자 한 줄**이다. 상세 모드는 제대로
#   표시하는데 요약만 무너졌고, **사람은 요약만 본다.**
#   ⇒ 이 검사의 1급 축은 "분류가 맞는가" 가 아니라 **"요약이 분류를 접지 않는가"** 다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$ROOT/02_Infrastructure/ops/scheduler_alert_status.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP  상태 스크립트 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0
fi

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
ADIR="$FIX/.cache/scheduler_alerts"; mkdir -p "$ADIR"

mk(){ # mk <파일명> <component> <reason>
  printf 'ts=2026-08-22T00:00:00+09:00\ncomponent=%s\nreason=%s\ndetail=fixture\n' "$2" "$3" > "$ADIR/$1.alert"
}
run(){ QVEST_ALERT_DIR="$ADIR" bash "$SCRIPT" --status-line 2>/dev/null; }

# 스크립트가 디렉터리를 어떻게 잡는지 확인 — env 미지원이면 cwd 기반으로 실행
probe(){ (cd "$FIX" && CLAUDE_PROJECT_DIR="$FIX" QM_ROOT="$FIX" bash "$SCRIPT" --status-line 2>/dev/null); }
OUT="$(probe)"
if ! echo "$OUT" | grep -q "SchedAlerts"; then
  echo "  SKIP  픽스처 경로 주입 불가 (스크립트가 고정 경로 사용) — 실 저장소 축만 검사"
  echo "== 실 저장소 축: 'yes 아닌 것' 을 '자동복구' 로 적지 않는가 =="
  REAL="$(bash "$SCRIPT" --status-line 2>/dev/null)"
  # 실제 분류를 독립 산출해 대조한다
  source "$ROOT/02_Infrastructure/ops/_sched_failure_classify.sh" 2>/dev/null
  ny=0; nn=0
  for f in "$ROOT"/.cache/scheduler_alerts/*.alert; do
    [ -f "$f" ] || continue
    r=$(grep -m1 '^reason=' "$f" | cut -d= -f2-)
    a=$(sched_failure_autorecovers "$r" 2>/dev/null || echo unknown)
    [ "$a" = "yes" ] && ny=$((ny+1)) || nn=$((nn+1))
  done
  echo "  실측: yes=$ny · yes아님=$nn"
  if [ "$nn" -gt 0 ] && echo "$REAL" | grep -q "전부 자동복구 대상"; then
    ng "요약이 분류를 접음" "yes 아닌 것이 ${nn}건인데 '전부 자동복구 대상' 이라 적는다"
  else
    ok "yes 아닌 건이 있으면 '전부 자동복구' 라 적지 않는다"
  fi
  if [ "$nn" -gt 0 ]; then
    echo "$REAL" | grep -qE "판정불가|사람 조치|부분복구" \
      && ok "yes 아닌 분류가 요약에 이름으로 노출된다" \
      || ng "노출" "분류가 요약에서 사라진다: $REAL"
  fi
  echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi

echo "== 위반 주입 1: unknown 만 있을 때 '전부 자동복구' 라 하지 않는가 (실사고 재현) =="
rm -f "$ADIR"/*.alert; mk a task_health scheduled_task_unhealthy
OUT="$(probe)"
echo "$OUT" | grep -q "전부 자동복구 대상" \
  && ng "unknown 접힘" "모름을 자동복구로 바꾼다 — 26일 은폐의 기전" \
  || ok "unknown → '전부 자동복구' 아님"
echo "$OUT" | grep -q "판정불가" && ok "unknown 이 '판정불가' 로 명시된다" \
  || ng "unknown 표기" "got=$OUT"

echo "== 위반 주입 2: partial 을 자동복구로 뭉개지 않는가 =="
rm -f "$ADIR"/*.alert; mk b mode_queue timeout_kill
OUT="$(probe)"
echo "$OUT" | grep -q "전부 자동복구 대상" \
  && ng "partial 접힘" "원장·텔레그램 유실 가능한 실패를 완전복구로 표시" \
  || ok "partial → '전부 자동복구' 아님"
echo "$OUT" | grep -q "부분복구" && ok "partial 이 '부분복구' 로 명시된다" || ng "partial 표기" "got=$OUT"

echo "== 양성 대조: 정말 전부 yes 면 '전부 자동복구' 라 해도 된다 (과잉 수리 방지) =="
rm -f "$ADIR"/*.alert; mk c alpha_queue spend_limit; mk d router rate_limit
OUT="$(probe)"
echo "$OUT" | grep -q "전부 자동복구 대상" && ok "전부 yes → '전부 자동복구' 유지" \
  || ng "양성 대조" "자동복구 건까지 경고로 바꾸면 그것도 학습된 무시다: $OUT"

echo "== 축 보존: 사람 조치(no) 는 여전히 최우선 표기되는가 =="
rm -f "$ADIR"/*.alert; mk e router auth_expired; mk f alpha_queue spend_limit
OUT="$(probe)"
echo "$OUT" | grep -q "사람 조치" && ok "no → 사람 조치 표기 유지" || ng "no 축" "got=$OUT"

echo "== 혼합: 네 분류가 섞이면 넷 다 보이는가 =="
rm -f "$ADIR"/*.alert
mk g router auth_expired; mk h alpha_queue spend_limit; mk i mode_queue timeout_kill; mk j task_health scheduled_task_unhealthy
OUT="$(probe)"
n=0
for w in "사람 조치" "자동복구" "부분복구" "판정불가"; do echo "$OUT" | grep -q "$w" && n=$((n+1)); done
[ "$n" -eq 4 ] && ok "혼합 시 4분류 전부 노출" || ng "혼합 표기" "노출 $n/4 — got=$OUT"

echo "== 계약: 분류기를 재구현하지 않고 정본에 위임하는가 =="
if grep -q "sched_failure_autorecovers" "$SCRIPT"; then
  ok "분류는 정본(_sched_failure_classify.sh)에 위임"
else
  ng "분류 복제" "소비자가 자기 판정표를 갖는다 — 정본과 갈릴 자리"
fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
