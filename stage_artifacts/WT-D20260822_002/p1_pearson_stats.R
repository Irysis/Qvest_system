## WT-D20260822_002 · P1 — 처치 (a) 원자료: 팩터×월 **Pearson IC**
##
## 승계(재계산 금지): 대조군 통계량 `ic`(Spearman) = WT-D20260813_005 s1_factor_month_stats.rds
##                    처치(b) 통계량 `meandepth`(top-25 평균 스프레드) = 같은 WT depth_aligned/d1_depth_stats.rds
##   두 arm 은 자구 승계로 **재현이 보장**된다. 본 파일은 신규 arm (a) 의 원자료만 만든다.
##
## 정의 (s1/d1 과 **동일 표본·동일 마스크**, 함수형만 다르다):
##   valid       = z 유한 ∧ fwd 유한, n >= 30
##   ic_pe       = Pearson(z, fwd)                     ← 소비함수(평균/선형)와 같은 함수족
##   ic_pe_w1    = Pearson(z, winsor(fwd, 1%))         ← 진단 전용(arm 아님 — 추가 시 sweep)
##   ic_sp_chk   = Spearman(z, fwd)                    ← s1$FS$ic 와 대조해 마스크 동일성 실증
##
## PIT: 여기 산출물은 각 홀딩월의 **실현** 통계(그 달 말에 알려짐). trailing 창 절단은 P2 책임.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p1_pearson_stats.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
SRC  <- "stage_artifacts/fq233_probe0_20260813"
W005 <- "stage_artifacts/WT-D20260813_005"
OUT  <- "stage_artifacts/WT-D20260822_002"
LAST_COMPLETE <- as.Date("2026-07-01")   # 미완료 홀딩월 절단 (s1 자구 승계)
MIN_N <- 30L

cat("=== 1) 승계 입력 ===\n")
S1 <- readRDS(file.path(W005, "s1_factor_month_stats.rds"))
D1 <- readRDS(file.path(W005, "depth_aligned", "d1_depth_stats.rds"))
FACS <- S1$FACS; anchors_s1 <- S1$anchors
stopifnot(identical(D1$FACS, FACS), identical(D1$anchors, anchors_s1), D1$D_DEPTH == 25L)
cat(sprintf("  승계 재료 %d팩터 · %d개월 (%s ~ %s) · 깊이 D=%d\n",
            length(FACS), length(anchors_s1), min(anchors_s1), max(anchors_s1), D1$D_DEPTH))

pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
pan <- pan[anchor <= LAST_COMPLETE & is.finite(fwd_ret_1m)]
anchors <- sort(unique(pan$anchor))
stopifnot(identical(anchors, anchors_s1))          # ★프레임 승계 검문
cat(sprintf("  패널 %d행 · %d개월 · 월중앙 %d종목 — 프레임 승계 검문 통과\n",
            nrow(pan), length(anchors), as.integer(median(pan[, .N, by = anchor]$N))))

winsor <- function(x, p = 0.01) {
  q <- stats::quantile(x, probs = c(p, 1 - p), na.rm = TRUE, type = 7)
  pmin(pmax(x, q[1]), q[2])
}
month_pearson <- function(dt) {
  fwd_all <- dt$fwd_ret_1m
  out <- vector("list", length(FACS))
  for (j in seq_along(FACS)) {
    z <- dt[[FACS[j]]]; ok <- is.finite(z); n <- sum(ok)
    if (n < MIN_N) { out[[j]] <- list(n_obs=n, ic_pe=NA_real_, ic_pe_w1=NA_real_, ic_sp_chk=NA_real_); next }
    zz <- z[ok]; ff <- fwd_all[ok]
    if (!is.finite(stats::sd(zz)) || stats::sd(zz) <= 0) {
      out[[j]] <- list(n_obs=n, ic_pe=NA_real_, ic_pe_w1=NA_real_, ic_sp_chk=NA_real_); next }
    out[[j]] <- list(n_obs = n,
                     ic_pe     = suppressWarnings(stats::cor(zz, ff, method = "pearson")),
                     ic_pe_w1  = suppressWarnings(stats::cor(zz, winsor(ff, 0.01), method = "pearson")),
                     ic_sp_chk = suppressWarnings(stats::cor(zz, ff, method = "spearman")))
  }
  data.table(fac = FACS,
             n_obs     = vapply(out, `[[`, numeric(1), "n_obs"),
             ic_pe     = vapply(out, `[[`, numeric(1), "ic_pe"),
             ic_pe_w1  = vapply(out, `[[`, numeric(1), "ic_pe_w1"),
             ic_sp_chk = vapply(out, `[[`, numeric(1), "ic_sp_chk"))
}

