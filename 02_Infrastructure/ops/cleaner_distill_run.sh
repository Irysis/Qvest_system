#!/usr/bin/env bash
#==============================================================================
# cleaner_distill_run.sh — 주간 증류 **무인 레인** (도훈 지시 2026-09-05)
#
# 무엇을 바꾸나:
#   구판은 스윕(토 09:00)이 재료만 쌓고 status="awaiting_distill" 로 멈춘 뒤, 다음 대화
#   세션의 /cleaner 가 증류하기로 되어 있었다. 그 세션이 3주 안 왔다 — digest 마지막
#   2026-08-15, pending_5axis 백로그 49→104건. 2026-07-04 "증류 자동화 금지" 와
#   2026-08-30 "모든 작업을 무인화" 가 충돌하던 지점이고, 도훈이 무인화로 정합했다.
#
# 범위 (도훈 2026-09-05 ①안 + 삭제 전면 무인):
#   ① weekly_digest 작성(실측만)  ② DIST pending_5axis → proposed 자동초안(적대검증 5체크)
#   ③ 미적립 학습 L-code 발행     ④ 잔재 삭제 — **판단은 LLM, 집행·검증은 기계**
#   ★불변: proposed → distilled 활성화는 여전히 도훈 승인(INV-6). 초안은 주입 안 된다.
#
# 안전 (rf_b1_design.sh 규율 승계):
#   ① 에이전트는 **Bash 를 못 쓴다** — 스스로 지울 수 없고, 삭제 요청을 JSON 으로만 낸다.
#   ② 집행 전 기계가 재도출한다: 보호목록·참조0 git grep·24h mtime·건수/용량 상한.
#   ③ 검증 실패 = release 하지 않음 → 다음 훅이 재시도(조용한 통과 없음).
#   ④ claim 으로 세션 /cleaner 와의 2-pass 차단, gate 로 2계층 러너와의 충돌 회피.
#
# 호출: Qvest_WeeklyCleaner.bat(스윕 직후) · morning_run.sh [0.75](일간 재시도)
#       수동: bash 02_Infrastructure/ops/cleaner_distill_run.sh
# 연기(exit 11)는 실패가 아니다 — pending 이 남아 다음 훅이 집는다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
LIB="$ROOT/02_Infrastructure/ops/cleaner_distill_lib.R"
LOG="$ROOT/.cache/scheduler_logs/cleaner_distill_$(date +%Y%m%d).log"
OWNER="auto_distill"
mkdir -p "$(dirname "$LOG")"

jl(){ echo "[$(date -Iseconds)] [cleaner_distill] $*" >> "$LOG"; echo "[cleaner_distill] $*"; }

# ── (0) 게이트 — 꺼짐/할 일 없음/충돌 판정 ─────────────────────────────────────
GV="$(Rscript "$LIB" gate 2>>"$LOG")"; GRC=$?
jl "gate rc=$GRC $GV"
case "$GRC" in
  0)  : ;;                                   # 진행
  10) exit 0 ;;                              # 할 일 없음 — 무동작(정상)
  11) exit 0 ;;                              # 충돌 — 연기(다음 훅 재시도). 실패 아님
  12) exit 0 ;;                              # kill switch
  *)  jl "gate 비정상 rc=$GRC — 물러남"; exit 0 ;;
esac

WEEK="$("$PY" -c "
import io,json
try: print(json.loads(io.open(r'$ROOT/.cache/cleaner_pending.json','rb').read().decode('utf-8')).get('week_of') or 'unknown')
except Exception: print('unknown')" 2>/dev/null)"
WDIR="$ROOT/.cache/cleaner_distill/${WEEK}"
mkdir -p "$WDIR"
MAT="$WDIR/materials.txt"
RES="$WDIR/distill_result.json"
PF="$WDIR/prompt.txt"

command -v claude >/dev/null 2>&1 || { jl "claude CLI 없음 — skip"; exit 0; }

