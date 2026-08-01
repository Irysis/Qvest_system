#!/usr/bin/env bash
#==============================================================================
# test_ast_verify_dialect.sh — ast_verify 방언 수용 + 빈 순회 차단 위반 주입
#------------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/ast/ast_verify.py
#
# ★왜: WT-D20260802_001 라운드가 ALB-007(CRITICAL)을 적발했다 — 정적검증기가
#   컴파일러 방언(`args`/`type:leaf`/`params`)을 순회하지 못해 **leaf_count=0 으로
#   'PASS' 를 발행**했다. 실행되는 트리에 대한 PIT 검증이 사실상 사망한 상태였고,
#   "위반 0" 과 "검사 0" 이 같은 출력으로 보였다. 단일 실행으로는 판별 불가였고,
#   두 방언을 나란히 돌려 비교했을 때만 드러났다.
#
#   수리 후 같은 패키지: leaf_count 0→4 · op_count 1→12 · PASS(실검증).
#   이 테스트는 그 수리가 되돌아가지 않게 하고, 무엇보다
#   **빈 순회가 다시 PASS 가 되지 않게** 상시 시험한다.
#
# 실행: bash 08_Tests/hooks/test_ast_verify_dialect.sh
#==============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}}"
ROOT="${ROOT//\\//}"
PY="${QVEST_PY:-python}"
VERIFY="$ROOT/02_Infrastructure/ast/ast_verify.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }

[ -f "$VERIFY" ] || { echo "검증기 부재: $VERIFY"; exit 1; }

# 패키지 생성기: 컴파일러 방언(args / type:leaf+class / params) 사용
mkpkg() {
  "$PY" - "$1" "$TMP" <<'PY'
import json, sys, os
variant, tmp = sys.argv[1], sys.argv[2]

def stored(parity=False, avail=None, drop_parity=False):
    c = {"path": "stage_artifacts/t/p.parquet", "value_col": "value",
         "store_build_hash": "deadbeef", "generator_code_path": "gen.py",
         "generated_at": "2026-08-01 00:00:00"}
    if not drop_parity:
        c["production_parity_verified"] = parity
    leaf = {"type": "leaf", "class": "STORED_SCORE", "source": "stored_panel",
            "field": "x", "contract": c}
    if avail:
        leaf["embedded_data_through"] = avail
    return leaf

def lag(child, k=12):
    return {"type": "op", "op": "TS_LAG", "args": [child], "params": {"k": k}}

if variant == "good":
    ast = {"type": "op", "op": "CS_ZSCORE", "args": [lag(stored())]}
elif variant == "empty":                      # 리프 0개 — 빈 순회
    ast = {"type": "op", "op": "CS_ZSCORE", "args": []}
elif variant == "lookahead":                  # 동월 vintage 형상(실사고 2)
    ast = {"type": "op", "op": "CS_ZSCORE", "args": [lag(stored(avail="2026-08-01"))]}
elif variant == "parity_missing":             # 선언 회피
    ast = {"type": "op", "op": "CS_ZSCORE", "args": [lag(stored(drop_parity=True))]}
elif variant == "parity_false":               # 정직한 false
    ast = {"type": "op", "op": "CS_ZSCORE", "args": [lag(stored(parity=False))]}
elif variant == "bad_k":                      # params 에도 최상위에도 k 없음
    n = {"type": "op", "op": "TS_LAG", "args": [stored()]}
    ast = {"type": "op", "op": "CS_ZSCORE", "args": [n]}
else:
    raise SystemExit("unknown variant")

pkg = {"spec_version": "ast_v1.1", "strategy_id": "T_DIALECT",
       "pit": {"sig_date": "2026-07-31", "decision_ts": "2026-07-31"},
       "ast": ast}
p = os.path.join(tmp, variant + ".json")
with open(p, "w", encoding="utf-8") as f:
    json.dump(pkg, f, ensure_ascii=False)
print(p)
PY
}

field() {   # $1=json파일 $2=키
  "$PY" -c "import json,sys;d=json.load(open(sys.argv[1],encoding='utf-8'));v=d.get(sys.argv[2]);print(len(v) if isinstance(v,list) else v)" "$1" "$2"
}

run() { "$PY" "$VERIFY" "$1" --out "$TMP/out.json" >/dev/null 2>&1; }

