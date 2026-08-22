## WT-D20260821_002 착수 0항 — 저장 스코어 3종 해시 + 월/종목 커버리지 검증
## 핸드오프 next_steps ① : "저장 스코어 3종 해시·월 커버리지 검증"
## 판정 전 단계 — 성과량 일절 산출하지 않는다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(digest)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260821_002"

files <- c(armA = file.path(SRC, "armA_scores.parquet"),
           armB = file.path(SRC, "armB_scores.parquet"),
           armC = file.path(SRC, "armC_scores.parquet"))

prov <- list()
panels <- list()
for (nm in names(files)) {
  f <- files[[nm]]
  stopifnot(file.exists(f))
  d <- as.data.table(read_parquet(f))
  d[, Date := as.Date(Date)]
  d[, Ticker := as.character(Ticker)]
  panels[[nm]] <- d
  prov[[nm]] <- list(
    path = f,
    sha256_file = digest(f, algo = "sha256", file = TRUE),
    mtime = format(file.info(f)$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    bytes = as.numeric(file.info(f)$size),
    n_rows = nrow(d),
    cols = names(d),
    n_months = uniqueN(d$Date),
    date_min = as.character(min(d$Date)),
    date_max = as.character(max(d$Date)),
    n_tickers = uniqueN(d$Ticker),
    ## 키 집합 해시 — arm 간 (Date,Ticker) 정렬 동일성 검증용
    sha256_keyset = digest(d[order(Date, Ticker), paste0(Date, "|", Ticker)], algo = "sha256")
  )
  cat(sprintf("[%s] %d행 · %d개월 (%s~%s) · %d종목 · sha256 %s\n",
              nm, nrow(d), uniqueN(d$Date), min(d$Date), max(d$Date), uniqueN(d$Ticker),
              substr(prov[[nm]]$sha256_file, 1, 16)))
}

## --- 키 집합 일치 (paired 정렬 무결성의 필요조건) ---
ks <- vapply(prov, function(p) p$sha256_keyset, character(1))
keyset_identical <- length(unique(ks)) == 1L
cat(sprintf("\n키집합(Date,Ticker) 3-arm 동일: %s\n", keyset_identical))

## --- 월 커버리지 교차 ---
mA <- sort(unique(panels$armA$Date)); mB <- sort(unique(panels$armB$Date)); mC <- sort(unique(panels$armC$Date))
common_months <- Reduce(intersect, list(as.character(mA), as.character(mB), as.character(mC)))
cat(sprintf("월 교집합 %d (A %d · B %d · C %d)\n", length(common_months), length(mA), length(mB), length(mC)))

## --- 수익 패널 대조 ---
inp <- readRDS(file.path(SRC, "r33_inputs.rds"))
frd <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                  Ret_1m = as.numeric(Ret_1m))]
cat(sprintf("forward return 패널 %d행 · %d개월 (%s~%s) · sha256(r33_inputs.rds) %s\n",
            nrow(frd), uniqueN(frd$Date), min(frd$Date), max(frd$Date),
            substr(digest(file.path(SRC, "r33_inputs.rds"), algo = "sha256", file = TRUE), 1, 16)))

## 스코어 월 중 수익 패널에 있는 월 (= 실제 측정 가능 월)
meas_months <- sort(intersect(common_months, as.character(unique(frd$Date))))
cat(sprintf("측정 가능 월(스코어∩수익) = %d\n", length(meas_months)))

## 월별 종목 커버리지 (F2 top-100 / F3 전브레드스 가용성 확인)
cov_m <- panels$armA[, .(n_names = .N), by = Date][order(Date)]
cov_ret <- merge(panels$armA[, .(Date, Ticker)], frd, by = c("Date", "Ticker"))[
  , .(n_with_ret = .N), by = Date][order(Date)]
