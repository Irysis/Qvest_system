#!/usr/bin/env bash
#==============================================================================
# rf_llm_env.sh — 무인 LLM 레인의 모델·노력수준 **단일 정본** (2026-09-04 도훈 지시)
#
# 왜: 레인이 넷인데(충실구현·오버레이 제안·B1 설계·충실도 감사) 각자 `:-opus` / `:-max` 를
#   들고 있었고, 설정의 llm 블록(model/effort/rationale)은 **읽는 코드가 0건**이었다.
#   정책을 적어 둔 문서를 아무도 소비하지 않는 상태 — 한 곳을 바꿔도 넷은 그대로다.
#   (이 저장소가 반복해서 밟는 형태: 생산자만 있고 소비자가 없는 계기.)
#
# 우선순위: 레인별 환경변수 > 설정 llm.<lane> > 설정 llm > 하드 기본값(opus/max)
#   하드 기본값은 설정 파일이 깨졌을 때의 마지막 방어선이지 정책이 아니다 —
#   정책은 06_Registry/reinforce_auto_config.json 의 llm 블록이다.
#
# ★모델은 **별칭**으로 적는다 (2026-09-17 도훈 지시 "opus, fable 모두 다른 명령 없이도 항상 최신 모델").
#   CLI 가 별칭을 그날의 최신 모델로 푼다 — CLI 2.1.261 실측(--output-format json 의 modelUsage):
#   fable → claude-fable-5-1 · opus → claude-opus-5. ID(claude-fable-5-1)를 박으면 다음 출시 때 낡는다.
#
# ★Fable 한도 폴백 (2026-09-17 도훈 지시 "fable 한도 소진하면 opus 5 최대 effort 로 진행").
#   rf_llm_resolve 가 Fable 계열로 해석하면 LLM_FALLBACK_MODEL/EFFORT 를 함께 싣는다
#   (정본 = 설정 llm.fable_limit_fallback · 블록이 없으면 opus/max · QVEST_LLM_FALLBACK=off 면 끈다).
#   rf_llm_agent_run 이 두 겹으로 집행한다:
#     ① --fallback-model — CLI 가 과부하·사용불가로 판단할 때의 내부 전환. 한도 소진이 여기 드는지는
#        CLI 문서에 없다 → 이것만 믿으면 "한도 = 사용불가" 라는 확인 안 된 가정 위에 서게 된다.
#     ② 보장선 — 이번 실행 출력에 한도 문구가 있으면 폴백 모델로 **처음부터** 1회 재실행.
#        재실행 직전 호출자 훅 rf_llm_before_fallback(정의돼 있으면)이 반쪽 산출물을 치운다.
#
# 사용:
#   . "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
#   rf_llm_resolve fidelity_audit "$QVEST_FA_MODEL" "$QVEST_FA_EFFORT"
#   → LLM_MODEL / LLM_EFFORT (+ Fable 계열이면 LLM_FALLBACK_MODEL / LLM_FALLBACK_EFFORT)
#   rf_llm_agent_run <prompt_file> <run_out> <timeout_sec> [claude 추가 인자...]
#   → LLM_RC · LLM_USED_MODEL · LLM_USED_EFFORT · LLM_FELL_BACK(0|1) · 폴백 시 1차 출력 = <run_out>.primary
#==============================================================================

# 한도 문구 — 실측 표본: "You've reached your Fable limit"(09-07) · "You've hit your session limit ·
#   resets 2am (Asia/Seoul)"(09-02·09-15) · 429 rate_limit_error. 문구가 한 종이 아니라 여기 하나로 모은다
#   (충실구현 레인의 환경 실패 판정도 이 정규식을 쓴다 — 두 벌이면 한쪽만 고쳐진다).
RF_LLM_LIMIT_RE="(reached|hit) your [A-Za-z0-9 .-]*limit|(session|usage) limit|manage usage credits|rate_limit_error|API Error: 429|resets [0-9]+(:[0-9]+)?(am|pm)"

rf_llm_is_fable() {
  case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in
    fable*|claude-fable*) return 0 ;;
    *) return 1 ;;
  esac
}

rf_llm_limit_hit() {
  [ -f "${1:-}" ] && grep -qiE "$RF_LLM_LIMIT_RE" "$1" 2>/dev/null
}

