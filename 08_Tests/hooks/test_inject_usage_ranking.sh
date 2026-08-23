#!/usr/bin/env bash
# test_inject_usage_ranking — 주입 훅의 **극성**과 예산 검증 (v9 Lean Loop 재작성 2026-08-23)
#
# 이 파일이 원래 재던 것(2026-08-16 신설): DIST negative top-5 의 랭킹이 실사용 빈도를 따르는가.
# v9 재설계로 **그 블록 자체가 주입면에서 빠졌다** — negative 카드 top-5 를 매 spawn 마다
# 싣던 것이 "죽은 방향 재제안 금지" 편향의 본체였기 때문이다(distilled 167 중 negative 71 vs
# positive 11). 랭킹을 재는 검사는 대상이 없어졌으므로, 같은 자리에서 **재설계가 실제로
# 성립했는지**를 잰다. 랭킹 계산(build_distilled_usage.py) 자체는 살아 있고 그 산출물
# `.cache/distilled_usage.json` 도 계속 생성되나, 주입 경로의 소비자는 없다.
#
# 재는 것 (전부 주입문 실측 — 문서 선언이 아니라 훅 출력):
#   [A] 예산: additionalContext ≤ 2,000자 (v9 컨텍스트 예산)
#   [B] 양성: 전략 id(STR_*) 줄이 ≥1 — "무엇이 통했나" 가 실제로 실린다
#   [C] 교훈: L-code(L-XX-…) 줄이 ≥1 — "최근 교훈" 이 실제로 실린다
#   [D] 극성: "재제안 금지 / 재시도 금지" 문구 0건 — 금지 목록으로 되돌아가면 FAIL
#   [E] 무결: 유효 JSON + 고정부(공리·고정 축·dead 포인터) 상시 존재
#   [F] 폴백(위반 주입): .cache/positive_context.json 이 없어도 죽지 않고 고정부만 낸다
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}"
ROOT="${ROOT//\\//}"
HOOK="$ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
PC="$ROOT/.cache/positive_context.json"
PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
BAK=""

note() { printf '  %-58s %s\n' "$1" "$2"; }
ok()   { PASS=$((PASS+1)); note "$1" "OK"; }
bad()  { FAIL=$((FAIL+1)); note "$1" "★FAIL — $2"; }

cleanup() {
  if [ -n "$BAK" ] && [ -f "$BAK" ]; then mv -f "$BAK" "$PC"; fi
}
trap cleanup EXIT

# 훅 1회 발화 → additionalContext 원문(stdout). 실패 시 __BADJSON__.
ctx_of() {
  printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"alpha-research","prompt":"t"}}' \
    | CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" 2>/dev/null \
    | "$PY" -c "
import json,sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    d=json.load(sys.stdin)
except Exception:
    print('__BADJSON__'); raise SystemExit
print(d.get('hookSpecificOutput',{}).get('additionalContext') or d.get('additionalContext') or '')
"
}

echo "=== test_inject_usage_ranking (v9 주입 극성·예산) ==="

# ── 사전: 변동부 산출물 최신화 (생산자 = lcode_harvester) ──────────────────────
#   ★없으면 훅은 고정부만 낸다 = B/C 가 FAIL 한다. 그건 훅 결함이 아니라 생산자 미실행이므로
#     여기서 한 번 돌려 조건을 맞춘 뒤 잰다(생산자 실패 자체도 아래에서 드러난다).
"$PY" "$ROOT/02_Infrastructure/axiom/lcode_harvester.py" >/dev/null 2>&1
[ -f "$PC" ] && ok "positive_context 산출물 존재" || bad "positive_context 산출물" "$PC 부재"

CTX=$(ctx_of)
if [ "$CTX" = "__BADJSON__" ] || [ -z "$CTX" ]; then
  bad "E1 훅이 유효 JSON + 비어있지 않은 컨텍스트" "출력=[$CTX]"
  echo; echo "=== $PASS PASS / $FAIL FAIL ==="
  echo "{\"test\":\"test_inject_usage_ranking\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
  exit 1
fi
ok "E1 훅이 유효 JSON + 비어있지 않은 컨텍스트"

