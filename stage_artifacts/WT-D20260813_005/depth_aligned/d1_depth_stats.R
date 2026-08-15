## WT-D20260813_005 후속 · D1 — **깊이-정합** 월별 팩터 통계 (top-25 버킷)
##
## 사전등록: stage_artifacts/WT-D20260813_005/depth_aligned/PREREG_depth.md (측정 전 봉인)
##
## 유일한 변경점: 선별 통계량의 상위 버킷 깊이를 **소비 깊이(top-25)** 에 맞춘다.
##   직전(Q5)  : mean(fwd | 상위 20%, 월 ~69종) − mean(fwd | 전체)
##   본 라운드 : mean(fwd | **상위 25종**)       − mean(fwd | 전체)      ← D = top_n = 25 (파생값, 스윕 금지)
##
## 기준선(mean(fwd|전체))·재료(320종)·표본(valid 마스크)·패널·절단 전부 직전과 동일 —
##   기준선까지 바꾸면 축이 둘이 되어 깊이 효과가 격리되지 않는다.
##
## PIT: 여기 산출물은 각 홀딩월의 **실현** 통계(그 달 말에 알려짐). trailing 창으로만 소비하는 것은 D2 책임.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d1_depth_stats.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_005"
DOUT <- file.path(OUT, "depth_aligned")
dir.create(DOUT, showWarnings = FALSE, recursive = TRUE)

D_DEPTH <- 25L                     # ★PREREG §1 — 소비 top_n 에서 파생. 단일 고정, 스윕 0회.
LAST_COMPLETE <- as.Date("2026-07-01")
MIN_N <- 30L                       # 직전 s1 과 동일한 유효 표본 하한
MIN_HEADROOM <- 5L                 # n <= D + 5 이면 "상위 버킷 = 사실상 전체" → NA

cat("=== 1) 입력 (직전 s1 과 동일 경로·동일 절단) ===\n")
S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
FACS <- S1$FACS; anchors_s1 <- S1$anchors
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
pan <- pan[anchor <= LAST_COMPLETE & is.finite(fwd_ret_1m)]
anchors <- sort(unique(pan$anchor))
stopifnot(identical(anchors, anchors_s1))            # ★프레임 승계 검문 (PREREG §6)
nper <- pan[, .N, by = anchor]
cat(sprintf("  %d행 · %d개월 (%s ~ %s) · 종목수 min %d / 중앙 %d / max %d\n",
            nrow(pan), length(anchors), min(anchors), max(anchors),
            min(nper$N), as.integer(median(nper$N)), max(nper$N)))
cat(sprintf("  깊이 D = %d종 → 유니버스 대비 %.2f%% (중앙) · 직전 Q5 = 20%% (월 ~%d종)\n",
            D_DEPTH, 100 * D_DEPTH / median(nper$N), as.integer(median(nper$N)/5)))

