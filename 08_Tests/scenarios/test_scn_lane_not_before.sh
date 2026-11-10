#!/usr/bin/env bash
#==============================================================================
# test_scn_lane_not_before.sh — 충실구현 레인 시작 관문(not_before) · 1슬롯 구성 · 감시기 오경보 양성 대조
#   (도훈 11-10 REPLICATION-LANE-RESTART-SLOTS-20261110 "충실구현레인 리셋 뒤 1슬롯 켜")
#   G1 관문 전 디스패처(foreground) — 0 종료 · 틱 · 발행 · 작업자 · 에이전트 0 / G2 관문 전 슬롯 작업자 — claim · 에이전트 0 · 요청 그대로 /
#   G3 관문 전 구판 단일 슬롯 — claim · 에이전트 0 / G4 관문 뒤 — 종전대로 디스패치 / G5 해석 불가 · 시간대 없음 · 숫자 = 닫힘 /
#   G6 키 없음 · 빈 값 = 종전 / C1 설정 CLI config not-before(값 검사 · 거부 시 무변경 · clear) · enable --cpu 0 --gpu 1 /
#   S1 1슬롯({"cpu":0,"gpu":1}) — 논문 셋 대기 → 슬롯 1 · 발행 1 · 에이전트 1 · CPU 논문도 받는다 · 인계함 GPU 논문 우선 · 임대 중 새 착수 보류 /
#   F1 감시기 사본 — 작업 켜짐 + 관문 대기(틱 래퍼 실제 실행) → replication_lane 이상 0 · 양방향(로그 없음 → lane_alive · rc=1 줄 → lane_errors) /
#   M1 돌연변이(관문 뗀 사본) → 관문 전에 일한다(검출)
#   격리: 임시 루트 · QVEST_RP_* · 갱신 잠금 경로 · 후보 · 발행 대역 · 에이전트 대역 · 감시 상태 · task_health 경로. 운영 설정 · 요청 · claim · 로그 무접촉.
#   교체 전 시험 = QVEST_TEST_LANE_SH · QVEST_TEST_SLOTS_PY 로 후보 사본을 가리킨다(운영은 미설정 = 저장소 정본).
#==============================================================================
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
BASH_BIN="${BASH:-bash}"
LANE="${QVEST_TEST_LANE_SH:-$ROOT/02_Infrastructure/ops/rf_replication_auto.sh}"
SLOTS_SRC="${QVEST_TEST_SLOTS_PY:-$ROOT/02_Infrastructure/ops/rf_replication_slots.py}"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T0="$(cygpath -m "$(mktemp -d)" 2>/dev/null)"; [ -n "$T0" ] || T0="$(mktemp -d)"
upath(){ cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }
trap 'rm -rf "$T0"' EXIT
CFG_MD5_0=$(md5sum "$ROOT/06_Registry/reinforce_auto_config.json" | cut -d' ' -f1)

# 설정 CLI 후보는 qv_lock · rf_compute_class 옆에서 돈다(같은 폴더 import)
mkdir -p "$T0/ops"
cp "$SLOTS_SRC" "$T0/ops/rf_replication_slots.py"
cp "$ROOT/02_Infrastructure/ops/qv_lock.py" "$ROOT/02_Infrastructure/ops/rf_compute_class.py" "$T0/ops/"
NB="2026-11-13T19:10:00+09:00"
NB_EPOCH=$("$PY" -c "import datetime as d;print(int(d.datetime.fromisoformat('$NB').timestamp()))" | tr -d '\r')
BEFORE=$((NB_EPOCH - 3600)); AFTER=$((NB_EPOCH + 60))

