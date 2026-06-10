#==============================================================================
# measure_returns.R - measure a NET-RETURN-series method (VoC) via contract, comparable
# to measure_scores.R (CA/APT). Takes (date, ret_net, BM_Ret) -> build_benchmark_compare
# -> PORT_t_nw_lag3 / IR / alpha (same .nw_t_mean as canonical_screen_bt). LONG-ONLY.
#
# Env: MEASURE_RET (parquet w/ date,ret_net,BM_Ret) MEASURE_TAG MEASURE_OUT
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R")))

RET <- Sys.getenv("MEASURE_RET", ""); if (!nzchar(RET)) stop("MEASURE_RET required")
TAG <- Sys.getenv("MEASURE_TAG", tools::file_path_sans_ext(basename(RET)))
OUT <- Sys.getenv("MEASURE_OUT", file.path(dirname(RET), paste0("measure_", TAG, ".json")))

d <- as.data.table(read_parquet(RET))
# normalize columns
if (!"date" %in% names(d) && "Date" %in% names(d)) setnames(d, "Date", "date")
bm_col <- intersect(c("BM_Ret","BM_Ret_1m","benchmark_ret"), names(d))[1]
stopifnot(all(c("date","ret_net") %in% names(d)), !is.na(bm_col))
d <- d[!is.na(get("ret_net")) & !is.na(get(bm_col))]
d[, date := as.Date(date)]
setorder(d, date)

pr <- data.table(date = d$date, ret_net = d$ret_net, frequency = "monthly")
br <- data.table(date = d$date, benchmark_ret = d[[bm_col]], benchmark_id = "KOSPI200_total_return")
bc <- build_benchmark_compare(pr, br, run_id = TAG, strategy_id = TAG, annualization_factor = 12)
getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }

active <- d$ret_net - d[[bm_col]]
net_sr <- mean(active) / stats::sd(active) * sqrt(12)
port_t <- getbc("Portfolio_Alpha_t_NW_lag3"); ir <- getbc("Information_Ratio")
summ <- list(tag = TAG, ret_path = RET, n_months = nrow(d),
             portfolio_alpha_t_nw_lag3 = port_t, information_ratio = ir,
             alpha_annualized = getbc("Alpha_Annualized"), net_sr = net_sr,
             mean_active_net = mean(active),
             gate_port_t_2_95 = isTRUE(!is.na(port_t) && port_t >= 2.95),
             gate_ir_pos = isTRUE(!is.na(ir) && ir > 0.2))
cat(sprintf("[measure_ret:%s] n=%s PORT_t_nw=%.3f IR=%.3f net_SR=%.3f\n",
            TAG, nrow(d), ifelse(is.na(port_t),NA,port_t), ifelse(is.na(ir),NA,ir),
            ifelse(is.na(net_sr),NA,net_sr)))
write_json(summ, OUT, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[measure_ret:", TAG, "] saved ->", OUT, "\n")