echo "=== test_ast_verify_dialect (방언 수용 + 빈 순회 차단) ==="
echo "--- A. 양성 대조: 컴파일러 방언 정상 트리 ---"
P=$(mkpkg good); run "$P"
V=$(field "$TMP/out.json" verdict); LC=$(field "$TMP/out.json" leaf_count); OC=$(field "$TMP/out.json" op_count)
case "$V" in PASS|WARN_RESTATEMENT) ok "A1 컴파일러 방언 정상 트리 → 통과($V)";; *) bad "A1 컴파일러 방언 정상 트리 통과" "got $V";; esac
[ "${LC:-0}" -gt 0 ] 2>/dev/null && ok "A2 ★리프를 실제로 셌다 (leaf_count=$LC)" || bad "A2 리프 계수" "leaf_count=$LC — 빈 순회 PASS 재발"
[ "${OC:-0}" -gt 1 ] 2>/dev/null && ok "A3 연산자 순회 (op_count=$OC)" || bad "A3 연산자 순회" "op_count=$OC"
[ "$(field "$TMP/out.json" dialect_args_used)" = "True" ] && ok "A4 args 방언 사용 플래그 노출" || bad "A4 args 방언 플래그" ""

echo "--- B. ★빈 순회는 PASS 가 될 수 없다 (ALB-007 근본 방어) ---"
P=$(mkpkg empty); run "$P"; V=$(field "$TMP/out.json" verdict); LC=$(field "$TMP/out.json" leaf_count)
[ "$V" != "PASS" ] && ok "B1 ★리프 0개 순회 → PASS 아님 (got $V)" || bad "B1 리프 0개 순회 차단" "PASS 발행됨 — 검사 사망이 통과로 위장"
[ "${LC:-1}" -eq 0 ] 2>/dev/null && ok "B2 leaf_count=0 이 결과에 그대로 노출(은폐 없음)" || bad "B2 leaf_count 노출" "got $LC"

echo "--- C. 위반 주입: 실제 look-ahead 를 잡는가 ---"
P=$(mkpkg lookahead); run "$P"; V=$(field "$TMP/out.json" verdict)
[ "$V" = "FAIL_LOOKAHEAD" ] && ok "C1 ★동월 vintage(embedded_data_through > t_d-1) → FAIL_LOOKAHEAD" \
  || bad "C1 look-ahead 검거" "got $V — PIT 정적검증 본체 사망"

echo "--- D. ALB-002: 선언 회피와 정직한 false 를 구분하는가 ---"
P=$(mkpkg parity_missing); run "$P"; V=$(field "$TMP/out.json" verdict)
[ "$V" = "FAIL_CONTRACT" ] && ok "D1 production_parity_verified 키 부재 → FAIL_CONTRACT(선언 회피)" \
  || bad "D1 선언 회피 차단" "got $V"
P=$(mkpkg parity_false); run "$P"; V=$(field "$TMP/out.json" verdict); PU=$(field "$TMP/out.json" parity_unverified)
case "$V" in
  PASS|WARN_RESTATEMENT) ok "D2 ★false 는 정직 선언으로 통과 (신규 비-return 원천 진입 경로 확보, $V)" ;;
  *) bad "D2 정직 false 통과" "got $V — v8.3 주력 lane 이 기계로 막힘" ;;
esac
[ "${PU:-0}" -gt 0 ] 2>/dev/null && ok "D3 미검증 사실을 parity_unverified 로 전달(§7b judge 입력)" \
  || bad "D3 parity 플래그 전달" "got $PU"

echo "--- E. params 방언: 누락은 여전히 잡아야 한다 (오탐 아님을 실증) ---"
P=$(mkpkg bad_k); run "$P"; V=$(field "$TMP/out.json" verdict)
[ "$V" = "FAIL_CONTRACT" ] && ok "E1 k 가 어디에도 없으면 FAIL_CONTRACT (병합이 검사를 죽이지 않음)" \
  || bad "E1 k 결측 검거" "got $V"

echo "--- G. ALB-003: 미등재 리프의 개정위험을 조용히 건너뛰지 않는가 ---"
P=$(mkpkg good); run "$P"
UR=$(field "$TMP/out.json" unmapped_restatement); V=$(field "$TMP/out.json" verdict)
[ "${UR:-0}" -gt 0 ] 2>/dev/null && ok "G1 ★field_map 미등재 STORED_SCORE 를 unmapped_restatement 로 표면화 (=$UR)"   || bad "G1 미등재 리프 표면화" "got $UR — 개정위험 확인 불가가 '위험 없음'으로 통과"
[ "$V" = "WARN_RESTATEMENT" ] && ok "G2 판정이 WARN_RESTATEMENT (통과 + 스펙 플래그 — 과차단 아님)"   || bad "G2 WARN_RESTATEMENT 판정" "got $V"

echo "--- F. 음성 통제 ---"
P=$(mkpkg good); run "$P"; V=$(field "$TMP/out.json" verdict)
case "$V" in PASS|WARN_RESTATEMENT) ok "F1 B~E 주입 후에도 정상 입력은 통과 (검사기 생존)";; *) bad "F1 검사기 생존" "got $V";; esac

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
printf '{"test":"ast_verify_dialect","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
