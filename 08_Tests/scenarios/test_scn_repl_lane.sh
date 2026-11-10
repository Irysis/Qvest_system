#!/usr/bin/env bash
#==============================================================================
# test_scn_repl_lane.sh — 레인 D 시나리오(2026-11-10 v10.2 감사): 충실구현 무인 레인 재가동 전 운영 사고
#   L1 디스패처 로그 격리 — 상태 폴더를 격리하면 디스패처 로그도 그 아래로(운영 .cache/scheduler_logs 무접촉) · 돌연변이(구판 줄) = 운영 로그 오염 탐지
#   L2 큐가 비었다 — 발행 0 · 띄우기 0 · 틱 실패 0(조용한 멈춤이 아니라 정상 대기)
#   L3 크래시 뒤 재가동 — 다른 기기(11-07 노트북→메인)가 남긴 claim: 소유자 pid 없음 → 회수 · in_progress 요청은 그대로 → 다음 작업자가 되살림
#   L4 pid 재사용 — claim 의 소유자 pid 가 이 기기에서 살아 있지만 시작 시각이 다르다 → 회수(산 프로세스를 소유자로 오인하지 않는다)
#   L5 OneDrive 읽기 전용(R) 속성 claim 폴더 — 회수가 폴더를 실제로 지운다(claim_reclaim_incomplete 없음)
#   L6 생존 소유자 장시간 — 계산 시간 상한 없음(도훈 10-17): 회수하지 않고 claim_live_long 1회만(같은 틱 반복 시 중복 없음)
# 격리: QVEST_RP_*(설정 · 상태 · 슬롯 요청 · 저널 · 구판 요청/claim · 작업 디렉터리) · QVEST_GPU_LEASE · 갱신 잠금 · 후보 · 발행 대역.
#   운영 요청 · claim · 레인 로그 · 재구현 대기열 무접촉(L1 이 로그 무접촉을 단정한다). 에이전트 · 측정 · 네트워크 없음.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
LANE="${SCN_REPL_LANE:-02_Infrastructure/ops/rf_replication_auto.sh}"   # 돌연변이 사본 대입용(검사 전용)
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T0="$(cygpath -m "$(mktemp -d)" 2>/dev/null)"; [ -n "$T0" ] || T0="$(mktemp -d)"
trap 'attrib -R "$(cygpath -w "$T0" 2>/dev/null)\\*" /S /D >/dev/null 2>&1; rm -rf "$T0"' EXIT
OPLOG="$ROOT/.cache/scheduler_logs/replication_auto_$(date +%Y%m%d).log"
op_sig(){ if [ -f "$OPLOG" ]; then "$PY" -c "import os,sys;s=os.stat(sys.argv[1]);print(s.st_size,int(s.st_mtime_ns))" "$OPLOG"; else echo absent; fi; }

mkfx(){   # $1 이름 · $2 후보 JSON
  T="$T0/$1"; mkdir -p "$T/state" "$T/slots" "$T/strat"
  "$PY" -X utf8 - "$ROOT/06_Registry/reinforce_auto_config.json" "$T/cfg.json" <<'PYC'
import io, json, sys
c = json.load(io.open(sys.argv[1], encoding="utf-8"))
c["replication_lane"] = {"enabled": True, "slots": {"cpu": 1, "gpu": 0}, "gpu_lease": {"default_cap_hours": 12, "max_cap_hours": 12}}
c["claim_stale_hours"] = 6
io.open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(c, ensure_ascii=False))
PYC
  printf '%s\n' '{"status":"done","paper":{"paper_key":"LEGACY.done","url":"u"}}' > "$T/legacy_req.json"
  printf '%s\n' "${2:-[]}" > "$T/cands.json"
  cat > "$T/issue_stub.py" <<'P'
