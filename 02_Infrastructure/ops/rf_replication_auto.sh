#!/usr/bin/env bash
#==============================================================================
# rf_replication_auto.sh — **논문 충실구현 무인 실행** (도훈 지시 2026-08-30)
#
# ★경계 변경 고지: cleaner 선례가 "무인 LLM 호출은 권한/판단 리스크로 배제" 라고 명시했고
#   나도 그 선을 지켜 왔다. 도훈이 두 번 명시 요청해 그 경계를 넘는다. 대신 리스크를 구조로 막는다:
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
  if [ -n "$COWN" ] && ! kill -0 "$COWN" 2>/dev/null; then CDEAD=1; fi
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
        "reason": "무인 충실구현 3회 연속 no_engine — 에이전트가 엔진을 산출하지 못했다. "
                  "★판정 철회는 status=revoked 로 (AX-000 — 새 각도면 재시도 정당)."})
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
command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }
mkdir "$CLAIM" 2>/dev/null || { jl halt_claimed; exit 0; }
echo $$ > "$CLAIM/owner"
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
print('C_A=%s'       % q(c.get('a') or ''))
print('C_B=%s'       % q(c.get('b') or ''))
print('C_A_URL=%s'   % q(c.get('a_url') or ''))
print('C_B_URL=%s'   % q(c.get('b_url') or ''))
print('C_A_TITLE=%s' % q(c.get('a_title') or ''))
print('C_B_TITLE=%s' % q(c.get('b_title') or ''))
print('C_A_T=%s'     % q(c.get('a_t') if c.get('a_t') is not None else ''))
print('C_B_T=%s'     % q(c.get('b_t') if c.get('b_t') is not None else ''))
print('C_A_ENGINE=%s' % q(c.get('a_engine') or ''))
print('C_B_ENGINE=%s' % q(c.get('b_engine') or ''))
print('C_COUNT=%s'   % q('1' if c.get('count_paper') else '0'))")"
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
#   결합은 "두 엔진의 rank-Z 평균" 이 아니다. 두 논문을 읽고 **하나의 전략을 설계**하는 일이다.
#   공통 꼬리(산출 형식·고정 축·실행 환경·금지)는 위 프롬프트에서 그대로 잘라 쓴다 —
#   여기에 다시 적으면 두 벌이 갈라지고, 갈라지는 순간 한쪽만 고쳐진다.
if [ "${IS_COMBO:-0}" = "1" ]; then
  PROMPT_TAIL=$(printf '%s\n' "$PROMPT" | sed -n '/^## 산출 (이것만)/,$p')
  PROMPT="논문 **2편을 결합한 전략**을 설계하라. 산출은 **엔진 R 파일 하나**다.

## 논문 A
제목: ${C_A_TITLE}
원문: ${C_A_URL}
단독 성적(다중검정 t, 현행 축): ${C_A_T}

## 논문 B
제목: ${C_B_TITLE}
원문: ${C_B_URL}
단독 성적(다중검정 t, 현행 축): ${C_B_T}

## 설계 원칙 (★이게 이 작업의 전부다)
- **두 신호를 평균하지 마라.** rank-Z 평균은 이미 다섯 번 돌렸고 전부 희석이었다
  (결합 entry 5건 · 최고 t 0.766 · 부모 단독 성적을 한 번도 못 넘었다). 평균은 설계가 아니다.
- 두 논문을 읽고 **기전이 어떻게 맞물리는지**를 먼저 정하라. 쓸 만한 맞물림의 예:
  (1) 한쪽이 **자격**을 정하고 다른 쪽이 **순위**를 정한다 (조건부 선택)
  (2) 한쪽이 **국면**을 말하고 다른 쪽 신호를 그 국면에서만 쓴다 (조건부 발화)
  (3) 한쪽의 구조적 결함을 다른 쪽이 **직교 보완**한다 (잔차 위에 얹기)
  (4) 두 논문이 같은 잠재변수를 다른 관측면으로 재고 있다 (측정 결합)
  맞물림을 못 찾겠으면 **그렇다고 적고 ABORT** 하라 — 억지 결합은 희석 한 건을 더 만들 뿐이다.
