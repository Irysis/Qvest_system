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
# 사용:
#   . "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
#   rf_llm_resolve fidelity_audit "$QVEST_FA_MODEL" "$QVEST_FA_EFFORT"
#   → LLM_MODEL / LLM_EFFORT 설정
#==============================================================================
rf_llm_resolve() {
  local lane="${1:-}" ov_model="${2:-}" ov_effort="${3:-}"
  local cfg="${QVEST_RF_CONFIG:-${ROOT}/06_Registry/reinforce_auto_config.json}"
  local py="${QVEST_PY:-${ROOT}/.venv_qvest_ml/Scripts/python.exe}"
  local resolved
  resolved=$("$py" -c "
import io,json,sys
lane=sys.argv[1]
try: c=json.loads(io.open(sys.argv[2],'rb').read().decode('utf-8'))
except Exception: c={}
llm=c.get('llm') or {}
per=(llm.get('lanes') or {}).get(lane) or {}
print('%s\t%s' % (per.get('model') or llm.get('model') or 'opus',
                  per.get('effort') or llm.get('effort') or 'max'))" "$lane" "$cfg" 2>/dev/null)
  LLM_MODEL="${resolved%%	*}"
  LLM_EFFORT="${resolved##*	}"
  [ -n "$LLM_MODEL" ]  || LLM_MODEL="opus"
  [ -n "$LLM_EFFORT" ] || LLM_EFFORT="max"
  # ★환경변수가 최우선 — 검사와 일회성 실험이 설정을 건드리지 않고 갈아탈 수 있어야 한다.
  [ -n "$ov_model" ]  && LLM_MODEL="$ov_model"
  [ -n "$ov_effort" ] && LLM_EFFORT="$ov_effort"
  export LLM_MODEL LLM_EFFORT
}
