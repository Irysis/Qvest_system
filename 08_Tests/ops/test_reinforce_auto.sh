#!/usr/bin/env bash
#==============================================================================
# test_reinforce_auto.sh — 강화 무인 러너 **양방향 검사** (2026-08-30)
#
# 왜 양방향인가: 이 저장소의 반복 교훈 — "경고 0" 을 보고하는 순간이 최고 위험이고,
#   위반 주입 없이 통과만 확인한 계기는 방어선으로 세지 않는다. 그래서 각 가드마다
#   ①정상 경로에서 통과하는가 ②위반을 주입하면 실제로 막는가 를 **둘 다** 건다.
#
# 실행: bash 08_Tests/ops/test_reinforce_auto.sh
# 부작용 없음 — 원장·산출물에 쓰지 않는다(kill switch off 상태에서만 러너를 부른다).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="$ROOT/06_Registry/reinforce_auto_config.json"
CLAIM="$ROOT/.cache/reinforce_auto.claim"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

BAK="$(mktemp)"; cp "$CFG" "$BAK" 2>/dev/null
restore(){ [ -s "$BAK" ] && cp "$BAK" "$CFG"; rm -f "$BAK"; rm -rf "$CLAIM"; }
trap restore EXIT

echo "=== 1. 구문 ==="
for f in 02_Infrastructure/reinforcement/rf_cell_engine.R \
         02_Infrastructure/ops/reinforce_auto_run.R \
         02_Infrastructure/ops/reinforce_auto_next_paper.R; do
  if Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1; then ok "parse $f"; else ng "parse $f"; fi
done
if "$PY" -c "import ast,io,sys; ast.parse(io.open('02_Infrastructure/ops/rf_next_paper_pick.py',encoding='utf-8').read())" 2>/dev/null; then
  ok "parse rf_next_paper_pick.py"; else ng "parse rf_next_paper_pick.py"; fi

echo "=== 2. kill switch (양방향) ==="
# ②위반 주입: enabled=false → 반드시 즉시 정지하고 아무것도 안 한다
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=False
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_disabled"; then ok "kill switch off → halt_disabled"; else ng "kill switch off" "$(printf '%s' "$OUT" | head -2)"; fi
if [ -d "$CLAIM" ]; then ng "kill switch off 인데 claim 을 잡았다"; else ok "kill switch off → claim 미점유"; fi

# ①정상 대조: enabled=true 면 halt_disabled 가 아니어야 한다(다른 사유로는 멈출 수 있다)
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=True;d['daily_cap']=0
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_disabled"; then ng "enabled=true 인데 halt_disabled" ; else ok "enabled=true → kill switch 통과"; fi
# ②daily_cap=0 주입 → 예산 가드가 실제로 막는가
if printf '%s' "$OUT" | grep -q "halt_daily_cap"; then ok "daily_cap 가드 발화"; else ng "daily_cap=0 인데 미발화" "$(printf '%s' "$OUT" | head -2)"; fi

echo "=== 3. claim mutex (양방향) ==="
# ★daily_cap 은 claim 보다 **먼저** 판정된다. 오늘 실행분이 많으면 claim 축에 닿기도 전에
#   halt_daily_cap 으로 멈춰 이 검사가 엉뚱한 이유로 실패한다(2026-08-30 실사고).
#   그래서 claim 축만 재도록 상한을 충분히 올린다.
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=True;d['daily_cap']=9999
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
mkdir -p "$CLAIM"                       # ②위반 주입: 이미 점유된 상태
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_claimed"; then ok "claim 점유 중 → halt_claimed"; else ng "claim 점유 무시" "$(printf '%s' "$OUT" | head -2)"; fi
rm -rf "$CLAIM"
if [ ! -d "$CLAIM" ]; then ok "claim 해제 확인"; else ng "claim 해제 실패"; fi

echo "=== 4. 프로그램 격자 무결성 ==="
"$PY" - <<'PYEOF'
import io, json, sys
d = json.load(io.open("06_Registry/reinforce_program.json", encoding="utf-8"))
n = sum(b["n"] for b in d["blocks"])
assert n == 20, "총 칸 %d != 20" % n
codes = [c["code"] for b in d["blocks"] for c in b["cells"]]
assert len(codes) == 20 and len(set(codes)) == 20, "코드 중복/누락: %s" % codes
for b in d["blocks"]:
    assert len(b["cells"]) == b["n"], "%s 선언 n=%d 실제 %d" % (b["id"], b["n"], len(b["cells"]))
    for c in b["cells"]:
        if b["id"] != "B4":
            assert c.get("root_paper", {}).get("url", "").startswith("http"), "%s 근거 논문 링크 없음" % c["code"]
