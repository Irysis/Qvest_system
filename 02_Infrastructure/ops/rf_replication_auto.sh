#!/usr/bin/env bash
#==============================================================================
# rf_replication_auto.sh — **논문 충실구현 무인 실행** (도훈 지시 2026-08-30)
#
# ★경계 변경 고지: cleaner 선례가 "무인 LLM 호출은 권한/판단 리스크로 배제" 라고 명시했고
#   나도 그 선을 지켜 왔다. 도훈이 두 번 명시 요청해 그 경계를 넘는다. 대신 리스크를 구조로 막는다:
#   (후기 2026-09-05 — 그 cleaner 선례 자체가 폐기됐다. 증류도 무인화됐고 삭제 판단까지 LLM 이
#    진다: `cleaner_distill_run.sh`. 아래 ①~④ 와 같은 구조 — 산출은 계약이 검증하고 권한은 좁힌다.
#    즉 여기 인용된 "cleaner 선례" 는 이제 **사료**다. 새 인용의 근거로 쓰지 말 것.)
#
#   ① 에이전트 산출물은 **엔진 파일 하나**뿐이다. 측정·등급·PIT 는 전부 계약이 강제하므로
#      에이전트가 등급을 지어낼 수 없다(AX-008: 산출은 Forge).
#   ② 권한 축소 — 쓰기는 지정 디렉터리로, 도구는 화이트리스트로 제한한다.
#   ③ 사후 검증 게이트 — 엔진 존재·계약 산출물·고정 축·PIT 를 **기계가 재도출**한다.
#      하나라도 어기면 원장에 열지 않고 세션 대기로 되돌린다(조용한 통과 없음).
#   ④ 실패는 실패로 기록한다 — 텔레그램 + 요청 파일 status=failed_needs_session.
#
# 흐름: replication_request.json(pending) → claude -p 헤드리스 → 검증 → rf_open_entry → 강화 재개
# 호출: 스케줄러(tick) 또는 수동. kill switch 는 강화 러너와 공유한다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
# ★검사가 격리 사본을 쓸 수 있게 (강화 러너의 QVEST_RF_CONFIG/QVEST_RF_CLAIM 선례와 동일 규약).
#   공유 요청·claim 을 검사가 직접 만지면 그 창에 스케줄러 tick 이 끼어든다. 그리고 이 배선이
#   없으면 claim 상태기계를 **양방향으로 잴 방법 자체가 없다** — 그래서 2026-09-01 의 순서 결함이
#   test_reinforce_auto.sh 15항을 다 통과한 채로 살아 있었다.
REQ="${QVEST_RP_REQUEST:-$ROOT/06_Registry/replication_request.json}"
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"
LOG="$ROOT/.cache/scheduler_logs/replication_auto_$(date +%Y%m%d).log"
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
CLAIM="${QVEST_RP_CLAIM:-$ROOT/.cache/rf_replication.claim}"
mkdir -p "$(dirname "$LOG")"

jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'replication_auto'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[rp_auto] '+sys.argv[1])" "$@" ; }

