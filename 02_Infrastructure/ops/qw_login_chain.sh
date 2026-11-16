#!/usr/bin/env bash
#==============================================================================
# qw_login_chain.sh — 퀀티 로그인 뒤 보류 작업 1회성 체인 (도훈 11-16 '퀀티 로그인만 해결하면 바로 보류된 작업들 실행되게' · '네, 연결해')
#
# 왜: 11-16 에 RAWDATA 상장 전 이력 제외(RAWDATA-PRELISTING-EXCLUDE-20261116) · 재무 법정기한 + 45일(FUNDAMENTAL-AVAIL-DEADLINE45-20261116)이
#   정해졌고, 둘 다 팩터 DB 전체 재빌드가 끝나야 측정에 쓸 수 있다. 막힌 곳은 하나 — 상장일 잣대(퀀티 시장구분 R100100 일별)를 받으려면
#   퀀티 세션이 살아 있어야 한다. 로그인되면 아래가 사람 없이 차례로 돈다.
# 단계(상태 = .cache/qw_login_chain/status.json · 로그 = .cache/scheduler_logs/qw_login_chain_<날짜>.log):
#   ① market  시장구분 파일이 없으면 밤 갱신과 같은 래퍼(qw_updatefile_unattended.sh · ext · ListingMarket)로 받고 적재(qw_ext_ingest.py)
#             — 세션이 없으면 드라이버가 로그인 클릭 없이 멈춘다(SAVEUSERPW=0 · exit 3) → 대기 상태로 끝내고 다음 틱에 다시 본다
#   ② cut     리프레시 배리어 free 대기 → RAWDATA writer 잠금 → rawdata_listing_cut.py --apply --backup(상장 전 행 삭제만 · 값 무변경)
#             · 판 표식 RAWDATA-PRELISTING-EXCLUDE-20261116 줄이 없으면 더한다(completed_at null)
#   ③ rebuild 팩터 DB 전체 재빌드(run_factor_db_full_rebuild.sh — 단계마다 배리어 대기) ④ view 결합용 뷰 --full ⑤ ff 한국 FF 요인
#   ⑥ vintage 판 표식 셋(재무 1개월 · 법정기한 + 45일 · 상장 전 제외)의 completed_at 을 채운다
#   ⑦ unhold  충실구현 레인 measure_hold = false(다음 레인 틱이 보류된 논문을 검증기만 재실행)
#   텔레그램 = 자르기 시작 1통 · 끝 1통 · 실패 1통(tg_agent_brief 단일 진입 · 성과 수치 없음).
# 하지 않는 것: 새 검사 · 대조(도훈 11-16) · 실패 단계 자동 재시도(실패 = failed 로 멈추고 알림 — 사람이 보고 --reset) · P1S03 재측정 · P4C03 등록(감독 아래).
# 호출: Qvest_StandingBoard.bat(매시 :37) 이 `--tick` — 끝났거나 실패면 무동작 · 살아 있는 실행이 있으면 무동작 · 아니면 `--run` 을 떼어 띄우고 바로 끝난다.
#   손으로: bash qw_login_chain.sh --status | --run(전경) | --reset(실패 뒤 다시 · status 를 지운다)
# 끄기: QVEST_QW_LOGIN_CHAIN=0
#==============================================================================
set -u
[ "${QVEST_QW_LOGIN_CHAIN:-1}" = "0" ] && exit 0
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 2
D=.cache/qw_login_chain; mkdir -p "$D" .cache/scheduler_logs
ST="$D/status.json"; LK="$D/run.lock"
LOG=".cache/scheduler_logs/qw_login_chain_$(date +%Y%m%d).log"
PY="${QVENV_PY:-.venv_qvest_ml/Scripts/python.exe}"
MARKET=".cache/qw_ext/listing_market/market_type.parquet"
SELF="02_Infrastructure/ops/qw_login_chain.sh"