cat("\n=== 2) 월별 팩터 깊이-통계 ===\n")
## 정의 (직전과 동일 표본, **깊이만** 다르다):
##   valid       = z 유한 ∧ fwd 유한
##   meandepth   = mean(fwd | top-D by z)   − mean(fwd | valid 전체)
##   meddepth    = median(fwd | top-D by z) − median(fwd | valid 전체)
##   skewtop     = 상위 D 버킷 내 forward 왜도 (깊이-네이티브 진단, 반증축 ② 보조)
##   n_top       = 실제 상위 버킷 크기 (= D, 검문용)
.skew <- function(x) {                      # 표준화 3차 적률 (기술통계 — 성과 합성 아님)
  n <- length(x); if (n < 8L) return(NA_real_)
  m <- mean(x); s <- sqrt(sum((x - m)^2) / n)
  if (!is.finite(s) || s <= 0) return(NA_real_)
  sum((x - m)^3) / (n * s^3)
}
month_depth <- function(dt) {
  fwd_all <- dt$fwd_ret_1m
  md <- vector("list", length(FACS))
  for (j in seq_along(FACS)) {
    z <- dt[[FACS[j]]]
    ok <- is.finite(z); n <- sum(ok)
    if (n < MIN_N || n <= D_DEPTH + MIN_HEADROOM) {
      md[[j]] <- list(n_obs = n, n_top = NA_real_, meandepth = NA_real_,
                      meddepth = NA_real_, skewtop = NA_real_); next
    }
    zz <- z[ok]; ff <- fwd_all[ok]
    ti <- head(order(zz, decreasing = TRUE), D_DEPTH)   # 상위 D종 (결정적 — 동점은 색인순)
    top <- ff[ti]
    md[[j]] <- list(n_obs = n, n_top = length(top),
                    meandepth = mean(top) - mean(ff),
                    meddepth  = stats::median(top) - stats::median(ff),
                    skewtop   = .skew(top))
  }
  data.table(fac = FACS,
             n_obs     = vapply(md, `[[`, numeric(1), "n_obs"),
             n_top     = vapply(md, `[[`, numeric(1), "n_top"),
             meandepth = vapply(md, `[[`, numeric(1), "meandepth"),
             meddepth  = vapply(md, `[[`, numeric(1), "meddepth"),
             skewtop   = vapply(md, `[[`, numeric(1), "skewtop"))
}
t0 <- Sys.time()
lst <- vector("list", length(anchors))
for (i in seq_along(anchors)) {
  a <- anchors[i]; s <- month_depth(pan[anchor == a]); s[, anchor := a]; lst[[i]] <- s
  if (i %% 50 == 0) cat(sprintf("    %d/%d (%.1f분)\n", i, length(anchors),
                                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
DS <- rbindlist(lst)
setcolorder(DS, c("anchor","fac","n_obs","n_top","meandepth","meddepth","skewtop"))
cat(sprintf("  %d행 (= %d개월 × %d팩터) · %.1f분\n", nrow(DS), length(anchors), length(FACS),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

cat("\n=== 3) 검문 — 깊이가 실제로 바뀌었는가 (변경점이 통한 것을 실측으로 확인) ===\n")
## ★변경이 코드에는 있는데 산출에는 없는 경우를 잡는다. Q5 통계와 깊이 통계가 사실상 같은 수라면
##   이 라운드는 아무것도 안 바꾼 것이므로 그 사실을 먼저 알아야 한다.
J <- merge(S1$FS[, .(anchor, fac, ic, meanspread, medspread)], DS, by = c("anchor","fac"))
cat(sprintf("  조인 %d행 (이론 %d) — 손실 %.3f%%\n", nrow(J), nrow(DS), 100*(1 - nrow(J)/nrow(DS))))
stopifnot(nrow(J) == nrow(DS))
n_top_bad <- DS[is.finite(n_top) & n_top != D_DEPTH, .N]
cat(sprintf("  상위 버킷 크기 != %d 인 셀: %d (요구 0)\n", D_DEPTH, n_top_bad))
stopifnot(n_top_bad == 0L)
fin <- J[is.finite(meanspread) & is.finite(meandepth)]
cor_ms <- stats::cor(fin$meanspread, fin$meandepth)
cat(sprintf("  cor(Q5 meanspread, DEPTH meandepth) = %+.4f (셀 %d)\n", cor_ms, nrow(fin)))
cat(sprintf("  스케일: sd(Q5) %.5f vs sd(DEPTH) %.5f (배율 %.3f) · |평균| %.5f vs %.5f\n",
            sd(fin$meanspread), sd(fin$meandepth), sd(fin$meandepth)/sd(fin$meanspread),
            mean(abs(fin$meanspread)), mean(abs(fin$meandepth))))
if (cor_ms > 0.98) cat("  ★경고: 두 통계량이 거의 동일 — 깊이 변경이 산출에 도달하지 않았을 수 있다(코드 재확인)\n") else
  cat("  ⇒ 깊이 변경이 산출에 실제로 도달함 (두 통계량이 구분됨)\n")

cat("\n=== 4) 팩터-레벨 프로파일 (기전 전제 — 깊이에서 갈림이 커지는가) ===\n")
source("02_Infrastructure/contracts/backtest_result_contract.R")
sm <- DS[, .(mean_depth = mean(meandepth, na.rm=TRUE), mean_meddepth = mean(meddepth, na.rm=TRUE),
             mean_skewtop = mean(skewtop, na.rm=TRUE),
             t_depth = .nw_t_mean(meandepth[is.finite(meandepth)]),
             t_meddepth = .nw_t_mean(meddepth[is.finite(meddepth)])), by = fac]
sq <- S1$factor_summary[, .(fac, mean_ms, mean_mds, t_ms, t_mds)]
SM <- merge(sm, sq, by = "fac")
SM <- merge(SM, S1$FS[, .(mean_ic = mean(ic, na.rm=TRUE)), by = fac], by = "fac")
n_split_depth <- SM[sign(mean_depth) != sign(mean_ic), .N]
n_split_q5    <- SM[sign(mean_ms)    != sign(mean_ic), .N]
cat(sprintf("  평균-스프레드 vs rank-IC 부호 갈림 : DEPTH %d/320 (%.1f%%) · Q5 %d/320 (%.1f%%)\n",
            n_split_depth, 100*n_split_depth/320, n_split_q5, 100*n_split_q5/320))
cat(sprintf("  선별 순위 상관 (팩터 t 값): cor(t_depth, t_ms) = %+.4f · cor(t_depth, t_ic-계열 미산출)\n",
            stats::cor(SM$t_depth, SM$t_ms, use = "complete.obs")))
cat(sprintf("  상위 버킷 왜도 평균 %+.4f (깊이 %d종) — 꼬리 노출 지표\n", mean(SM$mean_skewtop, na.rm=TRUE), D_DEPTH))

saveRDS(list(DS = DS, FACS = FACS, anchors = anchors, D_DEPTH = D_DEPTH,
             depth_frac_median = D_DEPTH / median(nper$N),
             universe_n = list(min = min(nper$N), median = as.integer(median(nper$N)), max = max(nper$N)),
             change_reached_output = list(cor_q5_depth = cor_ms,
                                          sd_q5 = sd(fin$meanspread), sd_depth = sd(fin$meandepth)),
             factor_profile = SM,
             sign_split = list(depth = n_split_depth, q5 = n_split_q5)),
        file.path(DOUT, "d1_depth_stats.rds"))
cat(sprintf("\n저장: %s/d1_depth_stats.rds\n", DOUT))
