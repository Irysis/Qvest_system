## FQ-241 blast radius probe 1 — Lane A 분포 형태 수치의 유니버스 오염 재검
## metric_type = panel_statistic (횡단면 패널 통계 — 성과수치 아님. PORT_t/SR/IR 산출 금지)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/FQ241_blast_radius_20260822/fq241_recompute.R")'
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(4)
OUT <- "stage_artifacts/FQ241_blast_radius_20260822"
PAN <- "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet"

cat("=== 1) base (id 축) ===\n")
sch  <- arrow::open_dataset(PAN)$schema$names
idc  <- c("anchor","sig_date","Ticker","fwd_ret_1m")
facs <- setdiff(sch, idc)
base <- as.data.table(read_parquet(PAN, col_select = c("sig_date","Ticker","fwd_ret_1m")))
base[, ym := format(as.Date(sig_date), "%Y%m")]
k2 <- as.data.table(read_parquet(".cache/universe_support/us_k200.parquet"))
k2 <- k2[K200 %in% c(TRUE,1L,1,"1","Y")]
K  <- unique(k2[, .(ym = format(as.Date(Date),"%Y%m"), Ticker = as.character(Ticker), inK200 = TRUE)])
base[, rid := .I]
base <- merge(base, K, by = c("ym","Ticker"), all.x = TRUE, sort = FALSE)
setorder(base, rid); base[is.na(inK200), inK200 := FALSE]
cat(sprintf("  행 %d · 팩터 %d · 월 %d (%s~%s) · K200 행비중 %.1f%%\n",
            nrow(base), length(facs), uniqueN(base$ym), min(base$ym), max(base$ym), 100*mean(base$inK200)))

## ── arm 정의 (행 마스크) ────────────────────────────────────────────────────
ARMS <- list(
  A_orig     = quote(rep(TRUE, .N_)),          # 전기간 K200∪KQ150 (원 창)
  A_early134 = quote(ym <= "201603"),          # ★길이-정합 통제(오염창 포함, 134개월)
  B_clean    = quote(ym >= "201507"),          # 청정창 (KQ150 실시간 산출 개시 이후)
  C_k200     = quote(inK200)                   # K200 단독 (진단 통제 — 결론 근거로 쓰지 않음)
)
mask <- lapply(ARMS, function(e) { .N_ <- nrow(base); eval(e, base, parent.frame()) })
for (nm in names(mask)) cat(sprintf("  arm %-11s 행 %7d · 월 %3d\n", nm, sum(mask[[nm]]),
                                    uniqueN(base$ym[mask[[nm]]])))

skew <- function(x){ x<-x[is.finite(x)]; n<-length(x); if(n<3) return(NA_real_)
  m<-mean(x); s<-sqrt(sum((x-m)^2)/n); if(s==0) return(NA_real_); sum((x-m)^3)/(n*s^3) }

cat("\n=== 2) 팩터별 월별 분위통계 (청크) ===\n")
CH <- 25L; acc <- list(); t0 <- Sys.time()
for (i in seq(1, length(facs), by = CH)) {
  cols <- facs[i:min(i+CH-1L, length(facs))]
  zz <- as.data.table(read_parquet(PAN, col_select = cols))
  for (nm in names(mask)) {
    m <- mask[[nm]]
    D <- cbind(base[m, .(ym, y = fwd_ret_1m)], zz[m])
    Dl <- melt(D, id.vars = c("ym","y"), variable.name = "fac", value.name = "z",
               variable.factor = FALSE)
    Dl <- Dl[is.finite(z) & is.finite(y)]
    if (!nrow(Dl)) next
    Dl[, nq := .N, by = .(fac, ym)]; Dl <- Dl[nq >= 50]
    if (!nrow(Dl)) next
    Dl[, q := as.integer(as.character(cut(frank(z, ties.method="average"),
        breaks = quantile(frank(z, ties.method="average"), probs=seq(0,1,.2), na.rm=TRUE),
        include.lowest = TRUE, labels = 1:5))), by = .(fac, ym)]
    pm <- Dl[, .(mean_r = mean(y), med_r = median(y), sk = skew(y)), by = .(fac, ym, q)]
    acc[[length(acc)+1L]] <- pm[, arm := nm][]
    rm(D, Dl, pm)
  }
  rm(zz); gc(FALSE)
  cat(sprintf("  %d/%d (%.1f분)\n", min(i+CH-1L, length(facs)), length(facs),
              as.numeric(difftime(Sys.time(), t0, units="mins"))))
}
PM <- rbindlist(acc); rm(acc); gc(FALSE)
saveRDS(PM, file.path(OUT, "fq241_quintile_stats.rds"))
cat(sprintf("  분위통계 %d행 저장\n", nrow(PM)))
cat("\n[stage1 완료]\n")