cm <- merge(cov_m, cov_ret, by = "Date", all.x = TRUE)
cm[is.na(n_with_ret), n_with_ret := 0L]
cat(sprintf("월별 스코어 종목수: min %d · p05 %d · median %d · max %d\n",
            min(cm$n_names), as.integer(quantile(cm$n_names, .05)),
            as.integer(median(cm$n_names)), max(cm$n_names)))
cat(sprintf("월별 수익 매칭 종목수: min %d · p05 %d · median %d · max %d\n",
            min(cm$n_with_ret), as.integer(quantile(cm$n_with_ret, .05)),
            as.integer(median(cm$n_with_ret)), max(cm$n_with_ret)))
cat(sprintf("★top-100 가용 월(수익매칭 >=100): %d / %d\n",
            sum(cm$n_with_ret >= 100), nrow(cm)))
cat(sprintf("★top-50 가용 월(수익매칭 >=50): %d / %d\n",
            sum(cm$n_with_ret >= 50), nrow(cm)))

## --- 스코어 컬럼 결측 ---
na_rate <- list(
  armA = mean(is.na(panels$armA$score)),
  armB = mean(is.na(panels$armB$q50)),
  armC = mean(is.na(panels$armC$score)))
print(na_rate)

## --- 기존 결과 재현 대조 (armA canonical top-25 EW) : 저장 결과와 값 일치 확인 ---
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressPackageStartupMessages({library(xts); library(PerformanceAnalytics)})
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(frd[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
cat(sprintf("bench 축 정렬 %d개월 (덮개 %.1f%%)\n", nrow(bench_dt),
            100*nrow(bench_dt)/uniqueN(frd$Date)))

A_stored <- readRDS(file.path(SRC, "armA_canonical_result.rds"))
A_re <- canonical_screen_bt(
  scores_dt = panels$armA[, .(Date, Ticker, score = as.numeric(score))],
  returns_dt = frd, bench_dt = bench_dt, top_n = 25L, cost_bps_oneway = 15,
  strategy_id = "WT002_repro_armA", run_id = "WT002_repro", diag_dual_basis = FALSE)
repro <- list(
  stored_port_t = as.numeric(A_stored$portfolio_alpha_t_nw_lag3),
  repro_port_t  = as.numeric(A_re$portfolio_alpha_t_nw_lag3),
  stored_net_sr = as.numeric(A_stored$net_sr),
  repro_net_sr  = as.numeric(A_re$net_sr),
  stored_n_months = as.numeric(A_stored$n_months),
  repro_n_months  = as.numeric(A_re$n_months),
  stored_mean_active = as.numeric(A_stored$mean_active_net),
  repro_mean_active  = as.numeric(A_re$mean_active_net))
repro$max_abs_reldiff <- max(abs(c(
  repro$repro_port_t - repro$stored_port_t,
  repro$repro_net_sr - repro$stored_net_sr,
  repro$repro_mean_active - repro$stored_mean_active)))
cat("\n=== armA 저장결과 재현 대조 ===\n"); print(repro)

write_json(list(
  wt_id = "WT-D20260821_002", step = "step0_provenance",
  computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stored_scores = prov,
  keyset_identical_across_arms = keyset_identical,
  n_common_months = length(common_months),
  n_measurable_months = length(meas_months),
  monthly_name_coverage = list(
    score_names = list(min = min(cm$n_names), median = median(cm$n_names), max = max(cm$n_names)),
    ret_matched = list(min = min(cm$n_with_ret), median = median(cm$n_with_ret), max = max(cm$n_with_ret)),
    months_ge_50 = sum(cm$n_with_ret >= 50), months_ge_100 = sum(cm$n_with_ret >= 100),
    n_months_total = nrow(cm)),
  score_na_rate = na_rate,
  armA_reproduction = repro,
  bench_axis_months = nrow(bench_dt)),
  file.path(OUT, "step0_provenance.json"), auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null")
saveRDS(list(panels = panels, frd = frd, bench_dt = bench_dt, cm = cm),
        file.path(OUT, "step0_inputs.rds"))
cat("\n저장: step0_provenance.json · step0_inputs.rds\n")
