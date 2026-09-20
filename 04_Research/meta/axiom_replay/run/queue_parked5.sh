#!/usr/bin/env bash
# queue_parked5.sh — 파킹 entry 4건을 **루프 유휴 시점**에 언파크해 정상 격자(25+칸)에 태운다.
#   도훈 지시 2026-09-18: "파킹 5건 측정 진행해. 루프는 켜지 마"
#   ★이 스크립트는 루프를 켜지도 끄지도 않는다. 2026-09-19 02:2x 에 다른 세션이 켠 루프
#     (06_Registry/reinforce_auto_config.json::paused_reason 에 사유 기록)를 그대로 둔다.
#   ★진행 중 승격 사슬(RP_20260917_105807_22632_combo_rulefast_promo2 · 09-20 00:20 개설)을 **선점하지 않는다**.
#     러너(reinforce_auto_parallel.R)는 act[[1]] = 원장 순서 최고참 active 를 집는다. 파킹 4건은 원장 idx 11·26·47·51,
#     promo2 는 idx 59 — 지금 언파크하면 08-31 entry 가 promo2 를 밀어낸다. 그래서 다음 4조건이 동시에 참일 때만 언파크:
#       enabled=true ∧ active entry 0 ∧ 러너 claim 없음 ∧ 충실구현 요청이 in_progress 아님.
#     (tick 순서: replication_auto → overlay → b1_design → b5_design → runner. 사슬이 소진되면 next_paper 가 요청을
#      pending 으로 세우고, 다음 tick 의 replication_auto 가 집기 전에(≤8분) 이 감시자가 60초 폴링으로 먼저 언파크한다.
#      lane 은 active 가 있으면 halt_reinforce_active 로 물러나고 요청은 pending 으로 보존된다.)
#   ★대상 4건 = 기저 PORT_t ∈ [-0.7, 0] 인 파킹 6건에서
#     (a) 2608.23944 중복 복제(202530 — 204546 과 같은 구현·같은 -0.408 · parked_reason "5회 반복" 소급분) 제외
#     (b) 1403.8125(165332) 제외 — base_artifacts 가 RP_20260904_163647_18444_rescued 와 **동일 디렉터리**(20260904_163647_18444).
#         구제 경로가 이미 35칸 측정(최고 2.109 B → promo3 2.567). 같은 기저를 다시 돌리면 복제 측정이다.
#   ★언파크 후 러너 처리 순서 = 원장 순서: 0831_204546 → 0904_102326(combo) → 0912_212323 → 0913_084807.
#     next_paper 는 active 가 남아 있는 동안 halt_active_exists 로 물러나므로 4건이 연속으로 돈다.
set -u
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PILOT="$ROOT/04_Research/meta/axiom_replay"
LOG="$PILOT/run/queue_parked5.log"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PY" ] || PY=python
POLL=${POLL:-60}
HEARTBEAT_S=${HEARTBEAT_S:-21600}
IDS=(RP_20260831_204546_skipped_base RP_20260904_102326_skipped_base RP_20260912_212323_skipped_base RP_20260913_084807_skipped_base)
REASON="도훈 지시 2026-09-18 — 기저 관문 반사실 측정(파킹분 기저 [-0.7,0] 고유 기저 4건). 루프 유휴 시점 투입(승격 사슬 미선점 · 루프 on/off 무변경). parked_reason 보존."

ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