# ── (1) claim — 세션 /cleaner 와의 2-pass 차단 (W29 프로토콜 재사용) ───────────
CLM="$(Rscript -e "source('02_Infrastructure/ops/cleaner_claim.R'); r <- cleaner_claim_distill('$OWNER'); cat(isTRUE(r\$claimed), r\$reason)" 2>>"$LOG")"
jl "claim: $CLM"
case "$CLM" in
  TRUE*) : ;;
  *) jl "claim 실패 — 다른 소비자가 증류 중이거나 이미 완료. 물러남"; exit 0 ;;
esac
# ★claim 을 쥔 채 죽으면 stale(6h) 까지 다음 훅이 막힌다 — 비정상 종료 경로에서 반납한다.
release_claim(){ Rscript -e "source('02_Infrastructure/ops/cleaner_claim.R'); invisible(cleaner_release_distill('$OWNER', final_status='pending', force=TRUE))" >>"$LOG" 2>&1 || true; }
trap 'release_claim' EXIT

# ── (2) 재료 조립 ────────────────────────────────────────────────────────────
Rscript "$LIB" materials "$MAT" >> "$LOG" 2>&1 || { jl "materials 실패 — 물러남"; exit 1; }
[ -s "$MAT" ] || { jl "materials 빈 파일 — 물러남"; exit 1; }

DIGEST="04_Research/01_reports/weekly/weekly_digest_$(date +%Y%m%d).md"

PROMPT="주간 리서치 **증류**를 수행하라. 산출은 digest 1편과 결과 JSON 1개다.

$(cat "$MAT")

---

# 네가 하는 일 (④까지 전부 — 도훈 지시 2026-09-05 무인화)

## ① 주간 digest 작성 → \`${DIGEST}\`
지난 7일의 실험별 결론·수치를 정리한다.
- **실측만.** 수치는 그 런의 실제 기록 파일에서 인용하고 **출처 경로를 같이 적는다**.
  추정·재구성·기억으로 쓴 수치는 금지다(권위 등급은 authoritative_remeasure.json 만 인용).
  값이 없는 축은 비워 두고 \"미측정\" 이라 적어라 — 채우지 마라.
- 각 실험: 가설 1줄 / 결론(Grade·PASS·FAIL·screen-tier) / 핵심 수치(출처 경로) / 후속 여부.
- **의무 절 2개**: (a) 공리 사이클 현황 — 활성화된 공리, 정제보류(HELD)는 **사유를 반드시**
  적는다(사유 없는 보류 목록은 다음 주에 아무 행동도 유발하지 않는다). HOLD 가 걸렸으면
  맨 위에 경고 1줄. (b) 이번 주 삭제·거부 요약.
- 재료의 인벤토리는 **입력이지 결론이 아니다** — stage_artifacts 의 실제 산출물을 읽어 역추적하라.

