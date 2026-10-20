#!/bin/bash
# resolve_project.sh (hooks 판) — 디바이스/드라이브 독립적 프로젝트 경로 해석
# 우선순위: CLAUDE_PROJECT_DIR → QM_ROOT → 자기 위치 역추론 → 후보 glob.
# 소비자: auto_commit_on_stop.sh · auto_push_on_stop.sh (settings.json SessionEnd 등록)
#   · 미등록 legacy: pipeline_trigger.sh(v9 해제 MANIFEST #26) · task_complete_guard.sh · teammate_idle_guard.sh
# Usage: source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
#
# ★ops/resolve_project.sh 와 **의도적으로 두 군데 다르다**. 하나로 합치지 않는다:
#
#   (1) 우선순위 — hooks 판만 CLAUDE_PROJECT_DIR 이 tier 0 (2026-08-01 도훈 결정).
#       settings.json 의 훅 command 30곳은 전부 `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 로
#       **worktree** 를 고르는데, 그 훅이 source 하는 resolver 가 QM_ROOT(=main)를 답하면
#       "코드는 worktree, 데이터 루트는 main" 으로 갈린다. 실측(settings.json:105 →
#       pipeline_trigger.sh:18 → stage_dispatch.py): 미병합 worktree 사본이 main 의 정본
#       WT mailbox 에 mkdir/이동/Popen 을 건다. tier 0 이 그 갈림을 없앤다.
#       ★ops 판은 **QM_ROOT-first 유지** — 스케줄러 10종·daily_refresh·PG2 러너 등 28 소비자의
#         루트 해석 의미를 바꾸지 않기 위함(그쪽은 CPD 가 QM_ROOT 로 핀되거나 미설정이라 no-op).
#         이 분기는 실수가 아니라 결정이며, 검사기가 **양방향으로** 못박는다.
#
#   (2) 후단 — ops 판은 python3 shim 을 정의하는데, 그건 최대 5회 인터프리터 probe(프로세스
#       spawn)라 PreToolUse 훅 경로에 얹으면 지연이 붙는다(훅은 _shared_parse.sh 의
#       QVEST_PY_BIN 체인을 쓴다).
#
#   동기화·분기 둘 다 **검사기가 강제**한다 — 08_Tests/hooks/test_resolve_project_marker.sh
#   가 두 벌 모두에 marker 게이트를 요구하고, 우선순위는 서로 다름을 요구한다.
#   (주석 규율이 아니라 테스트가 드리프트를 막는다. 동명 2벌 함정의 재발 방지 장치.)
#
# ★모든 tier 는 **marker 파일**로 정체성을 검사한다 (r-portability.md 금칙 ③).
#   `-d` 존재 검사만으로는 "존재하지만 그 프로젝트가 아닌" 디렉토리가 통과한다.
#   marker 미충족 후보는 기각하고 다음 tier 로 흘린다(조용히 수용 금지).

QVEST_ROOT_MARKER="02_Infrastructure/hooks/qvest_hook_router.py"

# 후보가 *이* 프로젝트 루트인지 판정. 성공 시 정규화된 경로를 stdout 으로 반환.
#   ★역슬래시(`C:\Users\...`)는 판정 **전에** 정규화한다 — 2026-08-01 실사고에서
#     User scope QM_ROOT 가 역슬래시라 R 소스문자열 주입 시 `\U` 로 파싱돼 죽었다.
#     형식이 틀려도 `-d` 는 통과하므로, 정규화를 검사 뒤로 미루면 의미가 없다.
_qvest_root_ok() {
  local c="${1:-}"
  [ -n "$c" ] || return 1
  c="${c//\\//}"
  [ -f "$c/$QVEST_ROOT_MARKER" ] || return 1
  printf '%s' "$c"
}

PROJECT=""
QVEST_ROOT_SOURCE=""    # 어느 tier 가 해석했는지 (진단용)

# 0) 세션/훅 컨텍스트 (CLAUDE_PROJECT_DIR) — hooks 판 전용 tier
#    settings.json 이 훅을 띄울 때 고른 트리와 동일한 값이다. 이걸 먼저 봐야 호출자(라우터)와
#    피호출 모듈이 같은 루트를 쓴다. marker 미충족이면 수락하지 않고 QM_ROOT 로 내려간다 —
#    즉 오염된 CPD 를 상속받아도(예: 별개 Qvest 시스템) 게이트가 한 겹 더 있다.
if PROJECT="$(_qvest_root_ok "${CLAUDE_PROJECT_DIR:-}")"; then
  QVEST_ROOT_SOURCE="CLAUDE_PROJECT_DIR"
else
  PROJECT=""
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    echo "[WARN] CLAUDE_PROJECT_DIR='${CLAUDE_PROJECT_DIR}' 기각 — marker 부재($QVEST_ROOT_MARKER). 다음 tier 로 해석합니다." >&2
  fi
fi

# 1) 명시 override (QM_ROOT)
if [ -z "$PROJECT" ]; then
  if PROJECT="$(_qvest_root_ok "${QM_ROOT:-}")"; then
    QVEST_ROOT_SOURCE="QM_ROOT"
  else
    PROJECT=""
    if [ -n "${QM_ROOT:-}" ]; then
      echo "[WARN] QM_ROOT='${QM_ROOT}' 기각 — marker 부재($QVEST_ROOT_MARKER). 다음 tier 로 해석합니다." >&2
    fi
  fi
fi

# 2) 자기 위치에서 역추론 (이 파일은 $ROOT/02_Infrastructure/hooks/ 에 위치)
if [ -z "$PROJECT" ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _cand="$(cd "$(dirname "$_self")/../.." 2>/dev/null && pwd)"
  if PROJECT="$(_qvest_root_ok "$_cand")"; then
    QVEST_ROOT_SOURCE="self"
  else
    PROJECT=""
  fi
  unset _self _cand
fi

# 3) 후보 경로 glob (드라이브 무관)
#    ★`ls -d ... | head -1` 금지 — 첫 *존재* 후보를 무조건 집어 marker 검사를 건너뛴다.
#      파이프가 아니라 프로세스 치환인 이유: 파이프는 subshell 이라 PROJECT 대입이 소실된다.
if [ -z "$PROJECT" ]; then
  while IFS= read -r _g; do
    if PROJECT="$(_qvest_root_ok "$_g")"; then
      QVEST_ROOT_SOURCE="glob"
      break
    fi
    PROJECT=""
  done < <(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/g/Ent/Quant_Module_Moltbot \
                 /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null)
  unset _g
fi

if [ -z "$PROJECT" ]; then
  echo "[ERROR] Quant_Module_Moltbot 루트를 찾을 수 없습니다 — marker($QVEST_ROOT_MARKER) 를 가진 후보 0건." >&2
  echo "[ERROR]   QM_ROOT 환경변수를 marker 가 있는 루트로 설정하세요 (현재: '${QM_ROOT:-미설정}')" >&2
  return 1 2>/dev/null || exit 1
fi

# 구분자 정규화 — 역슬래시 루트가 R 소스문자열로 주입되면 `\U` 파싱으로 죽는다(2026-08-01 실사고).
# (_qvest_root_ok 가 이미 정규화해 반환하므로 방어적 no-op — 경로 추가 시 안전망)
PROJECT="${PROJECT//\\//}"

# 스크립트별 변수명 호환
PROJECT_ROOT="$PROJECT"
BASE="$PROJECT"
