#!/usr/bin/env bash
# P2R05 GPU 창 연쇄 v5(2026-11-06 · 1계층 사이드 세션) — 분리 실행(_lib/detached_env.sh · 세션 밖 · 인자 없음). 측정 절차 · 판정과 무관(사전등록 핀 아님).
#   방침(원 세션 11-06 12:3x · 도훈 최신 결정 J-20261018-008 'P2R05 먼저 · THGNN 일시정지'): GPU 임대로 GPU 슬롯만 보류 · CPU 슬롯은 계속 ·
#   워밍 → 측정 → 임대 해제 뒤 THGNN. (v1~v3 = 레인 전체 보류 · THGNN 먼저 — 근거였던 J-20261018-007 이 J-008 로 대체돼 있었다 · Superfan T3 C-20261106-001)
#   ① 시작 — 이 연쇄의 앞판이 걸어 둔 레인 보류(paused_note 에 gpu_chain)를 푼다(CPU 슬롯 계속) → GPU 임대 획득(보유자 = 이 연쇄 Windows pid ·
#      상한 12h · 남은 1시간 미만이면 놓고 다시 잡아 이어 간다). 진행 중인 THGNN 은 임대와 무관하게 계속 돈다(임대는 새 GPU 착수만 막는다).
#   ② 준비 대기(v5) — 데이터 준비 표식 night_state/p2r05_data_ready.ok(원 세션의 10-20~11-05 수급 · 컨센서스 · 유니버스 복구 + factor_db 202610 · 202611 ·
#      fdb_daily 재빌드 끝 — 1계층 세션이 원 세션 통지와 데이터 확인 뒤 쓴다 · 국면 원장 재발행은 P2R05 값 · 지문과 무관(11-06 의존 감사)) 뒤,
#      표식 뒤에 끝난 갱신(Done — 예약 실행 daily_refresh.log · ensure 경로 /tmp/qm_daily_refresh_<날짜>.log) ∧ START_HOUR_MAX 시 전 ∧ 리프레시 잠금 없음 ∧
#      ensure_data_current --check-only rc 0 일 때만 시작한다(P2R05 DT 엔진은 .cache/consensus · fundamental_merged · RAWDATA 를 읽고 측정 판본 지문은
#      파일 상태 기반 — 워밍 fp_start 부터 평가 끝까지 데이터 파일이 바뀌면 워밍 실패 · 측정 거부).
#   ③ 시작 시점에 THGNN(gpu1)이 아직 돌면 일시정지 — 작업자 bash(claim owner_win) · thgnn.py · 그 부모 검증기 Rscript 만 끝낸다(다른 슬롯 무접촉) →
#      gpu1 요청 failure=session_reverify(재개 = 엔진 보존 검증기만 · 10-20 표식과 같음).
#   ④ 임대 새로 잡기 → warm_cache.sh --allow-lane-on(레인 켜짐 · GPU 슬롯은 임대가 막는다) → 임대 새로 잡기 → notify_done.sh(1통) + measure_now_vram.sh.
#   ⑤ 끝 = 임대 해제(trap) → 다음 틱에 THGNN 재개(일시정지했으면 검증기만). 강제 종료(taskkill /F)면 trap 이 안 돈다 → 임대는 보유자 사망으로 틱이 푼다.
#   비정상 출구(임대 실패 · 준비 마감 · 일시정지 실패)마다 알림 1통 = gpu_chain_alert.R(prep_send 푸시). 워밍 실패는 warm_cache.sh 가 스스로 알린다.
# 로그 = .cache/scheduler_logs/p2r05_gpu_chain_<시작일>.log(detached_env.sh 두 번째 인자)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=$ROOT/04_Research/programs/P2_DEFENSE/P2R05_distribution_target
ST=$ROOT/04_Research/programs/_lib/night_state
READY=$ST/p2r05_data_ready.ok
CLAIM=$ROOT/.cache/rf_replication.claim.gpu1
REQ=$ROOT/06_Registry/replication_slots/gpu1/replication_request.json
DONE_LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
REFRESH_LOCK=/tmp/qm_daily_refresh.lock
PY=$ROOT/.venv_qvest_ml/Scripts/python.exe
QVL=$ROOT/02_Infrastructure/ops/qv_lock.py
CFG=$ROOT/06_Registry/reinforce_auto_config.json
HOLDER=P2R05_gpu_chain
THGNN_TOKEN=RP_AUTO_CLEAN_2601_04602     # THGNN 작업 디렉터리 — 이 문자열을 명령 줄에 가진 파이썬만 THGNN 으로 본다(다른 슬롯 무접촉)
PURPOSE="P2R05 GPU 창(워밍 · 측정) — 원 세션 11-06 · 도훈 J-20261018-008 P2R05 먼저"
READY_DEADLINE=$(date -d '2026-11-08 12:00' +%s)
cd $ROOT || exit 2
WINPID=$(tr -d '\r\n ' < /proc/$$/winpid 2>/dev/null)
say() { echo "== $(date +%F' '%T) [P2R05 GPU 연쇄 v5] $*"; }
alert() { Rscript "$RDR/gpu_chain_alert.R" "$1" "$2" "$3" > /dev/null 2>&1 && say "알림 1통($1)" || say "알림 실패($1)"; }

