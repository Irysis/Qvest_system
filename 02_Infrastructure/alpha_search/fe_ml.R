# fe_ml.R — ML 모멘텀 앙상블 예측 Score (ml_momentum_ensemble.py 산출 ml_momentum_pred.parquet)
# pred(XGBoost 예측 forward수익)를 Score로 사용. universe는 ML이 쓴 K200∪KQ150 실제 멤버십(pred에 내재).
suppressPackageStartupMessages(library(arrow))
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.ml_pred_path <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                           ".cache", "ml_momentum_pred.parquet")
stopifnot(file.exists(.ml_pred_path))
.pred <- as.data.table(read_parquet(.ml_pred_path))
.pred[, Date := as.Date(Date)]
FACTORS <- merge(RAWDATA[LiqPass == TRUE, .(Date, Ticker)],
                 .pred[is.finite(pred), .(Date, Ticker, Score = pred)],
                 by = c("Date", "Ticker"))
cat(sprintf("[fe_ml] rows=%d dates=%d (ML XGBoost 앙상블 예측 Score)\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
