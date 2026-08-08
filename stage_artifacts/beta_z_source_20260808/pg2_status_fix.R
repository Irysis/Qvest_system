suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

cat("■ PG2 정체성 (qepm/mailbox/governor/book_state.json)\n")
bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyDataFrame = FALSE)
for (k in c("admitted_ids","current_pg2_official_name","incumbent_book_ir","ir_convention",
            "updated","last_updated","book_version")) {
  v <- bs[[k]]
  if (!is.null(v)) cat(sprintf("  %-26s: %s\n", k, paste(unlist(v), collapse=", ")))
}

cat("\n■ 하드 제약 재검증 (CASH 행 제외 — 앞선 '위반' 보고는 내 스크립트 오류)\n")
W <- fread("05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe/20260801_M4gAE_weights_cap_0p20.csv")
E <- W[Ticker != "CASH"]; inv <- sum(E$Weight); cash <- W[Ticker == "CASH"]$Weight
mx_raw <- max(E$Weight); mx_norm <- mx_raw / inv
chk <- function(ok) if (ok) "충족" else "★위반"
cat(sprintf("  종목수            : %d          (<=25 → %s)\n", nrow(E), chk(nrow(E) <= 25)))
cat(sprintf("  invested (Σ주식)  : %.4f      (= manifest invested)\n", inv))
cat(sprintf("  CASH              : %.4f\n", cash))
cat(sprintf("  Σ전체             : %.6f    (=1 → %s)\n", inv + cash, chk(abs(inv+cash-1) < 1e-9)))
cat(sprintf("  max w (원장부)    : %.4f\n", mx_raw))
cat(sprintf("  max w (노출정규화): %.4f      (<=0.20 → %s)\n", mx_norm, chk(mx_norm <= 0.2001)))
cat(sprintf("  long-only         : min w %.4f (>=0 → %s)\n", min(E$Weight), chk(all(E$Weight >= 0))))