## 레인 스위치 = 설정 값으로 확인(파일 교체가 OneDrive 에 WinError 5 로 실패할 수 있다 — 11-06 실측) · 경로는 인자로(MSYS 는 인자만 C:/ 로 바꾼다)
lane_enabled() { "$PY" -X utf8 -c "import io,json,sys;print(json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))['replication_lane'].get('enabled'))" "$CFG" 2>/dev/null | tr -d '\r'; }
lane_note() { "$PY" -X utf8 -c "import io,json,sys;print(json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))['replication_lane'].get('paused_note') or '')" "$CFG" 2>/dev/null | tr -d '\r'; }
lane_set() {
  local want=True; [ "$1" = "pause" ] && want=False
  for k in $(seq 1 20); do
    "$PY" -X utf8 "$RDR/lane_hold.py" "$1" "$2" 2>&1 | tail -1
    [ "$(lane_enabled)" = "$want" ] && return 0
    say "레인 $1 확인 실패(시도 $k/20 · enabled=$(lane_enabled)) — 30초 뒤 다시"; sleep 30
  done
  return 1
}
## GPU 임대 — 보유자 = 이 연쇄(Windows pid). 상태 판독은 qv_lock CLI(JSON).
lease_json() { "$PY" -X utf8 "$QVL" lease status --json 2>/dev/null | tr -d '\r'; }
lease_mine() {   # 0 = 이 연쇄가 쥐고 남은 시간 ≥ $1 시간
  "$PY" -X utf8 -c "import json,sys
try: d=json.loads(sys.argv[1] or '{}')
except Exception: sys.exit(1)
ok=d.get('state')=='held' and d.get('holder')==sys.argv[2] and float(d.get('remaining_h') or 0)>=float(sys.argv[3])
sys.exit(0 if ok else 1)" "$(lease_json)" "$HOLDER" "${1:-1}"
}
lease_take() {   # 놓고 새로 잡는다(같은 보유자 재획득은 연장이 없어서) — 0 = 새 12시간 보유
  "$PY" -X utf8 "$QVL" lease release --holder "$HOLDER" > /dev/null 2>&1
  "$PY" -X utf8 "$QVL" lease acquire --holder "$HOLDER" --purpose "$PURPOSE" --cap-hours 12 --holder-pid "$WINPID" --json 2>&1 | tail -1
  lease_mine 11
}
lease_keep() { lease_mine 1 || { say "임대 갱신(남은 1시간 미만 또는 보유 아님)"; lease_take > /dev/null || say "임대 갱신 실패($(lease_json | cut -c1-160))"; }; }
lease_drop() { "$PY" -X utf8 "$QVL" lease release --holder "$HOLDER" 2>&1 | tail -1; }
trap 'say "끝 — 임대 해제: $(lease_drop)"' EXIT

