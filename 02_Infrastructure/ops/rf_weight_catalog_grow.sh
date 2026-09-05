#!/usr/bin/env bash
#==============================================================================
# rf_weight_catalog_grow.sh — 비중 카탈로그 **성장 + 재색인** (도훈 지시 2026-08-30)
#
# ★왜: 생성기(generate_weight_variants.R)와 카탈로그(sync_catalog)가 2026-08-24 에
#   만들어졌는데 **주기 호출자가 0개**였다. weight_catalog.R 헤더가 이미 진단한 그 병 —
#   "계약 충돌이 아니라 아무도 한 줄을 안 썼기 때문이다" — 를 생성 쪽에서도 반복하고 있었다.
#   강화 격자가 이제 카탈로그를 소비하므로(rf_weight_arms.R), 카탈로그가 늘면 격자도 넓어진다.
#
# 안전: 생성기는 **성과를 보지 않는다**(generate_siblings 인자에 ir·measured 없음).
#   방출은 선언 축의 결정적 함수이고 측정 전에 원장에 기록되며 형제가 같은 trial_family_id 를
#   받는다 — 패자를 숨길 수 없다. 그래서 자동 성장이 sweep 스누핑이 되지 않는다.
#
# ★2026-09-05 수리 2건 (스케줄 Qvest_WeightCatalogGrow 11:00 런이 ② 에서 죽었다):
#   A. QM_ROOT 는 Windows 사용자 환경에서 `C:\Users\…` 로 온다. 그것을 R 문자열 리터럴에 끼워 넣으면
#      `\U` 가 유니코드 이스케이프로 읽혀 "'\U' used without hex digits" 로 정지한다. 이제 경로는
#      슬래시로 정규화하고 **env(CLAUDE_PROJECT_DIR)로만** 건넨다 — R 리터럴에 경로를 넣지 않는다.
#      (QM_ROOT 는 ~/.Renviron 이 R 시작 시 덮어쓰므로 셸 export 로는 R 에 닿지 않는다 — R 안에서
#       Sys.setenv 로 핀한다. 값은 env 에서 읽는다.)
#   B. ② 는 bare Rscript 였다 — lean 빌트인 23종의 calc_* 는 backtest_harness.R 이 전역에 정의하므로
#      probe 가 전부 "빌트인 함수 부재" 로 실패 기록되고, rf_cell_engine 이 그 JSON 을 읽으면 lean arm
#      전체가 "카탈로그 arm 부재" 가 된다. 이제 probe 전에 하네스를 명시 적재하고(로그에 남긴다),
#      weight_catalog.R 도 자체 적재 + 계기 미적재 실패의 보존 병합을 한다(.WC_INSTRUMENT_MARK).
#      사후 검사: lean probe ok 수가 줄면 WARN.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
ROOT="${ROOT//\\//}"                       # C:\Users\… → C:/Users/…  (R 리터럴 '\U' 사고 재발 방지)
cd "$ROOT" || exit 1
export CLAUDE_PROJECT_DIR="$ROOT"          # R 은 이 변수로만 루트를 받는다(.wc_root 1순위 · .Renviron 미간섭)
export LANGUAGE=en                         # 스케줄러 login shell 은 LANG=ko_KR — R 오류문이 한국어로 바뀌어 probe.log 가
                                           # 세션(영문)과 달라진다. 파생 파일의 자구를 재생성 주체와 무관하게 고정한다.
LOG="$ROOT/.cache/scheduler_logs/weight_catalog_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG")"

# 카탈로그 상태 2수치: 엔트리 수 · lean 빌트인 probe ok 수 (cwd = ROOT)
wc_state() {
  Rscript -e 'j <- jsonlite::fromJSON("06_Registry/weight_catalog.json", simplifyVector = FALSE); n <- length(j$entries); k <- sum(vapply(j$entries, function(e) grepl("^lean:", e$catalog_id) && isTRUE(e$probe$ok), logical(1))); cat(n, k)' 2>/dev/null
}

{
  echo "=== $(date -Iseconds) 카탈로그 성장 시작 (ROOT=$ROOT) ==="
  read -r BEFORE BEFORE_LEAN <<< "$(wc_state)"
  echo "before: ${BEFORE:-?} entries · lean probe ok ${BEFORE_LEAN:-?}/23"
  # ① 변형 생성 (있으면)
  [ -f "$ROOT/02_Infrastructure/methods/generate_weight_variants.R" ] && \
    Rscript "$ROOT/02_Infrastructure/methods/generate_weight_variants.R" || echo "생성기 skip"
  # ② 재색인 — R1/R2/R3 를 다시 훑어 카탈로그 갱신 (probe=TRUE)
  #   경로 리터럴 0 — 루트는 CLAUDE_PROJECT_DIR 에서 읽는다. 하네스는 sync 전에 명시 적재한다.
  Rscript -e 'r <- Sys.getenv("CLAUDE_PROJECT_DIR"); Sys.setenv(QM_ROOT = r); setwd(r); .WC_QUIET_LOAD <- TRUE; suppressMessages(source("02_Infrastructure/portfolio/weight_catalog.R")); hl <- .wc_ensure_lean_builtins(r); cat(sprintf("harness: loaded=%s calc_ivol_weights=%s\n", hl, exists("calc_ivol_weights", mode = "function"))); out <- tryCatch(sync_catalog(root = r, probe = TRUE), error = function(e) { cat("sync ERR:", conditionMessage(e), "\n"); NULL }); if (is.null(out)) quit(save = "no", status = 2)'
  RC=$?
  [ "$RC" -ne 0 ] && echo "WARN: ② 재색인 rc=$RC — 카탈로그는 이전 파일 그대로다(원자 교체 전 정지)"
  read -r AFTER AFTER_LEAN <<< "$(wc_state)"
  echo "after: ${AFTER:-?} entries · lean probe ok ${AFTER_LEAN:-?}/23"
  if [ "${AFTER_LEAN:-0}" -lt "${BEFORE_LEAN:-0}" ]; then
    echo "WARN: lean probe ok 감소 ${BEFORE_LEAN} → ${AFTER_LEAN} — 계기(backtest_harness.R) 적재 여부를 위 로그에서 확인할 것"
  fi
  echo "=== $(date -Iseconds) 종료 ==="
} >> "$LOG" 2>&1
