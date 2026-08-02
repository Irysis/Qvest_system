#!/usr/bin/env bash
# test_deployed_holdings_check.sh — 배포 홀딩 제약 검사기 위반 주입 테스트
#
# 대상: 02_Infrastructure/validation/deployed_holdings_check.py
#
# 왜: 이 검사기는 월간 리밸 Gate C 직후에 도는 마지막 방어선이다. 검사기가 죽으면
#     "전부 OK" 와 "아무것도 안 잼" 이 겉보기에 같다 — 2026-08-01 실측으로 확인된 계통
#     (파일 존재/mtime/프로세스명 검사가 각각 형식·신호일·인자를 재지 못했다).
#     그래서 양성 대조만이 아니라 **일부러 틀린 입력을 넣어 발화하는지**를 고정한다.
#
# 픽스처는 tempdir 에만 만든다 — 05_Production 실산출을 건드리지 않는다.
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
_QM_ENV="${QM_ROOT:-}"          # export 로 덮기 전의 원본 (인터프리터 후보로 재사용)
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"

# PROJ 해석 — ★앵커 1순위 = BASH_SOURCE, env 아님. 테스트는 **자기가 실린 트리**를 검사한다
#   (test_resolve_project_marker.sh 와 동일 규약). 구판은 CLAUDE_PROJECT_DIR→QM_ROOT 를
#   먼저 봐서, worktree 에서 돌려도 QM_ROOT 가 가리키는 main 의 구판을 검사할 수 있었다.
_pick_proj() {
  local c
  for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "$_QM_ENV" "$PWD"; do
    if [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ]; then (cd "${c//\\//}" && pwd); return 0; fi
  done
  return 1
}
if ! PROJ="$(_pick_proj)"; then
  echo "❌ PROJECT_ROOT 해석 실패 — 표지 '$MARKER_REL' 를 가진 후보 없음" >&2
  echo '{"test":"deployed_holdings_check","pass":0,"fail":1,"total":1,"preflight":"no_root"}'
  exit 1
fi
export QM_ROOT="$PROJ"

# 주입구(DHC_FORCE_*)는 **자기검사(T14~T16) 중에만** 유효하다 — env 에 남아 있던 값이
# 조용히 다른 검사기/인터프리터를 가리키는 사고를 막는다.
if [ "${DHC_SELFTEST:-}" != "1" ]; then unset DHC_FORCE_CHK DHC_FORCE_PY; fi
CHK="${DHC_FORCE_CHK:-$PROJ/02_Infrastructure/validation/deployed_holdings_check.py}"

# ── 인터프리터 해석 (2026-08-02 수리) ─────────────────────────────────────────
# 원 결함: PY 후보가 `$PROJ/.venv_qvest_ml` 하나뿐이고 부재 시 bare python3/python 으로
#   낙하했다. worktree 에는 venv junction 이 없고(bootstrap.sh §4h-2 가 부팅 때 만든다 —
#   미부팅 세션엔 부재) bare `python3` 는 **Windows Store 스텁**으로 해석돼 stdout 에
#   "Python " 한 줄만 찍고 rc=49 로 즉시 죽는다. 그래서 14 케이스가 전부 exit 49 가 됐고,
#   배터리에는 "검사기가 위반을 하나도 못 잡음"으로 보였다 — 실제로는 **검사기가 한 번도
#   실행되지 않았다**. ("미실행"과 "검거 실패"가 같은 출력이 되는 계통.)
# ★더 위험한 변종: pandas 가 없는 인터프리터(시스템 Python312 = $QVEST_PY 가 그렇다)는
#   ModuleNotFoundError 로 **rc=1** 을 낸다. rc=1 은 T1~T10 의 기대값이라, 완전히 죽은
#   검사기가 **10/14 초록**을 만든다. uniform 49 보다 오히려 발견이 어렵다.
#   → 실행 가능(-x)만으로는 부족하고, **기능 프로브(pandas·pyarrow import)** 를 통과한
#     후보만 채택한다. bare python3/python 은 후보 목록에서 영구 제외한다.
# 후보 순서는 훅 29종의 규약과 같다: env → 자기 트리 venv → main 트리 venv(절대경로).
_py_works() { [ -n "${1:-}" ] && [ -x "$1" ] && "$1" -c 'import pandas,pyarrow' >/dev/null 2>&1; }
PY=""
if [ -n "${DHC_FORCE_PY:-}" ]; then _PY_CANDS=("${DHC_FORCE_PY}")   # 자기검사 주입구(T14/T15)
else _PY_CANDS=("${QVEST_PY_BIN:-}" "${QVEST_PY:-}" \
                "$PROJ/.venv_qvest_ml/Scripts/python.exe" \
                "$_QM_ENV/.venv_qvest_ml/Scripts/python.exe" \
                "/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"); fi
