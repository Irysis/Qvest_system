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
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
LOG="$ROOT/.cache/scheduler_logs/weight_catalog_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) 카탈로그 성장 시작 ==="
  BEFORE=$(Rscript -e 'cat(length((jsonlite::fromJSON("06_Registry/weight_catalog.json", simplifyVector=FALSE))$entries))' 2>/dev/null)
  echo "before: $BEFORE entries"
  # ① 변형 생성 (있으면)
  [ -f "$ROOT/02_Infrastructure/methods/generate_weight_variants.R" ] && \
    Rscript "$ROOT/02_Infrastructure/methods/generate_weight_variants.R" || echo "생성기 skip"
  # ② 재색인 — R1/R2/R3 를 다시 훑어 카탈로그 갱신
  Rscript -e 'Sys.setenv(QM_ROOT="'"$ROOT"'"); setwd("'"$ROOT"'"); suppressMessages(source("02_Infrastructure/portfolio/weight_catalog.R")); r <- tryCatch(sync_catalog(probe = TRUE), error=function(e){cat("sync ERR:", conditionMessage(e), "\n"); NULL})' || true
  AFTER=$(Rscript -e 'cat(length((jsonlite::fromJSON("06_Registry/weight_catalog.json", simplifyVector=FALSE))$entries))' 2>/dev/null)
  echo "after: $AFTER entries"
  echo "=== $(date -Iseconds) 종료 ==="
} >> "$LOG" 2>&1
