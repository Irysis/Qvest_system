#!/usr/bin/env bash
# P2R05 GPU 창 연쇄(2026-11-06 · 1계층 사이드 세션 · 도훈 10-18 'THGNN 끝난 뒤 레인 보류') — 분리 실행(_lib/detached_env.sh · 세션 밖 · 인자 없음).
#   측정 절차 · 판정과 무관(사전등록 고정 대상 아님 — GPU 배분 · 순서만). 같은 일을 하던 gpu_handover.py(10-18)는 THGNN 이 새 축 · 처음부터로 바뀌어 전제가 무효다.
#   ① THGNN(2601.04602 · 레인 gpu1) 측정 시작 대기 — 레인 저널에 T0(11-06 07:20) 뒤 gpu1 axis_override 사건(재구현 · 감사가 끝나 측정 직전).
#      감사 기각 → 재구현 연쇄는 레인 스위치 관문을 다시 지나므로, 측정이 시작되기 전에는 레인을 멈추지 않는다. 마감 START_WAIT_H 안에 없으면 아무것도 바꾸지 않고 끝.
#   ② 레인 보류 — lane_hold.py pause(진행 중 작업은 끝까지 · 새 논문 · 새 GPU 작업 없음 — CPU 슬롯 새 논문도 이 창 동안 쉰다).
#   ③ THGNN 끝 대기 — gpu1 claim 폴더 없음 2회 연속(2분 간격). 마감 END_WAIT_H 를 넘으면 워밍하지 않고 끝(레인 재개).
#   ④ 같은 데이터 배치 — 다음 'Daily Refresh v2 Done' 줄(마감 06:00 규칙 = measure.sh 와 같음) 뒤에 워밍 · 측정이 들어가게 한다
#      (워밍 센티널은 워밍 시작 · 끝 dnn_input 지문을 남기고 측정 precheck --warm-check 가 현재 지문과 대조한다 — 사이에 갱신이 끼면 측정이 거부된다).
#   ⑤ warm_cache.sh(레인 꺼짐 · GPU 게이트 마감 = 지금 + 2시간 · 실패 = 자체 알림) → rc 0 이면 notify_done.sh(분기점 1통) + measure_now_vram.sh(측정 → 평가).
#   ⑥ 끝 = 레인 재개(lane_hold.py resume — 이 스크립트가 보류를 걸었을 때만 · 성공 · 실패 무관 · trap EXIT). 강제 종료(taskkill /F)면 trap 이 안 돈다 →
#      세션이 `python lane_hold.py resume "<사유>"` 로 직접 켠다.
# 로그 = .cache/scheduler_logs/p2r05_gpu_chain_<시작일>.log(detached_env.sh 두 번째 인자로 준다)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=$ROOT/04_Research/programs/P2_DEFENSE/P2R05_distribution_target
JL=$ROOT/.cache/reinforce_auto_log.jsonl
CLAIM=$ROOT/.cache/rf_replication.claim.gpu1
REQ=$ROOT/06_Registry/replication_slots/gpu1/replication_request.json
DONE_LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
PY=$ROOT/.venv_qvest_ml/Scripts/python.exe
CFG=$ROOT/06_Registry/reinforce_auto_config.json
START_WAIT_H=18
END_WAIT_H=40
cd $ROOT || exit 2
say() { echo "== $(date +%F' '%T) [P2R05 GPU 연쇄] $*"; }
T0=2026-11-06T07:20:00     # 노트북 예약 작업 재가동 시각(원 세션 11-06) — 그 뒤 첫 gpu1 측정 시작만 센다(11-01 중단분 제외 · 연쇄를 측정 시작 뒤에 띄워도 잡힌다)
PAUSED=0
## 레인 스위치 = 설정 파일 replication_lane.enabled 를 읽어 확인한다 — lane_hold.py 의 파일 교체(os.replace)는 OneDrive 가 파일을 쥔 순간
##   WinError 5 로 실패할 수 있다(11-06 session_resume.json 실측). 종료 코드가 아니라 결과 값으로 판정하고 30초 간격 최대 20회 다시 한다.
lane_enabled() { "$PY" -X utf8 -c "import io,json,sys;print(json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))['replication_lane'].get('enabled'))" "$CFG" 2>/dev/null | tr -d '\r'; }   # 경로는 인자로 — MSYS 는 인자만 C:/ 로 바꾼다(-c 문자열 안 /c/ 경로는 Windows 파이썬이 못 연다)
lane_set() {
  local want=True; [ "$1" = "pause" ] && want=False
  for k in $(seq 1 20); do
    "$PY" -X utf8 "$RDR/lane_hold.py" "$1" "$2" 2>&1 | tail -1
    [ "$(lane_enabled)" = "$want" ] && return 0
    say "레인 $1 확인 실패(시도 $k/20 · enabled=$(lane_enabled)) — 30초 뒤 다시"; sleep 30
  done
  return 1
}
resume_lane() {
  [ "$PAUSED" = "1" ] || return 0
  if lane_set resume "$1"; then PAUSED=0; say "레인 재개 확인(enabled=True)"
  else say "★레인 재개 실패 — 레인이 꺼진 채다 · 세션이 python $RDR/lane_hold.py resume '<사유>' 로 켤 것"; fi
}
trap 'resume_lane "P2R05 GPU 연쇄 종료(trap) — 레인 재개"' EXIT
say "시작 — THGNN(gpu1) 측정 시작 대기(마감 ${START_WAIT_H}h · 기준 시각 $T0)"

