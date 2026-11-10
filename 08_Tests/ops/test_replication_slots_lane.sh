#!/usr/bin/env bash
#==============================================================================
# test_replication_slots_lane.sh — 레인 셸(rf_replication_auto.sh)의 다중 슬롯 배선 양성 대조 (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)
#   판정 로직(rf_replication_slots.py)은 test_replication_slots.py 가 잰다. 여기는 셸이 그 판정을 **실제로 타는지** — 디스패처가 작업자를 띄우고,
#   작업자가 슬롯 경로 · 논문 잠금 · 등급 관문 · GPU 임대를 지나는지 — 를 레인을 진짜로 돌려 잰다(에이전트 = 대역 · 측정 없음 · GPU 미사용).
#   D1 디스패처(print) — 등급별 발행 · 3슬롯 띄우기 기록 · 구판 요청 무접촉 / D2 스위치 꺼짐 = 디스패치 없음 / D3 구판 설정(slots 없음) = 디스패치 없음 /
#   W1 같은 슬롯 작업자 3개 동시 = 에이전트 1회(claim) / W2 CPU 슬롯의 GPU 논문 = 에이전트 전에 인계(에이전트 0회) /
#   W3 측정 직전 관문(함수 격리 — torch 엔진 = verify-only 인계 · 아니면 통과 · 뮤테이션) / W4 GPU 슬롯의 인계분 = 에이전트 없이 검증기만(슬롯 요청 경로 전달) /
#   W5 같은 논문을 다른 슬롯이 쥐면 착수 안 함 / W6 GPU 임대 = GPU 슬롯 새 착수 보류 · 연쇄(깊이 ≥ 1)는 진행 /
#   W7 끝까지(foreground) — 디스패처 → 작업자 2개 → 슬롯 로그 · 요청 · claim 해제 · 저널 slot 필드
#   격리: QVEST_RP_*(설정 · 상태 · 슬롯 요청 · 저널 · 구판 요청/claim · 작업 디렉터리) · QVEST_GPU_LEASE · 갱신 잠금 경로 · 후보 · 발행 대역 ·
#   에이전트 대역(RF_CLAUDE_BIN) · CUDA_VISIBLE_DEVICES 빈 값. 운영 요청 · claim · 재구현 대기열 · 레인 로그 무접촉.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
LANE=02_Infrastructure/ops/rf_replication_auto.sh
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T0="$(cygpath -m "$(mktemp -d)" 2>/dev/null)"; [ -n "$T0" ] || T0="$(mktemp -d)"
upath(){ cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }   # PATH 항목은 MSYS 형(/c/…) — 'C:/…' 는 ':' 에서 갈라진다
KIDS=""
trap 'for k in $KIDS; do kill "$k" 2>/dev/null; done; rm -rf "$T0"' EXIT

