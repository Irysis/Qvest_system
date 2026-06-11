library(jsonlite)
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
d <- fromJSON("stage_artifacts/alpha_search/20260611_143226_18772/bsc_result.json", simplifyVector = FALSE)
reg <- d$headline_reg
rt <- function(r) if (is.null(r)) "n/a" else sprintf("%+.2f%%/yr (t=%.2f)", .as_num(r$alpha_ann_pct), .as_num(r$alpha_t))
test <- function(tag, expr) tryCatch({ v <- expr; cat(sprintf("[OK ] %-12s : %s\n", tag, v)) },
                                     error = function(e) cat(sprintf("[ERR] %-12s : %s\n", tag, conditionMessage(e))))
pf_raw <- d$perf$raw_wml; pf_mgd <- d$perf$managed_wml; pf_himgd <- d$perf$long_managed
ds_raw <- d$dist$raw; ds_mgd <- d$dist$managed
sub <- d$subperiod; wr <- d$worst_raw_month; mf <- d$factor_alpha
d_sr <- .as_num(pf_mgd$Sharpe) - .as_num(pf_raw$Sharpe)
test("rt(reg)",   rt(reg))
test("ctx",       sprintf("%s 샤프 %.2f→%.2f (%s)", rt(reg), .as_num(pf_raw$Sharpe), .as_num(pf_mgd$Sharpe), "효과"))
test("kv-sharpe", sprintf("%.2f → %.2f (Δ%+.2f)", .as_num(pf_raw$Sharpe), .as_num(pf_mgd$Sharpe), d_sr))
test("kv-mdd",    sprintf("%.1f%% → %.1f%%", -abs(.as_num(pf_raw$MDD)), -abs(.as_num(pf_mgd$MDD))))
test("kv-skew",   sprintf("%.2f → %.2f", .as_num(ds_raw$skew), .as_num(ds_mgd$skew)))
test("kv-kurt",   sprintf("%.1f → %.1f", .as_num(ds_raw$kurt), .as_num(ds_mgd$kurt)))
test("kv-worst",  sprintf("%s raw%+.0f%% / 관리%+.0f%%", as.character(wr$ym), .as_num(wr$raw)*100, NA_real_*100))
test("kv-sub",    sprintf("pre %.2f→%.2f / post %.2f→%.2f", .as_num(sub$pre2017$sr_raw), .as_num(sub$pre2017$sr_mgd), .as_num(sub$post2017$sr_raw), .as_num(sub$post2017$sr_mgd)))
test("kv-lo",     sprintf("%.2f (캡[0,1])", .as_num(pf_himgd$Sharpe)))
test("kv-grade",  sprintf("%s · %.0f/100", as.character("B"), .as_num(42.2)))
best <- mf[[names(mf)[1]]]
test("kv-mf",     sprintf("%s %+.2f%%/yr (t=%.2f)", as.character(best$model), .as_num(best$alpha)*12*100, .as_num(best$alpha_tstat)))
cat("\nNOTE: mf$alpha_ann_pct already annualized? best names:", paste(names(best),collapse=","), "\n")
str(best)