## ① 측정 시작 — 저널의 gpu1 axis_override(ts ≥ T0)
started() { "$PY" -X utf8 - "$JL" "$T0" <<'PYX'
import io, json, sys
p, t0 = sys.argv[1], sys.argv[2]
hit = ""
try:
    with io.open(p, "rb") as f:
        f.seek(0, 2); n = f.tell(); f.seek(max(0, n - 4 * 1024 * 1024))
        for ln in f.read().decode("utf-8", "replace").splitlines():
            if '"axis_override"' not in ln or '"gpu1"' not in ln:
                continue
            try:
                e = json.loads(ln)
            except Exception:
                continue
            if e.get("event") == "axis_override" and e.get("slot") == "gpu1" and str(e.get("ts", ""))[:19] >= t0:
                hit = e.get("ts")
except Exception:
    pass
print(hit)
PYX
}
dl=$(( $(date +%s) + START_WAIT_H * 3600 ))
while :; do
  s=$(started | tr -d '\r')
  [ -n "$s" ] && { say "THGNN 측정 시작 확인($s)"; break; }
  [ "$(date +%s)" -ge "$dl" ] && { say "마감 — THGNN 측정 시작 없음 · 레인 그대로 · 끝"; exit 0; }
  sleep 120
done

## ② 레인 보류
PAUSED=1      # 먼저 세운다 — 보류가 반쯤 성공한 채 끝나도 trap 이 재개를 시도한다(재개는 이미 켜져 있으면 확인만 하고 끝난다)
lane_set pause "도훈 10-18 'THGNN 끝난 뒤 레인 보류' — P2R05 GPU 창(THGNN 측정 시작 확인 뒤 · gpu_chain.sh)" \
  || { say "레인 보류 실패(20회) — 워밍하지 않고 끝"; exit 3; }
say "레인 보류 확인(enabled=False)"

## ③ THGNN 끝 — gpu1 claim 없음 2회 연속
dl=$(( $(date +%s) + END_WAIT_H * 3600 )); gone=0
while :; do
  if [ -d "$CLAIM" ]; then gone=0; else gone=$((gone + 1)); fi
  [ "$gone" -ge 2 ] && break
  [ "$(date +%s)" -ge "$dl" ] && { say "마감 — THGNN 이 ${END_WAIT_H}h 안에 끝나지 않음 · 워밍하지 않고 끝(레인 재개)"; exit 4; }
  sleep 120
done
st=$("$PY" -X utf8 -c "import io,json,sys;d=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'));print(d.get('status'),((d.get('paper') or {}).get('paper_key')))" "$REQ" 2>/dev/null | tr -d '\r')
say "THGNN 끝(gpu1 claim 없음 · 요청 $st)"

## ④ 같은 데이터 배치 — 다음 갱신 완료 줄(마감 06:00 규칙)
n0=$(grep -c "=== Daily Refresh v2 Done" "$DONE_LOG" 2>/dev/null || true); n0=${n0:-0}
say "데이터 갱신 완료 줄 대기(현재 $n0 · 06~12시면 현 배치로 진행)"
while :; do
  n=$(grep -c "=== Daily Refresh v2 Done" "$DONE_LOG" 2>/dev/null || true); n=${n:-0}
  [ "$n" -gt "$n0" ] && { say "갱신 완료 줄 확인($n0 → $n)"; break; }
  hh=$((10#$(date +%H))); [ "$hh" -ge 6 ] && [ "$hh" -lt 12 ] && { say "06~12시 — 현 배치로 진행"; break; }
  sleep 120
done

## ⑤ 워밍 → 측정
GDL=$(date -d '+2 hours' +%Y-%m-%dT%H:%M)
say "워밍 시작(warm_cache.sh --gpu-deadline=$GDL)"
bash "$RDR/warm_cache.sh" --gpu-deadline="$GDL"; wrc=$?
say "워밍 끝 rc=$wrc"
if [ "$wrc" != "0" ]; then say "워밍 실패 — 측정하지 않는다(warm_cache.sh 가 알림 · Q 확인)"; exit 5; fi
bash "$RDR/notify_done.sh" > "$ROOT/.cache/scheduler_logs/p2r05_notify_done_$(date +%Y%m%d).log" 2>&1 &
bash "$RDR/measure_now_vram.sh"; mrc=$?
say "측정 · 평가 끝 rc=$mrc"
exit 0