latest_done_epoch() {   # 두 로그(예약 실행 >> daily_refresh.log · daily_refresh.sh 자체 tee /tmp/qm_daily_refresh_<날짜>.log — ensure 경로 실행은 여기에만)의 마지막 Done 시각 최댓값
  local f ln ts e best=0
  for f in "$DONE_LOG" /tmp/qm_daily_refresh_*.log; do
    [ -f "$f" ] || continue
    ln=$(grep -a "=== Daily Refresh v2 Done" "$f" 2>/dev/null | tail -1)
    [ -n "$ln" ] || continue
    ts=$(printf '%s' "$ln" | sed -E 's/.*@ (.*) ===.*/\1/')
    e=$(date -d "$ts" +%s 2>/dev/null) || continue
    [ "$e" -gt "$best" ] && best=$e
  done
  echo "$best"
}
data_current() {   # 0 = ensure_data_current 감사 '최신'(rc 0) — 아니면 다음 부팅 · 아침 체인(07:10) · /qvest 가 워밍 중에 갱신을 다시 돌린다(지문 뒤집힘)
  bash "$ROOT/02_Infrastructure/ops/ensure_data_current.sh" --check-only > "$ST/p2r05_gpu_chain_edc.log" 2>&1
}
claim_alive() {    # 0 = gpu1 claim 이 살아 있다 · 1 = 없음 · 소유자 사망 · 표식 없는 빈 claim 10분 초과
  [ -d "$CLAIM" ] || return 1
  local w age
  w=$( { tr -d '\r\n ' < "$CLAIM/owner_win"; } 2>/dev/null )
  if [ -z "$w" ]; then
    age=$(( $(date +%s) - $(date -r "$CLAIM" +%s 2>/dev/null || date +%s) ))
    [ "$age" -lt 600 ]; return $?
  fi
  tasklist //FI "PID eq $w" //NH 2>/dev/null | awk -v p="$w" '$2==p{f=1} END{exit !f}'
}
req_state() { "$PY" -X utf8 -c "import io,json,sys;d=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'));print(d.get('status'),((d.get('paper') or {}).get('paper_key')))" "$REQ" 2>/dev/null | tr -d '\r'; }
stop_thgnn() {   # THGNN 트리만 끝낸다 — claim 소유자 bash · RP_AUTO_CLEAN_2601_04602 를 실행 중인 파이썬 · 그 파이썬의 부모(검증기 Rscript)
  local w; w=$( { tr -d '\r\n ' < "$CLAIM/owner_win"; } 2>/dev/null )
  powershell.exe -NoProfile -Command "\$t=@(); if ('$w' -match '^[0-9]+\$') { \$t += [int]'$w' };
    Get-CimInstance Win32_Process | Where-Object { \$_.Name -match '^python' -and \$_.CommandLine -match '$THGNN_TOKEN' } | ForEach-Object {
      \$t += \$_.ProcessId; \$pp = Get-CimInstance Win32_Process -Filter ('ProcessId=' + \$_.ParentProcessId);
      if (\$pp -and \$pp.Name -match '^(Rscript|Rterm|R)\.exe\$') { \$t += \$pp.ProcessId } };
    \$t | Sort-Object -Unique | ForEach-Object { try { Stop-Process -Id \$_ -Force -ErrorAction Stop; 'stopped ' + \$_ } catch { 'skip ' + \$_ } }" 2>&1 | tr -d '\r' | paste -sd' ' -
}
mark_reverify() {
  "$PY" -X utf8 - "$REQ" <<'PYX'
import io, json, os, sys, tempfile, time
p = sys.argv[1]
d = json.loads(io.open(p, "rb").read().decode("utf-8"))
if d.get("status") in ("in_progress", "pending") and (d.get("paper") or {}).get("paper_key") == "2601.04602":
    d["failure"] = "session_reverify"
    d["failure_detail"] = ("P2R05 GPU 창(gpu_chain.sh v4 · 원 세션 11-06 · 도훈 J-20261018-008 P2R05 먼저)으로 측정 중 일시정지 — "
                           "재개는 엔진 보존 검증기만(10-20 · 11-06 과 같은 표식)")
    d["session_reverify_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    for k in range(20):
        try:
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix=".tmp")
            with io.open(fd, "wb") as f:
                f.write(json.dumps(d, ensure_ascii=False, indent=1).encode("utf-8"))
            os.replace(tmp, p); print("marked session_reverify"); break
        except OSError as e:
            try: os.remove(tmp)
            except OSError: pass
            time.sleep(3)
    else:
        print("mark failed")
else:
    print("not marked (status=%s key=%s)" % (d.get("status"), (d.get("paper") or {}).get("paper_key")))
PYX
}