ax = d["fixed_axes"]
assert ax["long_only"] is True and ax["n_max"] == 25, "고정 축 위반: %s" % ax
print("  OK   격자 20칸 · 코드 유일 · 근거 논문 링크 · 고정 축")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL 격자 무결성"; }

echo "=== 5. 논문 선택기 (양방향) ==="
OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py stage_artifacts/paper_recharge 2>&1)
if printf '%s' "$OUT" | "$PY" -c "
import sys,json; o=json.loads(sys.stdin.read()); sys.exit(0 if o.get('url','').startswith('http') else 1)"; then
  ok "큐 상단 논문 + 원문 링크 산출"; else ng "논문 선택 실패" "$OUT"; fi
# ②위반 주입: 빈 디렉터리 → 반드시 링크를 지어내지 않는다
TMPD=$(mktemp -d); OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py "$TMPD" 2>&1); rm -rf "$TMPD"
if printf '%s' "$OUT" | grep -q '"error"'; then ok "빈 큐 → 오류 반환(링크 날조 없음)"; else ng "빈 큐인데 링크를 냈다" "$OUT"; fi

echo "=== 6. 자본 경계 (정적) ==="
# ★주석 제외 — 이 검사의 첫 판이 러너의 "book_state/05_Production 에 도달하는 코드 없음"
#   이라는 **주석 자체**에 걸려 오탐했다. 판정 축은 실행 코드다.
HITS=$(for f in 02_Infrastructure/ops/reinforce_auto_run.R                 02_Infrastructure/ops/reinforce_auto_next_paper.R                 02_Infrastructure/reinforcement/rf_cell_engine.R; do
         sed 's/#.*$//' "$f" | grep -nE "book_state|05_Production" | sed "s|^|$f:|"
       done)
if [ -n "$HITS" ]; then ng "무인 러너 실행 코드가 book_state/05_Production 을 참조한다" "$HITS"
else ok "자본 경계 — 실행 코드에 book_state/05_Production 미참조"; fi
# ①양성 대조: 검사기가 실제로 발화하는가 (위반 주입)
TMPF="$ROOT/.cache/_rf_boundary_probe.R"; printf 'x <- "05_Production/foo"
' > "$TMPF"
if sed 's/#.*$//' "$TMPF" | grep -qE "book_state|05_Production"; then ok "자본 경계 검사기 양성 대조 발화"
else ng "자본 경계 검사기가 위반 주입에도 미발화 — 죽은 검사"; fi
rm -f "$TMPF"

echo "=== 7. 병렬 배치 (규칙) ==="
for f in 02_Infrastructure/ops/reinforce_auto_parallel.R 02_Infrastructure/ops/rf_cell_worker.R; do
  if Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1; then ok "parse $f"; else ng "parse $f"; fi
done
# ★워커는 원장을 만지면 안 된다 (병렬 경합 원천 차단 계약)
if sed 's/#.*$//' 02_Infrastructure/ops/rf_cell_worker.R | grep -qE "rf_record_result|rf_append_attempt|rf_write"; then
  ng "워커가 원장을 쓴다 — 병렬 경합 위험"
else ok "워커 원장 미접근 (등록·수집은 부모 순차)"; fi
PRB="$ROOT/.cache/_rf_worker_probe.R"; printf 'rf_record_result(1L)\n' > "$PRB"
if sed 's/#.*$//' "$PRB" | grep -qE "rf_record_result"; then ok "워커 원장검사 양성 대조 발화"
else ng "워커 원장검사 미발화 — 죽은 검사"; fi
rm -f "$PRB"
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
e=g.get('execution') or {}
sys.exit(0 if e.get('mode')=='parallel_within_block' and 'ledger_contract' in e else 1)"; then
  ok "정본에 병렬 규칙(블록 내 한정 + 원장 계약) 명시"; else ng "정본에 병렬 규칙 없음"; fi

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
