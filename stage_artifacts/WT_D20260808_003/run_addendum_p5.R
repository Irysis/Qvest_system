# =============================================================================
# run_addendum_p5.R — dual-basis 진단: post-2015 상단 −12%/yr 중 얼마가 벤치-측 상수인가
#   근거: capw−EW 격차는 벤치-측 상수(2026-08-08 확정, n=167 arm 12개 d 평균 +3.82%/yr).
#         cap-w 판정 권위는 불변이나, 기각 전 EW-대비 생존 확인은 v8.3 M2 의무.
#   ★ diag 를 포트폴리오 진술(사이즈 노출)로 읽지 말 것 — 08-08 오독 확정 사례.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_addendum_p5.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[m5] ", fmt, "\n"), ...))
M2 <- readRDS(file.path(OUT, "measure_p2.rds")); P0 <- readRDS(file.path(OUT, "p0_panels.rds"))
X <- M2$X; returns_dt <- P0$returns_dt; bench_dt <- P0$bench_dt
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
# EW-유니버스 벤치 = 판정 패널의 월별 동일가중 수익 (cap-w 벤치와 basis 비교용)
EW <- merge(X[, .(Date, Ticker)], returns_dt, by = c("Date","Ticker"))[is.finite(Ret_1m),
        .(EW_Ret = mean(Ret_1m), n_names = .N), by = Date]
BB <- merge(EW, bench_dt, by = "Date")
say("INPUT EW-유니버스 벤치: %d개월 월평균 %.0f종목 | capw−EW 격차 연 %+.2f%% (NW t %+.2f)",
    nrow(BB), mean(BB$n_names), 100*12*mean(BB$BM_Ret - BB$EW_Ret), nw_t(BB$BM_Ret - BB$EW_Ret))
p15 <- BB[Date >= as.Date("2015-01-01")]
say("  post-2015 capw−EW 격차 연 %+.2f%% (NW t %+.2f, n=%d) — 벤치-측 상수",
    100*12*mean(p15$BM_Ret - p15$EW_Ret), nw_t(p15$BM_Ret - p15$EW_Ret), nrow(p15))

RET <- merge(X[, .(Date, Ticker, q01, q01_n)], returns_dt, by = c("Date","Ticker"))
top_ret <- function(zc, kind) RET[is.finite(get(zc)) & is.finite(Ret_1m), {
  o <- order(-get(zc)); qr <- frank(get(zc))/.N
  .(r = if (kind == "top25") mean(Ret_1m[o[seq_len(min(25L, .N))]]) else mean(Ret_1m[qr > 0.8])) }, by = Date]
res <- list()
for (zc in c("q01","q01_n")) for (kd in c("top25","topq")) {
  tr <- merge(top_ret(zc, kd), BB, by = "Date")
  for (win in c("full","post2015")) {
    d <- if (win == "full") tr else tr[Date >= as.Date("2015-01-01")]
    a_cap <- d$r - d$BM_Ret; a_ew <- d$r - d$EW_Ret
    k <- sprintf("%s_%s_%s", zc, kd, win)
    res[[k]] <- list(capw_ann_pct = 100*12*mean(a_cap), capw_t = nw_t(a_cap),
                     ew_ann_pct = 100*12*mean(a_ew), ew_t = nw_t(a_ew), n = nrow(d))
    say("  %-24s cap-w 대비 연 %+7.2f%% (t %+5.2f) | EW-유니버스 대비 연 %+7.2f%% (t %+5.2f)  n=%d",
        k, 100*12*mean(a_cap), nw_t(a_cap), 100*12*mean(a_ew), nw_t(a_ew), nrow(d))
  }
}
write_json(list(capw_minus_ew_full_ann_pct = 100*12*mean(BB$BM_Ret - BB$EW_Ret),
                capw_minus_ew_post2015_ann_pct = 100*12*mean(p15$BM_Ret - p15$EW_Ret),
                arms = res,
                caveat = "diag 는 벤치-측 basis 비교이며 포트폴리오의 사이즈 노출 진술이 아니다(2026-08-08 오독 확정). cap-w 판정 권위 불변."),
           file.path(OUT, "alpha_validation_dualbasis.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== dual-basis 완료 ===")
