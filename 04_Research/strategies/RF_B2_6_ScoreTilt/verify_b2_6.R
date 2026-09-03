# verify_b2_6.R — 신호 이식 재현 확인 + 비중 분포 실측 (보고용, 측정 아님)
suppressPackageStartupMessages(library(data.table))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

b15 <- fread(file.path(ROOT, "04_Research/strategies/RF_B1_5_MomIlliq/stage",
                       "20260829_230711_27764", "04_holdings.csv"))
b26_dir <- list.dirs(file.path(ROOT, "04_Research/strategies/RF_B2_6_ScoreTilt/stage"),
                     recursive = FALSE)
b26_dir <- file.path(ROOT, "04_Research/strategies/RF_B2_6_ScoreTilt/stage/20260829_234856_14924")
b26 <- fread(file.path(b26_dir, "04_holdings.csv"))
cat("[verify] B2-6 stage dir:", basename(b26_dir), "\n")

a <- b15[, .(date, ticker)]; b <- b26[, .(date, ticker)]
dts <- intersect(unique(a$date), unique(b$date))
cat(sprintf("[verify] 리밸일 B1-5 %d · B2-6 %d · 공통 %d\n",
            uniqueN(a$date), uniqueN(b$date), length(dts)))
ov <- sapply(dts, function(d) {
  x <- a[date == d, ticker]; y <- b[date == d, ticker]
  length(intersect(x, y)) / max(length(x), length(y))
})
cat(sprintf("[verify] 종목집합 일치율: median %.4f · min %.4f · 완전일치 월 %d/%d\n",
            median(ov), min(ov), sum(ov >= 1 - 1e-9), length(ov)))

# ---- 비중 분포 실측 ----
wd <- readRDS(file.path(ROOT, "04_Research/strategies/RF_B2_6_ScoreTilt/weight_diag.rds"))
w <- b26[, .(date, ticker, target_weight)]
sw <- w[, .(s = sum(target_weight), n = .N,
            wmax = max(target_weight), wmin = min(target_weight),
            top5 = sum(head(sort(target_weight, decreasing = TRUE), 5L)),
            effn = 1 / sum(target_weight^2)), by = date]
cat(sprintf("[verify] Sum(w): median %.6f · min %.6f · max %.6f\n",
            median(sw$s), min(sw$s), max(sw$s)))
cat(sprintf("[verify] 종목수: median %d · min %d · max %d\n",
            as.integer(median(sw$n)), min(sw$n), max(sw$n)))
cat(sprintf("[verify] w_max: median %.4f · max %.4f | w_min: median %.3e · min %.3e\n",
            median(sw$wmax), max(sw$wmax), median(sw$wmin), min(sw$wmin)))
cat(sprintf("[verify] 상위5 합계: median %.4f (범위 %.4f~%.4f)\n",
            median(sw$top5), min(sw$top5), max(sw$top5)))
cat(sprintf("[verify] 유효종목수 1/sum(w^2): median %.2f (범위 %.2f~%.2f)\n",
            median(sw$effn), min(sw$effn), max(sw$effn)))

# 회전율 (계약 산출값 — PORTFOLIO_LOG)
bt <- readRDS(file.path(b26_dir, "bt_result.rds"))
cat("[verify] audit critical FAIL:",
    nrow(bt$audit[severity == "critical" & status == "FAIL"]), "\n")