for _c in "${_PY_CANDS[@]}"; do
  _c="${_c//\\//}"
  if _py_works "$_c"; then PY="$_c"; break; fi
done

# ── 사전 점검: 계측이 살아 있음을 케이스 실행 *전에* 확정한다 ─────────────────
# 아래가 깨진 채 케이스를 돌리면 14건 전부가 거짓 판정이다. 그래서 케이스 결과를
# 아예 발행하지 않고 총계 1건 실패로 끊는다 — 0/14 는 반드시 "검거 실패"로 오독된다.
preflight_fail() {
  echo "❌ 사전 점검 실패 — $1" >&2
  echo "   케이스는 실행하지 않는다(죽은 계측의 0/14 는 '검거 실패'로 읽힌다)." >&2
  echo "{\"test\":\"deployed_holdings_check\",\"pass\":0,\"fail\":1,\"total\":1,\"preflight\":\"$2\"}"
  exit 1
}
[ -n "$PY" ] || preflight_fail \
  "pandas/pyarrow 를 갖춘 python 부재 (후보: ${_PY_CANDS[*]}) — bare python3=Store 스텁(rc49)은 후보 제외" "no_python"
[ -f "$CHK" ] || preflight_fail "검사기 파일 부재: $CHK" "no_checker"
# 카나리아 — `--help` 는 모듈 최상단 import(pandas) 를 지나 argparse 까지 도달해야 rc=0.
#   Store 스텁 rc=49 / import 실패 rc=1 / 스크립트 부재 rc=2 와 전부 구분된다.
_cout="$("$PY" "$CHK" --help 2>&1)"; _crc=$?
if [ "$_crc" -ne 0 ] || ! printf '%s' "$_cout" | grep -q -- "--skip-liquidity"; then
  preflight_fail "카나리아 rc=$_crc — 검사기가 실행 단계에서 죽음: $(printf '%s' "$_cout" | head -3 | tr '\n' ' ')" "canary"
fi

PASS=0; FAIL=0
chk(){ local n="$1" exp="$2" got="$3"
  if [ "$exp" = "$got" ]; then PASS=$((PASS+1)); echo "  ok   $n"
  else FAIL=$((FAIL+1)); echo "  FAIL $n (기대=$exp 실제=$got)"; fi; }

TD="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/dhc_$$")"; mkdir -p "$TD"
cleanup(){ rm -rf "$TD"; }
trap cleanup EXIT   # ★함수 프레임 아님(스크립트 최상위) — bash trap 은 발화한다(R on.exit 금칙과 무관)

# ── 픽스처: 규약을 만족하는 base 홀딩/매니페스트 + 전월본 ────────────────────
"$PY" - "$TD" <<'PYEOF'
import json, sys, csv, os
TD = sys.argv[1]
def write(name, rows):
    with open(os.path.join(TD, name), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["rank","Ticker","Name","Sector","Weight"])
        for i, (t, wt) in enumerate(rows): w.writerow([i, t, f"N{t}", "테스트", wt])
# invested 0.30 = gate 1.00 x beta 0.30 · 주식 10종(각 0.03) · CASH 0.70
cur = [("CASH", 0.70)] + [(f"A{i:06d}", 0.03) for i in range(1, 11)]
write("cur.csv", cur)
# 전월: 다른 비중(지문이 달라야 정상)
prev = [("CASH", 0.70)] + [(f"A{i:06d}", 0.03 if i != 1 else 0.029) for i in range(1, 11)]
prev[1] = ("A000001", 0.029); prev.append(("A000011", 0.001))
write("prev.csv", prev)
man = {
  "strategy": "TEST", "as_of": "2026-08-01",
  "overlays": {"m4_scalar": 1.0, "ae_fire_seq": 1, "m4_ae_gate": 1.0,
               "beta_R05_V5": {"value": 0.30, "regime": "CRISIS", "R05_z_avg": -0.35}},
  "invested": 0.30, "cash_pct": 0.70, "n_equity": 10,
  "pit": {"no_future_reference": True, "ae_last_feat": "2026-06-30", "ae_pit_ok": True},
}
json.dump(man, open(os.path.join(TD, "man.json"), "w", encoding="utf-8"), ensure_ascii=False)
PYEOF

run(){ "$PY" "$CHK" --as-of "${AS_OF:-2026-08-01}" --holdings "$1" --manifest "$2" \
        ${3:+--prev-holdings "$3"} --skip-liquidity >/dev/null 2>&1; echo $?; }

echo "── T0 양성 대조 (규약 만족 → PASS) ───────────────────────────────────────"
chk "T0 정상 입력은 통과" "0" "$(run "$TD/cur.csv" "$TD/man.json" "$TD/prev.csv")"

