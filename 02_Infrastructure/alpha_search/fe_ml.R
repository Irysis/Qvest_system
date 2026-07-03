# fe_ml.R — ML 모멘텀 앙상블 예측 Score (ml_momentum_ensemble.py 산출 ml_momentum_pred.parquet)
# pred(XGBoost 예측 forward수익)를 Score로 사용. universe는 ML이 쓴 K200∪KQ150 실제 멤버십(pred에 내재).
suppressPackageStartupMessages(library(arrow))
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.ml_root <- function() {
  if (exists("PROJECT_ROOT", inherits = TRUE)) return(get("PROJECT_ROOT", inherits = TRUE))
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  stop("[fe_ml] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
.ml_pred_path <- file.path(.ml_root(), ".cache", "ml_momentum_pred.parquet")
stopifnot(file.exists(.ml_pred_path))
.pred <- as.data.table(read_parquet(.ml_pred_path))
.pred[, Date := as.Date(Date)]
FACTORS <- merge(RAWDATA[LiqPass == TRUE, .(Date, Ticker)],
                 .pred[is.finite(pred), .(Date, Ticker, Score = pred)],
                 by = c("Date", "Ticker"))
cat(sprintf("[fe_ml] rows=%d dates=%d (ML XGBoost 앙상블 예측 Score)\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
