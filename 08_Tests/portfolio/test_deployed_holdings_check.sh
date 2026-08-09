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
else
  # main 체크아웃의 venv 도 후보다(worktree 엔 junction 이 없을 수 있다). 단 경로를
  # **하드코딩하지 않는다** — 선행 `/` 절대경로 박기는 r-portability 금칙 ③ 이고,
  # 여기선 부작용이 하나 더 있다: 어떤 트리에서 돌려도 main 의 venv 가 잡히므로
  # "전제 부재" 상태를 **만들 수 없게** 되어 skip 계약을 검증할 수단이 사라진다
  # (실측 2026-08-03: 빈 가짜 루트에서도 main venv 가 잡혀 skip 축이 전부 빨강).
  # 정본 = git 이 알려주는 공통 git-dir 에서 역산 (경로 추측·dir.exists 신뢰 금지).
  _MAIN_ROOT=""
  if _gcd="$(git -C "$PROJ" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$_gcd" ]; then
    case "$_gcd" in /*|[A-Za-z]:*) : ;; *) _gcd="$PROJ/$_gcd" ;; esac
    [ -d "$_gcd" ] && _MAIN_ROOT="$(dirname "$(cd "$_gcd" && pwd)")"
  fi
  _PY_CANDS=("${QVEST_PY_BIN:-}" "${QVEST_PY:-}" \
             "$PROJ/.venv_qvest_ml/Scripts/python.exe" \
             "$_QM_ENV/.venv_qvest_ml/Scripts/python.exe" \
             ${_MAIN_ROOT:+"$_MAIN_ROOT/.venv_qvest_ml/Scripts/python.exe"} \
             ${_MAIN_ROOT:+"$_MAIN_ROOT/.venv_qvest_ml/bin/python"})
fi
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
# ★ N_AXES = 이 파일이 전제 충족 시 실제로 판정하는 축 수 (2026-08-03).
#   skip 을 낼 때 "몇 건을 판정하지 않았나"를 주장하려면 그 수가 참이어야 한다.
#   정적 grep(`^chk "T`)으로 세지 않는다 — 들여쓴 호출·루프 안 호출을 놓쳐 거짓 수를 낸다
#   (실측: grep 은 10, 실제 판정은 21). 대신 이 상수를 선언하고,
#   test_prereq_skip_contract.sh 가 **전제 충족 실행의 pass 수와 대조**해 참임을 실증한다
#   (정적 대조가 아니라 측정 대조 — 축이 늘거나 줄면 그 검사가 즉시 빨개진다).
N_AXES=21

# ── 전제 부재 = 판정 없음(제3상태) vs 실제 결함(fail) 의 분기 ──────────────────
# 해석기(venv)는 **gitignore 산출물**이다 — 이 트리에 없는 것이 회귀는 아니다.
#   구현은 이걸 preflight_fail 로 처리했는데, 그러면 worktree 배터리가 환경 사유로
#   영구 빨강이 되고 "계약 위반"과 "전제 부재"가 같은 색이 된다(오진단).
#   반대로 조용히 통과시키면 이 저장소가 12회 수리한 "빈 결과 = 합격" 계통이다.
#   → 제3상태로 낸다: pass 0 · fail 0 · skipped N_AXES · rc 0 · **없는 경로를 명시**.
# ★검사기 본체($CHK)는 **추적 파일**이라 부재가 곧 결함 — 그건 계속 fail 이다.
#   카나리아 실패(설치는 됐는데 실행 단계에서 죽음)도 fail — 전제는 있는데 깨진 것이다.
preflight_skip() { # $1=사유 $2=없는 경로
  echo "⊘ SKIP: $1" >&2
  echo "   전제 부재는 통과도 실패도 아니다 — $N_AXES개 축을 판정하지 않았음을 그대로 보고한다." >&2
  printf '{"test":"deployed_holdings_check","pass":0,"fail":0,"skipped":%s,"total":0,' "$N_AXES"
  printf '"skips":[{"axis":"ALL(%s축)","reason":"%s","missing":"%s"}]}\n' "$N_AXES" "$1" "$2"
  exit 0
}
# ★"지정했는데 깨졌다" 와 "이 트리에 없다" 를 가른다 (2026-08-03).
#   DHC_FORCE_PY 가 있는데 프로브를 통과 못 했다면 그건 **주입된 결함**이다(자기검사
#   T14/T15 가 정확히 그 상황을 만든다: 스텁 rc49 · pandas 없는 해석기 rc1).
#   호출자가 "이걸 쓰라"고 지목한 것이 깨진 것이므로 전제 부재가 아니라 차단 대상 —
#   여기서 skip 을 내면 T15 가 경고한 '10/14 거짓 초록'이 이번엔 '전량 skip'으로
#   되살아난다(죽은 검사기가 조용해지는 형태). 발견 실패로 무해해 보이는 쪽이 더 위험하다.
if [ -z "$PY" ]; then
  if [ -n "${DHC_FORCE_PY:-}" ]; then
    preflight_fail "지정된 해석기가 pandas/pyarrow 프로브 실패: ${DHC_FORCE_PY} — 전제 부재 아님(호출자가 지목한 해석기가 깨짐)" "no_python"
  fi
  preflight_skip \
    "pandas/pyarrow 를 갖춘 python 해석기 부재 (후보: ${_PY_CANDS[*]}) — bare python3=Store 스텁(rc49)은 후보 제외" \
    "$PROJ/.venv_qvest_ml/Scripts/python.exe"
fi
[ -f "$CHK" ] || preflight_fail "검사기 파일 부재: $CHK (추적 파일 — 전제 부재 아님)" "no_checker"
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

echo "── T1~T4 홀딩 제약 위반 주입 (단일-제약) ─────────────────────────────────"
# ★2026-08-02 교락 수리: 구판 픽스처는 Σw=1 을 맞추려 **CASH 를 조정**했다. 그러면
#   매니페스트 정합(cash == 1-invested)이 **먼저** 발화해 제약 검사를 그늘에 가린다.
#   실측: 하드 제약 4종 검사를 코드에서 통째로 지워도 v_names/v_neg/v_ub 가 여전히 rc=1
#   → T1~T3 이 "통과"인 채로 25종·long-only·상한이 **미검사**였다.
#   ("위반 주입이 발화했다" ≠ "그 제약을 쟀다" — 다른 검사가 낸 1 일 수 있다.)
#   수리 = CASH 를 0.70 에 고정하고 **주식 쪽만** 변형해 목표 제약 하나만 위반시킨다.
"$PY" - "$TD" <<'PYEOF'
import pandas as pd, os, sys
TD = sys.argv[1]; h = pd.read_csv(os.path.join(TD, "cur.csv"))
def put(name, df): df.to_csv(os.path.join(TD, name), index=False)

# T1 종목수만: 주식 26종 × (0.30/26) — 주식합 0.30 유지, CASH 0.70, Σw=1
rows = [{"rank": 0, "Ticker": "CASH", "Name": "CASH", "Sector": "Cash", "Weight": 0.70}]
for i in range(1, 27):
    rows.append({"rank": i, "Ticker": f"A{i:06d}", "Name": f"N{i}", "Sector": "t",
                 "Weight": 0.30/26})
put("v_names.csv", pd.DataFrame(rows))

# T2 음수만: A2 = 0.03→-0.01 (Δ -0.04) 를 A1·A3·A4·A5 에 **분산** 상계(각 0.03→0.04).
#   주식합 0.30 유지, CASH 0.70, long_only 만 위반.
#   ★2026-08-09 수리 — 구판은 Δ 를 A1 하나에 몰아 0.07 로 뒀고 "최대 0.07 < 0.20" 이라 안전하다고 봤다.
#     그런데 2026-08-08 에 상한 검사의 basis 가 **전략기준**(주식 내 정규화)으로 명시되면서
#     0.07/0.30 = **0.2333 > 0.20** 이 되어 상한 위반이 함께 발화했다
#     (실측 로그: "FAIL 상한 초과(전략기준) 1건 · max 0.233333 > 0.2").
#     그 결과 T2 와 돌연변이 축 T17b(long_only 제거 → 뒤집힘) 가 **자기가 재려는 제약을 못 쟀다**
#     — 다른 검사가 낸 1 이 그늘을 만든 것이고, 이 파일이 08-02 에 고친 바로 그 실패 모드다.
#   ★교훈: 픽스처의 안전 여유는 **검사기가 쓰는 basis 로** 계산해야 한다. 배포기준(CASH 포함)
#     0.07 은 안전해 보이지만 전략기준으로는 상한의 1.17배다. basis 가 바뀌면 픽스처가 먼저 썩는다.
#   분산 후 전략기준 최대 = 0.04/0.30 = 0.1333 < 0.20 (여유 33%).
b = h.copy()
b.loc[b.Ticker == "A000002", "Weight"] = -0.01
for _t in ("A000001", "A000003", "A000004", "A000005"):
    b.loc[b.Ticker == _t, "Weight"] = 0.04
put("v_neg.csv", b)

# T3 상한만: A3 = 0.25(>0.20), 나머지 9종이 0.05 를 균분. 주식합 0.30, CASH 0.70
c = h.copy()
c.loc[c.Ticker == "A000003", "Weight"] = 0.25
oth = (c.Ticker != "CASH") & (c.Ticker != "A000003")
c.loc[oth, "Weight"] = 0.05/int(oth.sum())
put("v_ub.csv", c)

# T4 Σw만: A1 을 0.03→0.05 (주식합 0.32). CASH 0.70 그대로 → Σw=1.02, cash 정합은 통과
d = h.copy()
d.loc[d.Ticker == "A000001", "Weight"] = 0.05
put("v_sum.csv", d)
PYEOF

# 단일-제약 단언 — rc 뿐 아니라 **어느 검사가 발화했는지**까지 고정한다.
#   rc=1 만 보면 그늘에 가린 미검사를 다시 놓친다(위 교락이 정확히 그 형태였다).
runf(){ "$PY" "$CHK" --as-of "${AS_OF:-2026-08-01}" --holdings "$1" --manifest "$TD/man.json" \
          --prev-holdings "$TD/prev.csv" --skip-liquidity 2>&1; }
chk_single(){ # $1=케이스명 $2=픽스처 $3=목표 제약의 FAIL 정규식
  # 단언 = "발화한 hard FAIL 이 **전부** 목표 제약의 것" (≥1건 ∧ 무관 FAIL 0건).
  #   개수를 1 로 고정하지 않는 이유: max_names 는 실질보유/주식행수 2줄로 표현된다
  #   — 같은 제약의 2줄과 '다른 제약이 그늘을 만든 2줄'을 구분해야 하므로 소속으로 잰다.
  local out tot hit
  out="$(runf "$2")"
  tot="$(printf '%s\n' "$out" | grep -c '^  FAIL')"
  hit="$(printf '%s\n' "$out" | grep -E "^  FAIL.*($3)" | grep -c .)"
  if [ "$hit" -ge 1 ] && [ "$tot" = "$hit" ]; then
    PASS=$((PASS+1)); echo "  ok   $1"
  else
    FAIL=$((FAIL+1)); echo "  FAIL $1 (hard FAIL 총 ${tot}건 중 목표 ${hit}건 — 무관 발화가 그늘을 만듦): $(printf '%s\n' "$out" | grep '^  FAIL' | tr '\n' ' ')"
  fi
}
chk_single "T1 종목수 25 초과만 검거"  "$TD/v_names.csv" "실질 보유|주식 행수"
chk_single "T2 음수 비중만 검거"       "$TD/v_neg.csv"   "음수 비중"
chk_single "T3 개별 상한 초과만 검거"  "$TD/v_ub.csv"    "상한 초과"
chk_single "T4 Sum(w)!=1 만 검거"      "$TD/v_sum.csv"   "Sum\(w\)"

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

  # ── T17 돌연변이 1:1 대응 — 각 하드 제약을 지우면 해당 케이스가 실제로 뒤집히는가 ──
  # 이것이 "그 제약을 쟀다"의 유일한 직접 증거다. 단일-제약 픽스처라 목표 검사를 제거하면
  # 해당 케이스는 rc 0(무검거)이 되어야 한다 — 다른 검사가 대신 1을 내면 교락이 남은 것.
  # (구판 실측: 4종 검사를 통째로 지워도 v_names/v_neg/v_ub 가 rc=1 → 4종 전부 미검사였다.)
  echo "── T17 돌연변이 1:1 대응 (제약 제거 → 해당 케이스 뒤집힘) ────────────────"
  # 돌연변이는 **호출 하나만 무력화**한다(구간 삭제 금지).
  #   ★구간 삭제판을 먼저 짰다가 밟았다: 앵커~다음 chk 사이를 지우니 그 사이의
  #     `n_over = ...` 대입까지 사라져 NameError → rc=1. 그런데 rc=1 은 "여전히 검거"의
  #     기대값이라 **깨진 돌연변이가 '제약이 살아있다'로 읽혔다** — 이 파일이 고치는
  #     종료코드 충돌이 돌연변이 하네스 안에서 재현된 것. 그래서 ①치환식 무력화(구조 보존)
  #     ②돌연변이가 clean 입력에서 rc=0 인지 먼저 확인(살아있는 돌연변이인가) 두 겹을 둔다.
  mutate(){ # $1=출력태그, 나머지=무력화할 chk 앵커들 → 돌연변이 경로를 stdout
    local tag="$1"; shift
    "$PY" - "$CHK" "$TD" "$tag" "$@" <<'PYEOF'
import sys, os
src = open(sys.argv[1], encoding="utf-8").read()
TD, tag, anchors = sys.argv[2], sys.argv[3], sys.argv[4:]
# chk 와 같은 시그니처의 무해 함수를 주입(구조·대입 전부 보존)
defn = "    def chk(cond, ok, bad, hard=True):"
src = src.replace(defn, "    _nochk = lambda *a, **k: None\n" + defn, 1)
for a in anchors:
    if a not in src: raise SystemExit("앵커 미발견: " + a)
    src = src.replace(a, a.replace("chk(", "_nochk(", 1), 1)
out = os.path.join(TD, "mut_%s.py" % tag)
open(out, "w", encoding="utf-8").write(src)
print(out)
PYEOF
  }
  mut_case(){ # $1=이름 $2=태그 $3=픽스처 $4...=앵커들
    local nm="$1" tag="$2" fx="$3"; shift 3
    local m rc rc0
    m="$(mutate "$tag" "$@")" || { FAIL=$((FAIL+1)); echo "  FAIL $nm (돌연변이 생성 실패)"; return; }
    # ①살아있는 돌연변이인가 — clean 입력에서 rc=0 이어야 한다(깨진 돌연변이의 rc=1 배제)
    "$PY" "$m" --as-of 2026-08-01 --holdings "$TD/cur.csv" --manifest "$TD/man.json" \
       --prev-holdings "$TD/prev.csv" --skip-liquidity >/dev/null 2>&1; rc0=$?
    if [ "$rc0" != "0" ]; then
      FAIL=$((FAIL+1)); echo "  FAIL $nm (돌연변이가 clean 입력에서 rc=$rc0 — 돌연변이가 깨진 것이지 제약 판정이 아님)"; return
    fi
    # ②그 제약을 정말 쟀다면, 제거 후 이 케이스는 검거되지 않아야(rc=0) 한다
    "$PY" "$m" --as-of 2026-08-01 --holdings "$fx" --manifest "$TD/man.json" \
       --prev-holdings "$TD/prev.csv" --skip-liquidity >/dev/null 2>&1; rc=$?
    if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "  ok   $nm"
    else FAIL=$((FAIL+1)); echo "  FAIL $nm (제약 제거 후에도 rc=$rc — 다른 검사가 그늘을 만들어 이 케이스는 해당 제약을 재지 않는다)"; fi
  }
  mut_case "T17a max_names 제거 → T1 뒤집힘"   names "$TD/v_names.csv" \
           'chk(len(held) <= C["max_names"]' 'chk(len(eq) <= C["max_names"]'
  mut_case "T17b long_only 제거 → T2 뒤집힘"   neg   "$TD/v_neg.csv"   'chk(n_neg == 0'
  mut_case "T17c upper_bound 제거 → T3 뒤집힘" ub    "$TD/v_ub.csv"    'chk(n_over == 0'
  mut_case "T17d sum_w 제거 → T4 뒤집힘"       sum   "$TD/v_sum.csv"   'chk(abs(df.Weight.sum()'
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIPPED=0"
echo "{\"test\":\"deployed_holdings_check\",\"pass\":$PASS,\"fail\":$FAIL,\"skipped\":0,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