echo "── T1~T4 홀딩 제약 위반 주입 ─────────────────────────────────────────────"
"$PY" - "$TD" <<'PYEOF'
import pandas as pd, os, sys
TD = sys.argv[1]; h = pd.read_csv(os.path.join(TD, "cur.csv"))
# 종목수: 26종으로
ex = pd.DataFrame({"rank": range(90, 106), "Ticker": [f"X{i:05d}" for i in range(16)],
                   "Name": "주입", "Sector": "t", "Weight": 0.001})
a = pd.concat([h, ex], ignore_index=True); a.loc[a.Ticker == "CASH", "Weight"] = 0.70 - 0.001*16
a.to_csv(os.path.join(TD, "v_names.csv"), index=False)
b = h.copy(); b.loc[b.Ticker == "A000002", "Weight"] = -0.01
b.loc[b.Ticker == "CASH", "Weight"] = 0.74
b.to_csv(os.path.join(TD, "v_neg.csv"), index=False)
c = h.copy(); c.loc[c.Ticker == "A000003", "Weight"] = 0.35
c.loc[c.Ticker == "CASH", "Weight"] = 0.70 - 0.32
c.to_csv(os.path.join(TD, "v_ub.csv"), index=False)
d = h.copy(); d.loc[d.Ticker == "CASH", "Weight"] = 0.60
d.to_csv(os.path.join(TD, "v_sum.csv"), index=False)
PYEOF
chk "T1 종목수 25 초과 검거"  "1" "$(run "$TD/v_names.csv" "$TD/man.json" "$TD/prev.csv")"
chk "T2 음수 비중 검거"        "1" "$(run "$TD/v_neg.csv"   "$TD/man.json" "$TD/prev.csv")"
chk "T3 개별 상한 초과 검거"   "1" "$(run "$TD/v_ub.csv"    "$TD/man.json" "$TD/prev.csv")"
chk "T4 Sum(w)!=1 검거"        "1" "$(run "$TD/v_sum.csv"   "$TD/man.json" "$TD/prev.csv")"

echo "── T5~T9 매니페스트 위반 주입 ────────────────────────────────────────────"
"$PY" - "$TD" <<'PYEOF'
import json, os, sys
TD = sys.argv[1]; base = json.load(open(os.path.join(TD, "man.json"), encoding="utf-8"))
def put(name, mut):
    m = json.loads(json.dumps(base)); mut(m)
    json.dump(m, open(os.path.join(TD, name), "w", encoding="utf-8"), ensure_ascii=False)
put("m_asof.json",  lambda m: m.__setitem__("as_of", "2026-07-01"))
put("m_zna.json",   lambda m: m["overlays"]["beta_R05_V5"].__setitem__("R05_z_avg", None))
put("m_beta.json",  lambda m: m["overlays"]["beta_R05_V5"].__setitem__("value", 0.85))
put("m_gate.json",  lambda m: m["overlays"].__setitem__("m4_ae_gate", 0.70))
put("m_aepit.json", lambda m: m["pit"].__setitem__("ae_pit_ok", False))
PYEOF
chk "T5 as_of 불일치 검거"          "1" "$(run "$TD/cur.csv" "$TD/m_asof.json"  "$TD/prev.csv")"
chk "T6 R05_z 결측(폴백) 검거"      "1" "$(run "$TD/cur.csv" "$TD/m_zna.json"   "$TD/prev.csv")"
chk "T7 beta 규칙표 위반 검거"      "1" "$(run "$TD/cur.csv" "$TD/m_beta.json"  "$TD/prev.csv")"
chk "T8 게이트 규칙 불일치 검거"    "1" "$(run "$TD/cur.csv" "$TD/m_gate.json"  "$TD/prev.csv")"
chk "T9 AE PIT 위반 검거"           "1" "$(run "$TD/cur.csv" "$TD/m_aepit.json" "$TD/prev.csv")"

echo "── T10~T12 조용한 재출력 / 부재 ──────────────────────────────────────────"
chk "T10 전월과 지문 동일 검거"  "1" "$(run "$TD/cur.csv" "$TD/man.json" "$TD/cur.csv")"
chk "T11 홀딩 부재는 2"          "2" "$(run "$TD/nope.csv" "$TD/man.json" "$TD/prev.csv")"
chk "T12 매니페스트 부재는 2"    "2" "$(run "$TD/cur.csv" "$TD/nope.json" "$TD/prev.csv")"

echo "── T13 음성 통제: 검사기가 무조건 FAIL 을 뱉는 게 아님 ───────────────────"
# T0 이 이미 PASS 이지만, 전월 미지정(경고만)에서도 hard FAIL 이 아님을 확인한다 —
# 경고와 실패를 구분하지 못하면 게이트로 쓸 수 없다.
chk "T13 전월 미지정은 WARN(통과)" "0" "$(run "$TD/cur.csv" "$TD/man.json")"