# 고정물 — $1 이름 · $2 slots JSON(빈 값 = 키 없음) · $3 not_before JSON 값(빈 값 = 키 없음 · 예 '"2026-…"' · '12345' · '""')
mkfx(){
  T="$T0/$1"; mkdir -p "$T/bin" "$T/state" "$T/slots" "$T/strat"
  "$PY" -X utf8 - "$ROOT/06_Registry/reinforce_auto_config.json" "$T/cfg.json" "${2:-}" "${3:-}" <<'PYC'
import io, json, sys
src, dst, slots, nb = sys.argv[1:5]
c = json.load(io.open(src, encoding="utf-8"))
rl = {"enabled": True, "gpu_lease": {"default_cap_hours": 12, "max_cap_hours": 12}}
if slots:
    rl["slots"] = json.loads(slots)
if nb:
    rl["not_before"] = json.loads(nb)
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
  cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
d=""; prev=""
for a in "$@"; do [ "$prev" = "--add-dir" ] && d="$a"; prev="$a"; done
echo "$(date +%s) $d" >> "$STUB_AGENT_LOG"
cat > /dev/null
[ -n "$d" ] && echo "stub abort (test)" > "$d/ABORT.txt"
exit 0
S
  chmod +x "$T/bin/claude"
  : > "$T/j.jsonl"; : > "$T/agent.log"; : > "$T/issue.log"; : > "$T/lane.out"
}
lane(){   # $1 = 레인 스크립트 · 나머지 = 추가 환경(VAR=값 …)
  local sh="$1"; shift
  env QM_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$ROOT" QVEST_PY="$PY" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" \
      QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" QVEST_RP_REQUEST="$T/legacy_req.json" QVEST_RP_CLAIM="$T/state/rf_replication.claim" \
      QVEST_RP_WDIR_BASE="$T/strat" QVEST_GPU_LEASE="$T/state/gpu_lease.json" QVEST_RP_CANDIDATES_JSON="$T/cands.json" \
      QVEST_RP_ISSUE_CMD="$T/issue_stub.py" STUB_LOG="$T/issue.log" QM_REFRESH_LOCKDIR="$T/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$T/writer.lock" \
      RF_CLAUDE_BIN="$T/bin/claude" STUB_AGENT_LOG="$T/agent.log" CUDA_VISIBLE_DEVICES="" PATH="$(upath "$T/bin"):$PATH" \
      QVEST_TG_DRY_RUN=1 "$@" "$BASH_BIN" "$sh" >> "$T/lane.out" 2>&1
}
ev(){ "$PY" -c "
import io,json,sys
n=0
for l in io.open(sys.argv[1],encoding='utf-8'):
    try: r=json.loads(l)
    except Exception: continue
    if r.get('event')==sys.argv[2] and (sys.argv[3]=='*' or r.get('slot')==sys.argv[3] or r.get('state')==sys.argv[3]): n+=1
print(n)" "$T/j.jsonl" "$1" "${2:-*}" 2>/dev/null | tr -d '\r'; }
rqf(){ "$PY" -c "
import io,json,sys
try: d=json.load(io.open(sys.argv[1],encoding='utf-8'))
except Exception: d={}
v=d
for k in sys.argv[2].split('.'): v=(v or {}).get(k) if isinstance(v,dict) else None
print(v if v is not None else '')" "$1" "$2" 2>/dev/null | tr -d '\r'; }
rq(){ rqf "$T/slots/$1/replication_request.json" "$2"; }
putreq(){ mkdir -p "$T/slots/$1"
  printf '{"status":"%s","slot":"%s","lane_mode":"normal","paper":{"paper_key":"%s","paper_title":"%s","url":"http://127.0.0.1:9/%s"}}\n' \
    "${4:-pending}" "$1" "$2" "$3" "$2" > "$T/slots/$1/replication_request.json"; }
nl_(){ local n; n=$(grep -c . "$1" 2>/dev/null | tr -d '\r'); echo "${n:-0}"; }
slots_cli(){ env QM_ROOT="$ROOT" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$T/state" QVEST_RP_SLOT_DIR="$T/slots" QVEST_RP_JLOG="$T/j.jsonl" \
             QVEST_RP_REQUEST="$T/legacy_req.json" QVEST_RP_CLAIM="$T/state/rf_replication.claim" QVEST_GPU_LEASE="$T/state/gpu_lease.json" \
             "$PY" -X utf8 "$T0/ops/rf_replication_slots.py" --root "$ROOT" "$@"; }

echo "=== G. 시작 관문 ==="
# G1 관문 전 디스패처 — 띄우기 방식 foreground(실제로 작업자를 돌리는 방식)여도 아무것도 안 한다
mkfx g1 '{"cpu":0,"gpu":1}' "\"$NB\""
lane "$LANE" QVEST_RP_NOW_EPOCH="$BEFORE" QVEST_RP_LAUNCH=foreground; rc=$?
[ "$rc" = "0" ] && [ "$(ev halt_not_before wait)" = "1" ] && [ "$(ev slots_tick)" = "0" ] && [ "$(nl_ "$T/issue.log")" = "0" ] && [ "$(nl_ "$T/agent.log")" = "0" ] \
  && [ ! -e "$T/slots/gpu1" ] && [ "$(ls -A "$T/state" 2>/dev/null | paste -sd, -)" = "scheduler_logs" ] && [ -z "$(ls -A "$T/state/scheduler_logs" 2>/dev/null)" ] && grep -q '시작 관문 대기' "$T/lane.out" \
  && ok "G1 관문 전 디스패처 — rc 0 · halt_not_before 1 · 틱 0 · 발행 0 · 에이전트 0 · 슬롯 파일 · claim 무생성(상태 폴더엔 빈 로그 폴더뿐) · 대기 줄 표준 출력" \
  || ng "G1 관문 전 디스패처" "rc=$rc nb=$(ev halt_not_before wait) tick=$(ev slots_tick) agent=$(nl_ "$T/agent.log") $(tail -3 "$T/lane.out" | tr '\n' ' ')"
"$PY" -c "
import io,json,sys
r=[json.loads(l) for l in io.open(sys.argv[1],encoding='utf-8') if l.strip()]
sys.exit(0 if len(r)==1 and r[0]['event']=='halt_not_before' and r[0].get('not_before','').startswith('2026-11-13T19:10:00') and int(r[0].get('wait_s'))==3600 else 1)" "$T/j.jsonl" \
  && ok "G1 저널 = halt_not_before 한 줄뿐(not_before · wait_s=3600 · 다른 사건 0)" || ng "G1 저널" "$(cat "$T/j.jsonl")"
# G2 관문 전 슬롯 작업자(RP_SLOT=gpu1 · 대기 요청 있음)
mkfx g2 '{"cpu":0,"gpu":1}' "\"$NB\""
putreq gpu1 A.cpu "Momentum crash factor" pending
lane "$LANE" QVEST_RP_NOW_EPOCH="$BEFORE" RP_SLOT=gpu1; rc=$?
[ "$rc" = "0" ] && [ "$(ev halt_not_before wait)" = "1" ] && [ "$(nl_ "$T/agent.log")" = "0" ] && [ "$(ev start)" = "0" ] && [ ! -d "$T/state/rf_replication.claim.gpu1" ] \
  && [ "$(rq gpu1 status)" = "pending" ] && [ -z "$(ls -A "$T/strat" 2>/dev/null)" ] \
  && ok "G2 관문 전 슬롯 작업자 — 에이전트 0 · start 0 · claim 무생성 · 요청 pending 그대로 · 작업 디렉터리 무생성" \
  || ng "G2 관문 전 작업자" "rc=$rc nb=$(ev halt_not_before wait) agent=$(nl_ "$T/agent.log") st=$(rq gpu1 status)"
# G3 관문 전 구판 단일 슬롯(slots 키 없음 · 구판 요청 pending)
mkfx g3 '' "\"$NB\""
printf '%s\n' '{"status":"pending","lane_mode":"normal","paper":{"paper_key":"L.p","paper_title":"Value spread","url":"http://127.0.0.1:9/L"}}' > "$T/legacy_req.json"
lane "$LANE" QVEST_RP_NOW_EPOCH="$BEFORE"; rc=$?
[ "$rc" = "0" ] && [ "$(ev halt_not_before wait)" = "1" ] && [ "$(nl_ "$T/agent.log")" = "0" ] && [ ! -d "$T/state/rf_replication.claim" ] \
  && [ "$(rqf "$T/legacy_req.json" status)" = "pending" ] && [ "$(ev halt_refresh_lock)" = "0" ] \
  && ok "G3 관문 전 구판 단일 슬롯 — 에이전트 0 · claim 무생성 · 구판 요청 pending 그대로(리프레시 배리어보다 앞)" \
  || ng "G3 구판" "rc=$rc agent=$(nl_ "$T/agent.log") st=$(rqf "$T/legacy_req.json" status)"
# G4 관문 뒤 — 종전대로
mkfx g4 '{"cpu":0,"gpu":1}' "\"$NB\""
lane "$LANE" QVEST_RP_NOW_EPOCH="$AFTER" QVEST_RP_LAUNCH=print
[ "$(ev halt_not_before)" = "0" ] && [ "$(ev slots_tick)" = "1" ] && [ "$(ev slot_launch_dry)" = "1" ] && [ "$(rq gpu1 paper.paper_key)" = "A.cpu" ] \
  && ok "G4 관문 뒤 — halt_not_before 0 · 틱 1 · 띄우기 1(gpu1 ← A.cpu)" || ng "G4 관문 뒤" "nb=$(ev halt_not_before) tick=$(ev slots_tick) dry=$(ev slot_launch_dry) gpu1=$(rq gpu1 paper.paper_key)"
# G5 해석 불가 = 닫힘(시각과 무관 — 관문 뒤 시각으로 돌려도 닫힌다)
for v in '"tomorrow 19시"' '"2026-11-13T19:10:00"' '12345' '{"at":"x"}'; do
  mkfx g5 '{"cpu":0,"gpu":1}' "$v"
  lane "$LANE" QVEST_RP_NOW_EPOCH="$AFTER" QVEST_RP_LAUNCH=print; rc=$?
  [ "$rc" = "0" ] && [ "$(ev halt_not_before invalid)" = "1" ] && [ "$(ev slots_tick)" = "0" ] && [ "$(nl_ "$T/issue.log")" = "0" ] \
    && ok "G5 not_before=$v — 닫힘(halt_not_before state=invalid · 틱 0)" || ng "G5 $v" "rc=$rc inv=$(ev halt_not_before invalid) tick=$(ev slots_tick)"
  rm -rf "$T"
done
# G6 키 없음 · 빈 문자열 · null = 종전
for v in '' '""' 'null'; do
  mkfx g6 '{"cpu":0,"gpu":1}' "$v"
  lane "$LANE" QVEST_RP_NOW_EPOCH="$BEFORE" QVEST_RP_LAUNCH=print
  [ "$(ev halt_not_before)" = "0" ] && [ "$(ev slots_tick)" = "1" ] && ok "G6 not_before=${v:-<키 없음>} — 관문 없음(종전 · 틱 1)" || ng "G6 ${v:-none}" "nb=$(ev halt_not_before) tick=$(ev slots_tick)"
  rm -rf "$T"
done

echo "=== C. 설정 CLI ==="
mkfx c1 '{"cpu":2,"gpu":1}' ''
slots_cli config not-before "$NB" >/dev/null 2>&1; r1=$?
v1=$(rqf "$T/cfg.json" replication_lane.not_before)
m0=$(md5sum "$T/cfg.json" | cut -d' ' -f1)
slots_cli config not-before "2026-11-13T19:10:00" >/dev/null 2>&1; r2=$?
slots_cli config not-before "내일" >/dev/null 2>&1; r3=$?
m1=$(md5sum "$T/cfg.json" | cut -d' ' -f1)
[ "$r1" = "0" ] && [ "$v1" = "2026-11-13T19:10:00+09:00" ] && [ "$r2" = "2" ] && [ "$r3" = "2" ] && [ "$m0" = "$m1" ] \
  && ok "C1 config not-before — 시간대 있는 값 저장 · 시간대 없음 · 해석 불가 = rc 2 + 설정 무변경" || ng "C1 not-before" "r1=$r1 v1=$v1 r2=$r2 r3=$r3 same=$([ "$m0" = "$m1" ] && echo 1 || echo 0)"
slots_cli config enable --cpu 0 --gpu 1 >/dev/null 2>&1; r4=$?
lane "$LANE" QVEST_RP_NOW_EPOCH="$BEFORE" QVEST_RP_LAUNCH=print
[ "$r4" = "0" ] && [ "$(rqf "$T/cfg.json" replication_lane.slots.cpu)" = "0" ] && [ "$(rqf "$T/cfg.json" replication_lane.slots.gpu)" = "1" ] \
  && [ "$(rqf "$T/cfg.json" replication_lane.not_before)" = "$NB" ] && [ "$(ev halt_not_before wait)" = "1" ] \
  && ok "C1 config enable --cpu 0 --gpu 1 — slots {cpu 0 · gpu 1} · not_before 보존 · CLI 로 쓴 값을 레인 관문이 그대로 읽는다(대기)" \
  || ng "C1 enable 0/1" "r4=$r4 slots=$(rqf "$T/cfg.json" replication_lane.slots) nb=$(ev halt_not_before wait)"
slots_cli config not-before clear >/dev/null 2>&1; r5=$?
slots_cli config show 2>/dev/null | grep -q '"not_before": null' && [ "$r5" = "0" ] && [ -z "$(rqf "$T/cfg.json" replication_lane.not_before)" ] \
  && ok "C1 config not-before clear — 키 제거 · show 에 not_before 표기" || ng "C1 clear" "r5=$r5 $(slots_cli config show 2>&1)"

echo "=== S. 1슬롯 구성 {\"cpu\":0,\"gpu\":1} ==="
mkfx s1 '{"cpu":0,"gpu":1}' ''
n_slots=$(slots_cli status --json 2>/dev/null | "$PY" -c "import sys,json;print(','.join(r['slot'] for r in json.load(sys.stdin)['slots']))" | tr -d '\r')
lane "$LANE" QVEST_RP_LAUNCH=foreground
[ "$n_slots" = "gpu1" ] && [ "$(ev slots_tick)" = "1" ] && [ "$(nl_ "$T/issue.log")" = "1" ] && [ "$(nl_ "$T/agent.log")" = "1" ] && [ "$(ev start gpu1)" = "1" ] \
  && [ "$(rq gpu1 paper.paper_key)" = "A.cpu" ] && [ ! -e "$T/slots/cpu1" ] \
  && ok "S1 논문 셋 대기 → 슬롯 1(gpu1) · 발행 1 · 에이전트 1 · CPU 논문(A.cpu)도 GPU 슬롯이 받는다 · cpu 슬롯 무생성" \
  || ng "S1 1슬롯" "slots=$n_slots tick=$(ev slots_tick) issue=$(nl_ "$T/issue.log") agent=$(nl_ "$T/agent.log") gpu1=$(rq gpu1 paper.paper_key) $(tail -2 "$T/lane.out" | tr '\n' ' ')"
# 같은 틱 · 다음 틱 — 슬롯이 바쁜 동안(요청 busy) 새 발행 없음 = 동시 실행 1
putreq gpu1 A.cpu "Momentum crash factor" in_progress; : > "$T/issue.log"
lane "$LANE" QVEST_RP_LAUNCH=print
[ "$(nl_ "$T/issue.log")" = "0" ] && [ "$(rq gpu1 paper.paper_key)" = "A.cpu" ] && ok "S1 슬롯이 논문을 든 동안 다음 틱은 새 논문을 발행하지 않는다(동시 1)" || ng "S1 바쁜 슬롯" "issue=$(nl_ "$T/issue.log")"
# 인계함의 GPU 논문(구 CPU 슬롯이 넘긴 것)이 큐보다 먼저 — torch 논문이 굶지 않는다
mkfx s2 '{"cpu":0,"gpu":1}' ''
mkdir -p "$T/slots/_gpu_inbox"
printf '%s\n' '{"status":"pending","slot":"cpu2","lane_mode":"normal","handoff":{"from_slot":"cpu2","at":"2026-11-01T00:00:00+0900","reason":"t"},"paper":{"paper_key":"H.gpu","paper_title":"LSTM forecasting","url":"http://127.0.0.1:9/H"}}' \
  > "$T/slots/_gpu_inbox/H.gpu_test.json"
lane "$LANE" QVEST_RP_LAUNCH=print
[ "$(rq gpu1 paper.paper_key)" = "H.gpu" ] && [ "$(ev gpu_inbox_taken gpu1)" = "1" ] && [ "$(nl_ "$T/issue.log")" = "0" ] \
  && ok "S2 인계함 GPU 논문(H.gpu) 먼저 — gpu_inbox_taken 1 · 큐 발행 0" || ng "S2 인계함" "gpu1=$(rq gpu1 paper.paper_key) taken=$(ev gpu_inbox_taken gpu1)"
# GPU 임대 중 — 1슬롯이면 CPU 논문 새 착수도 보류된다(사실 기록 · 임대 상한 12h 가 끝)
mkfx s3 '{"cpu":0,"gpu":1}' ''
putreq gpu1 A.cpu "Momentum crash factor" pending
env QVEST_GPU_LEASE="$T/state/gpu_lease.json" QVEST_RF_CONFIG="$T/cfg.json" "$PY" -X utf8 "$T0/ops/qv_lock.py" lease acquire --holder P2R05_measure --purpose test --json > "$T/lease.out" 2>&1
lst=$(env QVEST_GPU_LEASE="$T/state/gpu_lease.json" "$PY" "$T0/ops/qv_lock.py" lease status --json 2>/dev/null | tail -1 | tr -d '\r')
if printf '%s' "$lst" | grep -q '"held"'; then
  lane "$LANE" RP_SLOT=gpu1
  [ "$(ev halt_gpu_lease gpu1)" = "1" ] && [ "$(nl_ "$T/agent.log")" = "0" ] && [ "$(rq gpu1 status)" = "pending" ] \
    && ok "S3 GPU 임대 중 — 1슬롯 작업자는 CPU 논문도 새 착수 보류(halt_gpu_lease · 에이전트 0 · 요청 보존)" || ng "S3 임대" "lease=$(ev halt_gpu_lease gpu1) agent=$(nl_ "$T/agent.log")"
else ng "S3 임대 고정물 — 임대를 못 잡았다" "$lst $(head -c 200 "$T/lease.out")"; fi

echo "=== F. 감시기 사본 — 작업 켜짐 + 관문 대기 ==="
W="$T0/wroot"; mkdir -p "$W/02_Infrastructure/programs" "$W/02_Infrastructure/ops" "$W/06_Registry/replication_slots" "$W/.cache/scheduler_logs"
cp "$ROOT/02_Infrastructure/programs/superfan_watch.py" "$W/02_Infrastructure/programs/"
cp "$ROOT/02_Infrastructure/ops/reinforce_auto_tick.sh" "$ROOT/02_Infrastructure/ops/refresh_barrier.sh" "$W/02_Infrastructure/ops/"
cp "$LANE" "$W/02_Infrastructure/ops/rf_replication_auto.sh"
"$PY" -X utf8 - "$ROOT/06_Registry/superfan_components.json" "$W/reg.json" "$W/th.json" <<'PYC'
import io, json, sys, os, datetime as dt, socket
reg = json.load(io.open(sys.argv[1], encoding="utf-8"))
reg["components"] = [c for c in reg["components"] if c["id"] == "replication_lane"]
io.open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(reg, ensure_ascii=False))
th = {"measured_on": os.environ.get("COMPUTERNAME") or socket.gethostname(), "measured_at": dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
      "tasks": [{"task": "Qvest_ReinforceAutoLoop", "enabled": True}]}
io.open(sys.argv[3], "w", encoding="utf-8").write(json.dumps(th))
PYC
printf '%s\n' '{"status":"adopted_by_slot","slot":"cpu1"}' > "$W/06_Registry/replication_request.json"
printf '%s\n' '{"schema":"replication_slots_status_v1","worst_status":"ok"}' > "$W/06_Registry/replication_slots/_status.json"
T="$T0/f1"; mkfx f1 '{"cpu":0,"gpu":1}' "\"$NB\""
wtick(){ env QM_ROOT="$W" CLAUDE_PROJECT_DIR="$W" QVEST_PY="$PY" QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_STATE_DIR="$W/.cache" QVEST_RP_JLOG="$T/j.jsonl" \
            QVEST_RP_NOW_EPOCH="$BEFORE" QM_REFRESH_LOCKDIR="$T/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$T/writer.lock" RF_CLAUDE_BIN="$T/bin/claude" \
            STUB_AGENT_LOG="$T/agent.log" PATH="$(upath "$T/bin"):$PATH" QVEST_TG_DRY_RUN=1 "$BASH_BIN" "$W/02_Infrastructure/ops/reinforce_auto_tick.sh" >/dev/null 2>&1; }
# 작업 상태 = '켜짐' — 감시기의 직접 조회 이음새(QVEST_SUPERFAN_TASK_QUERY_CMD · 이름|상태 줄)와 task_health 경로 둘 다 고정(운영 스케줄러에 묻지 않는다)
printf '%s\n' 'import sys' 'for n in sys.argv[1:]: print("%s|Ready" % n)' > "$W/fake_tq.py"
TQ_PY="$(cygpath -m "$PY" 2>/dev/null || printf '%s' "$PY")"; TQ_PY="${TQ_PY//\\//}"
case "$TQ_PY $W" in *" "*" "*) TQ_CMD=""; ng "F 고정물 — 파이썬 · 임시 경로에 공백(이음새는 공백 분리)" "$TQ_PY $W" ;; *) TQ_CMD="$TQ_PY $W/fake_tq.py" ;; esac
wscan(){ env QVEST_SUPERFAN_TASK_QUERY_CMD="$TQ_CMD" QVEST_SUPERFAN_REGISTRY_PATH="$W/reg.json" QVEST_SUPERFAN_WATCH_PATH="$W/.cache/sw.json" QVEST_SUPERFAN_TASK_HEALTH_PATH="$W/th.json" \
            QVEST_ALERT_DEDUP_PATH="$W/.cache/dd.json" "$PY" -X utf8 "$W/02_Infrastructure/programs/superfan_watch.py" scan --component replication_lane --quiet >/dev/null 2>&1
         "$PY" -c "
import io,json,sys
W=json.load(io.open(sys.argv[1],encoding='utf-8'))
o=[a for a in W.get('anomalies',{}).values() if a['component']=='replication_lane' and a['status']=='open']
print(len(o), ','.join(sorted(set(a['rule'] for a in o))))" "$W/.cache/sw.json" 2>/dev/null | tr -d '\r'; }
wtick; wtick
TL="$W/.cache/scheduler_logs/reinforce_auto_$(date +%Y%m%d).log"
F1=$(wscan)
[ -s "$TL" ] && grep -q '\[rp_auto\] halt_not_before' "$TL" && grep -q '시작 관문 대기' "$TL" && grep -q 'tick 종료 rc=0' "$TL" && [ "$(nl_ "$T/agent.log")" = "0" ] \
  && [ "${F1%% *}" = "0" ] \
  && ok "F1 작업 켜짐 + 관문 대기(틱 래퍼 2회 실제 실행) — 일별 틱 로그 신선 · 대기 줄 기록 · 에이전트 0 · 감시기 replication_lane 열린 이상 0" \
  || ng "F1 관문 대기 오경보" "scan='$F1' agent=$(nl_ "$T/agent.log") $(tail -4 "$TL" 2>/dev/null | tr '\n' ' ')"
# 양방향 — 같은 감시기 · 같은 등록부가 진짜 고장은 잡는다
echo "=== $(date -Iseconds) tick 종료 rc=1 ===" >> "$TL"
F2=$(wscan)
case "$F2" in *lane_errors*) ok "F2 양성 대조 — 같은 로그에 'tick 종료 rc=1' → lane_errors 열림($F2)" ;; *) ng "F2 lane_errors 양성 대조" "$F2" ;; esac
for _i in 1 2 3 4 5; do mv -f "$TL" "$TL.away" 2>/dev/null; [ -e "$TL" ] || break; sleep 1; done
F3=$(wscan)
case "$F3" in *lane_alive*) ok "F3 양성 대조 — 일별 틱 로그 없음 → lane_alive 열림($F3)" ;;
  *) ng "F3 lane_alive 양성 대조" "$F3 · 로그 남음=$([ -e "$TL" ] && echo 1 || echo 0) · $(ls "$W/.cache/scheduler_logs" | paste -sd, -) · $("$PY" -c "
