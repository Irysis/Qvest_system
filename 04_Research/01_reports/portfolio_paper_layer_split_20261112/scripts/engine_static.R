## 엔진 코드 구조만 본다(R 파서 토큰 — 주석 · 문자열 제외). 성과 산출물은 읽지 않는다.
suppressMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
root <- args[1]; out <- args[2]
dirs <- Sys.glob(file.path(root, "04_Research/strategies/RP_AUTO_*"))
OPT <- c("solve.QP", "optim", "optimize", "optimise", "constrOptim", "nlminb", "nloptr", "lp", "Rglpk_solve_LP", "ROI_solve", "ipop",
         "LowRankQP", "solve_osqp", "osqp", "auglag", "slsqp", "cobyla", "DEoptim", "ga", "uniroot", "solnp", "gosolnp", "lsei", "nnls", "quadprog")
RISK <- c("cov", "cor", "cov.wt", "cov2cor", "hclust", "cutree", "eigen", "svd", "prcomp", "princomp", "chol", "chol2inv", "ginv", "solve",
          "crossprod", "tcrossprod", "mahalanobis", "var", "sd", "mad", "frollapply", "frollmean", "frollsum", "dist", "kmeans")
MODEL <- c("lm", "lm.fit", ".lm.fit", "glm", "glmnet", "cv.glmnet", "ranger", "randomForest", "xgboost", "xgb.train", "xgb.DMatrix", "lgb.train",
           "nnet", "predict", "arima", "ar", "garch", "ugarchfit", "nls", "loess", "smooth.spline", "gam", "rq", "system2", "system", "shell",
           "py_run_file", "source_python", "import", "torch_tensor", "nn_module", "nn_linear", "optim_adam", "keras_model_sequential", "fit",
           "depmix", "viterbi", "em", "filter", "embed", "fft", "kernel", "density", "ecdf", "qnorm", "pnorm")
SEL <- c("frank", "frankv", "rank", "order", "setorder", "setorderv", "quantile", "head", "tail", "cut", "ntile", "findInterval", "which.max",
         "which.min", "sort", "rev", "sample", "sample.int")
rows <- list()
for (d in dirs) {
  ep <- file.path(d, "engine.R")
  if (!file.exists(ep)) { rows[[length(rows) + 1L]] <- list(dir = basename(d), has_engine = FALSE); next }
  ex <- tryCatch(parse(file = ep, keep.source = TRUE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(ex, "error")) { rows[[length(rows) + 1L]] <- list(dir = basename(d), has_engine = TRUE, parse_ok = FALSE); next }
  pd <- utils::getParseData(ex); pd <- pd[pd$terminal, c("line1", "col1", "token", "text")]; pd <- pd[order(pd$line1, pd$col1), ]
  tok <- pd$token; txt <- pd$text; n <- nrow(pd)
  nx <- c(tok[-1L], NA_character_); pv <- c(NA_character_, tok[-n])
  outsym <- c("FACTORS", "PORTFOLIO", "SIGNAL_BREADTH")
  is_out <- tok == "SYMBOL" & txt %in% outsym & (nx %in% c("LEFT_ASSIGN", "EQ_ASSIGN") | pv %in% "RIGHT_ASSIGN")
  outs <- txt[is_out]; out_lines <- pd$line1[is_out]
  for (i in which(tok == "SYMBOL_FUNCTION_CALL" & txt == "assign")) if (i + 2L <= n && tok[i + 2L] == "STR_CONST") {
    v <- gsub("^[\"']|[\"']$", "", txt[i + 2L]); if (v %in% outsym) { outs <- c(outs, v); out_lines <- c(out_lines, pd$line1[i]) } }
  calls <- unique(txt[tok == "SYMBOL_FUNCTION_CALL"])
  strs <- txt[tok == "STR_CONST"]
  strs_l <- tolower(strs)
  syms <- unique(txt[tok %in% c("SYMBOL", "SYMBOL_SUB", "SYMBOL_FORMALS")])
  rows[[length(rows) + 1L]] <- list(
    dir = basename(d), has_engine = TRUE, parse_ok = TRUE, md5 = unname(tools::md5sum(ep)), bytes = file.info(ep)$size,
    n_code_lines = length(unique(pd$line1)),
    outputs = paste(sort(unique(outs)), collapse = "+"),
    out_lines = paste(sprintf("%s@%d", outs, out_lines), collapse = " "),
    opt_calls = paste(sort(intersect(calls, OPT)), collapse = ","),
    risk_calls = paste(sort(intersect(calls, RISK)), collapse = ","),
    model_calls = paste(sort(intersect(calls, MODEL)), collapse = ","),
    sel_calls = paste(sort(intersect(calls, SEL)), collapse = ","),
    uses_python = any(grepl("\\.py[\"']?$|python", strs_l)),
    leg_short = any(grepl("^[\"']SHORT[\"']$", strs)), leg_long = any(grepl("^[\"']LONG[\"']$", strs)),
    reads_size = any(c("Size", "MarketCap", "Mktcap", "MktCap", "market_cap") %in% syms),
    fdb = paste(sort(intersect(calls, c("load_month_factors", "load_daily_factors", "fc_load_month", "fc_load_months", "fc_daily"))), collapse = ","),
    all_calls = paste(sort(calls), collapse = ","))
}
writeLines(toJSON(rows, auto_unbox = TRUE, pretty = TRUE, null = "null"), out)
cat("engines:", sum(vapply(rows, function(r) isTRUE(r$has_engine), logical(1))), "/", length(rows), "\n")
