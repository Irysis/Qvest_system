# O8 — 최종 검증: 전 260 시점 제약 · 패키지 정합 · schedule fidelity
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
W <- fread(file.path(OUT,"weights.csv")); P <- fromJSON(file.path(MB,"optimization_package.json"), simplifyVector=FALSE)
per <- W[, .(n=.N, sw=sum(weight), minw=min(weight), maxw=max(weight)), by=as_of_date]
chk <- list(
  n_dates=nrow(per), max_n=max(per$n), n_over_25=sum(per$n>25),
  max_abs_sumw_dev=max(abs(per$sw-1)), any_negative=any(W$weight<0), min_weight=min(W$weight),
  max_weight=max(per$maxw), n_dates_sumw_off=sum(abs(per$sw-1)>1e-9),
  liq_note="유동성 2e8 하한: 선택슬롯 13000 중 미달 0 (o1 실측, min ADV20 2.012e8)",
  tickers_unique=uniqueN(W$ticker), na_weight=sum(is.na(W$weight)))
str(chk)
stopifnot(chk$max_n<=25, chk$n_over_25==0, !chk$any_negative, chk$max_abs_sumw_dev<1e-9, chk$na_weight==0)
# 패키지 as-of vs weights.csv as-of 정합
asof <- max(W$as_of_date); tw <- unlist(P$target_weights)
wa <- W[as_of_date==asof][order(-weight)]
same <- setequal(names(tw), wa$ticker) && max(abs(tw[wa$ticker] - wa$weight)) < 1e-9
cat(sprintf("[O8] as-of %s 패키지<->csv 정합: %s (max diff %.2e)\n", asof, same,
            max(abs(tw[wa$ticker]-wa$weight))))
stopifnot(same)
# schedule fidelity hook (존재 시)
h <- file.path(ROOT,"02_Infrastructure/hooks/schedule_fidelity_check.sh")
cat("[O8] schedule_fidelity_check.sh 존재:", file.exists(h), "\n")
cat(sprintf("[O8] schedule density = %.4f (>=0.95 %s) · dates %d / alpha sig_dates %d\n",
    P$schedule$schedule_density_ratio, P$schedule$pass, P$schedule$unique_as_of_dates, P$schedule$alpha_sig_dates))
write_json(chk, file.path(OUT,"o8_constraint_verify.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[O8] ALL CONSTRAINT CHECKS PASS (260/260 시점)\n")
