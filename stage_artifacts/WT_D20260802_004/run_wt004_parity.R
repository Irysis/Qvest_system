# run_wt004_parity.R — defensive AST 스펙 재선언(const 노드) + parity + compile_meta 저장
#   (canonical 6 패널은 이미 컴파일 완료 — 재사용)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
say <- function(fmt, ...) cat(sprintf(paste0("[wt004p] ", fmt, "\n"), ...))
F5 <- c("D03_RealVol", "D01_IdioVol", "D41_Vol_of_Vol", "D45_Downside_Dev", "D55_Vol_Trend")

leaf_of <- function(f) list(type = "leaf", class = "FIELD", source = "factor_db_monthly", field = f)
const_neg1 <- list(type = "const", value = -1)
for (f in F5) {
  write_json(list(type = "op", op = "MUL", args = list(leaf_of(f), const_neg1)),
             file.path(OUT, sprintf("ast_%s_defensive.json", f)), auto_unbox = TRUE, pretty = TRUE)
}
say("defensive AST 재선언 (const 노드 형식)")

# SIG 재구성 (compile 스크립트와 동일 규칙)
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
SIG  <- MEND[MEND >= as.Date("2004-12-01") & MEND < max(MEND)]
UNIV <- RAW[Date %in% SIG & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
rm(RAW); gc(verbose = FALSE)

source("02_Infrastructure/ast/ast_compile.R")
probe_dates <- SIG[format(SIG, "%Y-%m") %in% c("2008-11", "2015-06", "2020-03", "2024-12")]
probe_univ  <- UNIV[Date %in% probe_dates]
parity <- list()
for (f in F5) {
  cmp_d <- ast_compile(file.path(OUT, sprintf("ast_%s_defensive.json", f)),
                       eval_dates = probe_dates, universe = probe_univ,
                       manifest_out = file.path(OUT, sprintf("ast_manifest_%s_defensive.json", f)))
  can <- as.data.table(read_parquet(file.path(OUT, sprintf("panel_%s_canonical.parquet", f))))
  m <- merge(cmp_d$panel[, .(Date, Ticker, v_def = value)],
             can[, .(Date, Ticker, v_can = value)], by = c("Date", "Ticker"))
  m <- m[is.finite(v_def) & is.finite(v_can)]
  parity[[f]] <- m[, max(abs(v_def + v_can))]
  say("parity %s: n=%d max|def + can| = %.2e %s", f, nrow(m), parity[[f]],
      ifelse(parity[[f]] < 1e-10, "PASS", "FAIL"))
}
if (any(unlist(parity) >= 1e-10)) stop("[wt004p] defensive parity FAIL")
saveRDS(list(parity = parity, SIG = SIG), file.path(OUT, "compile_meta.rds"))
say("완료 — compile_meta.rds 저장")