import json, os, sys, io
a = sys.argv[1:]
g = lambda f: a[a.index(f) + 1] if f in a else ""
req, key, slot = g("--req"), g("--only-key"), g("--slot")
io.open(os.environ["STUB_LOG"], "a", encoding="utf-8").write("%s %s\n" % (slot, key))
os.makedirs(os.path.dirname(req), exist_ok=True)
io.open(req, "w", encoding="utf-8").write(json.dumps({"status": "pending", "slot": slot, "lane_mode": "normal",
    "paper": {"paper_key": key, "paper_title": key, "url": "http://127.0.0.1:9/" + key}}))
P
  : > "$T/j.jsonl"; : > "$T/issue.log"
}
envs(){ printf '%s\n' QM_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$ROOT" QVEST_PY="$PY" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" \
  QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" QVEST_RP_REQUEST="$T/legacy_req.json" QVEST_RP_CLAIM="$T/state/rf_replication.claim" \
  QVEST_RP_WDIR_BASE="$T/strat" QVEST_GPU_LEASE="$T/state/gpu_lease.json" QVEST_RP_CANDIDATES_JSON="$T/cands.json" \
  QVEST_RP_ISSUE_CMD="$T/issue_stub.py" STUB_LOG="$T/issue.log" QM_REFRESH_LOCKDIR="$T/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$T/writer.lock" \
  QVEST_TG_DRY_RUN=1 QVEST_RP_LAUNCH=print; }
lane(){ local sh="${1:-$LANE}"; env $(envs) bash "$sh" >> "$T/lane.out" 2>&1; }
slots_py(){ env $(envs) "$PY" -X utf8 02_Infrastructure/ops/rf_replication_slots.py --root "$ROOT" "$@"; }
ev(){ "$PY" -c "
import io,json,sys
n=0
for l in io.open(sys.argv[1],encoding='utf-8'):
    try: r=json.loads(l)
    except Exception: continue
    if r.get('event')==sys.argv[2]: n+=1
print(n)" "$T/j.jsonl" "$1" 2>/dev/null | tr -d '\r'; }
mkclaim(){   # $1 슬롯 · $2 owner_win · $3 owner_start(빈 값 = 없음) · $4 논문
  local c="$T/state/rf_replication.claim.$1"; mkdir -p "$c"
  echo 4242 > "$c/owner"; echo "$2" > "$c/owner_win"; [ -n "$3" ] && echo "$3" > "$c/owner_start"; echo "$4" > "$c/paper"; echo "$1" > "$c/slot"
  mkdir -p "$T/slots/$1"
  printf '{"status":"in_progress","slot":"%s","lane_mode":"clean","audit_retries":1,"paper":{"paper_key":"%s","url":"http://127.0.0.1:9/%s"}}\n' "$1" "$4" "$4" \
    > "$T/slots/$1/replication_request.json"
}

echo "=== L1 디스패처 로그 격리 ==="
mkfx l1 '[{"key":"Z1.cpu","source":"queue","meta":{"paper_title":"Value spread"}}]'
s0=$(op_sig); lane; s1=$(op_sig)
SL="$T/state/scheduler_logs/replication_auto_$(date +%Y%m%d).log"
[ "$s0" = "$s1" ] && [ -s "$SL" ] && grep -q "Z1.cpu" "$SL" && [ "$(ev slots_tick)" = "1" ] \
  && ok "L1 상태 폴더 격리 → 디스패처 로그도 격리 폴더(운영 로그 무접촉 · 판정 줄은 격리 로그에)" \
  || ng "L1 로그 격리" "op $s0→$s1 · iso=$( [ -s "$SL" ] && echo y || echo n) · tick=$(ev slots_tick)"
# 돌연변이: 구판 줄(운영 .cache 고정)을 격리 사본에 되살리면 같은 실행이 '운영' 로그를 건드린다 — 사본의 ROOT 를 격리 가짜 루트로 바꿔 운영 무접촉 유지
M="$T0/mut"; mkdir -p "$M/02_Infrastructure/ops" "$M/.cache"
cp "$LANE" "$M/02_Infrastructure/ops/rf_replication_auto.sh"; cp 02_Infrastructure/ops/refresh_barrier.sh "$M/02_Infrastructure/ops/" 2>/dev/null
"$PY" - "$M/02_Infrastructure/ops/rf_replication_auto.sh" "$ROOT" <<'PYM'
import io, sys
p, root = sys.argv[1], sys.argv[2]
s = io.open(p, encoding="utf-8").read()
new = 'LOG="${QVEST_RP_STATE_DIR:-$ROOT/.cache}/scheduler_logs/replication_auto_$(date +%Y%m%d).log"'
old = 'LOG="$ROOT/.cache/scheduler_logs/replication_auto_$(date +%Y%m%d).log"'
assert s.count(new) == 1, "치환 대상 없음"
s = s.replace(new, old)
s = s.replace('SLOTS_PY="$ROOT/02_Infrastructure/ops/rf_replication_slots.py"', 'SLOTS_PY="%s/02_Infrastructure/ops/rf_replication_slots.py"' % root)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mutated")
PYM
mkfx l1m '[{"key":"Z2.cpu","source":"queue","meta":{"paper_title":"Value spread"}}]'
env $(envs) QM_ROOT="$M" CLAUDE_PROJECT_DIR="$M" bash "$M/02_Infrastructure/ops/rf_replication_auto.sh" >> "$T/lane.out" 2>&1
ML="$M/.cache/scheduler_logs/replication_auto_$(date +%Y%m%d).log"
[ -s "$ML" ] && [ ! -s "$T/state/scheduler_logs/replication_auto_$(date +%Y%m%d).log" ] \
  && ok "L1 돌연변이(구판 줄) — 디스패처 로그가 상태 폴더 밖(루트 .cache)으로 샌다 = 시험이 결함을 잡는다" \
  || ng "L1 돌연변이" "mut_log=$( [ -s "$ML" ] && echo y || echo n) $(tail -2 "$T/lane.out" | tr '\n' ' ')"

echo "=== L2 큐가 비었다 ==="
mkfx l2 '[]'
lane
[ "$(ev slots_tick)" = "1" ] && [ "$(ev slot_launch_dry)" = "0" ] && [ "$(ev slots_tick_failed)" = "0" ] && [ ! -s "$T/issue.log" ] \
  && ok "L2 빈 큐 — 틱 1 · 발행 0 · 띄우기 0 · 틱 실패 0" || ng "L2 빈 큐" "tick=$(ev slots_tick) dry=$(ev slot_launch_dry) fail=$(ev slots_tick_failed) issue=$(cat "$T/issue.log")"

echo "=== L3 다른 기기 claim(소유자 pid 없음) ==="
mkfx l3 '[]'
mkclaim cpu1 999991 "1794010925.056" 1109.3488
slots_py tick > "$T/tick.out" 2>&1
[ ! -d "$T/state/rf_replication.claim.cpu1" ] && [ "$(ev claim_stale_reclaim)" = "1" ] && [ "$(ev claim_reclaim_incomplete)" = "0" ] \
  && grep -q "LAUNCH cpu1" "$T/tick.out" && grep -q '"in_progress"' "$T/slots/cpu1/replication_request.json" \
  && ok "L3 죽은 소유자 claim 회수 · 요청 in_progress 보존(작업자가 되살림) · cpu1 띄우기" \
  || ng "L3 회수" "claim=$( [ -d "$T/state/rf_replication.claim.cpu1" ] && echo left || echo gone) reclaim=$(ev claim_stale_reclaim) $(cat "$T/tick.out" | tr '\n' ' ')"

echo "=== L4 pid 재사용(산 프로세스 · 시작 시각 불일치) ==="
mkfx l4 '[]'
LIVE=$("$PY" -c "import os; print(os.getppid())")      # 이 시험 셸 — 살아 있다(Windows pid 는 파이썬이 본 부모)
WLIVE=$(powershell -NoProfile -Command "(Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1).Id" 2>/dev/null | tr -d '\r')
[ -n "$WLIVE" ] || WLIVE=4                                # System(pid 4) — 늘 산다
mkclaim cpu1 "$WLIVE" "1000000000.0" 2106.06164
slots_py tick > "$T/tick.out" 2>&1
[ ! -d "$T/state/rf_replication.claim.cpu1" ] && grep -q '"why": *"pid_reused"\|"why":"pid_reused"' "$T/j.jsonl" \
  && ok "L4 살아 있는 pid($WLIVE)지만 시작 시각이 다르다 → pid_reused 로 회수(다른 기기 claim 을 산 소유자로 오인 안 함)" \
  || ng "L4 pid 재사용" "claim=$( [ -d "$T/state/rf_replication.claim.cpu1" ] && echo left || echo gone) $(grep -o '"why": *"[a-z_]*"' "$T/j.jsonl" | tail -1)"

echo "=== L5 읽기 전용(R) claim 폴더 ==="
mkfx l5 '[]'
mkclaim cpu1 999992 "" 2601.04602
attrib +R "$(cygpath -w "$T/state/rf_replication.claim.cpu1")" /S /D >/dev/null 2>&1
attrib +R "$(cygpath -w "$T/state/rf_replication.claim.cpu1")\\*" /S >/dev/null 2>&1
slots_py tick > "$T/tick.out" 2>&1
[ ! -d "$T/state/rf_replication.claim.cpu1" ] && [ "$(ev claim_reclaim_incomplete)" = "0" ] \
  && ok "L5 읽기 전용 속성 claim 도 실제로 지운다(회수 미완 기록 없음)" \
  || ng "L5 읽기 전용" "claim=$( [ -d "$T/state/rf_replication.claim.cpu1" ] && echo left || echo gone) incomplete=$(ev claim_reclaim_incomplete)"

echo "=== L6 생존 소유자 장시간(상한 없음) ==="
mkfx l6 '[]'
WSELF=$("$PY" -c "
import ctypes, os
print(os.getppid())")
# 이 기기에서 확실히 산 Windows pid + 그 시작 시각(qv_lock.proc_start) — 소유자로 인정되는 claim 을 만든다
read WP WS < <("$PY" -c "
import sys; sys.path.insert(0, r'$ROOT/02_Infrastructure/ops')
import qv_lock, subprocess
out = subprocess.run(['powershell','-NoProfile','-Command','(Get-Process -Name explorer,System -ErrorAction SilentlyContinue | Select-Object -First 1).Id'],capture_output=True,text=True).stdout.strip() or '4'
p = int(out.split()[0]); st = qv_lock.proc_start(p)
print(p, st if st is not None else '')" 2>/dev/null | tr -d '\r')
mkclaim cpu1 "$WP" "$WS" 2106.06164
"$PY" -c "import os,sys,time; t=time.time()-8*3600; os.utime(sys.argv[1],(t,t))" "$T/state/rf_replication.claim.cpu1"
slots_py tick > "$T/tick.out" 2>&1; slots_py tick >> "$T/tick.out" 2>&1
[ -d "$T/state/rf_replication.claim.cpu1" ] && [ "$(ev claim_live_long)" = "1" ] && [ "$(ev claim_stale_reclaim)" = "0" ] && ! grep -q "LAUNCH cpu1" "$T/tick.out" \
  && ok "L6 산 소유자(pid $WP) 8시간 — 회수 안 함 · claim_live_long 1회(틱 2번) · 띄우기 없음" \
  || ng "L6 생존 장시간" "claim=$( [ -d "$T/state/rf_replication.claim.cpu1" ] && echo kept || echo gone) live_long=$(ev claim_live_long) reclaim=$(ev claim_stale_reclaim) ws=$WS"

echo "=== L7 측정 도중 중단 뒤 되살림 — 검증기만(엔진 보존) ==="
upath(){ cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }
mkstubs(){   # 에이전트 대역(ABORT.txt) · 검증기 대역(부른 인자 기록) — 측정 · LLM 없음
  mkdir -p "$T/bin" "$T/rbin"
  cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
d=""; prev=""
for a in "$@"; do [ "$prev" = "--add-dir" ] && d="$a"; prev="$a"; done
echo "$(date +%s) $d" >> "$STUB_AGENT_LOG"; cat > /dev/null
[ -n "$d" ] && echo "stub abort (test)" > "$d/ABORT.txt"; exit 0
S
  cat > "$T/rbin/Rscript" <<'S'
#!/usr/bin/env bash
echo "$* | REQ=${QVEST_RP_REQUEST:-} | SLOT=${RP_SLOT:-}" >> "$STUB_R_LOG"; exit 0
S
  chmod +x "$T/bin/claude" "$T/rbin/Rscript"; : > "$T/agent.log"; : > "$T/r.log"
}
l7(){   # $1 이름 · $2 표식 md5 를 맞출지(1) 어긋낼지(0)
  mkfx "$1" '[]'; mkstubs
  local W="$T/strat/RP_AUTO_V_cpu"; mkdir -p "$W"; printf 'FACTORS <- data.frame(Date = Sys.Date(), Ticker = "A", Score = 1)\n# padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding\n' > "$W/engine.R"
  local m; m=$("$PY" -c "import hashlib,sys;print(hashlib.md5(open(sys.argv[1],'rb').read()).hexdigest())" "$W/engine.R" | tr -d '\r')
  [ "$2" = "1" ] || m="0000000000000000deadbeef00000000"
  mkdir -p "$T/slots/cpu1"
  printf '{"status":"in_progress","slot":"cpu1","lane_mode":"normal","audit_retries":1,"audit_feedback":"old finding","verify_engine_md5":"%s","verify_started_at":"2026-11-07T09:00:00+0900","paper":{"paper_key":"V.cpu","paper_title":"Value spread","url":"http://127.0.0.1:9/V.cpu"}}\n' "$m" \
    > "$T/slots/cpu1/replication_request.json"
  L7PATH="$(upath "$T/rbin"):$(upath "$T/bin"):$PATH"
  L7SKIP=""; if [ "$(PATH="$L7PATH"; hash -r; command -v Rscript)" != "$(upath "$T/rbin")/Rscript" ]; then L7SKIP="SKIP_PATH"; return; fi
  env $(envs) RP_SLOT=cpu1 RF_CLAUDE_BIN="$T/bin/claude" STUB_AGENT_LOG="$T/agent.log" STUB_R_LOG="$T/r.log" CUDA_VISIBLE_DEVICES="" PATH="$L7PATH" \
    bash "$LANE" >> "$T/lane.out" 2>&1
}
l7 l7a 1; r="$L7SKIP"
na=$(grep -c . "$T/agent.log" 2>/dev/null | tr -d '\r')
[ "$r" != "SKIP_PATH" ] && [ "${na:-0}" = "0" ] && [ "$(ev verify_only_retry)" = "1" ] && grep -q "rf_replication_verify.R" "$T/r.log" \
  && ok "L7a 검증기 시작 표식 + 엔진 지문 같음 → verify_interrupted · 에이전트 0회 · 검증기만" \
  || ng "L7a 측정 중단 되살림" "skip=$r agent=$na vo=$(ev verify_only_retry) r=$(head -c 200 "$T/r.log") $(tail -3 "$T/lane.out" | tr '\n' ' ')"
l7 l7b 0; r="$L7SKIP"
na=$(grep -c . "$T/agent.log" 2>/dev/null | tr -d '\r')
[ "$r" != "SKIP_PATH" ] && [ "${na:-0}" -ge 1 ] && [ "$(ev verify_only_retry)" = "0" ] \
  && ok "L7b 엔진 지문 다름 → 종전 경로(에이전트 착수) — 표식이 다른 엔진을 검증기만으로 보내지 않는다" \
  || ng "L7b 지문 불일치" "skip=$r agent=$na vo=$(ev verify_only_retry) $(tail -3 "$T/lane.out" | tr '\n' ' ')"

printf '{"test":"scn_repl_lane","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