say() { echo "[qw-login-chain $(date '+%F %T')] $*" >> "$LOG"; }
st()  { "$PY" -X utf8 -c "
import json,sys,time,os
p=sys.argv[1]; d={'step':sys.argv[2],'state':sys.argv[3],'at':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'note':sys.argv[4],'log':sys.argv[5]}
tmp=p+'.tmp'; open(tmp,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False)+'\n'); os.replace(tmp,p)" "$ST" "$1" "$2" "${3:-}" "$LOG"; }
st_get() { [ -f "$ST" ] && "$PY" -X utf8 -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))" "$ST" "$1" 2>/dev/null | tr -d '\r'; }
tg() {   # $1 제목 꼬리 · $2 본문 — 실패해도 체인은 계속
  QLC_T="$1" QLC_B="$2" Rscript -e 'suppressWarnings(suppressMessages(source(file.path(Sys.getenv("QM_ROOT"),"02_Infrastructure","telegram","telegram_notify.R")))); r <- tryCatch(tg_agent_brief(agent="Q-Lead", title=paste0("[1계층] 퀀티 로그인 뒤 체인 — ", Sys.getenv("QLC_T")), relaxed=TRUE, force=TRUE, lock_scope=paste0("qw_login_chain_", Sys.getenv("QLC_T")), sections=list(list(type="summary", emoji="\U0001F501", body=Sys.getenv("QLC_B")))), error=function(e) list(ok=FALSE)); cat("tg ok=", isTRUE(r$ok), "\n")' >> "$LOG" 2>&1 || true; }
lock_live() { [ -f "$LK" ] && kill -0 "$(cat "$LK" 2>/dev/null)" 2>/dev/null; }

case "${1:---tick}" in
  --status) cat "$ST" 2>/dev/null || echo '{"state":"not_started"}'; exit 0 ;;
  --reset)  rm -f "$ST"; echo "reset"; exit 0 ;;
  --tick)
    s="$(st_get state)"
    { [ "$s" = "done" ] || [ "$s" = "failed" ] || [ "$s" = "held" ]; } && exit 0   # held = 세션이 잠시 세움(재개 = --run 또는 state 를 지움)
    lock_live && exit 0
    nohup bash "$SELF" --run >> "$LOG" 2>&1 < /dev/null &
    disown $! 2>/dev/null || true
    exit 0 ;;
  --run) ;;
  *) echo "사용: $0 --tick|--run|--status|--reset"; exit 2 ;;
esac

lock_live && { say "다른 실행이 살아 있다 — 끝"; exit 0; }
echo $$ > "$LK"; trap 'rm -f "$LK"' EXIT
fail() { st "$1" failed "$2"; say "실패 $1 — $2"; tg "실패" "단계 $1 에서 멈췄습니다: $2 · 로그 $LOG · 다시 = bash $SELF --reset"; exit 1; }

## ① 상장일 잣대 — 퀀티 시장구분
if [ ! -s "$MARKET" ]; then
  bash 02_Infrastructure/ops/refresh_barrier.sh status > /dev/null 2>&1 || { st market waiting "리프레시 배리어 held — 다음 틱"; exit 0; }
  say "① 시장구분 수급(ext · ListingMarket)"; st market running
  QWUF_GROUP=ext QWUF_ONLY=ListingMarket QWUF_LOG="$ROOT/.cache/qw_updatefile_unattended_ext.json" \
    bash 02_Infrastructure/data/qw_updatefile_unattended.sh 0 "$PY" >> "$LOG" 2>&1; r=$?
  say "① 수급 rc=$r"
  "$PY" -X utf8 02_Infrastructure/data/qw_ext_ingest.py --book ListingMarket >> "$LOG" 2>&1; r=$?
  say "① 적재 rc=$r"
  [ -s "$MARKET" ] || { st market waiting_qw "시장구분 파일 없음 — 퀀티 세션 대기(로그인 뒤 다음 틱)"; exit 0; }
fi

## ② RAWDATA 상장 전 행 삭제
if [ "$(st_get step)" != "cut_done" ] && [ "$(st_get step)" != "rebuild" ] && [ "$(st_get step)" != "view" ] && [ "$(st_get step)" != "ff" ]; then
  say "② 자르기 — 배리어 대기"; st cut running
  bash 02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 >> "$LOG" 2>&1 || fail cut "리프레시 배리어가 2시간 넘게 held"
  tg "자르기 시작" "퀀티 시장구분을 받았습니다. RAWDATA 상장 전 행 삭제 → 팩터 DB 전체 재빌드(약 12시간) → 결합용 뷰 → FF 요인 → 레인 측정 보류 해제 순서로 진행합니다."
  # shellcheck source=/dev/null
  source 02_Infrastructure/ops/refresh_barrier.sh
  rb_writer_acquire qw_login_chain_cut || fail cut "RAWDATA writer 잠금 실패"
  QVEST_LISTING_CUT_LOCKED=1 "$PY" -X utf8 02_Infrastructure/data/rawdata_listing_cut.py --apply --backup --label qw_login_chain >> "$LOG" 2>&1; r=$?
  rb_writer_release
  say "② rc=$r"; [ "$r" = "0" ] || fail cut "rawdata_listing_cut.py rc=$r"
  "$PY" -X utf8 - >> "$LOG" 2>&1 <<'PY' || fail cut "판 표식 줄 쓰기 실패"