## ① 레인 · 임대
say "시작(pid $$ · Windows $WINPID) — 레인 $(lane_enabled) · 임대 $(lease_json | cut -c1-120)"
if [ "$(lane_enabled)" != "True" ]; then
  case "$(lane_note)" in
    *gpu_chain*) lane_set resume "P2R05 GPU 연쇄 v4 — 원 세션 방침: GPU 임대로 GPU 슬롯만 보류 · CPU 슬롯 계속(레인 전체 보류 해제)" \
                   && say "레인 재개 확인(enabled=True)" \
                   || alert "레인 재개 실패" "앞판 연쇄가 건 레인 보류를 풀지 못했다(20회)" "세션: python 04_Research/programs/P2_DEFENSE/P2R05_distribution_target/lane_hold.py resume '<사유>'" ;;
    *) say "레인이 꺼져 있으나 이 연쇄가 건 보류가 아니다($(lane_note | cut -c1-80)) — 건드리지 않는다" ;;
  esac
fi
if lease_take > /dev/null; then say "GPU 임대 획득(12h · 갱신하며 유지)"; else
  alert "GPU 임대 실패" "P2R05 GPU 창 임대를 잡지 못했다($(lease_json | cut -c1-200))" "세션: 임대 보유자 확인(python 02_Infrastructure/ops/qv_lock.py lease status --json) 뒤 연쇄 재기동"
  exit 3
fi

