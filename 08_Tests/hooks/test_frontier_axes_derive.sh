#!/usr/bin/env bash
#==============================================================================
# test_frontier_axes_derive.sh — 주입 훅 프론티어 줄의 CLAUDE.md 정본 파생 검증
#
# 배경 (2026-08-17 폐쇄루프 감사 Rank2):
#   axiom_context_inject.sh 가 프론티어 목록을 07-10 문장으로 하드코딩해 두어,
#   v8.4 재편(2026-08-13) 이후 38일간 매 spawn 마다 도훈이 08-09 에 닫은 lane 을
#   ①순위 레버로 광고했다. 주입문 실측에서 v8.4 키워드 5종 전부 0건.
#
# 이 검사가 지키는 것 (양방향 — 한쪽만 재면 검사 사망과 정상이 겉보기가 같다):
#   [A 정상 파생] 마커가 있으면 CLAUDE.md 의 현행 문구가 주입문에 나타난다.
#   [B 폴백 실효] 마커가 없으면 훅이 죽지 않고 폴백 문구로 떨어진다(회귀 없음).
#   [C 오염 내성] CLAUDE.md 자체가 없어도 훅은 유효 JSON 을 낸다.
#   [D 낙후 검출] 주입문에 v8.4 키워드가 실제로 실린다 = 하드코딩 재발 시 FAIL.
#   [E settled 파생] settled lane 패턴이 정본에서 파생된다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
HOOK="$ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
CM="$ROOT/CLAUDE.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

INPUT='{"tool_input":{"subagent_type":"alpha-research"}}'

# 주입문(additionalContext) 추출 — CRLF 제거(Windows Rscript/bash 혼용 함정 회피)
ctx_of(){
  CLAUDE_PROJECT_DIR="$1" printf '%s' "$INPUT" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null | tr -d '\r' \
    | "$QVEST_PY" -c 'import json,sys
try:
    d=json.loads(sys.stdin.read() or "{}")
    print(d.get("hookSpecificOutput",{}).get("additionalContext","") or "")
except Exception: print("")'
}

echo "== [A/D] 정상 파생 + v8.4 키워드 실적재 =="
CTX=$(ctx_of "$ROOT")
if [ -z "$CTX" ]; then ng "훅이 빈 컨텍스트 반환 (주입 자체 실패)"; else ok "훅 정상 출력 (${#CTX}자)"; fi
case "$CTX" in *"정본 파생"*) ok "프론티어 줄이 CLAUDE.md 파생 경로를 탐" ;;
                *) ng "파생 경로 미발화 — 폴백으로 떨어졌다" ;; esac
for K in 비대칭 분포-표적 일별 수리통계; do
  case "$CTX" in *"$K"*) ok "v8.4 키워드 '$K' 적재" ;;
                  *) ng "v8.4 키워드 '$K' 부재 — 하드코딩 낙후 재발 의심" ;; esac
done
case "$CTX" in *"07-10 실측"*) ng "구 하드코딩 문구('07-10 실측')가 아직 주입됨" ;;
                *) ok "구 하드코딩 문구 소거 확인" ;; esac
# ML 카브아웃: Lane A 를 죽은 ML 로 과일반화하지 않게 하는 줄
case "$CTX" in *"결합기"*|*"평균 예측기"*) ok "ML 카브아웃 적재 (Lane A 과일반화 방지)" ;;
                *) ng "ML 카브아웃 부재 — 분포-표적이 settled ML 로 오독될 위험" ;; esac

echo "== [B] 마커 제거 시 폴백 실효 (위반 주입) =="
# ★temp root 는 반드시 **native Windows 경로**여야 한다.
#   mktemp -d 는 MSYS 형(/tmp/...)을 주는데, 훅 L15-16 주석대로 그 형태를 native python glob 에
#   넘기면 0건 매치 → CACHE_BODY regen 실패 → 훅이 '{}' 로 조기 종료한다.
#   그러면 B/C/E 가 '수리 실패' 처럼 보이지만 실제로는 **검사 하네스 결함**이다(초판이 이 함정에 빠졌다).
TMP="$ROOT/.cache/_test_frontier_axes_root"
rm -rf "$TMP"
mkdir -p "$TMP/qepm/memory/axioms/active" "$TMP/.cache" "$TMP/06_Registry" "$TMP/02_Infrastructure/prompts"
cp -r "$ROOT/qepm/memory/axioms/active/." "$TMP/qepm/memory/axioms/active/" 2>/dev/null
cp "$ROOT/06_Registry/distilled_knowledge.json" "$TMP/06_Registry/" 2>/dev/null
# 마커만 제거한 CLAUDE.md
sed 's/FRONTIER_AXES_START/FRONTIER_AXES_XXXXX/; s/FRONTIER_AXES_END/FRONTIER_AXES_YYYYY/' "$CM" > "$TMP/CLAUDE.md"
CTX_B=$(ctx_of "$TMP")
if [ -z "$CTX_B" ]; then ng "마커 제거 시 훅 사망 (폴백 미작동)"; else ok "마커 제거해도 훅 생존 (${#CTX_B}자)"; fi
case "$CTX_B" in *"폴백"*) ok "폴백 문구 발화" ;;
                  *) ng "폴백 문구 미발화 — 마커 부재가 조용히 통과" ;; esac