## ② DIST 자동초안 (pending_5axis → proposed)
위 §3 후보 각각에 대해 \`statement_refined\` 초안 + 적대검증을 작성한다.
초안 수치·결론은 **supporting L-code 실측 결론만** — 창작 금지.
적대검증 5체크(a~e)를 각 초안마다 통과시켜라:
 (a) **과장** — 헤드라인이 게이트·재현·deflate 반영 없이 낙관적인가? envelope-상대 정직 서술로 강등.
 (b) **근거** — 결론이 supporting L-code 실측에 실제로 뒷받침되는가? (proxy 를 backtested 로 오라벨 금지)
 (c) **AX-000** — 3~4회 실패를 '구조적 한계/dead-end' 로 단정하는가? → 재작성(미해결 열어둠은 허용).
 (d) **제약 방화벽(의미 판정)** — 위 §4 컨텍스트를 읽고, 초안이 고정 제약(종목수≤25·유동성 2e8·
     long-only·Σw=1·K200∪KQ150·15bps)이나 PIT 를 **실패 원인으로 귀속**하거나 **완화를 레버로
     제시**하는지 의미로 판정하라. 정규식이 아니라 원리다 — 임의 패러프레이즈·영어도 잡는다.
     위반이면 envelope-안 레버(overlay·잔차 sleeve·비-return·DPL·regime-conditional·multi-sleeve·
     composite·ML sizing) 상대로 재작성. ('이 경로는 봉투 안에서 천장' 정직 서술은 위반 아님)
 (e) **프론티어** — 실패는 앞을 가리켜야 한다. 미탐색 인접(frontier)을 담아라. negative polarity 는
     \`frontier\`(배열) + \`live_trigger\`(객체: type/condition/monitored_source) + \`expiry\` 필수.
★ statement_refined 에 '[초안]' 류 표식이나 '확정 필요' 를 남기면 기계가 거부한다.
★ 활성화는 네 권한이 아니다 — proposed 까지다(주입 스트림에 안 들어간다, INV-6).

## ③ 미적립 학습 L-code
digest 를 쓰며 발견한 **유의미하지만 L-code 가 없는** 교훈만 발행 요청한다.
- 이미 있는 학습 재발행 금지(재료의 신규 L-code 목록과 대조. 기계도 corpus 로 중복을 막는다).
- \`metric_type\` 정직 라벨 — proxy 결과에 backtested 금지.
- 없으면 빈 배열로 둔다. **채우기 위해 만들지 마라.**

## ④ 잔재 삭제 — 판단은 너의 것, 집행은 기계
위 §5 후보에서 **지워도 되는 것만** 고른다. 표적은 죽은 코드·중복·캐시이지 지식 기록이 아니다.
- 후보에 \`⛔보호됨\` 이 붙은 것은 골라도 거부된다 — 고르지 마라.
- 참조가 1건이라도 있으면 고르지 마라. **판단이 갈리면 보존**하고 \`deferred\` 에 사유와 함께 남겨라.
- 기계가 집행 전에 다시 센다(보호목록·git grep 참조0·최근 24h 수정·건수/용량 상한).
  네 \`reason\` 이 근거가 아니라 **기계 재도출이 근거다** — 그러니 사유는 사람이 읽을 판단 근거로 적어라.
- 확신이 없으면 빈 배열이 정답이다. 이 레인은 매주 돈다.

# 산출 (이 둘만)
1. \`${DIGEST}\` — 위 ① 의 digest.
2. \`${RES}\` — 아래 형태의 JSON:
{
  \"schema\": \"cleaner_distill_v1\",
  \"week_of\": \"${WEEK}\",
  \"digest_path\": \"${DIGEST}\",
  \"dist_drafts\": [
    {\"dist_id\": \"DIST-XX-000\", \"statement_refined\": \"정제문(초안 표식 없이)\",
     \"retry_condition\": \"...\", \"adversarial_verdict\": {\"a_exaggeration\":\"...\",\"b_evidence\":\"...\",\"c_ax000\":\"...\",\"d_firewall\":\"...\",\"e_frontier\":\"...\"},
     \"frontier\": [\"...\"], \"live_trigger\": {\"type\":\"regime|spread|data|time\",\"condition\":\"...\",\"monitored_source\":\"...\"},
     \"expiry\": \"YYYY-MM-DD\"}
  ],
  \"lcodes\": [
    {\"mode\":\"cleaner\",\"strategy_id\":\"...\",\"grade\":\"...\",\"lesson_text\":\"...\",
     \"metric_type\":\"backtested|proxy|estimated\",\"mechanism_hypothesis\":\"...\",\"next_probe\":[\"...\",\"...\"]}
  ],
  \"deletions\": [ {\"path\": \"상대경로\", \"reason\": \"왜 죽었는지 1줄\"} ],
  \"deferred\":  [ {\"path\": \"상대경로\", \"reason\": \"왜 판단을 미뤘는지\"} ],
  \"report\": \"2~3줄 — 이번 주에 무엇이 켜졌고 무엇이 꺼졌나\"
}

# 금지
- \`05_Production/\` · \`01_Literature/\` · \`stage_artifacts/\` · \`qepm/\` · \`06_Registry/\` · \`.claude/\` 수정.
- 원장·훅·테스트·계약·설정 파일 수정. 백테스트 실행. 등급 산출·재계산(측정은 R 계약이 한다, AX-008).
- digest 에 추정 수치를 실측처럼 기재. 회피표현(\"영향 미미\"·\"관행적 허용\"·\"대부분 결과 동일\").
- 결과 JSON 밖에서 삭제를 시도하는 것(너에겐 Bash 가 없다 — 삭제는 기계가 집행한다).

두 파일을 쓰고 2~3줄로 이번 주 증류의 요지만 보고하라."

# ── (3) 에이전트 — 프롬프트는 stdin (argv 32K 상한 회피, 2026-09-04 실사고) ──────
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve cleaner_distill "${QVEST_CD_MODEL:-}" "${QVEST_CD_EFFORT:-}"
TMO="${QVEST_CD_TIMEOUT:-2400}"
jl "agent start week=$WEEK model=$LLM_MODEL effort=$LLM_EFFORT timeout=${TMO}s"
printf %s "$PROMPT" > "$PF"
# ★무인 LLM 단일 진입(P0-M1 2026-09-24) — rf_llm_agent_run 이 AutoMem 차단·무인 표식을 싣고
#   --model/--effort 는 위 rf_llm_resolve 값을 쓴다. 출력은 이번 실행 파일 → 로그에 덧붙임.
RUN_OUT="$(mktemp "${TMPDIR:-/tmp}/cleaner_run.XXXXXX")"
#   폴백 미탑재(LLM_FALLBACK_MODEL="" · 구판 동작 보존): 구판도 --fallback-model 없이 떴고 이 레인엔
#   반쪽 산출물 청소 훅(rf_llm_before_fallback)이 없다 — 폴백 확대는 청소 훅과 함께 별도 결정.
LLM_FALLBACK_MODEL="" rf_llm_agent_run "$PF" "$RUN_OUT" "$TMO" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep" \
  --disallowed-tools "Bash,Agent,WebFetch,WebSearch" \
  --add-dir "$WDIR"
ARC=$LLM_RC
[ -f "$RUN_OUT.primary" ] && cat "$RUN_OUT.primary" >> "$LOG"
cat "$RUN_OUT" >> "$LOG" 2>/dev/null
rm -f "$RUN_OUT" "$RUN_OUT.primary"
jl "agent done rc=$ARC"

if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401" "$LOG" 2>/dev/null; then
  jl "인증 만료 — claude 재인증 필요(리서치 실패 아님). claim 반납 후 종료"; exit 2; fi

[ -s "$RES" ] || { jl "결과 JSON 미생성($RES) — 증류 미완. claim 반납하고 다음 훅이 재시도"; exit 3; }

# ── (4) 검증 + 집행 — 기계 재도출 ────────────────────────────────────────────
Rscript "$LIB" apply "$RES" >> "$LOG" 2>&1
VRC=$?
jl "apply rc=$VRC"
if [ "$VRC" -ne 0 ]; then
  jl "집행 검증 실패(rc=$VRC) — digest 미작성 등. claim 반납하고 재시도 대기"; exit "$VRC"; fi

# ── (5) 완료 release — 여기서만 status=distilled 가 된다 ─────────────────────
trap - EXIT
Rscript -e "source('02_Infrastructure/ops/cleaner_claim.R'); r <- cleaner_release_distill('$OWNER'); cat(r\$reason)" >> "$LOG" 2>&1
jl "release done — bootstrap 증류 대기 WARN 해제"

# ── (6) 텔레그램 ─────────────────────────────────────────────────────────────
MAN="$ROOT/06_Registry/distill_manifest_$(date +%Y%m%d).json"
if [ "${QVEST_CLEANER_NO_TG:-0}" != "1" ] && [ -s "$MAN" ]; then
  Rscript "$LIB" notify "$MAN" >> "$LOG" 2>&1 || jl "telegram fail-soft"
fi
jl "무인 증류 완주 — week=$WEEK"
exit 0
