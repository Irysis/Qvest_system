#!/usr/bin/env bash
#==============================================================================
# test_boot_lean_memo.sh — 부팅(boot_lean.sh) 단축의 출력 불변 계약 (2026-11-10 H2 감사 2단계)
#
# 바꾼 것: ① Data 의 세 계산(rawdata 스키마 · 팩터 IC 이름 · 퀀티 최신성)을 원천 지문 키 메모(.cache/boot_memo.json)로 ·
#   ② Queue 의 자식 파이썬(research_pool_predicates.py alpha-pending)을 같은 프로세스 가져오기로 · ⑤ 훅 수를 command 값만 세게.
# 기준(참조) = 같은 블록을 QVEST_BOOT_MEMO=0 · QVEST_BOOT_INPROC=0 로 돌린 출력(= 구판의 계산 경로 그대로).
# 축:
#   E  등가 — 합성 루트에서 기준 = 차가운 메모 = 따뜻한 메모 = 메모 손상 = 메모 끔(부팅 출력 전체 · 훅 줄 제외 없음)
#   I  무효화 — IC 파일 · rawdata 스키마 · 벤치 최신일을 바꾸면 따뜻한 메모 판도 기준과 같이 바뀐다
#   P  양성 대조 — 메모가 실제로 쓰인다: 따뜻한 판에서 pyarrow 가져오기를 막아도(가짜 pyarrow) 출력이 같다 · 기준 판은 달라진다
#   N  실패 결과는 메모하지 않는다 — 벤치가 없을 때(NA) 메모에 bench_currency 항목이 없다
#   H  훅 수 — 설명문(_doc)에 .sh 경로가 있어도 command 값만 센다(13) · 사전 거름 후보 형태도 13
#   M  돌연변이 — 메모 키에서 지문 비교를 뗀 사본은 I 가 잡는다
# 격리: 임시 루트(합성 parquet · 등록부 사본 없음) · 운영 .cache 쓰기 0.
# 요약: 마지막 줄 {"test":"boot_lean_memo","pass":N,"fail":N,"total":N}
#==============================================================================
set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$SELF/../.." && pwd)"
BOOT="$ROOT/02_Infrastructure/ops/boot_lean.sh"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
finish() { echo "PASS=$PASS FAIL=$FAIL"; echo "{\"test\":\"boot_lean_memo\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }
[ -x "$PY" ] && [ -f "$BOOT" ] || { bad "0 전제" "venv python 또는 boot_lean.sh 없음"; finish; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TW="$(cygpath -m "$T" 2>/dev/null || echo "$T")"
PR="$TW/proj"; mkdir -p "$T/proj"

# 블록 추출(boot_lean.sh 의 파이썬 heredoc 본문)
awk '/<<.PYEOF.( |$)/{f=1;next} /^PYEOF/{if(f){exit}} f' "$BOOT" > "$T/block.py"
grep -q '_MEMO_P=R(".cache","boot_memo.json")' "$T/block.py" && ok "0 블록 추출 · 메모 코드 존재" || { bad "0 블록 추출" "메모 코드 없음"; finish; }

# 합성 루트
"$PY" -X utf8 - "$PR" <<'PYEOF'
import os, sys, json, datetime as dt
import pyarrow as pa, pyarrow.parquet as pq
P = sys.argv[1]
def mk(*a): os.makedirs(os.path.join(P, *a), exist_ok=True)
for d in (".cache/factor_db", "06_Registry", "02_Infrastructure/factor_db", "02_Infrastructure/data", "02_Infrastructure/ops",
          "02_Infrastructure/programs", "stage_artifacts/paper_recharge", ".claude", "qepm/observability"):
    mk(*d.split("/"))
pq.write_table(pa.table({"Date": [1], "K200": [1], "KQ150": [1], "Ticker": ["A"]}), os.path.join(P, ".cache", "rawdata.parquet"))
pq.write_table(pa.table({"Factor_Name": ["F1", "F2", "F2", "F3", None]}), os.path.join(P, ".cache", "factor_db", "factor_ic_monthly.parquet"))
json.dump({"F1": {}, "F2": {}, "F4": {}}, open(os.path.join(P, ".cache", "factor_db", "factor_registry.json"), "w"))
json.dump({"expected_absent": []}, open(os.path.join(P, "02_Infrastructure", "factor_db", "emission_expected_absent.json"), "w"))
today = dt.date.today()
days = [today - dt.timedelta(days=i) for i in range(1, 12)]
pq.write_table(pa.table({"Date": pa.array(days, pa.date32())}), os.path.join(P, ".cache", "benchmark.parquet"))
yrs = sorted({d.year for d in days} | {today.year})
json.dump({"years": yrs, "holidays": {}}, open(os.path.join(P, "06_Registry", "krx_holidays.json"), "w"))
s = {"_doc": "see 08_Tests/hooks/test_x.sh", "hooks": {"PreToolUse": [{"matcher": "Bash", "_doc_x": "08_Tests/hooks/test_hook_powershell_coverage.sh",
     "hooks": [{"type": "command", "command": 'DIR=x; bash "$DIR/02_Infrastructure/hooks/h%02d.sh"' % i} for i in range(13)]}]}}
json.dump(s, open(os.path.join(P, ".claude", "settings.json"), "w"))
s2 = json.loads(json.dumps(s))
PF = '$DIR/02_Infrastructure/hooks/_hook_prefilter.bash'
for h in s2["hooks"]["PreToolUse"][0]["hooks"][:6]:
    hp = h["command"].split('bash "')[1].rstrip('"')
    h["command"] = 'DIR=x; if [ -f "%s" ]; then . "%s" "%s"; else bash "%s"; fi' % (PF, PF, hp, hp)
json.dump(s2, open(os.path.join(P, ".claude", "settings_pref.json"), "w"))
PYEOF
for f in data/krx_holidays.py ops/research_pool_predicates.py ops/paper_id_norm.py ops/infra_currency.py programs/session_resume.py; do
  [ -f "$ROOT/02_Infrastructure/$f" ] && cp "$ROOT/02_Infrastructure/$f" "$T/proj/02_Infrastructure/$f"
done

# run <out> [env...]
run() { local o="$1"; shift; ( cd "$T/proj" && env -u QM_ROOT PROJECT="$PR" PY="$PY" "$@" "$PY" -X utf8 "$T/block.py" > "$o" 2>/dev/null ); }
REF=(QVEST_BOOT_MEMO=0 QVEST_BOOT_INPROC=0)
MEMO="$T/proj/.cache/boot_memo.json"

echo "=== E. 등가 ==="
run "$T/ref.txt" "${REF[@]}"
rm -f "$MEMO"; run "$T/cold.txt"
[ -f "$MEMO" ] && ok "E0 차가운 실행이 메모를 만든다" || bad "E0 메모 생성" "없음"
run "$T/warm.txt"
cmp -s "$T/ref.txt" "$T/cold.txt" && ok "E1 기준 = 차가운 메모" || bad "E1" "$(diff "$T/ref.txt" "$T/cold.txt" | head -4 | tr '\n' '|')"
cmp -s "$T/ref.txt" "$T/warm.txt" && ok "E2 기준 = 따뜻한 메모" || bad "E2" "$(diff "$T/ref.txt" "$T/warm.txt" | head -4 | tr '\n' '|')"
printf '{not json' > "$MEMO"; run "$T/corrupt.txt"
cmp -s "$T/ref.txt" "$T/corrupt.txt" && ok "E3 기준 = 손상된 메모(무시하고 계산)" || bad "E3" "$(diff "$T/ref.txt" "$T/corrupt.txt" | head -2 | tr '\n' '|')"
run "$T/off.txt" QVEST_BOOT_MEMO=0
cmp -s "$T/ref.txt" "$T/off.txt" && ok "E4 기준 = 메모 끔(가져오기만 같은 프로세스)" || bad "E4" "$(diff "$T/ref.txt" "$T/off.txt" | head -2 | tr '\n' '|')"
grep -q '^Data: ' "$T/ref.txt" && grep -q '팩터 2/3' "$T/ref.txt" && grep -q 'K200/KQ150 OK' "$T/ref.txt" && grep -q '퀀티 ' "$T/ref.txt" \
  && ok "E5 합성 루트의 Data 줄이 세 계산을 실제로 탄다(팩터 2/3 · K200/KQ150 OK · 퀀티 칸)" || bad "E5 Data 줄" "$(grep '^Data' "$T/ref.txt" | head -c 200)"
grep -qE '^Queue: (alpha-pending [0-9]+|.*UNREPORTED)' "$T/ref.txt" && ok "E6 Queue 줄 존재($(grep -oE '^Queue: [^·]*' "$T/ref.txt"))" || bad "E6 Queue 줄" "$(grep '^Queue' "$T/ref.txt" | head -c 120)"

echo "=== P. 양성 대조(메모가 실제로 쓰인다) ==="
rm -f "$MEMO"; run "$T/cold2.txt"
mkdir -p "$T/fakepa/pyarrow"; printf 'raise ImportError("fake pyarrow — 메모 판정용")\n' > "$T/fakepa/pyarrow/__init__.py"
FPA="$(cygpath -w "$T/fakepa" 2>/dev/null || echo "$T/fakepa")"
run "$T/warm_nopa.txt" PYTHONPATH="$FPA"
run "$T/ref_nopa.txt" PYTHONPATH="$FPA" "${REF[@]}"
cmp -s "$T/ref.txt" "$T/warm_nopa.txt" && ok "P1 pyarrow 를 막아도 따뜻한 메모 판 = 기준(가져오기 생략 실재)" || bad "P1" "$(diff "$T/ref.txt" "$T/warm_nopa.txt" | head -3 | tr '\n' '|')"
cmp -s "$T/ref.txt" "$T/ref_nopa.txt" && bad "P2 대조" "pyarrow 를 막아도 기준 판이 같다 — 대조가 아무것도 재지 않음" || ok "P2 기준 판은 pyarrow 를 막으면 달라진다(대조 유효)"

echo "=== I. 무효화 ==="
inval() { # $1=이름 $2=python 변경 코드
  "$PY" -X utf8 -c "$2" "$PR"
  run "$T/i_ref_$1.txt" "${REF[@]}"; run "$T/i_warm_$1.txt"
  if cmp -s "$T/i_ref_$1.txt" "$T/i_warm_$1.txt" && ! cmp -s "$T/ref.txt" "$T/i_ref_$1.txt"; then ok "I[$1] 원천이 바뀌면 메모 판도 기준과 같이 바뀐다"
  else bad "I[$1]" "ref_changed=$(cmp -s "$T/ref.txt" "$T/i_ref_$1.txt" && echo no || echo yes) $(diff "$T/i_ref_$1.txt" "$T/i_warm_$1.txt" | head -2 | tr '\n' '|')"; fi
}
run "$T/warm0.txt"   # 메모 따뜻하게
inval ic 'import sys,os,pyarrow as pa,pyarrow.parquet as pq; pq.write_table(pa.table({"Factor_Name":["F1","F2","F4"]}),os.path.join(sys.argv[1],".cache","factor_db","factor_ic_monthly.parquet"))'
inval schema 'import sys,os,pyarrow as pa,pyarrow.parquet as pq; pq.write_table(pa.table({"Date":[1],"K200":[1]}),os.path.join(sys.argv[1],".cache","rawdata.parquet"))'
cp "$T/i_ref_schema.txt" "$T/ref.txt"
inval bench 'import sys,os,datetime as dt,pyarrow as pa,pyarrow.parquet as pq; t=dt.date.today(); pq.write_table(pa.table({"Date":pa.array([t-dt.timedelta(days=20)],pa.date32())}),os.path.join(sys.argv[1],".cache","benchmark.parquet"))'

echo "=== Q. 큐 줄 시간 상한(11-10 검토 2차) ==="
# 논문 큐 모듈이 가져오기에서 멈추면(파일 읽기 정지 모사 = 60초 sleep) 상한 뒤 UNREPORTED 로 접고 나머지 줄을 전부 낸다
cp "$T/proj/02_Infrastructure/ops/research_pool_predicates.py" "$T/rpp.keep"
printf 'import time\ntime.sleep(60)\n' > "$T/proj/02_Infrastructure/ops/research_pool_predicates.py"
_q0=$(date +%s); run "$T/qhang.txt" QVEST_BOOT_QUEUE_TIMEOUT_S=3; _q1=$(date +%s)
grep -q '^Queue: alpha-pending UNREPORTED' "$T/qhang.txt" && grep -q '^Data: ' "$T/qhang.txt" && [ "$(grep -c '' "$T/qhang.txt")" = "$(grep -c '' "$T/ref.txt")" ] && [ $(( _q1 - _q0 )) -lt 45 ] \
  && ok "Q1 큐 모듈 정지 → 상한(3초) 뒤 UNREPORTED · 줄 수 = 기준과 같음($(grep -c '' "$T/qhang.txt")줄) · $(( _q1 - _q0 ))초 안에 끝남" \
  || bad "Q1" "$(( _q1 - _q0 ))초 · $(grep '^Queue' "$T/qhang.txt" | head -c 120) · 줄 $(grep -c '' "$T/qhang.txt")/$(grep -c '' "$T/ref.txt")"
cp "$T/rpp.keep" "$T/proj/02_Infrastructure/ops/research_pool_predicates.py"
run "$T/qref.txt" "${REF[@]}"; run "$T/qback.txt"   # 기준은 지금 상태로 새로 잰다(앞 절들이 합성 루트를 바꿨다)
cmp -s "$T/qref.txt" "$T/qback.txt" && ok "Q2 [대조] 모듈 복구 뒤 출력 = 지금 상태의 기준(메모 끔 · 자식 프로세스)" || bad "Q2" "$(diff "$T/qref.txt" "$T/qback.txt" | head -3 | tr '\n' '|')"

echo "=== N. 실패 결과는 메모하지 않는다 ==="
rm -f "$MEMO" "$T/proj/.cache/benchmark.parquet"; run "$T/na.txt"
"$PY" -X utf8 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print("has" if any(k.startswith("bench_currency") for k in d) else "none")' "$MEMO" > "$T/na.flag" 2>/dev/null
[ "$(cat "$T/na.flag")" = "none" ] && grep -q '퀀티 ?' "$T/na.txt" && ok "N1 벤치 부재(NA) 결과는 메모에 없다 · 출력은 '퀀티 ?'" || bad "N1" "flag=$(cat "$T/na.flag") $(grep -o '퀀티[^·]*' "$T/na.txt")"

echo "=== H. 훅 수 ==="
hkline() { grep -oE 'hooks [0-9]+/[0-9]+' "$1" | head -1; }
H1="$(hkline "$T/warm0.txt")"
[ "${H1%%/*}" = "hooks 13" ] && ok "H1 설명문 속 .sh 경로를 세지 않는다($H1)" || bad "H1" "$H1"
cp "$T/proj/.claude/settings.json" "$T/s_plain.json"; cp "$T/proj/.claude/settings_pref.json" "$T/proj/.claude/settings.json"
run "$T/pref.txt"; H2="$(hkline "$T/pref.txt")"
[ "${H2%%/*}" = "hooks 13" ] && ok "H2 사전 거름 후보 형태도 13($H2)" || bad "H2" "$H2"
cp "$T/s_plain.json" "$T/proj/.claude/settings.json"
OLDHK="$(cd "$T/proj" && "$PY" -c 'import re;print(len(set(re.findall(r"hooks/([A-Za-z0-9_.-]+\.sh)",open(".claude/settings.json",encoding="utf-8").read()))))')"
[ "$OLDHK" = "15" ] && ok "H3 [대조] 구 정규식은 같은 설정을 15 로 센다(설명문 속 경로 2개까지 · 오탐 재현)" || bad "H3 대조" "$OLDHK"

echo "=== M. 돌연변이 ==="
"$PY" -X utf8 -c 'import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read(); a="e.get(\"fp\")==fp and "
print(s.count(a)); io.open(sys.argv[2],"w",encoding="utf-8",newline="").write(s.replace(a,""))' "$T/block.py" "$T/block_mut.py" > "$T/m.n"
cp "$T/block.py" "$T/block_orig.py"; cp "$T/block_mut.py" "$T/block.py"
run "$T/m_warm.txt"   # 메모 따뜻하게(변이판)
"$PY" -X utf8 -c 'import sys,os,pyarrow as pa,pyarrow.parquet as pq; pq.write_table(pa.table({"Factor_Name":["F1"]}),os.path.join(sys.argv[1],".cache","factor_db","factor_ic_monthly.parquet"))' "$PR"
run "$T/m_after.txt"; run "$T/m_ref.txt" "${REF[@]}"
cp "$T/block_orig.py" "$T/block.py"
[ "$(tr -d '\r\n' < "$T/m.n")" = "1" ] && ! cmp -s "$T/m_ref.txt" "$T/m_after.txt" && ok "M1 지문 비교를 뗀 사본은 낡은 메모를 내고 I 축 방식이 그것을 잡는다(치환 1곳)" || bad "M1" "치환 $(cat "$T/m.n") · 같음=$(cmp -s "$T/m_ref.txt" "$T/m_after.txt" && echo yes || echo no)"
finish