# ── T14~T16 사전 점검 자체의 차단 실효 (2026-08-02 추가) ──────────────────────
# 위 T0~T13 이 "통과"인 것과 "계측이 살아 있다"는 별개다. 08-02 실사고가 정확히 그
# 틈이었다: 인터프리터가 죽어 14 케이스가 전부 exit 49 였는데 배터리엔 "검거 실패"로
# 보였다. 그래서 **일부러 죽은 인터프리터/검사기를 주입해** 사전 점검이 발화하는지,
# 그리고 그때 케이스 결과가 발행되지 *않는지*를 고정한다.
#   ★T15 가 핵심 — pandas 없는 인터프리터는 rc=1 을 내고 rc=1 은 T1~T10 의 기대값이라,
#     막지 않으면 완전히 죽은 검사기가 10/14 초록을 만든다(uniform 49 보다 은폐도가 높다).
if [ -z "${DHC_SELFTEST:-}" ]; then
  echo "── T14~T16 사전 점검 차단 실효 (죽은 계측 주입) ──────────────────────────"
  # 주입 실행 → 발행된 요약 JSON 한 줄을 회수한다.
  #   ★`env` 경유 필수 — `VAR=x "$@" bash …` 는 동작하지 않는다. 셸은 할당을 **파싱 시점**에
  #     인식하므로, 확장으로 생겨난 `VAR=x` 는 할당이 아니라 명령어 이름으로 취급된다.
  _SELF_ABS="$_SELF_DIR/$(basename "$_SELF")"
  inject(){ env DHC_SELFTEST=1 "$@" bash "$_SELF_ABS" 2>/dev/null | grep -E '^\{.*"test"' | tail -1; }
  # 주입 대상은 **합성**한다 — 실물(Store 스텁·시스템 Python)이 이 머신에 있는지에
  # 의존하면 "주입 대상 부재 → 자동 통과"가 되어, 지금 고치는 것과 같은 부류의
  # 구멍(전제 부재를 통과로 내려앉힘)을 검사기 안에 새로 만든다. 실물이 있으면 실물을 쓴다.
  STUB="$(command -v python3 2>/dev/null || true)"   # 실물 = Windows Store 스텁(rc 49)
  if [ -z "$STUB" ]; then
    STUB="$TD/fake_stub"; printf '#!/bin/sh\necho "Python "\nexit 49\n' > "$STUB"; chmod +x "$STUB"
  fi
  NOPD="${QVEST_PY:-}"; NOPD="${NOPD//\\//}"          # 실물 = 시스템 Python312(pandas 없음)
  if [ -z "$NOPD" ] || [ ! -x "$NOPD" ]; then
    NOPD="$TD/fake_nopandas"
    printf '#!/bin/sh\necho "ModuleNotFoundError: No module named %s" >&2\nexit 1\n' "'pandas'" > "$NOPD"
    chmod +x "$NOPD"
  fi
  DEADCHK="$TD/dead_checker.py"; printf 'import nonexistent_module_xyz\n' > "$DEADCHK"

  # T14 스텁 인터프리터(rc 49) → 케이스 미발행 + preflight 표식
  OUT14="$(inject DHC_FORCE_PY="$STUB")"
  case "$OUT14" in
    *'"preflight"'*) chk "T14 스텁 인터프리터(rc49)는 사전 점검에서 차단" "1" "1" ;;
    *) chk "T14 스텁 인터프리터(rc49)는 사전 점검에서 차단" "1" "0(발행=$OUT14)" ;;
  esac

  # T15 pandas 없는 인터프리터(rc 1) → 10/14 거짓초록이 아니라 차단
  #   rc=1 은 T1~T10 의 기대값이므로, 막지 않으면 죽은 검사기가 대부분 초록으로 보인다.
  OUT15="$(inject DHC_FORCE_PY="$NOPD")"
  case "$OUT15" in
    *'"preflight"'*) chk "T15 pandas 없는 인터프리터(rc1)는 차단(10/14 거짓초록 방지)" "1" "1" ;;
    *) chk "T15 pandas 없는 인터프리터(rc1)는 차단(10/14 거짓초록 방지)" "1" "0(발행=$OUT15)" ;;
  esac

  # T16 인터프리터는 멀쩡하나 검사기가 죽은 경우 → 카나리아가 잡는다
  OUT16="$(inject DHC_FORCE_CHK="$DEADCHK")"
  case "$OUT16" in
    *'"preflight":"canary"'*) chk "T16 죽은 검사기는 카나리아가 차단" "1" "1" ;;
    *) chk "T16 죽은 검사기는 카나리아가 차단" "1" "0(발행=$OUT16)" ;;
  esac
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"deployed_holdings_check\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