- 선택한 맞물림이 **왜 단독보다 나은지**를 한 줄로 적어라. 그 줄은 반증 가능해야 한다.
- 파라미터는 논문에서 오거나 그 시점 데이터에서 추정한다. 임의 상수 금지.

★산출에 \`${WDIR}/FIDELITY.json\` 을 함께 써라 — 결합은 키 값이 다르다:
  fidelity(\"combination\" 고정) · kept(두 논문에서 각각 남긴 기전 1줄씩) ·
  changed(맞물림 방식과 그 근거 1줄) · paper_original_form(두 논문의 원래 산출 형태) ·
  portfolio_spec(기계 판독 객체 — 아래 형식) · commission_paper(null 가능).
  결합 전략의 산출 형태는 네가 정한다:
    PORTFOLIO 를 만들면 {\"construction\":\"engine_direct\"}
    FACTORS 만 만들면 {\"construction\":\"top_n_long\",\"weighting\":\"ew\",\"rebalance\":\"monthly\",\"top_n\":25}

## 참고 (베끼지 말 것 — 두 논문의 이전 단독 구현이다)
- A: ${C_A_ENGINE:-없음}
- B: ${C_B_ENGINE:-없음}
읽어서 데이터 접근 방식을 참고하는 것은 좋다. 다만 **두 파일을 합치는 것은 설계가 아니다.**

${PROMPT_TAIL}"
fi

# ★모델·노력수준 명시 (도훈 지적 2026-08-30 — 구판은 미지정이라 CLI 기본값에 의존했다).
#   충실구현은 **깊이** 문제다: 논문 하나를 정확히 읽고 기전을 이식할 수 있는지 판단한다.
#   넓이(팬아웃)가 아니므로 울트라코드가 아니라 **단일 에이전트 · 최대 노력**이 맞다.
RP_MODEL="${QVEST_RP_MODEL:-opus}"
RP_EFFORT="${QVEST_RP_EFFORT:-max}"
jl model_selected "model=$RP_MODEL" "effort=$RP_EFFORT"
timeout 3000 claude -p "$PROMPT" \
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
# ★환경 실패와 리서치 실패를 구분한다 — 401/인증 만료는 "논문이 어려웠다" 가 아니라
#   "재인증하면 된다" 이고, 뭉뚱그리면 리서처가 엉뚱한 판단을 한다(2026-08-30 실측: OAuth 만료).
if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$LOG" 2>/dev/null; then
  jl halt_auth_expired "hint=claude 재인증 필요 — 리서치 실패 아님"
  "$PY" -c "
import io,json
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='pending'                      # ★pending 복원 — 재인증 후 자동 재시도된다
d['last_env_failure']='claude_auth_expired'
d['last_env_failure_at']=__import__('time').strftime('%Y-%m-%dT%H:%M:%S%z')
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"
  "$PY" - <<'PYX' 2>/dev/null || true
import io, os, time
m = r"$ROOT/.cache/scheduler_alerts"
os.makedirs(m, exist_ok=True)
f = os.path.join(m, "replication_auth_%s.alert" % time.strftime("%Y%m%d"))
if not os.path.exists(f):
    io.open(f, "w", encoding="utf-8").write("claude CLI OAuth 만료 — 무인 충실구현 정지. 재인증 필요
")
PYX
  exit 2
fi
[ -s "$WDIR/engine.R" ] || { jl no_engine; "$PY" -c "
import io,json
d=json.loads(io.open(r'$REQ','rb').read().decode('utf-8'))
d['status']='failed_needs_session'; d['failure']='no_engine'
io.open(r'$REQ','wb').write(json.dumps(d,ensure_ascii=False,indent=1).encode('utf-8'))"; exit 1; }

# ── 측정 + 검증 (계약이 판정한다 — 에이전트 진술은 근거가 아니다) ────────────
QM_ROOT="$ROOT" RP_WDIR="$WDIR" RP_URL="$P_URL" RP_TITLE="$P_TITLE" RP_KEY="$P_KEY" \
  RP_IS_COMBO="${IS_COMBO:-0}" RP_COUNT_PAPER="${C_COUNT:-1}" \
  Rscript "$ROOT/02_Infrastructure/ops/rf_replication_verify.R" >> "$LOG" 2>&1
VRC=$?
jl verify_done "rc=$VRC"
exit $VRC
