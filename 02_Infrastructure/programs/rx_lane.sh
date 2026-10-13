#!/usr/bin/env bash
#==============================================================================
# rx_lane.sh — 처방 루프 에이전트 1회 실행(청정 레인) · v10.01 S2 파일럿 · D7 별도 모듈
#
# 왜: 처방 루프의 분석가 · 처방 담당 · 리뷰어는 τ_D(2022-12-31) 이전 재료만 봐야 한다(설계 §3.4 R4 — 절대).
#   세션 서브에이전트는 세션 자동 기억(시험 창 수치 포함)을 주입받고 읽기 가드 밖이라 쓸 수 없다.
#   그래서 무인 단일 진입 rf_llm_agent_run(자동 기억 차단 · 무인 표식)에 청정 표식(QVEST_CLEAN_LANE · R6 읽기 가드 —
#   허용 목록 + 작업 디렉터리만)을 실어 띄운다(충실구현 청정 모드와 같은 장치 · 결정 FA-CLEAN-BASE-PATH).
#   도구 = 읽기 전용(Read · Glob · Grep). 산출 = 최종 응답(out.md) — 쓰기 도구를 주지 않는다.
#
# 사용: rx_lane.sh <lane_dir> [model=opus] [effort=max] [timeout_sec=3600]
#   입력 <lane_dir>/prompt.md · 출력 <lane_dir>/out.md(최종 응답) · <lane_dir>/run.log(rc · 모델)
#   ★세션에서 띄울 때 인증 = 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN(기억 카드 reference-session-launched-lanes-…-20261010)
#==============================================================================
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
LANE="${1:?usage: rx_lane.sh <lane_dir> [model] [effort] [timeout_sec]}"
MODEL="${2:-opus}"; EFFORT="${3:-max}"; TMO="${4:-3600}"
[ -f "$LANE/prompt.md" ] || { echo "[rx_lane] prompt.md 없음: $LANE" >&2; exit 2; }
cd "$ROOT" || exit 2                         # 훅은 저장소 cwd 기준으로 로드된다(cwd 이동 = 훅 전멸)
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve rx_lane "$MODEL" "$EFFORT"
LLM_FALLBACK_MODEL=""                        # 폴백 미탑재(단일 진입 이관 레인 규약)
STARTED="$(date '+%Y-%m-%dT%H:%M:%S%z')"
# ★레인은 작업 디렉터리 밖에 부작용이 없어야 한다 — 레인 세션 종료(SessionEnd) 훅의 자동 커밋 · 자동 푸시를 건너뛴다.
#   10-13 실측: P2R01 분석가 · 처방 담당 레인이 끝날 때마다 훅이 작업 트리 전체를 main 에 커밋 · 푸시했다(3,373 · 26 파일) —
#   부모 세션 도중의 의도치 않은 커밋이고, 훅의 SessionEnd 출력 형식 오류 문구가 레인 산출(out.md)에 섞였다.
QVEST_SKIP_AUTO_COMMIT=1 QVEST_SKIP_AUTO_PUSH=1 \
QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$LANE" rf_llm_agent_run "$LANE/prompt.md" "$LANE/out.md" "$TMO" \
  --permission-mode default \
  --allowed-tools "Read,Glob,Grep" \
  --disallowed-tools "Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent,Skill,Write,Edit,NotebookEdit,WebFetch,WebSearch" \
  --add-dir "$LANE"
printf 'started=%s\nfinished=%s\nrc=%s\nmodel=%s\neffort=%s\nfell_back=%s\n' "$STARTED" "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
  "$LLM_RC" "$LLM_USED_MODEL" "$LLM_USED_EFFORT" "$LLM_FELL_BACK" > "$LANE/run.log"
exit "$LLM_RC"
