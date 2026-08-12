## FQ-232 P3b — canonical_screen_bt parity 재측정 (★baseline 정정)
##  P2 의 "불일치 1건(diag_ew_universe)" 은 내 오류였다: csb_old.R 를 factor_validation 의
##  마지막 커밋(9c74d98b)에서 뽑는 바람에 2026-08-09 19:36 의 basis_channels 추가 이전
##  판본과 비교했다. 즉 **비교 대상을 잘못 골랐다**(존재 검사로 정체 검사를 대체한 계통).
##  올바른 baseline = canonical_screen_bt.R 를 마지막으로 건드린 커밋 51884de4.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq232_liquidity_ruler_restore_20260810")
SC  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/731a7a86-b8bf-4640-9de7-b5e7830e4ad8/scratchpad"
say <- function(fmt, ...) { cat(sprintf(paste0("[p3b] ", fmt, "\n"), ...)); flush.console() }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("★입력 실측: %d행 · %d 거래일", nrow(RAW), uniqueN(RAW$Date))
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); invisible(gc(FALSE))
suppressMessages(source("02_Infrastructure/ramp/factor_validation.R"))
fwd <- suppressWarnings(build_monthly_forward_returns(RAWME, ME))
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_002/alpha_scores.parquet"))
A[, Date := as.Date(Date)]
S <- A[, .(Date, Ticker, score = M26_Revenue_Mom)]
size_dt <- RAWME[, .(Date, Ticker, Size)]
runv <- function(f) { suppressMessages(source(f))
  suppressWarnings(canonical_screen_bt(S, fwd$returns_dt, fwd$bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = fwd$liq_dt, liq_min = 2e8,
    run_id = "par", strategy_id = "par", diag_dual_basis = TRUE, size_dt = size_dt)) }
r_old <- runv(file.path(SC, "csb_old2.R"))
r_new <- runv("02_Infrastructure/contracts/canonical_screen_bt.R")
common <- intersect(names(r_old), names(r_new))
diffs <- common[!vapply(common, function(k) isTRUE(all.equal(r_old[[k]], r_new[[k]])), logical(1))]
say("baseline = 51884de4 (2026-08-09 19:36, basis_channels 포함)")
say("공통 필드 %d · 불일치 %d [%s]", length(common), length(diffs),
    if (length(diffs)) paste(diffs, collapse = ",") else "없음")
say("신규 필드(append): [%s]", paste(setdiff(names(r_new), names(r_old)), collapse = ", "))
say("PORT_t old %+.10f / new %+.10f / Δ %.3g", r_old$portfolio_alpha_t_nw_lag3,
    r_new$portfolio_alpha_t_nw_lag3,
    r_new$portfolio_alpha_t_nw_lag3 - r_old$portfolio_alpha_t_nw_lag3)
say("★판정: 기존 필드 %s", if (!length(diffs)) "전건 bit-parity — 순수 additive" else "불일치 존재")
saveRDS(list(diffs = diffs, new_fields = setdiff(names(r_new), names(r_old)),
             port_t_old = r_old$portfolio_alpha_t_nw_lag3,
             port_t_new = r_new$portfolio_alpha_t_nw_lag3,
             baseline_commit = "51884de4e0654de51347e4a141bf793706e925c8"),
        file.path(OUT, "p3b_results.rds"))
say("완료")