# 고정물 하나 — $1 = 이름 · $2 = slots JSON(빈 값 = slots 키 없음) · $3 = replication_lane.enabled(1/0)
mkfx(){
  T="$T0/$1"; mkdir -p "$T/bin" "$T/rbin" "$T/state" "$T/slots" "$T/strat"
  "$PY" -X utf8 - "$ROOT/06_Registry/reinforce_auto_config.json" "$T/cfg.json" "${2:-}" "${3:-1}" <<'PYC'
import io, json, sys
src, dst, slots, en = sys.argv[1:5]
c = json.load(io.open(src, encoding="utf-8"))
rl = {"enabled": en == "1", "gpu_lease": {"default_cap_hours": 12, "max_cap_hours": 12}}
if slots:
    rl["slots"] = json.loads(slots)
c["replication_lane"] = rl
c["claim_stale_hours"] = 6
io.open(dst, "w", encoding="utf-8").write(json.dumps(c, ensure_ascii=False))
PYC
  printf '%s\n' '{"status":"done","paper":{"paper_key":"LEGACY.done","url":"u"}}' > "$T/legacy_req.json"
  cat > "$T/cands.json" <<'J'
[{"key":"A.cpu","source":"queue","meta":{"paper_title":"Momentum crash factor"}},
 {"key":"B.gpu","source":"queue","meta":{"paper_title":"LSTM forecasting of stock returns"}},
 {"key":"C.cpu","source":"queue","meta":{"paper_title":"Value spread"}}]
J
  cat > "$T/issue_stub.py" <<'P'
import json, os, sys, io
a = sys.argv[1:]
g = lambda f: a[a.index(f) + 1] if f in a else ""
req, key, slot = g("--req"), g("--only-key"), g("--slot")
io.open(os.environ["STUB_LOG"], "a", encoding="utf-8").write("%s %s\n" % (slot, key))
c = json.load(io.open(os.environ["QVEST_RP_CANDIDATES_JSON"], encoding="utf-8"))
m = next((x for x in c if x["key"] == key), {})
os.makedirs(os.path.dirname(req), exist_ok=True)
io.open(req, "w", encoding="utf-8").write(json.dumps({"status": "pending", "slot": slot, "lane_mode": "normal",
    "paper": {"paper_key": key, "paper_title": (m.get("meta") or {}).get("paper_title", key), "url": "http://127.0.0.1:9/" + key}}))
P
  # 에이전트 대역 — --add-dir 의 작업 디렉터리에 ABORT.txt 를 쓰고 끝난다(기동 횟수 기록 · 측정 없음)
  cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
d=""; prev=""
for a in "$@"; do [ "$prev" = "--add-dir" ] && d="$a"; prev="$a"; done
echo "$(date +%s) $d" >> "$STUB_AGENT_LOG"
cat > /dev/null
sleep "${STUB_SLEEP:-0}"
[ -n "$d" ] && echo "stub abort (test)" > "$d/ABORT.txt"
exit 0
S
  chmod +x "$T/bin/claude"
  # 검증기 대역(W4 전용 PATH) — 부른 인자 · 요청 경로 · 슬롯을 남기고 끝난다(측정 없음)
  cat > "$T/rbin/Rscript" <<'S'
#!/usr/bin/env bash
echo "$* | REQ=${QVEST_RP_REQUEST:-} | SLOT=${RP_SLOT:-}" >> "$STUB_R_LOG"
exit 0
S
  chmod +x "$T/rbin/Rscript"
  : > "$T/j.jsonl"; : > "$T/agent.log"; : > "$T/issue.log"; : > "$T/r.log"
}
lane(){   # 고정물 T 로 레인 1회 — 추가 환경은 인자로(VAR=값 …)
  env QM_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$ROOT" QVEST_PY="$PY" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" \
      QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" QVEST_RP_REQUEST="$T/legacy_req.json" QVEST_RP_CLAIM="$T/state/rf_replication.claim" \
      QVEST_RP_WDIR_BASE="$T/strat" QVEST_GPU_LEASE="$T/state/gpu_lease.json" QVEST_RP_CANDIDATES_JSON="$T/cands.json" \
      QVEST_RP_ISSUE_CMD="$T/issue_stub.py" STUB_LOG="$T/issue.log" QM_REFRESH_LOCKDIR="$T/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$T/writer.lock" \
      RF_CLAUDE_BIN="$T/bin/claude" STUB_AGENT_LOG="$T/agent.log" STUB_R_LOG="$T/r.log" CUDA_VISIBLE_DEVICES="" PATH="$(upath "$T/bin"):$PATH" \
      QVEST_TG_DRY_RUN=1 \
      "$@" bash "$LANE" >> "$T/lane.out" 2>&1
}
ev(){ "$PY" -c "
import io,json,sys
n=0
for l in io.open(sys.argv[1],encoding='utf-8'):
    try: r=json.loads(l)
    except Exception: continue
    if r.get('event')==sys.argv[2] and (sys.argv[3]=='*' or r.get('slot')==sys.argv[3]): n+=1
print(n)" "$T/j.jsonl" "$1" "${2:-*}" 2>/dev/null | tr -d '\r'; }
rq(){ "$PY" -c "
import io,json,sys
try: d=json.load(io.open(sys.argv[1],encoding='utf-8'))
except Exception: d={}
v=d
for k in sys.argv[2].split('.'): v=(v or {}).get(k) if isinstance(v,dict) else None
print(v if v is not None else '')" "$T/slots/$1/replication_request.json" "$2" 2>/dev/null | tr -d '\r'; }
putreq(){   # $1 슬롯 · $2 키 · $3 제목 · $4 상태 · $5 추가 JSON 조각(선택)
  mkdir -p "$T/slots/$1"
  printf '{"status":"%s","slot":"%s","lane_mode":"normal","paper":{"paper_key":"%s","paper_title":"%s","url":"http://127.0.0.1:9/%s"}%s}\n' \
    "${4:-pending}" "$1" "$2" "$3" "$2" "${5:+,$5}" > "$T/slots/$1/replication_request.json"
}
nagent(){ local n; n=$(grep -c . "$T/agent.log" 2>/dev/null | tr -d '\r'); echo "${n:-0}"; }
slots_py(){ env QM_ROOT="$ROOT" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" \
            QVEST_RP_REQUEST="$T/legacy_req.json" QVEST_RP_CLAIM="$T/state/rf_replication.claim" QVEST_RP_WDIR_BASE="$T/strat" \
            QVEST_GPU_LEASE="$T/state/gpu_lease.json" "$PY" -X utf8 02_Infrastructure/ops/rf_replication_slots.py --root "$ROOT" "$@"; }

echo "=== D. 디스패처 ==="
mkfx d1 '{"cpu":2,"gpu":1}' 1
t0=$(date +%s); lane QVEST_RP_LAUNCH=print; t1=$(date +%s)
[ "$(ev slots_tick)" = "1" ] && [ "$(ev slot_launch_dry)" = "3" ] && [ "$(rq gpu1 paper.paper_key)" = "B.gpu" ] && [ "$(rq cpu1 paper.paper_key)" = "A.cpu" ] \
  && [ "$(rq cpu2 paper.paper_key)" = "C.cpu" ] && grep -q '"LEGACY.done"' "$T/legacy_req.json" && [ $((t1 - t0)) -lt 60 ] \
  && ok "D1 디스패처 — 등급별 발행(B→gpu1 · A→cpu1 · C→cpu2) · 3슬롯 띄우기 기록 · 구판 요청 무접촉 · 곧바로 끝($((t1 - t0))s)" \
  || ng "D1 디스패처" "tick=$(ev slots_tick) dry=$(ev slot_launch_dry) gpu1=$(rq gpu1 paper.paper_key) $(tail -3 "$T/lane.out" | tr '\n' ' ')"
mkfx d2 '{"cpu":2,"gpu":1}' 0
lane QVEST_RP_LAUNCH=print
[ "$(ev halt_disabled)" = "1" ] && [ "$(ev slots_tick)" = "0" ] && ok "D2 레인 스위치 꺼짐 — 디스패치 없음(halt_disabled)" || ng "D2 스위치" "disabled=$(ev halt_disabled) tick=$(ev slots_tick)"
mkfx d3 '' 1
mkdir -p "$T/refresh.lock"                                   # 구판 경로는 갱신 잠금(격리)에서 멈춘다 — 운영 요청 · 재구현 대기열에 닿지 않게
lane QVEST_RP_LAUNCH=print
[ "$(ev slots_tick)" = "0" ] && [ "$(ev slot_launch_dry)" = "0" ] && [ ! -d "$T/slots/cpu1" ] && [ "$(ev halt_refresh_lock)" = "1" ] \
  && ok "D3 구판 설정(slots 키 없음) — 디스패처 무동작 · 슬롯 파일 미생성(구판 단일 슬롯 그대로)" || ng "D3 구판 설정" "tick=$(ev slots_tick)"

echo "=== W. 작업자 ==="
# W1 같은 슬롯 작업자 3개 동시 — claim 이 막는다(에이전트 1회)
mkfx w1 '{"cpu":2,"gpu":1}' 1
putreq cpu1 A.cpu "Momentum crash factor" pending
for i in 1 2 3; do lane RP_SLOT=cpu1 STUB_SLEEP=8 & KIDS="$KIDS $!"; done
wait
[ "$(nagent)" = "1" ] && [ "$(ev start cpu1)" = "1" ] && [ "$(ev aborted_by_agent cpu1)" = "1" ] && [ "$(rq cpu1 status)" = "failed_needs_session" ] \
  && [ ! -d "$T/state/rf_replication.claim.cpu1" ] \
  && ok "W1 같은 슬롯 작업자 3개 동시 — 에이전트 1회 · start 1회 · 끝나면 claim 해제(나머지 = halt_claimed $(ev halt_claimed cpu1) · 대기 $(ev no_pending_request cpu1))" \
  || ng "W1 경합" "agent=$(nagent) start=$(ev start cpu1) claimed=$(ev halt_claimed cpu1) st=$(rq cpu1 status)"
[ "$(ev start cpu1)" = "1" ] && "$PY" -c "
import io,json,sys
bad=[r for r in map(json.loads,io.open(sys.argv[1],encoding='utf-8')) if r.get('src')=='replication_auto' and r.get('slot')!='cpu1']
sys.exit(1 if bad else 0)" "$T/j.jsonl" && ok "W1 작업자 저널은 전부 slot=cpu1 필드를 단다(소진량 · 감시가 슬롯을 가른다)" || ng "W1 slot 필드"
# W2 CPU 슬롯의 GPU 논문 — 에이전트 전에 인계
mkfx w2 '{"cpu":2,"gpu":1}' 1
putreq cpu2 B.gpu "LSTM forecasting of stock returns" pending
lane RP_SLOT=cpu2
[ "$(nagent)" = "0" ] && [ "$(ev gpu_handoff_done cpu2)" = "1" ] && [ "$(ev start cpu2)" = "0" ] && [ "$(rq cpu2 status)" = "handed_off_gpu" ] \
  && ls "$T/slots/_gpu_inbox/"*.json >/dev/null 2>&1 \
  && ok "W2 CPU 슬롯의 GPU 논문(큐 메타 LSTM) — 에이전트 0회 · 인계함 1건 · cpu2 요청 = handed_off_gpu" \
  || ng "W2 오배치" "agent=$(nagent) handoff=$(ev gpu_handoff_done cpu2) st=$(rq cpu2 status) $(tail -2 "$T/lane.out" | tr '\n' ' ')"
mkfx w2b '{"cpu":2,"gpu":0}' 1
putreq cpu1 B.gpu "LSTM forecasting of stock returns" pending
lane RP_SLOT=cpu1
[ "$(ev gpu_paper_kept_no_gpu_slot cpu1)" = "1" ] && [ "$(nagent)" = "1" ] \
  && ok "W2 GPU 슬롯이 없는 설정 — 인계하지 않고 그 슬롯이 돈다(받을 자리가 없다 · 양방향)" || ng "W2 GPU 슬롯 없음" "kept=$(ev gpu_paper_kept_no_gpu_slot cpu1) agent=$(nagent)"

# W3 측정 직전 관문 — 함수 격리(에이전트가 쓴 엔진이 torch 를 부르는 경우) · 뮤테이션
mkfx w3 '{"cpu":2,"gpu":1}' 1
"$PY" - "$LANE" "$T/gate_fns.sh" <<'PYX'
import io, re, sys
s = io.open(sys.argv[1], "rb").read().decode("utf-8")
out = []
for name in ("rp_slot_handoff", "rp_slot_class", "rp_gpu_gate_pre_verify"):
    m = re.search(r"^%s\(\)\{[^\n]*\}\n" % name, s, re.M) or re.search(r"^%s\(\)\{.*?^\}\n" % name, s, re.S | re.M)   # 한 줄 함수 먼저
    out.append(m.group(0) if m else "")
io.open(sys.argv[2], "wb").write("".join(out).encode("utf-8"))
PYX
gate_run(){   # $1 함수 파일 · $2 engine.R 내용 → 결과 기록 파일
  local W="$T/strat/RP_AUTO_X_cpu"; rm -rf "$W"; mkdir -p "$W/_work" "$T/slots/cpu1"; rm -rf "$T/slots/_gpu_inbox"
  printf '%s\n' "$2" > "$W/engine.R"; printf 'import torch\n' > "$W/_work/net.py"
  putreq cpu1 X.cpu "Value spread" in_progress '"failure":""'
  ( ROOT="$ROOT"; PY="$PY"; SLOTS_PY="$ROOT/02_Infrastructure/ops/rf_replication_slots.py"; REQ="$T/slots/cpu1/replication_request.json"; WDIR="$W"
    LOG="$T/gate.log"; P_KEY=X.cpu; RP_SLOT=cpu1; RP_SLOT_CLASS=cpu
    export QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" QVEST_RP_REQUEST="$T/legacy_req.json" \
           QVEST_RP_CLAIM="$T/state/rf_replication.claim" QVEST_RP_WDIR_BASE="$T/strat" QVEST_GPU_LEASE="$T/state/gpu_lease.json" QM_ROOT="$ROOT"
    jl(){ echo "$1" >> "$T/gate_ev.log"; }
    . "$1"; rp_gpu_gate_pre_verify; echo "returned" >> "$T/gate_ev.log" ) >/dev/null 2>&1
}
if [ -s "$T/gate_fns.sh" ] && [ "$(grep -c '()' "$T/gate_fns.sh")" -ge 3 ]; then
  : > "$T/gate_ev.log"; gate_run "$T/gate_fns.sh" 'system2(PY, file.path(WDIR, "_work", "net.py"))'
  [ "$(rq cpu1 status)" = "handed_off_gpu" ] && grep -q gpu_handoff_done "$T/gate_ev.log" && ! grep -q returned "$T/gate_ev.log" \
    && "$PY" -c "import io,json,glob,sys;f=glob.glob(sys.argv[1]+'/_gpu_inbox/*.json');d=json.load(io.open(f[0],encoding='utf-8'));sys.exit(0 if d.get('failure')=='gpu_handoff' and (d.get('handoff') or {}).get('verify_only') else 1)" "$T/slots" \
    && ok "W3 측정 직전 — 엔진이 torch 스크립트를 부르면 측정하지 않고 인계(failure=gpu_handoff · verify_only) · 작업자 종료" \
    || ng "W3 torch 엔진 인계" "st=$(rq cpu1 status) ev=$(tr '\n' ' ' < "$T/gate_ev.log")"
  : > "$T/gate_ev.log"; gate_run "$T/gate_fns.sh" 'FACTORS <- data.frame()  # torch 안 씀'
  [ "$(rq cpu1 status)" = "in_progress" ] && grep -q returned "$T/gate_ev.log" && [ ! -d "$T/slots/_gpu_inbox" ] \
    && ok "W3 torch 를 안 부르는 엔진 — 관문 통과(측정으로 간다 · 양방향)" || ng "W3 CPU 엔진 통과" "st=$(rq cpu1 status) ev=$(tr '\n' ' ' < "$T/gate_ev.log")"
  sed 's/\[ "\${cl%% \*}" = "gpu" \] || return 0/return 0/' "$T/gate_fns.sh" > "$T/gate_fns_mut.sh"
  if ! cmp -s "$T/gate_fns.sh" "$T/gate_fns_mut.sh"; then
    : > "$T/gate_ev.log"; gate_run "$T/gate_fns_mut.sh" 'system2(PY, file.path(WDIR, "_work", "net.py"))'
    [ "$(rq cpu1 status)" = "in_progress" ] && grep -q returned "$T/gate_ev.log" \
      && ok "W3 뮤테이션(등급 판정 무시)판은 torch 엔진을 CPU 슬롯에서 측정하러 간다 → 위 검사가 잡는 결함" || ng "W3 뮤테이션 미검출"
  else ng "W3 뮤테이션 치환 불발(소스 텍스트)"; fi
else ng "W3 관문 함수 추출 실패" "$(head -c 200 "$T/gate_fns.sh")"; fi

# W4 GPU 슬롯이 받은 인계분 — 에이전트 없이 검증기만(슬롯 요청 경로 · 슬롯 이름 전달)
mkfx w4 '{"cpu":2,"gpu":1}' 1
mkdir -p "$T/strat/RP_AUTO_B_gpu"; printf 'import torch\n' > "$T/strat/RP_AUTO_B_gpu/net.py"
printf 'system2(PY, "net.py")\n' > "$T/strat/RP_AUTO_B_gpu/engine.R"
putreq gpu1 B.gpu "LSTM forecasting of stock returns" pending '"failure":"gpu_handoff","handoff":{"from_slot":"cpu1","verify_only":true}'
## ★검증기 대역이 PATH 에서 먼저 잡히는지 확인한 뒤에만 돌린다 — 아니면 진짜 검증기(RAWDATA 측정 · 발송)가 돈다(10-20 첫 판: Windows 형
##   경로 'C:/…' 를 PATH 에 넣어 ':' 로 갈라져 대역이 안 잡혔다 → 진짜 검증기가 engine_too_small 로 끝남 · 토큰 없음이라 발송 없음)
W4PATH="$(upath "$T/rbin"):$(upath "$T/bin"):$PATH"
if [ "$(PATH="$W4PATH"; hash -r; command -v Rscript)" = "$(upath "$T/rbin")/Rscript" ]; then
  lane RP_SLOT=gpu1 PATH="$W4PATH"
  [ "$(nagent)" = "0" ] && [ "$(ev verify_only_retry gpu1)" = "1" ] && grep -q "rf_replication_verify.R | REQ=$T/slots/gpu1/replication_request.json | SLOT=gpu1" "$T/r.log" \
    && ok "W4 gpu1 의 인계분(failure=gpu_handoff) — 에이전트 0회 · 검증기만 · 검증기에 슬롯 요청 경로(QVEST_RP_REQUEST) · RP_SLOT 전달" \
    || ng "W4 인계분 검증기만" "agent=$(nagent) vo=$(ev verify_only_retry gpu1) r=$(head -c 300 "$T/r.log") $(tail -2 "$T/lane.out" | tr '\n' ' ')"
else ng "W4 검증기 대역이 PATH 에서 안 잡힌다 — 진짜 검증기를 부르지 않으려고 건너뜀" "$(PATH="$W4PATH" command -v Rscript)"; fi

# W5 같은 논문을 다른 슬롯이 쥐었다
mkfx w5 '{"cpu":2,"gpu":1}' 1
putreq cpu1 A.cpu "Momentum crash factor" pending
slots_py paper-lock --slot cpu1 >/dev/null 2>&1
putreq cpu2 A.cpu "Momentum crash factor" pending
lane RP_SLOT=cpu2
[ "$(nagent)" = "0" ] && [ "$(ev halt_paper_locked_elsewhere cpu2)" = "1" ] && [ "$(rq cpu2 status)" = "duplicate_held_elsewhere" ] && [ "$(rq cpu1 status)" = "pending" ] \
  && ok "W5 다른 슬롯(cpu1)이 쥔 논문 — cpu2 작업자는 착수하지 않는다(에이전트 0회 · duplicate_held_elsewhere · cpu1 무접촉)" \
  || ng "W5 중복 논문" "agent=$(nagent) halt=$(ev halt_paper_locked_elsewhere cpu2) st2=$(rq cpu2 status)"

# W6 GPU 임대
mkfx w6 '{"cpu":2,"gpu":1}' 1
putreq gpu1 B.gpu "LSTM forecasting of stock returns" pending
env QVEST_GPU_LEASE="$T/state/gpu_lease.json" QVEST_RF_CONFIG="$T/cfg.json" "$PY" -X utf8 02_Infrastructure/ops/qv_lock.py lease acquire --holder P2R05_measure --purpose test --json >/dev/null 2>&1
lane RP_SLOT=gpu1
[ "$(nagent)" = "0" ] && [ "$(ev halt_gpu_lease gpu1)" = "1" ] && [ "$(rq gpu1 status)" = "pending" ] \
  && ok "W6 GPU 임대 중 — GPU 슬롯 새 착수 보류(에이전트 0회 · 요청 pending 보존)" || ng "W6 임대 보류" "agent=$(nagent) halt=$(ev halt_gpu_lease gpu1) st=$(rq gpu1 status)"
lane RP_SLOT=gpu1 RP_CHAIN_DEPTH=1
[ "$(nagent)" = "1" ] && [ "$(ev start gpu1)" = "1" ] && ok "W6 진행 중 연쇄(깊이 1)는 임대 중에도 끝까지 간다(양방향)" || ng "W6 연쇄 진행" "agent=$(nagent) start=$(ev start gpu1)"

# W7 끝까지 — 디스패처(foreground) → 작업자 2개
mkfx w7 '{"cpu":1,"gpu":1}' 1
lane QVEST_RP_LAUNCH=foreground
[ "$(ev slot_worker_done)" = "2" ] && [ "$(nagent)" = "2" ] && [ "$(rq cpu1 status)" = "failed_needs_session" ] && [ "$(rq gpu1 status)" = "failed_needs_session" ] \
  && [ "$(rq cpu1 failure)" = "agent_abort" ] && ls "$T/state/scheduler_logs/"replication_auto_*_cpu1.log >/dev/null 2>&1 \
  && ls "$T/state/scheduler_logs/"replication_auto_*_gpu1.log >/dev/null 2>&1 && [ ! -d "$T/state/rf_replication.claim.cpu1" ] && [ ! -d "$T/state/rf_replication.claim.gpu1" ] \
  && grep -q '"LEGACY.done"' "$T/legacy_req.json" \
  && ok "W7 디스패처 → 작업자 2개(cpu1 · gpu1) — 각자 슬롯 요청 · 슬롯 로그 · 에이전트 1회씩 · claim 해제 · 구판 요청 무접촉" \
  || ng "W7 끝까지" "done=$(ev slot_worker_done) agent=$(nagent) c=$(rq cpu1 status) g=$(rq gpu1 status) $(tail -3 "$T/lane.out" | tr '\n' ' ')"

# W8 논문별 측정 축 덮어쓰기(main 5170d410d · THGNN-AXIS-K200KQ150-20261020)가 슬롯 경로에서도 칸마다 그대로 적용되는가
#   검증기의 .BASE_ARGS + 덮어쓰기 블록을 원문에서 떼어 슬롯 작업자 환경(RP_SLOT · QVEST_RP_REQUEST = 슬롯 요청)으로 실행한다(측정 없음).
#   덮어쓰기 키 = 논문 키(RP_KEY = 레인 P_KEY — 슬롯과 무관) · 대표 · 변형 측정이 같은 .BASE_ARGS(변형은 modifyList 로 축 키를 건드리지 않는다).
mkfx w8 '{"cpu":2,"gpu":1}' 1
VER=02_Infrastructure/ops/rf_replication_verify.R
"$PY" - "$VER" "$T/axo_block.R" <<'PYX'
import io, re, sys
s = io.open(sys.argv[1], "rb").read().decode("utf-8")
m = re.search(r"^\.BASE_ARGS <- list\(.*?^if \(!is\.null\(\.AXO\)\) \{.*?^\}\n", s, re.S | re.M)
io.open(sys.argv[2], "wb").write((m.group(0) if m else "").encode("utf-8"))
PYX
cat > "$T/axo_driver.R" <<'R'
a <- commandArgs(trailingOnly = TRUE); blk <- a[1]; out <- a[2]
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QVEST_CODE_ROOT"); PKEY <- Sys.getenv("RP_KEY"); URL <- "u"; TITLE <- "t"; eng <- "engine.R"; .cmsn <- NULL
.RP_SLOT <- Sys.getenv("RP_SLOT", ""); REQ <- Sys.getenv("QVEST_RP_REQUEST", "")
EV <- character(0); jlog <- function(event, ...) EV <<- c(EV, event)
fail <- function(why, detail = "") stop(paste("FAIL", why, detail))
eval(parse(blk, encoding = "UTF-8"))
writeLines(toJSON(list(universe = .BASE_ARGS$universe %||% "", start_date = .BASE_ARGS$start_date %||% "",
                       alloc = Sys.getenv("PYTORCH_CUDA_ALLOC_CONF"), ev = paste(EV, collapse = ","), slot = .RP_SLOT, req = REQ),
                  auto_unbox = TRUE), out)
R
axo(){ env QVEST_CODE_ROOT="$ROOT" RP_SLOT="$1" RP_KEY="$2" QVEST_RP_REQUEST="$T/slots/$1/replication_request.json" PYTORCH_CUDA_ALLOC_CONF= \
         Rscript "$T/axo_driver.R" "$T/axo_block.R" "$T/axo_$1_$2.json" >/dev/null 2>&1; cat "$T/axo_$1_$2.json" 2>/dev/null; }
if [ -s "$T/axo_block.R" ] && [ -f 06_Registry/replication_axis_overrides.json ]; then
  O1=$(axo gpu1 2601.04602); O2=$(axo cpu1 1801.01777); O3=$(axo cpu2 2601.04602)
  # (2026-11-10) 기대 시작일은 등록부에서 읽는다 — 10-20 도훈 지시(2005 → 2000) 뒤 고정 글자 '2005-01-01' 이 낡아 W8 이 계속 실패했다
  _w8_sd=$("$PY" -c "import json,io;print(json.load(io.open('06_Registry/replication_axis_overrides.json',encoding='utf-8'))['papers']['2601.04602']['start_date'])" 2>/dev/null | tr -d '\r')
  [ -n "$_w8_sd" ] && printf '%s' "$O1" | grep -q '"universe":"K200_KQ150"' && printf '%s' "$O1" | grep -q "\"start_date\":\"$_w8_sd\"" \
    && printf '%s' "$O1" | grep -q '"alloc":"roundup_power2_divisions:2"' && printf '%s' "$O1" | grep -q '"ev":"axis_override"' \
    && printf '%s' "$O1" | grep -q '"slot":"gpu1"' && printf '%s' "$O3" | grep -q '"universe":"K200_KQ150"' \
    && ok "W8 슬롯 작업자(gpu1 · 다른 슬롯 cpu2 도) 검증기 — 2601.04602 는 K200_KQ150 · 등록부 시작일($_w8_sd) · 할당기 처방 env 로 잰다(덮어쓰기 = 논문 키 기준 · 슬롯 무관)" \
    || ng "W8 슬롯 경로 축 덮어쓰기" "$O1 | $O3"
  printf '%s' "$O2" | grep -q '"universe":""' && printf '%s' "$O2" | grep -q '"alloc":""' && printf '%s' "$O2" | grep -q '"ev":""' \
    && ok "W8 목록에 없는 논문(1801.01777) — 축 · env 불변(활성 epoch · 양방향)" || ng "W8 음성 대조" "$O2"
  _l_ax=$(grep -n '^if (!is.null(.AXO)) {' "$VER" | head -1 | cut -d: -f1); _l_hd=$(grep -n '^res <- tryCatch(do.call(run_paper_replication, c(.BASE_ARGS,' "$VER" | head -1 | cut -d: -f1)
  _l_vr=$(grep -n '\.v1001_measure_variants(.VP, dirname(ar), as.character(AR\$run_id %||% "")\[1\], .BASE_ARGS, .pspec)' "$VER" | head -1 | cut -d: -f1)
  _mod=$(sed -n '/^\.v1001_measure_variants <- function/,/^}/p' "$VER" | sed -n '/modifyList(base_args, list(/,/)))/p')
  [ -n "$_l_ax" ] && [ -n "$_l_hd" ] && [ -n "$_l_vr" ] && [ "$_l_ax" -lt "$_l_hd" ] && [ "$_l_hd" -lt "$_l_vr" ] \
    && ! printf '%s' "$_mod" | grep -qE 'universe|start_date|data_cutoff' \
    && ok "W8 칸마다 — 덮어쓰기(행 $_l_ax) < 대표 측정(행 $_l_hd) < 변형 측정(행 $_l_vr · 같은 .BASE_ARGS · modifyList 가 축 키를 건드리지 않음)" \
    || ng "W8 칸 순서 · 변형 인자" "ax=$_l_ax hd=$_l_hd vr=$_l_vr"
else ng "W8 덮어쓰기 블록 또는 설정 파일 없음" "$(head -c 120 "$T/axo_block.R")"; fi

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"replication_slots_lane","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
