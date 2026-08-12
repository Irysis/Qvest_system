## FQ-232 P3 — P2 가 보고한 canonical_screen_bt 불일치 1건(diag_ew_universe) 의 정체 규명
##  ★"1개 다르다"를 기전 없이 보고하지 않는다. 값 차이인가 구조/속성 차이인가를 분리한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq232_liquidity_ruler_restore_20260810")
SC  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/731a7a86-b8bf-4640-9de7-b5e7830e4ad8/scratchpad"
say <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }

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

runv <- function(srcfile) {
  suppressMessages(source(srcfile))
  suppressWarnings(canonical_screen_bt(S, fwd$returns_dt, fwd$bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = fwd$liq_dt, liq_min = 2e8,
    run_id = "par", strategy_id = "par", diag_dual_basis = TRUE, size_dt = size_dt))
}
r_old <- runv(file.path(SC, "csb_old.R"))
r_new <- runv("02_Infrastructure/contracts/canonical_screen_bt.R")
a <- r_old$diag_ew_universe; b <- r_new$diag_ew_universe
say("diag_ew_universe class: old %s / new %s", class(a)[1], class(b)[1])
say("names old: [%s]", paste(names(a), collapse = ", "))
say("names new: [%s]", paste(names(b), collapse = ", "))
for (k in union(names(a), names(b))) {
  va <- a[[k]]; vb <- b[[k]]
  eq <- isTRUE(all.equal(va, vb))
  if (!eq) {
    say("  ★불일치 필드 '%s': class old=%s new=%s", k, class(va)[1], class(vb)[1])
    if (is.data.frame(va) && is.data.frame(vb)) {
      say("    dim old %s / new %s", paste(dim(va), collapse="x"), paste(dim(vb), collapse="x"))
      say("    all.equal msg: %s", paste(all.equal(va, vb), collapse=" | "))
      num <- intersect(names(va), names(vb))
      for (cc in num) if (is.numeric(va[[cc]]) && is.numeric(vb[[cc]]))
        say("    max|Δ %s| = %.3g", cc, max(abs(va[[cc]] - vb[[cc]]), na.rm = TRUE))
        else if (!identical(va[[cc]], vb[[cc]])) say("    '%s' 비수치 불일치", cc)
    } else {
      say("    old=%s / new=%s", paste(utils::head(as.character(va),3), collapse=","),
          paste(utils::head(as.character(vb),3), collapse=","))
      say("    all.equal msg: %s", paste(all.equal(va, vb), collapse=" | "))
    }
  }
}
## 재현성 대조: 같은 판본을 두 번 돌려도 같은 필드가 흔들리는가(= 결정성 문제인지)
r_new2 <- runv("02_Infrastructure/contracts/canonical_screen_bt.R")
say("동일 판본 2회 실행 시 diag_ew_universe 동일 = %s",
    isTRUE(all.equal(r_new$diag_ew_universe, r_new2$diag_ew_universe)))
say("동일 판본 2회 PORT_t 동일 = %s",
    identical(r_new$portfolio_alpha_t_nw_lag3, r_new2$portfolio_alpha_t_nw_lag3))
saveRDS(list(old = a, new = b), file.path(OUT, "p3_diag_probe.rds"))
say("완료")