case "$CTX_B" in *"정본 파생"*) ng "마커 없는데 파생 경로를 탐 (거짓 성공)" ;;
                  *) ok "마커 없으면 파생 경로 미발화 (음성 대조)" ;; esac

echo "== [C] CLAUDE.md 부재 내성 =="
rm -f "$TMP/CLAUDE.md"
CTX_C=$(ctx_of "$TMP")
if [ -z "$CTX_C" ]; then ng "CLAUDE.md 부재 시 훅 사망"; else ok "CLAUDE.md 부재에도 유효 출력 (${#CTX_C}자)"; fi
case "$CTX_C" in *"고정 축"*) ok "고정 제약 축 블록은 여전히 주입" ;;
                  *) ng "고정 축 블록 소실" ;; esac

echo "== [E] 정본 변경 전파 (박제 아님) =="
# (v9 재조준 2026-08-23) 구판은 정본 **꼬리**의 settled-negative 문장을 치환해 전파를 쟀다.
#   v9 이 프론티어 줄 상한을 330→200자로 낮추면서 그 문장(정본 기준 ~230자 지점)은 주입
#   대상에서 빠진다 — 구판 [E]는 그래서 '박제'가 아니라 '예산'을 재게 됐다.
#   ★수리 전 baseline 도 같은 이유로 이미 FAIL 이었다(330자 상한 < 문장 위치). 즉 이 조정은
#     검사를 통과시키려는 완화가 아니라, 재던 성질을 실제로 잴 수 있는 지점으로 옮기는 것이다.
#   재는 성질(정본을 고치면 주입문이 따라 바뀐다 = 하드코딩 아님)은 그대로.
sed 's/① \*\*비대칭 표적\*\*/① **ZZTESTLANE**/' "$CM" > "$TMP/CLAUDE.md"
CTX_E=$(ctx_of "$TMP")
case "$CTX_E" in *"ZZTESTLANE"*) ok "정본 레버 문구 변경이 주입문에 전파" ;;
                  *) ng "정본 변경이 전파 안 됨 — 어딘가 아직 박제" ;; esac
rm -rf "$TMP"

echo "== [F] 절단이 폐쇄 lane 을 레버로 남기지 않는가 (v9 신설) =="
# 정본 꼬리 = 'DPL·regime-conditional·ML sizing 은 settled-negative — 레버 아님'.
# 200자 상한에 **부정어만** 걸려 잘리면 폐쇄 lane 목록이 '레버 프론티어' 줄에 그대로 남는다
# — v8 이 38일간 저지른 오독(닫힌 lane 을 ①순위 레버로 광고)의 재생산이다. 잘릴 바엔 버린다.
FRONTIER_LINE=$(printf '%s\n' "$CTX" | grep -m1 '조건-안 레버 프론티어' || true)
if [ -z "$FRONTIER_LINE" ]; then
  ng "프론티어 줄 자체를 못 찾음"
elif printf '%s' "$FRONTIER_LINE" | grep -q 'settled-negative'; then
  ok "settled 문장이 부정어까지 온전히 실림"
elif printf '%s' "$FRONTIER_LINE" | grep -qE 'DPL|regime-conditional|uncertainty sizing'; then
  ng "부정어 없이 폐쇄 lane 만 남음 — 레버로 오독된다"
else
  ok "절단 시 폐쇄 lane 목록도 함께 제거 (반쪽 인용 없음)"
fi

echo
printf '== 결과: %d PASS / %d FAIL ==\n' "$PASS" "$FAIL"
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 UNREPORTED(=1 fail)로
#   계상됐다(내부는 전건 통과였다). 계약 결측이지 결함이 아니었음.
echo "{\"test\":\"frontier_axes_derive\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