## ② 준비 대기 — 데이터 준비 표식 → 그 뒤 첫 갱신 완료 줄(또는 06~12시 · 잠금 없음)
## 시작 조건(전부 참일 때만 — 의존 감사 11-06 워크플로 결론 · 워밍 fp_start 부터 평가 끝까지 데이터 파일이 바뀌면 워밍 실패 · 측정 거부):
##   표식 있음 ∧ 표식 뒤에 끝난 갱신(Done)이 있음 ∧ 지금 START_HOUR_MAX 시 전(워밍 ≈8h + 측정 · 평가가 다음 00:03 갱신 전에 끝나게) ∧
##   리프레시 잠금 없음 ∧ ensure_data_current 감사 rc 0(최신이 아니면 아침 체인 · 부팅 · /qvest 가 워밍 중에 갱신을 다시 돌린다)
##   Done 줄은 다른 세션 시험 사본이 같은 /tmp 로그에 쓸 수 있어 단독 신호로 쓰지 않는다(겹조건이 막는다).
START_HOUR_MAX=10
say "준비 대기 — 표식 $READY(원 세션 데이터 복구 · 재발행 끝) → 표식 뒤 갱신 완료 ∧ ${START_HOUR_MAX}시 전 ∧ 잠금 없음 ∧ ensure 최신 · 마감 $(date -d @$READY_DEADLINE +%F' '%T)"
RSEEN=0; THR=0; LAST_NOTE=""
note_once() { [ "$1" = "$LAST_NOTE" ] || { say "$1"; LAST_NOTE="$1"; }; }
while :; do
  lease_keep
  if [ "$RSEEN" = "0" ] && [ -f "$READY" ]; then
    RSEEN=1; THR=$(date -r "$READY" +%s)
    say "데이터 준비 표식 확인($(head -c 200 "$READY" | tr '\n' ' ')) — 이 시각($(date -d @$THR +%F' '%T)) 뒤에 끝난 갱신을 기다린다"
  fi
  if [ "$RSEEN" = "1" ]; then
    ld=$(latest_done_epoch); hh=$((10#$(date +%H)))
    if [ "$ld" -le "$THR" ]; then note_once "표식 뒤 갱신 완료 대기(마지막 Done $(date -d @$ld +%F' '%T))"
    elif [ "$hh" -ge "$START_HOUR_MAX" ]; then note_once "갱신 완료($(date -d @$ld +%F' '%T))는 있으나 ${START_HOUR_MAX}시 이후 — 워밍 · 측정이 다음 00:03 갱신을 넘는다 · 다음 갱신까지 기다린다"; THR=$ld
    elif [ -d "$REFRESH_LOCK" ]; then note_once "리프레시 잠금 있음 — 끝날 때까지 기다린다"
    elif data_current; then say "시작 조건 충족 — 갱신 완료 $(date -d @$ld +%F' '%T) · 잠금 없음 · ensure 최신"; break
    else note_once "ensure 감사가 최신 아님($(grep -a -E '사전 감사|stale' "$ST/p2r05_gpu_chain_edc.log" | head -1 | cut -c1-120)) — 다음 갱신까지 기다린다"; THR=$ld
    fi
  fi
  if [ "$(date +%s)" -ge "$READY_DEADLINE" ]; then
    say "마감 — 데이터 준비 표식 · 갱신 완료가 마감 안에 오지 않았다 · 워밍 안 함(임대 해제)"
    alert "준비 대기 마감" "데이터 준비 표식 또는 그 뒤 갱신 완료가 마감($(date -d @$READY_DEADLINE +%F' '%T)) 안에 오지 않았다 — P2R05 워밍 안 함 · GPU 임대 해제" "세션: 원 세션 복구 상태 확인 → 표식 쓰고 연쇄 재기동"
    exit 4
  fi
  sleep 120
done

## ③ THGNN 이 아직 돌면 일시정지
if claim_alive; then
  say "THGNN(gpu1 · $(req_state)) 아직 실행 중 — 일시정지(도훈 J-20261018-008 P2R05 먼저): $(stop_thgnn)"
  for k in $(seq 1 30); do claim_alive || break; sleep 20; done
  if claim_alive; then
    alert "THGNN 일시정지 실패" "gpu1 작업이 10분 안에 끝나지 않았다 — P2R05 워밍 안 함(임대 해제)" "세션: THGNN 프로세스 확인(작업자 bash · thgnn.py · 검증기 Rscript) 뒤 연쇄 재기동"
    exit 6
  fi
  say "THGNN 멈춤 확인 · gpu1 요청: $(mark_reverify)"
else
  say "THGNN 은 이미 끝났다(gpu1 요청 $(req_state))"
fi

## ④ 워밍 → 측정(임대는 단계마다 새로 잡아 12시간 상한 안에서 이어 간다)
lease_take > /dev/null && say "임대 새로 잡음(워밍)" || say "임대 새로 잡기 실패 — 워밍 GPU 게이트가 다른 연산을 기다린다"
GDL=$(date -d '+2 hours' +%Y-%m-%dT%H:%M)
say "워밍 시작(warm_cache.sh --allow-lane-on --gpu-deadline=$GDL)"
bash "$RDR/warm_cache.sh" --allow-lane-on --gpu-deadline="$GDL"; wrc=$?
say "워밍 끝 rc=$wrc"
if [ "$wrc" != "0" ]; then say "워밍 실패 — 측정하지 않는다(warm_cache.sh 가 알림 · Q 확인)"; exit 5; fi
lease_take > /dev/null && say "임대 새로 잡음(측정)" || say "임대 새로 잡기 실패"
bash "$RDR/notify_done.sh" > "$ROOT/.cache/scheduler_logs/p2r05_notify_done_$(date +%Y%m%d).log" 2>&1 &
bash "$RDR/measure_now_vram.sh"; mrc=$?
say "측정 · 평가 끝 rc=$mrc"
exit 0