import io,json,sys
W=json.load(io.open(sys.argv[1],encoding='utf-8'))
print([(a['rule'],a['status'],a.get('msg','')[:60]) for a in W.get('anomalies',{}).values()])" "$W/.cache/sw.json" 2>&1 | head -c 400)" ;; esac

echo "=== M. 돌연변이 — 관문 뗀 사본 ==="
MUT="$T0/mut_lane.sh"
"$PY" -X utf8 - "$LANE" "$MUT" <<'PYC'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8", newline="").read()
a = 'case "${NB_LINE%% *}" in'
n = s.count(a)
io.open(sys.argv[2], "w", encoding="utf-8", newline="").write(s.replace(a, 'case "open" in'))
print(n)
PYC
nsub=$(grep -c 'case "open" in' "$MUT" | tr -d '\r')
mkfx m1 '{"cpu":0,"gpu":1}' "\"$NB\""
lane "$MUT" QVEST_RP_NOW_EPOCH="$BEFORE" QVEST_RP_LAUNCH=foreground
[ "$nsub" = "1" ] && [ "$(ev halt_not_before)" = "0" ] && [ "$(ev slots_tick)" = "1" ] && [ "$(nl_ "$T/agent.log")" -ge 1 ] \
  && ok "M1 관문 뗀 사본(치환 1곳 성사) — 관문 전에 틱 · 에이전트 $(nl_ "$T/agent.log")회 → 시험이 검출한다" \
  || ng "M1 돌연변이" "nsub=$nsub nb=$(ev halt_not_before) tick=$(ev slots_tick) agent=$(nl_ "$T/agent.log")"

CFG_MD5_1=$(md5sum "$ROOT/06_Registry/reinforce_auto_config.json" | cut -d' ' -f1)
[ "$CFG_MD5_0" = "$CFG_MD5_1" ] && ok "운영 설정(06_Registry/reinforce_auto_config.json) 무접촉" || ng "운영 설정이 바뀌었다"
echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"scn_lane_not_before","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
