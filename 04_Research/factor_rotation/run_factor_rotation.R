#!/usr/bin/env Rscript
# =============================================================================
# run_factor_rotation.R — Factor Rotation Mode 오케스트레이터 (allocation track 단일 진입).
# ★ 새 모듈 자동 인식: module_performance.json 신선도 체크 → 신규/변경 모듈(04_Research/strategies/*
#   또는 module_catalog) 감지 시 pool 자동 rebuild(build_module_performance + RCMA) → run_wf_ensemble.
# 즉 QEPM/alpha-search가 모듈을 만들면(=strategies/ 또는 register_module), 다음 FR 실행에서 자동 편입.
# Usage: Rscript run_factor_rotation.R           (자동 신선도)
#        FR_FORCE_REBUILD=1 Rscript ...           (강제 rebuild)
# 도훈 mandate 2026-06-05 ("새 모듈 바로바로 인식").
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)

mp    <- file.path(PROJ, "06_Registry/module_performance.json")
sims  <- Sys.glob(file.path(PROJ, "04_Research/strategies/*/sim_result.rds"))
mc    <- file.path(PROJ, "06_Registry/module_catalog.json")
inputs <- c(sims, if (file.exists(mc)) mc else NULL)

newest_mtime <- if (length(inputs)) max(file.info(inputs)$mtime, na.rm = TRUE) else Sys.time()
mp_mtime     <- if (file.exists(mp)) file.info(mp)$mtime else as.POSIXct("1970-01-01", tz = "UTC")
force <- Sys.getenv("FR_FORCE_REBUILD", "0") == "1"
n_pool_prev <- if (file.exists(mp)) length(jsonlite::fromJSON(mp, simplifyVector = FALSE)$modules) else 0L
stale <- force || !file.exists(mp) || newest_mtime > mp_mtime

cat(sprintf("[run_factor_rotation] 모듈 sim 파일 %d개 | 최신 모듈 mtime=%s | pool mtime=%s | stale=%s%s\n",
            length(sims), as.character(newest_mtime),
            if (file.exists(mp)) as.character(mp_mtime) else "없음", stale,
            if (force) " (FORCE)" else ""))

if (stale) {
  cat(sprintf("[run_factor_rotation] ★ 신규/변경 모듈 감지 → pool rebuild (이전 %d개)\n", n_pool_prev))
  source(file.path(PROJ, "02_Infrastructure/regime/build_module_performance.R"))   # 광역 scan → module_performance.json
  source(file.path(PROJ, "02_Infrastructure/portfolio/regime_module_admission.R")) # RCMA → module_regime_admission.json
} else {
  cat("[run_factor_rotation] pool 최신 — rebuild 생략\n")
}

# Track2 앙상블 (admitted union pool로 FR 산출 + 등재)
source(file.path(PROJ, "04_Research/factor_rotation/run_wf_ensemble.R"))
cat("\n[run_factor_rotation] 완료.\n")