import json, os
p = "06_Registry/factor_db_vintage.json"; d = json.load(open(p, encoding="utf-8"))
if not any(x.get("id") == "RAWDATA-PRELISTING-EXCLUDE-20261116" for x in d["entries"]):
    d["entries"].append({"id": "RAWDATA-PRELISTING-EXCLUDE-20261116", "completed_at": None, "scope": "all",
        "decision": "RAWDATA-PRELISTING-EXCLUDE-20261116(도훈 11-16 '상장전 이력까지 백테스팅에 활용하지마 · 상장된 시점 이후 퀀티와이즈 가격부터 · 없는 시점은 유니버스에서 제외')",
        "note": "RAWDATA 상장 전 행 삭제(rawdata_listing_cut.py · 퀀티 시장구분 R100100 첫 유가증권 · 코스닥 날짜) — 완료 = 팩터 DB 전체 재빌드 + 결합용 뷰 --full + FF 요인 rc 0(qw_login_chain.sh 가 채운다)",
        "evidence": ".cache/listing_cut/ · .cache/qw_login_chain/status.json"})
    tmp = p + ".tmp"; open(tmp, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=2) + "\n"); os.replace(tmp, p)
    print("vintage line added")
PY
  st cut_done ok "상장 전 행 삭제 끝"
fi

## ③ ④ ⑤ 재빌드 · 결합용 뷰 · FF
say "③ 팩터 DB 전체 재빌드"; st rebuild running
bash 02_Infrastructure/factor_db/run_factor_db_full_rebuild.sh --tag qw_login_chain ${QLC_REBUILD_ARGS:---any-time --skip-backup} >> "$LOG" 2>&1; r=$?
say "③ rc=$r"; [ "$r" = "0" ] || fail rebuild "run_factor_db_full_rebuild.sh rc=$r"
say "④ 결합용 뷰 전체"; st view running
Rscript 02_Infrastructure/factor_db/factor_combinable.R --build --full >> "$LOG" 2>&1; r=$?
say "④ rc=$r"; [ "$r" = "0" ] || fail view "factor_combinable.R rc=$r"
say "⑤ 한국 FF 요인"; st ff running
Rscript 02_Infrastructure/data/build_kr_factor_returns.R >> "$LOG" 2>&1; r=$?
say "⑤ rc=$r"; [ "$r" = "0" ] || fail ff "build_kr_factor_returns.R rc=$r"

## ⑥ 판 표식 완료 · ⑦ 측정 보류 해제
"$PY" -X utf8 - >> "$LOG" 2>&1 <<'PY' || fail vintage "판 표식 · 레인 설정 쓰기 실패"
import json, os, datetime
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
p = "06_Registry/factor_db_vintage.json"; d = json.load(open(p, encoding="utf-8"))
ids = ("FUNDAMENTAL-AVAIL-LAG-1M-20261116", "FUNDAMENTAL-AVAIL-DEADLINE45-20261116", "RAWDATA-PRELISTING-EXCLUDE-20261116", "FUNDAMENTAL-QW-ONLY-20261116", "FUNDAMENTAL-CACHES-REDEFINE-20261116")
for x in d["entries"]:
    if x.get("id") in ids and not str(x.get("completed_at") or "").strip():
        x["completed_at"] = now; print("vintage completed", x["id"])
tmp = p + ".tmp"; open(tmp, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=2) + "\n"); os.replace(tmp, p)
c = "06_Registry/reinforce_auto_config.json"; raw = open(c, "rb").read().decode("utf-8"); cfg = json.loads(raw)
rl = cfg["replication_lane"]; rl["measure_hold"] = False; rl["measure_hold_released_at"] = now; rl["measure_hold_released_by"] = "qw_login_chain.sh"
tmp = c + ".tmp"; open(tmp, "wb").write((json.dumps(cfg, ensure_ascii=False, indent=2) + ("\n" if raw.endswith("\n") else "")).encode("utf-8")); os.replace(tmp, c)
print("measure_hold released")
PY
st done ok "재빌드 · 판 표식 · 측정 보류 해제 끝"
say "끝"
tg "끝" "상장 전 행 삭제 · 팩터 DB 전체 재빌드 · 결합용 뷰 · FF 요인이 끝났고 판 표식 셋을 채웠습니다. 레인 측정 보류를 풀었습니다(다음 레인 틱부터 보류 논문 측정). 남은 것 = P1S03 재측정 · P4C03 등록(세션)."
exit 0
