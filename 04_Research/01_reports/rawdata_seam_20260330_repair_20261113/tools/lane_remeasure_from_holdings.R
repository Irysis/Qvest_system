## 오염 창(2026-11-11 11:28 ~ 11-13 09:07)에 측정된 충실구현 레인 산출물 — 저장 보유 기반 재측정(정본 계약 remeasure_from_holdings.R)
##   선정(무엇을 샀나)은 고정하고 수익 데이터(정정된 RAWDATA · 벤치)만 바뀐다 → 03-30 이음매 효과만 분리된다.
##   원 산출물은 읽기만 한다 · 출력 = 이 보고 폴더 remeasure_lane/<산출물>/remeasure_<regime>/ (원장 rebase 없음)
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/lane_remeasure_from_holdings.R <run_id> ...
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/remeasure_from_holdings.R"))
runs <- commandArgs(trailingOnly = TRUE)
if (!length(runs)) stop("usage: lane_remeasure_from_holdings.R <run_id> ...")
OUTD <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113/remeasure_lane")
dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)
mk <- rfh_load_market(ROOT, exec_prices = "close_t1")
cat(sprintf("[lane_rm] 시장 데이터 RAWDATA %s행 · 최신 %s\n", format(mk$fp$raw_nrow, big.mark = ","), mk$fp$raw_max_date))
res <- rbindlist(lapply(runs, function(r) {
  a <- file.path(ROOT, "stage_artifacts/replication", r)
  st <- tryCatch(rfh_stored(a), error = function(e) NULL)
  x <- tryCatch(rfh_remeasure(a, exec_price = "close_t1", raw = mk, out_dir = OUTD, root = ROOT),
                error = function(e) { cat(sprintf("[lane_rm] %s 실패: %s\n", r, conditionMessage(e))); NULL })
  if (is.null(x)) return(data.table(run_id = r, ok = FALSE))
  A <- x$auth; S0 <- fromJSON(file.path(a, "authoritative_remeasure.json"), simplifyVector = FALSE)
  g <- function(j, ...) { v <- j; for (k in list(...)) v <- v[[k]]; if (is.null(v)) NA else v }
  data.table(run_id = r, ok = TRUE, strategy = g(S0, "strategy_name"),
             grade_old = g(S0, "essence_grade"), grade_new = g(A, "essence_grade"),
             calmar_old = g(S0, "essence", "calmar"), calmar_new = g(A, "essence", "calmar"),
             cagr_old = g(S0, "essence", "cagr"), cagr_new = g(A, "essence", "cagr"),
             tw_old = g(S0, "grade_v3", "oos", "calmar_tw"), tw_new = g(A, "grade_v3", "oos", "calmar_tw"),
             out = x$out)
}), fill = TRUE)
print(res)
fwrite(res, file.path(OUTD, "lane_remeasure_summary.csv"))
cat(toJSON(res, auto_unbox = TRUE, digits = 6), "\n")