# ── [A] 예산 ≤ 2,000자 ────────────────────────────────────────────────────────
#   ★bash ${#VAR} 는 로케일에 따라 바이트를 세므로 **python 으로 문자 수**를 센다
#     (한글 1자 = UTF-8 3바이트 — 바이트로 재면 초록/빨강이 뒤집힌다).
read -r NCHARS NSTR NLC NBAN <<EOF
$(printf '%s' "$CTX" | "$PY" -c "
import re,sys
c=sys.stdin.buffer.read().decode('utf-8','replace')
lines=c.splitlines()
print(len(c),
      sum(1 for l in lines if re.search(r'STR_[A-Z0-9_]+', l)),
      sum(1 for l in lines if re.search(r'L-[A-Z]+-\d', l)),
      len(re.findall(r'재제안 금지|재시도 금지', c)))
")
EOF

[ "$NCHARS" -le 2000 ] && ok "A1 주입 예산 ≤2000자 (실측 ${NCHARS}자)" \
  || bad "A1 주입 예산 ≤2000자" "실측 ${NCHARS}자 — MAX 초과"

# ── [B] 양성 지식: 전략 id 줄 ≥1 ──────────────────────────────────────────────
[ "${NSTR:-0}" -ge 1 ] && ok "B1 STR_* 전략 줄 ≥1 (실측 ${NSTR}줄)" \
  || bad "B1 STR_* 전략 줄 ≥1" "0줄 — '무엇이 통했나' 가 주입되지 않는다"

# ── [C] 최근 교훈: L-code 줄 ≥1 ───────────────────────────────────────────────
[ "${NLC:-0}" -ge 1 ] && ok "C1 L-code 교훈 줄 ≥1 (실측 ${NLC}줄)" \
  || bad "C1 L-code 교훈 줄 ≥1" "0줄 — 최근 교훈이 주입되지 않는다"

# ── [D] 극성: 금지 어휘 0건 ───────────────────────────────────────────────────
[ "${NBAN:-1}" -eq 0 ] && ok "D1 '재제안/재시도 금지' 문구 0건" \
  || bad "D1 '재제안/재시도 금지' 문구 0건" "${NBAN}건 — 금지 목록 주입으로 회귀"

# ── [E] 고정부 상시 존재 ──────────────────────────────────────────────────────
case "$CTX" in *"AX-000"*) ok "E2 active 공리 적재" ;; *) bad "E2 active 공리 적재" "AX-000 부재" ;; esac
case "$CTX" in *"고정 축"*) ok "E3 고정 제약 축 적재" ;; *) bad "E3 고정 제약 축 적재" "블록 부재" ;; esac
case "$CTX" in *"dead configs"*) ok "E4 dead 포인터 1줄 적재" ;; *) bad "E4 dead 포인터 1줄" "부재" ;; esac
case "$CTX" in *"hypothesis_index.R lookup"*) ok "E5 dead 조회 명령 동봉" ;;
                *) bad "E5 dead 조회 명령 동봉" "lookup 명령 부재 — 개수만 주면 조회 불가" ;; esac

# ── [F] 폴백(위반 주입): 변동부 파일 제거 시 고정부만, 죽지 않음 ──────────────
#   ★이 축이 없으면 "훅이 살아있음" 과 "변동부를 실제로 읽음" 이 구분되지 않는다.
BAK="$PC.bak_test_$$"
cp -f "$PC" "$BAK" 2>/dev/null && rm -f "$PC"
CTX_F=$(ctx_of)
if [ "$CTX_F" = "__BADJSON__" ] || [ -z "$CTX_F" ]; then
  bad "F1 변동부 부재 시 훅 생존" "출력=[$CTX_F]"
else
  ok "F1 변동부 부재 시 훅 생존"
fi
case "$CTX_F" in *"AX-000"*) ok "F2 폴백에도 고정부 유지" ;; *) bad "F2 폴백에도 고정부 유지" "공리 소실" ;; esac
NSTR_F=$(printf '%s' "$CTX_F" | "$PY" -c "
import re,sys
c=sys.stdin.buffer.read().decode('utf-8','replace')
print(sum(1 for l in c.splitlines() if re.search(r'STR_[A-Z0-9_]+', l)))")
[ "${NSTR_F:-1}" -eq 0 ] && ok "F3 변동부 부재 시 전략 줄 소실(=실제로 그 파일을 읽는다)" \
  || bad "F3 변동부 부재 시 전략 줄 소실" "${NSTR_F}줄 잔존 — 어딘가 하드코딩"

# 복원
mv -f "$BAK" "$PC"; BAK=""

echo
echo "=== $PASS PASS / $FAIL FAIL ==="
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
echo "{\"test\":\"test_inject_usage_ranking\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ]