cat("\n=== 2) 월별 Pearson IC 산출 ===\n")
t0 <- Sys.time(); lst <- vector("list", length(anchors))
for (i in seq_along(anchors)) {
  a <- anchors[i]; s <- month_pearson(pan[anchor == a]); s[, anchor := a]; lst[[i]] <- s
  if (i %% 50 == 0) cat(sprintf("    %d/%d (%.1f분)\n", i, length(anchors),
                                as.numeric(difftime(Sys.time(), t0, units="mins"))))
}
PS <- rbindlist(lst); setcolorder(PS, c("anchor","fac","n_obs","ic_pe","ic_pe_w1","ic_sp_chk"))
cat(sprintf("  %d행 (= %d개월 × %d팩터) · %.1f분\n", nrow(PS), length(anchors), length(FACS),
            as.numeric(difftime(Sys.time(), t0, units="mins"))))

cat("\n=== 3) ★마스크 동일성 검문 — 내 Spearman 재산출이 승계 ic 와 같은가 ===\n")
J <- merge(S1$FS[, .(anchor, fac, ic, n_obs_s1 = n_obs)], PS, by = c("anchor","fac"))
stopifnot(nrow(J) == nrow(PS))
nb <- J[is.finite(n_obs) & is.finite(n_obs_s1) & n_obs != n_obs_s1, .N]
fin <- J[is.finite(ic) & is.finite(ic_sp_chk)]
dmax <- max(abs(fin$ic - fin$ic_sp_chk))
cat(sprintf("  조인 %d행 · n_obs 불일치 셀 %d (요구 0) · max|ic_s1 - ic_mine| = %.3e (요구 <1e-10)\n",
            nrow(J), nb, dmax))
stopifnot(nb == 0L, dmax < 1e-10)
cat("  ⇒ 표본 마스크·정렬 동일 확인 — (a) 는 (b)/대조군과 같은 표본 위에서 함수형만 다르다\n")

cat("\n=== 4) 통계량 분기 프로파일 (반증 축 1 원자료 — 성과 무관) ===\n")
fin2 <- J[is.finite(ic) & is.finite(ic_pe)]
cat(sprintf("  cor(Spearman IC, Pearson IC) 셀단위 = %+.4f (셀 %d)\n",
            stats::cor(fin2$ic, fin2$ic_pe), nrow(fin2)))
cat(sprintf("  sd: Spearman %.5f vs Pearson %.5f (배율 %.3f)\n",
            sd(fin2$ic), sd(fin2$ic_pe), sd(fin2$ic_pe)/sd(fin2$ic)))
D1DS <- D1$DS
fin3 <- merge(J[, .(anchor, fac, ic, ic_pe)], D1DS[, .(anchor, fac, meandepth)], by = c("anchor","fac"))
fin3 <- fin3[is.finite(ic) & is.finite(ic_pe) & is.finite(meandepth)]
cat(sprintf("  cor(Pearson IC, top25 meandepth) = %+.4f · cor(Spearman IC, meandepth) = %+.4f (셀 %d)\n",
            stats::cor(fin3$ic_pe, fin3$meandepth), stats::cor(fin3$ic, fin3$meandepth), nrow(fin3)))

saveRDS(list(PS = PS, FACS = FACS, anchors = anchors, MIN_N = MIN_N,
             mask_check = list(n_obs_mismatch = nb, max_abs_diff_spearman = dmax)),
        file.path(OUT, "p1_pearson_stats.rds"))
cat("\n[saved] p1_pearson_stats.rds\n")