rf_llm_resolve() {
  local lane="${1:-}" ov_model="${2:-}" ov_effort="${3:-}"
  local cfg="${QVEST_RF_CONFIG:-${ROOT}/06_Registry/reinforce_auto_config.json}"
  local py="${QVEST_PY:-${ROOT}/.venv_qvest_ml/Scripts/python.exe}"
  local resolved fbm="" fbe=""
  resolved=$("$py" -c "
import io,json,sys
lane=sys.argv[1]
try: c=json.loads(io.open(sys.argv[2],'rb').read().decode('utf-8'))
except Exception: c={}
llm=c.get('llm') or {}
per=(llm.get('lanes') or {}).get(lane) or {}
fb=llm.get('fable_limit_fallback') or {}
print('|'.join([per.get('model') or llm.get('model') or 'opus',
                per.get('effort') or llm.get('effort') or 'max',
                fb.get('model') or '', fb.get('effort') or '']))" "$lane" "$cfg" 2>/dev/null)
  resolved="$(printf '%s' "$resolved" | tr -d '\r')"   # Windows 파이썬 줄끝 방어 — $'\r' 표기는 셸 경로마다 달리 풀린다
  LLM_MODEL=""; LLM_EFFORT=""
  IFS='|' read -r LLM_MODEL LLM_EFFORT fbm fbe <<< "$resolved"
  [ -n "$LLM_MODEL" ]  || LLM_MODEL="opus"
  [ -n "$LLM_EFFORT" ] || LLM_EFFORT="max"
  # ★환경변수가 최우선 — 검사와 일회성 실험이 설정을 건드리지 않고 갈아탈 수 있어야 한다.
  [ -n "$ov_model" ]  && LLM_MODEL="$ov_model"
  [ -n "$ov_effort" ] && LLM_EFFORT="$ov_effort"
  # ★폴백은 **최종 해석된 모델**(환경변수 반영 후)이 Fable 계열일 때만 싣는다 — Opus 레인에 붙이면
  #   같은 모델로의 무의미한 재실행이 된다.
  LLM_FALLBACK_MODEL=""; LLM_FALLBACK_EFFORT=""
  if rf_llm_is_fable "$LLM_MODEL" && [ "${QVEST_LLM_FALLBACK:-on}" != "off" ]; then
    LLM_FALLBACK_MODEL="${fbm:-opus}"
    LLM_FALLBACK_EFFORT="${fbe:-max}"
  fi
  export LLM_MODEL LLM_EFFORT LLM_FALLBACK_MODEL LLM_FALLBACK_EFFORT
}

rf_llm_agent_run() {
  local pf="${1:?prompt_file}" out="${2:?run_out}" tmo="${3:?timeout_sec}"
  shift 3
  local bin="${RF_CLAUDE_BIN:-claude}"
  local fb=()
  [ -n "${LLM_FALLBACK_MODEL:-}" ] && fb=(--fallback-model "$LLM_FALLBACK_MODEL")
  LLM_FELL_BACK=0; LLM_USED_MODEL="$LLM_MODEL"; LLM_USED_EFFORT="$LLM_EFFORT"
  rm -f "$out.primary"
  timeout "$tmo" "$bin" -p --model "$LLM_MODEL" --effort "$LLM_EFFORT" ${fb[@]+"${fb[@]}"} "$@" \
    < "$pf" > "$out" 2>&1
  LLM_RC=$?
  # ★한도 판정은 **이번 실행 출력**만 본다 — 그날 로그 전체를 보면 앞선 실행의 한도 문구가 뒤의 성공을 덮는다.
  if [ -n "${LLM_FALLBACK_MODEL:-}" ] && rf_llm_limit_hit "$out"; then
    mv -f "$out" "$out.primary"
    if declare -F rf_llm_before_fallback >/dev/null 2>&1; then rf_llm_before_fallback; fi
    LLM_FELL_BACK=1
    LLM_USED_MODEL="$LLM_FALLBACK_MODEL"
    LLM_USED_EFFORT="${LLM_FALLBACK_EFFORT:-max}"
    timeout "$tmo" "$bin" -p --model "$LLM_USED_MODEL" --effort "$LLM_USED_EFFORT" "$@" \
      < "$pf" > "$out" 2>&1
    LLM_RC=$?
  fi
  export LLM_RC LLM_USED_MODEL LLM_USED_EFFORT LLM_FELL_BACK
  return "$LLM_RC"
}
