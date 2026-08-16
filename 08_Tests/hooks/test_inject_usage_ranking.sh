#!/usr/bin/env bash
# test_inject_usage_ranking — 주입 훅의 DIST 랭킹이 **실사용 빈도**를 따르는지 (2026-08-16 신설)
#
# 배경: 폐쇄루프 감사 실측 — 주입 top-5 중 4건이 인용 0건이고 최다 인용 카드(DIST-QPM-003)는
#       빠져 있었다. 원인 = 정렬 키가 refined_at 최신순이라 실사용과 무관.
#
# ★검사 설계 원칙: "오탐만 없애고 검출력이 죽으면 더 나쁘다" — 양방향으로 짠다.
#   A축(기능): usage 를 조작하면 주입 결과가 **따라 바뀌는가** (안 바뀌면 usage 를 안 읽는 것)
#   B축(폴백): usage 파일이 없으면 **기존 refined_at 동작**으로 돌아가는가 (회귀 방지)
#   C축(무결): 어느 경우에도 유효 JSON 을 내는가
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}"
HOOK="$ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
USAGE="$ROOT/.cache/distilled_usage.json"
PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
BAK=""

note() { printf '  %-58s %s\n' "$1" "$2"; }
ok()   { PASS=$((PASS+1)); note "$1" "OK"; }
bad()  { FAIL=$((FAIL+1)); note "$1" "★FAIL — $2"; }

cleanup() {
  if [ -n "$BAK" ] && [ -f "$BAK" ]; then mv -f "$BAK" "$USAGE"; fi
}
trap cleanup EXIT

fire() {  # $1=설명 → stdout 에 top-1 dist_id
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"alpha-research","prompt":"t"}}' \
    | CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" 2>/dev/null \
    | "$PY" -c "
import json,sys,re
try:
    d=json.load(sys.stdin)
except Exception:
    print('__BADJSON__'); raise SystemExit
ctx=d.get('hookSpecificOutput',{}).get('additionalContext','')
i=ctx.find('Distilled 탐색지도')
if i<0: print('__NOBLOCK__'); raise SystemExit
seg=ctx[i:]
j=seg.find('[부활')
if j>0: seg=seg[:j]
m=re.findall(r'DIST-[A-Z]+-\d+',seg)
print(m[0] if m else '__EMPTY__')
"
}

echo "=== test_inject_usage_ranking ==="

# ── 사전: 실사용 산출물 최신화 ────────────────────────────────────────────────
"$PY" "$ROOT/02_Infrastructure/ops/build_distilled_usage.py" --quiet >/dev/null 2>&1
[ -f "$USAGE" ] && ok "usage 산출물 생성" || bad "usage 산출물 생성" "$USAGE 부재"

# 주입 후보군(필터 통과분) 중 실사용 1위/최하위 id 를 계산 — 하드코딩 금지
export ROOT USAGE
read -r TOP_ID LOW_ID < <("$PY" -c "
import json,io,os
root=os.environ['ROOT']
u=json.load(io.open(os.path.join(root,'.cache','distilled_usage.json'),encoding='utf-8')).get('usage',{})
d=json.load(io.open(os.path.join(root,'06_Registry','distilled_knowledge.json'),encoding='utf-8'))
p=[e for e in d['entries'] if e.get('status')=='distilled'
   and e.get('polarity') in ('negative','conditional')
   and (e.get('statement_refined') or '').strip()]
p.sort(key=lambda e:(int(u.get(e['dist_id'],0)), e.get('refined_at') or ''), reverse=True)
print(p[0]['dist_id'], p[-1]['dist_id'])
")
[ -n "${TOP_ID:-}" ] && ok "후보군 1위/최하위 산출 ($TOP_ID / $LOW_ID)" || bad "후보군 산출" "빈 값"

# ── A축 (기능): 현행 usage 로 1위가 주입되는가 ────────────────────────────────
GOT=$(fire)
[ "$GOT" = "$TOP_ID" ] && ok "A1 실사용 1위가 주입 top-1" \
  || bad "A1 실사용 1위가 주입 top-1" "기대 $TOP_ID 실제 $GOT"

# ── A축 (위반 주입): usage 를 뒤집으면 결과가 따라 바뀌는가 ──────────────────
#   ★안 바뀌면 훅이 usage 를 안 읽는다는 뜻 = 배선 사망. 이 축이 본 검사의 본체다.
BAK="$USAGE.bak_test_$$"
cp -f "$USAGE" "$BAK"
export LOW_ID
"$PY" -c "
import json,io,os
p=os.environ['USAGE']; low=os.environ['LOW_ID']
d=json.load(io.open(p,encoding='utf-8'))
d['usage']={low: 999999}          # 최하위를 압도적 1위로 조작
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))
"
GOT2=$(fire)
[ "$GOT2" = "$LOW_ID" ] && ok "A2 usage 조작 시 주입이 따라 바뀜(위반 주입)" \
  || bad "A2 usage 조작 시 주입이 따라 바뀜" "기대 $LOW_ID 실제 $GOT2 — 훅이 usage 를 안 읽음"

# ── B축 (폴백): usage 파일 제거 시 refined_at 정렬로 회귀하는가 ──────────────
rm -f "$USAGE"
EXP_REFINED=$("$PY" -c "
import json,io,os
d=json.load(io.open(os.path.join(os.environ['ROOT'],'06_Registry','distilled_knowledge.json'),encoding='utf-8'))
p=[e for e in d['entries'] if e.get('status')=='distilled'
   and e.get('polarity') in ('negative','conditional')
   and (e.get('statement_refined') or '').strip()]
p.sort(key=lambda e:e.get('refined_at') or '', reverse=True)
print(p[0]['dist_id'])
")
GOT3=$(fire)
[ "$GOT3" = "$EXP_REFINED" ] && ok "B1 usage 부재 시 refined_at 폴백" \
  || bad "B1 usage 부재 시 refined_at 폴백" "기대 $EXP_REFINED 실제 $GOT3"

# ── C축 (무결): 손상된 usage 에도 유효 JSON ─────────────────────────────────
printf '%s' '{ this is not json' > "$USAGE"
GOT4=$(fire)
case "$GOT4" in
  __BADJSON__) bad "C1 손상 usage 에도 유효 JSON" "훅 출력이 JSON 아님" ;;
  __NOBLOCK__|__EMPTY__) bad "C1 손상 usage 에도 블록 유지" "dist 블록 소실 ($GOT4)" ;;
  *) ok "C1 손상 usage 에도 유효 JSON + 블록 유지 ($GOT4)" ;;
esac

# 복원
mv -f "$BAK" "$USAGE"; BAK=""
"$PY" "$ROOT/02_Infrastructure/ops/build_distilled_usage.py" --quiet >/dev/null 2>&1

echo
echo "=== $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