# ── 게이트 ────────────────────────────────────────────────────────────────────
EN=$("$PY" -c "
import io,json
try: print(json.loads(io.open(r'$CFG','rb').read().decode('utf-8')).get('enabled'))
except Exception: print('False')" 2>/dev/null)
[ "$EN" = "True" ] || { jl halt_disabled; exit 0; }
# ── ★강화가 도는 동안 새 논문을 돌리지 않는다 (도훈 지적 2026-09-04) ────────
#   가드가 **한쪽에만** 있었다: reinforce_auto_next_paper.R 은 active entry 를 보고
#   halt_active_exists 로 멈추는데, 이 레인은 그걸 안 봐서 대기 중인 요청을
#   그대로 집었다. 실사고: 2511.12490 이 18:34~19:15 에 에이전트+측정+감사 한 바퀴를
#   강화(1403.8125 구제분)와 **나란히** 돌았다.
#   ★요청을 지우지 않는다 — pending 으로 두면 강화가 끝난 뒤 그대로 집힌다.
if [ "${QVEST_RP_ALLOW_CONCURRENT:-0}" != "1" ]; then
  ACT=$("$PY" -c "
import io,json
try:
    d=json.loads(io.open(r'$ROOT/06_Registry/reinforce_ledger_l1.json','rb').read().decode('utf-8'))
    n=sum(1 for e in d.get('entries',[]) if e.get('status')=='active')
    print(n)
except Exception: print(0)" 2>/dev/null)
  if [ "${ACT:-0}" != "0" ]; then
    jl halt_reinforce_active "n=$ACT" "note=강화 entry 가 활성이다 — 새 논문 충실구현을 보류한다(요청은 pending 으로 보존)"
    exit 0
  fi
fi
# ── ★고아 claim 회수는 **상태 판정보다 먼저** 한다 (2026-09-01 수리) ────────────
#   구판은 이 블록이 pending 게이트 *뒤에* 있었다. 그런데 아래 재시도 로직은 in_progress 를
#   되살릴 때 "claim 이 없으면 죽은 실행" 이라는 조건을 쓴다 — 고아 claim 이 남아 있으면
#   되살리지 않고, 그러면 status 가 pending 이 아니라 게이트가 no_pending_request 로 나가고,
#   **회수 코드에는 영영 도달하지 못한다**. pid 사망을 보라고 넣어 둔 계기가 정작 pid 가
#   죽은 상태에서 실행되지 않는 구조였다.
#   실사고 2026-09-01: owner pid 20949 사망 + status=in_progress → 00:50~14:10 동안 무인 루프가
#   no_pending_request / halt_no_active_entry 만 반복. 13시간 무진행이 정상 대기와 같은 로그로 보였다.
#   ⇒ 회수를 앞으로 옮긴다. 살아있는 소유자가 있으면 이 블록은 아무것도 하지 않으므로
#     정상 병행 실행은 그대로 막힌다(회수 조건 = pid 사망 또는 2시간 경과).
# ★stale 재점유 (2026-08-30 수리 — 강화 러너의 claim_stale_hours 정책과 정합).
#   구판은 재점유가 없어 죽은 claim 하나가 **무인 루프를 영구 차단**했다. 강화 러너쪽엔
#   있고 여기만 없었다 — 같은 계통의 방어가 한쪽에만 깔린 전형이다.
#   충실구현 1회는 LLM ~10분 + 검증 ~6분이라 2시간이면 살아있을 리 없다.
# ★소유자 pid 를 남기고 **사망을 보면 나이 무관 즉시 회수**한다. 구판은 2시간 경과만 봐서,
#   에이전트가 죽으면 그 두 시간 동안 in_progress 복원 로직이 "아직 돌고 있다" 로 판단해
#   루프가 통째로 선다(2026-08-31 실사고: 22:58 에이전트 사망 후 45분간 halt_no_active_entry
#   만 반복, 회수 예정은 00:58 이었다). 강화 러너(rf_claim.R)는 이미 pid 사망을 본다 —
#   같은 계기가 한쪽에만 깔려 있으면 죽은 claim 하나가 루프를 영구 차단한다.
if [ -d "$CLAIM" ]; then
  CAGE=$(( ( $(date +%s) - $(date -r "$CLAIM" +%s 2>/dev/null || echo 0) ) / 3600 ))
  COWN=$(cat "$CLAIM/owner" 2>/dev/null || echo "")
  CDEAD=0
  CWIN=$(cat "$CLAIM/owner_win" 2>/dev/null || echo "")
  ## ★생존 판정은 Windows pid 로 한다 (2026-09-05 실측). kill -0 은 MSYS pid 공간을 보는데,
  ##   죽은 owner 69256 에 대해 TRUE 를 냈다(pid 재사용/잔존 테이블). 같은 pid 에 tasklist 는 0건.
  ##   그 오판이 in_progress + 고아 claim 교착을 만든다 — 2026-09-01 13시간 정지의 재발이 오늘이었다.
  ##   owner_win 이 없는 구판 claim 은 기존 kill -0 로 떨어진다(하위호환).
  if [ -n "$CWIN" ]; then
    tasklist //FI "PID eq $CWIN" //NH 2>/dev/null | awk -v p="$CWIN" '$2==p{f=1} END{exit !f}' || CDEAD=1
  elif [ -n "$COWN" ] && ! kill -0 "$COWN" 2>/dev/null; then
    CDEAD=1
  fi
  # owner 표식이 아예 없으면 구판이 만든 claim 이다 — 나이 기준만 적용한다
  if [ "$CDEAD" = "1" ] || [ "$CAGE" -ge 2 ]; then
    rm -rf "$CLAIM" 2>/dev/null
    jl claim_stale_reclaim "age_h=$CAGE dead=$CDEAD"
  fi
fi

# ★유한 재시도 (도훈 지시 "모든 작업 무인화" 정합 — 2026-08-30 실사고 수리)
#   실사고: 프롬프트 백틱 결함으로 no_engine → failed_needs_session 이 되자 루프가 통째로
#   멈췄다. active entry 가 없으면 두 러너 다 halt_no_active_entry 로 되돌아가고,
#   그 상태를 푸는 경로가 사람뿐이었다. **무인 파이프라인에 사람 대기 상태가 종점으로
#   존재하면 그건 무인이 아니다.** ⇒ 3회까지 자동 재시도, 소진하면 스킵리스트 → 다음 논문.
#   ★무한 재시도로 만들지 않는 이유: 진짜 재현 불가 논문에서 LLM 예산이 무한히 탄다.
"$PY" - "$REQ" "$CLAIM" <<'PYRETRY'
import io, json, os, sys, time
REQ, CLAIM = sys.argv[1], sys.argv[2]
try:
    d = json.loads(io.open(REQ, "rb").read().decode("utf-8"))
except Exception:
    sys.exit(1)
# ★in_progress 가 새 막다른 곰목이었다 (2026-08-30 실사고).
#   검증이 중간에 죽으면 상태가 in_progress 로 남는데, 그건 pending 도
#   failed_needs_session 도 아니라 무인 루프가 20분간 돌지도 멈추지도 못했다.
#   claim 이 없는데 in_progress 면 그 실행은 죽은 것이다 — pending 으로 되돌린다.
#   ★claim 유무로 판단하는 이유: 시간 문턱만 쓰면 정상 장시간 실행을 죽였다고 오판한다.
if d.get("status") == "in_progress" and not os.path.isdir(CLAIM):
    d["status"] = "pending"
    d["revived_from"] = "in_progress"
    d["revived_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    io.open(REQ, "wb").write(json.dumps(d, ensure_ascii=False, indent=1).encode("utf-8"))
    print("revived from in_progress (no claim)")
elif d.get("status") == "failed_needs_session":
    n = int(d.get("auto_retries") or 0)
    if n < 3:
        d["auto_retries"] = n + 1
        d["status"] = "pending"
        d["retry_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        io.open(REQ, "wb").write(json.dumps(d, ensure_ascii=False, indent=1).encode("utf-8"))
        print("retry %d/3" % (n + 1))
    else:
        d["status"] = "exhausted_retries"
        io.open(REQ, "wb").write(json.dumps(d, ensure_ascii=False, indent=1).encode("utf-8"))
        sys.exit(2)
PYRETRY
RRC=$?
if [ "$RRC" = "2" ]; then
  jl retries_exhausted
  "$PY" - "$REQ" "$ROOT/06_Registry/replication_skiplist.json" <<'PYSKIP'
import io, json, sys, time
REQ, SKP = sys.argv[1], sys.argv[2]
d = json.loads(io.open(REQ, "rb").read().decode("utf-8"))
pk = (d.get("paper") or {}).get("paper_key") or ""
try:
    sk = json.loads(io.open(SKP, "rb").read().decode("utf-8"))
except Exception:
    sk = {"schema": "replication_skiplist_v1", "entries": []}
if pk and not any(e.get("paper_key") == pk for e in sk.get("entries") or []):
    sk.setdefault("entries", []).append({
        "paper_key": pk, "status": "unreproducible",
        "added_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "last_failure": (d.get("failure") or ""),
        "reason": "무인 충실구현 3회 연속 실패(마지막 사유 %s) — 에이전트가 엔진을 산출하지 못했거나 검증기가 막았다. "
                  "★판정 철회는 status=revoked 로 (AX-000 — 새 각도면 재시도 정당)." % (d.get("failure") or "no_engine")})
    io.open(SKP, "wb").write(json.dumps(sk, ensure_ascii=False, indent=1).encode("utf-8"))
PYSKIP
  Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_next_paper.R" >> "$LOG" 2>&1
  exit 0
fi

"$PY" -c "
import io,json,sys
try: d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
except Exception: sys.exit(1)
sys.exit(0 if d.get('status')=='pending' else 1)" 2>/dev/null || { jl no_pending_request; exit 0; }
# ── ★환경 실패 백오프 게이트 (2026-09-07) ───────────────────────
#   모델 한도 소진은 사람도 리트라이도 못 고친다. 게이트가 없으면 매 tick(≈4분) 빈 CLI
#   호출이 쌓이고 로그가 오염된다. epoch 로 비교한다 — 문자열 시각은 시간대 표기에 깨진다.
#   ★재시도 예산을 안 태우므로 기다리는 동안 논문이 skiplist 로 내려앉지 않는다.
ENV_WAIT=$("$PY" -c "
import io,json,time
try: d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
except Exception: raise SystemExit(0)
t=d.get('env_retry_after_epoch')
if isinstance(t,(int,float)) and time.time() < t: print(int(t-time.time()))" 2>/dev/null)
if [ -n "$ENV_WAIT" ]; then
  jl halt_env_cooldown "wait_s=$ENV_WAIT" "kind=$("$PY" -c "
import io,json
try: print(json.loads(io.open(r'$REQ','rb').read().decode('utf-8')).get('last_env_failure') or '')
except Exception: print('')" 2>/dev/null)" "note=환경 실패 백오프 중 — 논문 사유 아님"
  exit 0
fi
# ── ★스킵리스트 게이트 (2026-09-04 실사고) ──────────────────────────────────
#   결합 런처가 스킵리스트 쌍을 재요청하던 결함은 런처 쪽에서 고쳤지만, **이미 쓰인 요청**은
#   그 수리가 못 막는다. 실측: 15:46 에 수리 전 런처가 쓴 요청이 남아 in_progress 로 죽었고,
#   재시도 장치가 그걸 pending 으로 되살리면 스킵리스트 쌍으로 3회를 또 태운다.
#   ⇒ 착수 직전에 한 번 더 본다. status=revoked 면 정상 후보다(철회 경로를 막지 않는다).
SKIPPED=$("$PY" -c "
import io,json,os,sys
req=r'$REQ'; sp=os.path.join(r'$ROOT','06_Registry','replication_skiplist.json')
try: d=json.loads(io.open(req,'rb').read().decode('utf-8'))
except Exception: sys.exit(0)
pk=(d.get('paper') or {}).get('paper_key') or ''
if not pk: sys.exit(0)
try: sk=json.loads(io.open(sp,'rb').read().decode('utf-8'))
except Exception: sys.exit(0)
for e in sk.get('entries') or []:
    if e.get('paper_key')==pk and (e.get('status') or '')!='revoked':
        print('%s|%s' % (pk, (e.get('reason') or '')[:100])); break" 2>/dev/null)
if [ -n "$SKIPPED" ]; then
  jl halt_skiplisted "key=${SKIPPED%%|*}" "note=스킵리스트 항목 — 착수하지 않는다(철회는 status=revoked)"
  "$PY" -c "
import io,json,time
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='skipped_by_skiplist'; d['skipped_at']=time.strftime('%Y-%m-%dT%H:%M:%S%z')
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"
  Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_next_paper.R" >> "$LOG" 2>&1
  exit 0
fi

command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli "who=$(whoami 2>&1)" "npm_ls=$(ls /c/Users/99922/AppData/Roaming/npm 2>&1 | paste -sd, - | cut -c1-200)" "npm_on_path=$(case ":$PATH:" in *Roaming/npm*) echo 1;; *) echo 0;; esac)"; exit 0; }
mkdir "$CLAIM" 2>/dev/null || { jl halt_claimed; exit 0; }
echo $$ > "$CLAIM/owner"
## ★Windows pid 를 함께 남긴다 — 회수 판정의 정본(위 CDEAD 주석 참조).
cat /proc/$$/winpid > "$CLAIM/owner_win" 2>/dev/null || true
trap 'rm -rf "$CLAIM" 2>/dev/null' EXIT

# ── 논문 정보 ─────────────────────────────────────────────────────────────────
eval "$("$PY" -c "
import io,json
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8')); p=d.get('paper') or {}
def q(s): return \"'\" + str(s).replace(\"'\",\"'\\\\''\") + \"'\"
print('P_TITLE=%s' % q(p.get('paper_title') or p.get('title') or ''))
print('P_URL=%s'   % q(p.get('url') or ''))
print('P_KEY=%s'   % q(p.get('paper_key') or ''))
print('P_FDEF=%s'  % q((p.get('factor_def') or '')[:400]))
print('P_FNAME=%s' % q(p.get('factor_name') or ''))
c=d.get('combo') or {}
print('IS_COMBO=%s' % q('1' if c else '0'))
print('C_SETKEY=%s' % q(c.get('setkey') or ''))
print('C_K=%s'      % q(c.get('k_items') or ''))
print('C_NP=%s'     % q(c.get('n_papers') or ''))
print('C_BEST_T=%s' % q(c.get('best_parent_t') if c.get('best_parent_t') is not None else ''))
print('C_TRIES=%s'  % q(c.get('tries_before') if c.get('tries_before') is not None else '0'))
# ★비결합 요청은 새 논문이다 — count_paper 키가 없다고 '세지 말라' 로 읽지 않는다 (2026-09-04 실사고:
#   무인 충실구현 전부 count_paper=0 → 결합 검토 카운터 정지 · 큐 미러 영구 침묵 · alpha-pending 과대).
#   결합만 combo.count_paper 를 명시하며(기본 FALSE), 최상위 count_paper 가 있으면 그것이 이긴다.
_cp = d.get('count_paper')
if _cp is None: _cp = (c.get('count_paper') if c else True)
print('C_COUNT=%s'  % q('1' if _cp else '0'))")"
[ -n "$P_URL" ] || { jl halt_no_url; exit 1; }

SLUG=$(printf '%s' "$P_KEY" | tr -c 'A-Za-z0-9' '_' | cut -c1-24)
WDIR="$ROOT/04_Research/strategies/RP_AUTO_${SLUG}"
# ★결합은 두 논문의 설계 산출물이라 단독 논문 작업본을 덮으면 안 된다.
#   paper_key 가 "combo:a+b" 라 SLUG 이 이미 다르지만, 접두로 의도를 드러낸다.
[ "${IS_COMBO:-0}" = "1" ] && WDIR="$ROOT/04_Research/strategies/RP_AUTO_COMBO_${SLUG}"
mkdir -p "$WDIR"
jl start "paper=$P_KEY" "url=$P_URL" "wdir=$WDIR"
# ★상태 전이 pending → in_progress (cleaner 의 distill_status 선례).
#   claim 이 1차 방어지만, 검증이 20분 넘게 돌 수 있어 그 사이 다른 소비자가 들어오면
#   LLM 호출이 중복된다. 상태가 그 창을 눈에 보이게 만든다(2026-08-30 실측: 중복 1회).
"$PY" -c "
import io,json,time
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='in_progress'; d['started_at']=time.strftime('%Y-%m-%dT%H:%M:%S%z')
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"

# ── 측정 + 검증 호출 — 한 곳 (정상 경로와 아래 감사 미실행 재시도가 같은 호출을 쓴다) ──
rp_verify(){
  QM_ROOT="$ROOT" RP_WDIR="$WDIR" RP_URL="$P_URL" RP_TITLE="$P_TITLE" RP_KEY="$P_KEY" \
    QVEST_RP_JLOG="$JLOG" RP_IS_COMBO="${IS_COMBO:-0}" RP_COUNT_PAPER="${C_COUNT:-1}" \
    Rscript "$ROOT/02_Infrastructure/ops/rf_replication_verify.R" >> "$LOG" 2>&1
  VRC=$?
  jl verify_done "rc=$VRC"
  return $VRC
}
# ── ★감사 미실행 재시도 = 검증기만 (2026-09-06 실사고) ─────────────────────────
#   audit_not_run 은 엔진의 결함이 아니라 감사 레인의 결함이다(역슬래시 QM_ROOT 병합 즉사 · 킬스위치 · CLI 부재).
#   검증기가 그 사유로 failed_needs_session 을 내면 위 auto_retries 가 pending 으로 되살리는데, 그때 30분짜리
#   Fable 재구현을 다시 태울 이유가 없다 — 엔진이 그대로 있으면 에이전트를 건너뛰고 측정+감사만 다시 돈다.
#   재시도 상한은 auto_retries(3회) 규약 그대로다(이 분기는 그 안에서 **무엇을 다시 하나**만 바꾼다).
#   엔진이 없으면(감사 기각으로 engine.rejected*.R 로 이름이 바뀐 경우) 정상 경로로 간다.
#   ★표식은 여기서 지운다 — 남겨 두면 뒤의 재구현 프롬프트가 낡은 사유(audit_not_run)를 안고 간다.
PREV_FAIL=$("$PY" -c "
import io,json
try: print((json.loads(io.open(r'$REQ','rb').read().decode('utf-8')).get('failure') or '').strip())
except Exception: print('')" 2>/dev/null)
if [ "$PREV_FAIL" = "audit_not_run" ] && [ -s "$WDIR/engine.R" ]; then
  jl verify_only_retry "paper=$P_KEY" "note=감사 미실행 재시도 — 에이전트 없이 검증기(측정+감사)만 재실행(엔진 보존)"
  "$PY" -c "
import io,json,time
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['failure']=''; d['failure_detail']=''; d['verify_only_at']=time.strftime('%Y-%m-%dT%H:%M:%S%z')
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"
  rp_verify; exit $?
fi

# ── 헤드리스 에이전트 (권한 축소 · 산출물은 엔진 1개) ────────────────────────
PROMPT="논문 1편의 **충실구현**을 수행하라. 산출은 **엔진 R 파일 하나**다.

## 논문
제목: ${P_TITLE}
원문: ${P_URL}
트리아지가 뽑은 후보 팩터: ${P_FNAME}
정의 초안: ${P_FDEF}

## 판정 순서 (★2026-08-30 도훈 지시 — 어떤 논문이라도 팩터 전략으로 변형 가능한
##   형태인지부터 판단하는 게 참된 리서치의 자세다. 인사이트가 중요한 거니까)
**논문이 횡단면 종목선택 형태가 아니어도 즉시 포기하지 마라.** 순서는 이렇다:

1. **충실구현이 되는가** — 논문 그대로 신호·종목수·비중·리밸. 되면 fidelity=faithful.
2. 안 되면 **인사이트가 이식되는가** — 논문의 *기전*을 횡단면 팩터로 옮길 수 있는가.
   되면 fidelity=adapted. ★이때 **무엇을 남기고 무엇을 바꿨는지 명시 의무**다.
   예: 리더-팔로워 군집 논문에서 특정 군집기·정렬기는 **한 구현일 뿐**이고, 기전은
   선행 종목의 움직임이 후행 종목을 예측한다는 것이다. 그건 가용한 추정기로 이식된다.
3. **데이터가 진짜 없으면** ABORT. 대리변수로 지어내지 마라 — 레버리지 ETF NAV,
   장중·종가단일가 같은 미보유 패널은 근사 대상이 아니다. ABORT.txt + 필요 데이터 명시.

★adapted 는 정직한 결과다. 등급은 계약이 내되 귀속이 충실구현이 아니라 **착안**이며,
  그 구분이 원장에 남으므로 misattribution 이 되지 않는다. 인사이트를 버리는 것보다 낫다.
★단 **지어내기와 이식은 다르다**: 논문이 주지 않는 수치를 임의로 정하면 그건 이식이 아니다.
  이식은 *기전*을 옮기는 것이고, 파라미터는 **우리 고정 축**(25종·월간·EW)을 쓴다.

★산출에 \`${WDIR}/FIDELITY.json\` 을 함께 써라 — 키 6개:
  fidelity(faithful 또는 adapted) · kept(논문에서 남긴 기전 1줄) ·
  changed(바꾼 것과 이유 1줄) · paper_original_form(논문 원래 산출 형태 1줄) ·
  ★portfolio_spec(러너에 그대로 넘어가는 **기계 판독** 객체) ·
  ★commission_paper(논문 명시 왕복비용. 미명시면 null).
  faithful 이면 changed 는 유니버스만 K200 합집합 KQ150 이다.
  portfolio_spec 은 산출 형태에 맞춰라 — 산문으로 적지 말고 이 형태로:
    PORTFOLIO 를 만들면 {\"construction\":\"engine_direct\"}
      (네가 만든 비중이 곧 논문 비중이다. 롱숏이면 반드시 이 값이어야 한다 —
       이게 없으면 러너가 숏 다리를 버리고 롱온리 top-N 으로 다시 구성한다.)
    FACTORS 만 만들면 {\"construction\":\"top_n_long\",\"weighting\":\"ew\",\"rebalance\":\"monthly\",\"top_n\":<논문값>}
  ★engine.R 주석에만 적지 마라 — 주석은 아무도 읽지 않는다. 이 파일이 유일한 통로다.

### ★changed 신고 체크리스트 — 논문에 없는데 네가 넣은 것을 **전부** 적어라
실측(2026-09-04, 적대적 감사 4편 · 지적 20건): 그중 **9건이 이 종류**였다 —
논문을 못 읽은 게 아니라, 합리적인 방어 코드를 넣고 **신고를 잊은** 것이다.
그래서 재구현 한 사이클(에이전트 12분 + 측정 + 감사 6축)이 통째로 타율다.
아래를 한 줄씩 훑고 해당하는 것을 changed 에 옮겨라. 해당 없으면 적지 마라.

- 값 하한·상한·커버리지 요건 (예: 관측 80% 이상만 정렬, 최소 종목수 30)
- 수치 가드 (분모 0 방지 · 변동성 바닥 · |값| 상한 치환 · winsorize·clip)
- 결측 처리 (nafill/locf · 상장 전 상수 · 비유한값 0 치환)
- 난수·재현 (set.seed · 초기값 · 앞상빌업 횟수 · 앜상블 여부)
- 창·워밍업 길이를 논문과 다르게 잡은 것
- 논문이 여러 설정을 보고했는데 하나를 골랏으면 **어느 칸을 골랐는지**
- 논문 수식을 근사한 것 (폐형·선형화·이산화)

★\"영향이 미미해서 안 적었다\" 는 사유가 아니다. 영향의 크기를 판단하는 것은
감사와 도훈이지 구현자가 아니고, 그 판단은 **적혀 있어야** 할 수 있다.
적어둔 변경은 adapted 로 통과하고, 안 적은 변경은 misdeclared 로 재구현을 부른다 —
**적는 쪽이 싼다.**

## 산출 (이것만)
## 산출 (이것만)
\`${WDIR}/engine.R\` — source 되면 \`FACTORS(Date,Ticker,Score)\` 또는
\`PORTFOLIO(Date,Ticker,Weight,Leg)\` 를 만드는 R 스크립트. 호출자가 환경에 \`RAWDATA\`·\`BM_DT\` 를 넣어준다.

## 축 (변수 아님)
- **논문 그대로** 복제하되 **유니버스만 K200∪KQ150**. 유동성 하한 adv20 ≥ 2e8 은 t-1 로 적용.
- 기간 2005-01-01~. 종목수·비중·리밸 주기는 논문 명시값을 따른다.
- **PIT C1~C15 절대**: 모든 창의 종점은 t-1. 전 표본 통계 금지(rolling/expanding만).
  팩터 DB 는 \`load_month_factors()\` 경유(C15), \`Z_Score_Aligned\` 만 소비(C13).
  ★\`detect_lookahead\` 는 비선언 idiom(전 표본 cov()/mean() · shift(-1) · 수동 미래 인덱싱)을
  못 잡는다 — 통과를 근거로 삼지 말고 **구조로** 보장하라.
- 원문 접근이 불가하면 **지어내지 마라**. \`${WDIR}/ABORT.txt\` 에 사유를 쓰고 끝내라.

## 실행 환경
- R 349개 패키지가 이미 있고(data.table · arrow · PerformanceAnalytics · xts · quadprog ·
  cluster · matrixStats · glmnet · TTR · roll · proxy 등), **없는 패키지는 호출자가 자동 설치**한다
  (검증 러너가 엔진을 스캔해 CRAN 에서 최대 6개까지 설치). 그러니 필요한 패키지를 자유롭게 쓰라.
- 다만 **정말 필요한 것만** 쓰라 — 의존이 6개를 넘으면 착수가 차단된다.
- 파이썬 연동(reticulate)도 가능하나, R 로 충분하면 R 로 하라(무인 실행에서 층이 하나 줄어든다).
- 원문 접근이 불가하거나 논문을 훼손하지 않고는 구현할 수 없으면 \`ABORT.txt\` 에 사유를 쓰고 멈춰라.

## 금지
- \`${WDIR}\` 밖 쓰기. 원장·설정·훅·테스트 수정. 백테스트 직접 실행(측정은 호출자 계약이 한다).
- 등급·성과 수치 선언(계약이 낸다).

엔진을 쓰고 1~2줄로 무엇을 구현했는지만 보고하라."

# --- KOMBO: 결합 설계 프롬프트 (2026-09-04 도훈 지시) -----------------------
#   ★"조합 갯수도, 설계 방식도 제한하지 마라" (도훈). 그래서 이 프롬프트는 형태를 지정하지
#   않는다 — 재료 논문과 실측 기록만 주고 **무엇을 어떻게 맞물릴지는 에이전트가 정한다**.
#   구판(2026-09-04 오전)은 맞물림 4종 메뉴에서 고르게 하고 못 찾으면 ABORT 시켰다.
#   그건 리서치를 규칙으로 환원한 것이고, 규칙으로 환원될 것이면 LLM 을 부를 이유가 없다.
#   ★남는 제약은 설계 제약이 아니라 **계약**이다 — PIT C1~C15 · 고정 축 · 임의 상수 금지 ·
#     산출 형식(engine.R + FIDELITY.json). 그건 공통 꼬리가 지고, 여기서 다시 적지 않는다.
if [ "${IS_COMBO:-0}" = "1" ]; then
  KOMBO_TXT="$ROOT/.cache/rf_combo_materials.txt"
  "$PY" - "$REQ" "$KOMBO_TXT" <<'PYKOMBO'
import io, json, sys
REQ, OUT = sys.argv[1], sys.argv[2]
d = json.loads(io.open(REQ, "rb").read().decode("utf-8"))
c = d.get("combo") or {}
L = []
L.append("## 재료 논문 (%s편)" % len(c.get("papers") or []))
for n, q in enumerate(c.get("papers") or [], 1):
    L.append("%d. %s" % (n, q.get("title") or q.get("key") or "?"))
    L.append("   원문: %s" % (q.get("url") or ""))
L.append("")
L.append("## 이 재료들의 이전 구현 (참고용 — 합치는 것이 설계가 아니다)")
for it in c.get("item_engines") or []:
    L.append("- %s : %s  (단독 다중검정 t %s)" % (it.get("key"), it.get("engine"), it.get("t")))
io.open(OUT, "w", encoding="utf-8", newline="").write("\n".join(L))
PYKOMBO
  PROMPT_TAIL=$(printf '%s\n' "$PROMPT" | sed -n '/^## 산출 (이것만)/,$p')
  PROMPT="논문 여러 편을 재료로 하는 **결합 전략**을 설계하라. 산출은 **엔진 R 파일 하나**다.

$(cat "$KOMBO_TXT")

## 설계 — 방식은 네가 정한다
결합의 형태를 지정하지 않는다. 고를 목록도 없다. 논문을 읽고 **무엇이 어떻게 맞물리는지
네가 판단하라.** 재료를 전부 쓸 필요도 없다 — 읽어 보고 일부만 쓰는 편이 낫다면 그렇게 하고
그 판단을 적어라.

남길 것은 형식이 아니라 **근거**다. FIDELITY.json 의 changed 에 두 줄로:
  (1) 무엇을 어떻게 결합했는가
  (2) 그것이 각 재료 **단독보다 나을 것**이라 보는 이유 — 반증 가능한 형태로

## 실측 기록 (금지가 아니라 자료다)
이 저장소는 결합 기저를 \"두 엔진 신호의 rank-Z 평균\" 으로 만든 판을 **5회** 측정했고,
전부 재료 단독 성적을 못 넘었다(그 계보 최고 다중검정 t 0.766 · 합격선 2.95).
이 재료 집합의 최고 단독 t 는 ${C_BEST_T} 이고, 같은 집합을 시도한 횟수는 ${C_TRIES} 회다.
평균을 다시 고르는 것도 네 자유지만, 이 기록을 읽고 고르라는 뜻이다.

★FIDELITY.json 의 fidelity 는 \"combination\" 으로 적어라. 나머지 키는 아래 규약과 같다.

${PROMPT_TAIL}"
fi

# --- 재구현 지적사항 (적대적 충실도 감사 2026-09-04) -------------------------
#   감사가 misdeclared 를 내면 검증기가 소비를 보류하고 요청을 pending 으로 되돌린다.
#   그때 지적사항을 프롬프트에 얹지 않으면 같은 구현이 그대로 다시 나온다 —
#   재시도가 아니라 되풀이가 된다(재개 장치의 고전적 실패 형태).
AUDFB=$("$PY" -c "
import io,json
try:
    d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
    print(d.get('audit_feedback') or '')
except Exception: print('')" 2>/dev/null)
# ★측정 실패 사유 — 사유별로 **다른 프레이밍**에 싣는다 (도훈 지시 2026-09-04).
#   뭉뚱그려 오류 문자열만 던지면 에이전트가 증상을 지워 넘긴다("adj 를 안 쓰면 되지").
#   그래서 종류를 갈라 "무엇을 다시 보라" 를 함께 준다. PIT 는 따로 세운다 — 계층 무관 절대다.
FAILFB=$("$PY" -c "
import io,json
try: d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
except Exception: d={}
why=(d.get('failure') or '').strip(); det=(d.get('failure_detail') or '').strip()
if not why: raise SystemExit
H={
 'pit_structural': ('PIT 구조 위반 — 계층 무관 절대 규칙이다',
   '이건 코드 오류가 아니라 **설계 오류**다. 창의 종점이 t-1 인지, 전 표본 통계를 쓰지 않았는지, '
   'Z_Score_Aligned 만 소비했는지를 구조로 다시 세워라. 우회하지 말고 되돌려라.'),
 'fixed_axis_violation': ('고정 축 위반',
   '종목수 25 이하 · long-only · 기간 · 비용은 협상 대상이 아니다. 논문 값과 충돌하면 '
   'FIDELITY.changed 에 그 사실을 적고 고정 축을 따르라.'),
 'replication_error': ('엔진 실행 오류',
   '오류를 **없애는 것**이 목표가 아니다. 그 줄이 논문의 어느 대목을 구현하려던 것인지 다시 보고, '
   '그 대목을 올바르게 쓰면 오류가 사라지는 형태로 고쳐라. 증상만 지우면 충실도 감사에서 걸린다.'),
 'too_many_missing_packages': ('의존 패키지 과다',
   '설계를 줄여라. 없는 패키지를 쓰는 것보다 **더 단순한 구현**이 낫다 — 기전이 남으면 된다.'),
 'dependency_install_failed': ('의존 설치 실패',
   '네 잘못이 아니다. 그 패키지 없이 되는 구현으로 바꿔라.'),
 'no_authoritative_remeasure': ('계약 미경유(측정 산출물 없음)',
   '엔진이 FACTORS 또는 PORTFOLIO 를 규약대로 내지 못했을 수 있다. 산출 형태를 먼저 확인하라.'),
 'audit_not_run': ('충실도 감사 미실행 — 앞 판 엔진의 결함이 아니었다',
   '앞 판은 측정을 통과했고 감사 레인이 안 돌았을 뿐이다(정상은 엔진을 두고 검증기만 재실행한다). '
   '엔진 파일이 없어 다시 부르는 것이니, 논문을 다시 읽고 같은 기준(충실구현)으로 구현하라.'),
}
title, guide = H.get(why, ('측정 실패', '아래 사유를 읽고 같은 실패를 반복하지 마라.'))
print('### %s' % title)
print(guide)
if det: print(''); print('원문 오류: %s' % det[:400])
" 2>/dev/null)
if [ -n "$FAILFB" ]; then
  jl reimplement_with_failure "paper=$P_KEY"
  PROMPT="$PROMPT

## ★재구현이다 — 앞 판이 **측정에서** 실패했다
아래는 계약이 낸 실패 사유다. 같은 자리에서 다시 죽지 마라.

$FAILFB

앞 판은 ${WDIR}/engine.R 에 그대로 있다(감사 기각분은 engine.rejected*.R).
★그래도 **목적은 충실구현이다.** 오류를 피하려고 논문을 훼손하지 마라 — 그렇게 만든 엔진은
측정은 통과하고 충실도 감사에서 걸린다(두 번 낭비)."
fi
if [ -n "$AUDFB" ]; then
  jl reimplement_with_audit "paper=$P_KEY"
  PROMPT="$PROMPT

## ★재구현이다 — 앞 구현이 적대적 충실도 감사에서 기각됐다
아래는 감사자가 **원문과 대조해** 찾은 지적이다. 같은 구현을 다시 내지 마라.

$AUDFB

앞 판은 ${WDIR}/engine.rejected*.R 로 남아 있다. 무엇이 틀렸는지 보고, 지적된 지점을
논문 원문으로 되돌려라. 지적이 부당하다고 판단하면 FIDELITY.json 의 changed 에
**왜 그것이 논문과 일치하는지** 원문 근거로 적어라 — 침묵으로 넘기지 마라."
fi

# ★모델·노력수준 명시 (도훈 지적 2026-08-30 — 구판은 미지정이라 CLI 기본값에 의존했다).
#   충실구현은 **깊이** 문제다: 논문 하나를 정확히 읽고 기전을 이식할 수 있는지 판단한다.
#   넓이(팬아웃)가 아니므로 울트라코드가 아니라 **단일 에이전트 · 최대 노력**이 맞다.
. "$ROOT/02_Infrastructure/ops/rf_axiom_brief.sh"
AXB="$(rf_axiom_brief)"
if [ -n "$AXB" ]; then PROMPT="$PROMPT

$AXB"; fi

# ★모델·노력수준은 설정의 llm 블록이 정본이다 (2026-09-04) — 네 레인이 각자 기본값을
#   들고 있으면 한 곳을 바꿔도 나머지가 그대로 남는다. 환경변수는 그대로 최우선.
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve replication "${QVEST_RP_MODEL:-}" "${QVEST_RP_EFFORT:-}"
RP_MODEL="$LLM_MODEL"
RP_EFFORT="$LLM_EFFORT"
jl model_selected "model=$RP_MODEL" "effort=$RP_EFFORT"
# ★프롬프트는 stdin 으로 (2026-09-04): argv 로 넘기면 Windows 인자 상한(32K)에 걸려 에이전트가 안 뜰다 — 승격 entry B1 설계 재료 41KB 실사고.
PF="$WDIR/prompt.txt"
printf %s "$PROMPT" > "$PF"
timeout 3000 claude -p < "$PF" \
  --model "$RP_MODEL" --effort "$RP_EFFORT" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep,WebFetch,WebSearch" \
  --disallowed-tools "Bash,Agent" \
  --add-dir "$WDIR" \
  >> "$LOG" 2>&1
RC=$?
jl agent_done "rc=$RC"

if [ -f "$WDIR/ABORT.txt" ]; then
  jl aborted_by_agent "reason=$(head -c 120 "$WDIR/ABORT.txt" | tr '\n' ' ')"
  "$PY" -c "
import io,json
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='failed_needs_session'; d['failure']='agent_abort'
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"
  exit 1
fi
# ★환경 실패와 리서치 실패를 구분한다 — 401/인증만료·모델 한도 소진은 "논문이
#   어려웠다" 가 아니라 "환경을 고치거나 기다리면 된다" 이다.
#   실사고 2026-08-30: OAuth 만료. 실사고 2026-09-07: 충실구현 레인이 Fable 한도에
#   걸렸는데("You've reached your Fable limit" · 09-02 판은 "You've hit your session limit ·
#   resets 11:30pm" — 문구가 한 종이 아니다) 이 분기가 그 문구를 안 봐서 no_engine 으로
#   떨어졌고, 재시도 3회를 태운 뒤 **3편 결합 논문이 skiplist 에 'unreproducible' 로
#   영구 등재**될 참이었다. 모델이 안 떴다는 사실은 논문에 대한 증거가 아니다.
# ★같은 날 발견한 두 번째 결함: 알림 블록이 한 번도 나간 적이 없다. 구판은 따옴표 헤레독(quoted delimiter)이라 $ROOT 가 안 풀렸고(리터럴 경로), 문자열 안에 생짜 개행이 있어
#   파이썬이 파싱에서 죽었다 — 2>/dev/null || true 가 그 죽음을 삼켰다.
#   ⇒ ROOT 를 argv 로 넘기고 개행은 \n 으로 쓴다(같은 계통 재발 방지 = 검사 B절).
ENV_FAIL=""
if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$LOG" 2>/dev/null; then
  ENV_FAIL="claude_auth_expired"
elif grep -qiE "(reached|hit) your [A-Za-z0-9 .-]*limit|(session|usage) limit|manage usage credits|rate_limit_error|API Error: 429|resets [0-9]+(:[0-9]+)?(am|pm)" "$LOG" 2>/dev/null; then
  ENV_FAIL="model_quota_exhausted"
fi
if [ -n "$ENV_FAIL" ]; then
  jl halt_env_failure "kind=$ENV_FAIL" "hint=환경 실패 — 리서치 실패 아님(재시도 예산 미소모)"
  "$PY" - "$REQ" "$ENV_FAIL" "${RP_ENV_COOLDOWN_SEC:-1800}" <<'PYENV'
import io, json, sys, time
REQ, KIND, CD = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = json.loads(io.open(REQ, "rb").read().decode("utf-8"))
d["status"] = "pending"                     # ★pending 복원 — 환경이 풀리면 자동 재개
d["last_env_failure"] = KIND
d["last_env_failure_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
# ★재시도 예산(auto_retries)을 태우지 않는다 — 모델이 안 떠서 산출이 없는 것은
#   논문에 대한 증거가 아니다. 구판은 이 경로가 없어 no_engine 3회 → skiplist 로 갔다.
# ★백오프: 한도는 사람이 못 고친다. 매 tick 재시도하면 빈 호출만 쌓인다.
#   문자열 비교는 시간대 표기에 깨진다 — epoch 를 게이트의 정본으로 둔다.
if KIND == "model_quota_exhausted":
    d["env_retry_after_epoch"] = int(time.time()) + CD
    d["env_retry_after"] = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() + CD))
io.open(REQ, "wb").write(json.dumps(d, ensure_ascii=False, indent=1).encode("utf-8"))
PYENV
  "$PY" - "$ROOT" "$ENV_FAIL" <<'PYX' 2>/dev/null || true
import io, os, sys, time
ROOT, KIND = sys.argv[1], sys.argv[2]
m = os.path.join(ROOT, ".cache", "scheduler_alerts")
os.makedirs(m, exist_ok=True)
f = os.path.join(m, "replication_env_%s_%s.alert" % (KIND, time.strftime("%Y%m%d")))
MSG = {"claude_auth_expired": "claude CLI OAuth 만료 — 무인 충실구현 정지. 재인증 필요",
       "model_quota_exhausted": "충실구현 레인 모델 한도 소진 — 재시도 예산은 안 태웠다. 한도 회복 시 자동 재개"}
if not os.path.exists(f):
    io.open(f, "w", encoding="utf-8").write(MSG.get(KIND, KIND) + "\n")
PYX
  exit 2
fi
[ -s "$WDIR/engine.R" ] || { jl no_engine; "$PY" -c "
import io,json
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='failed_needs_session'; d['failure']='no_engine'
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"; exit 1; }

# ── 측정 + 검증 (계약이 판정한다 — 에이전트 진술은 근거가 아니다) — rp_verify(위 정의) ──
rp_verify; exit $?