# 상태 1줄: enabled active_n claim_exists claim_age_min req_status
state() {
  "$PY" - <<'PYEOF'
import io,json,os,time,subprocess
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
def J(p):
    try: return json.loads(io.open(p,"rb").read().decode("utf-8"))
    except Exception: return {}
cfg=J(R+"/06_Registry/reinforce_auto_config.json")
en=cfg.get("enabled")
led=J(R+"/06_Registry/reinforce_ledger_l1.json")
act=sum(1 for e in (led.get("entries") or []) if e.get("status")=="active")
cl=R+"/.cache/reinforce_auto.claim"     # ★디렉터리다 — owner.json(소유자) · released.json(해제 표식). 정본 = ops/rf_claim.R
ce=os.path.isdir(cl); age=round((time.time()-os.path.getmtime(cl))/60,1) if ce else 0
# ★러너(rf_claim_acquire)와 같은 해석으로 '살아 있는 claim' 을 판정한다:
#   released.json 이 있으면 해제됨 · owner pid 가 죽었으면 고아(나이 무관 회수) · claim_stale_hours(기본 6h) 초과면 회수.
#   기기 종료로 남은 고아 claim(오늘 실측: pid 17612 · 09-20 00:42 · 30h) 을 '바쁨' 으로 세면 감시자가 영원히 기다린다.
def pid_alive(pid):
    try:
        pid=int(pid)
        if pid<=0: return True   # 모르면 보수적(러너와 동일)
        # ★text=True 금지 — tasklist 출력이 cp949 라 utf-8 리더 스레드가 죽고 빈 문자열이 돌아와 '죽음' 으로 오판한다(실측 09-21)
        out=subprocess.run(["tasklist","/FI",f"PID eq {pid}","/NH"],capture_output=True,timeout=20).stdout.decode("utf-8","ignore")
        return (" %d " % pid) in (" "+" ".join(out.split())+" ")
    except Exception: return True
live=0
if ce and os.path.exists(cl+"/owner.json") and not os.path.exists(cl+"/released.json"):
    o=J(cl+"/owner.json"); stale_h=float(cfg.get("claim_stale_hours") or 6)
    live=int(pid_alive(o.get("pid") or -1) and age < stale_h*60)
req=J(R+"/06_Registry/replication_request.json").get("status") or "none"
print(en, act, live, age, req)
PYEOF
}
status_of() {
  "$PY" - "$1" <<'PYEOF'
import io,json,sys
led=json.loads(io.open("C:/Users/99922/OneDrive/Quant_Module_Moltbot/06_Registry/reinforce_ledger_l1.json","rb").read().decode("utf-8"))
for e in led.get("entries") or []:
    if e.get("base_id")==sys.argv[1]: print(e.get("status")); break
else: print("missing")
PYEOF
}
idle() { [ "$1" = "True" ] && [ "$2" = "0" ] && [ "$3" = "0" ] && [ "$5" != "in_progress" ]; }

if [ "${1:-}" = "--probe" ]; then   # 상태만 찍고 끝낸다 (검증용 · 쓰기 0)
  read -r EN ACT CLM AGE REQ <<<"$(state)"
  echo "state: enabled=$EN active=$ACT claim=$CLM(${AGE}m) req=$REQ"
  for id in "${IDS[@]}"; do echo "  $id status=$(status_of "$id")"; done
  if idle "$EN" "$ACT" "$CLM" "$AGE" "$REQ"; then echo "idle=YES"; else echo "idle=NO"; fi
  exit 0
fi

log "=== 감시 시작 · 대상 ${#IDS[@]}건 · poll=${POLL}s · pid=$$ ==="
for id in "${IDS[@]}"; do log "  대상 $id status=$(status_of "$id")"; done
last=""; t0=$(date +%s); hb=$t0
while :; do
  read -r EN ACT CLM AGE REQ <<<"$(state)"
  cur="enabled=$EN active=$ACT claim=$CLM(${AGE}m) req=$REQ"
  if [ "$cur" != "$last" ]; then log "상태 $cur"; last="$cur"; fi
  now=$(date +%s)
  if [ $((now-hb)) -ge "$HEARTBEAT_S" ]; then log "heartbeat $(( (now-t0)/3600 ))h 대기 중 · $cur"; hb=$now; fi
  if idle "$EN" "$ACT" "$CLM" "$AGE" "$REQ"; then
    sleep 15   # tick 경계 회피 — 15초 뒤 재확인
    read -r EN ACT CLM AGE REQ <<<"$(state)"
    if idle "$EN" "$ACT" "$CLM" "$AGE" "$REQ"; then
      log "유휴 확인 2회 — 언파크 착수"
      n_ok=0
      for id in "${IDS[@]}"; do
        st=$(status_of "$id")
        if [ "$st" != "parked" ]; then log "  $id status=$st — 언파크 대상 아님(건너뜀)"; continue; fi
        Rscript "$PILOT/run/unpark_entry.R" "$id" "$REASON" >>"$LOG" 2>&1 || { log "  $id 언파크 실패 rc=$?"; continue; }
        st2=$(status_of "$id")
        if [ "$st2" = "active" ]; then n_ok=$((n_ok+1)); log "  $id parked -> active 확인"; else log "  $id 쓰기 후 status=$st2 (예상 active) — 점검 필요"; fi
      done
      log "=== 언파크 완료 ${n_ok}/${#IDS[@]} · 이후는 루프의 정상 tick(8분)이 원장 순서대로 처리 ==="
      exit 0
    fi
    log "재확인에서 유휴 아님 — 계속 대기"
  fi
  sleep "$POLL"
done
