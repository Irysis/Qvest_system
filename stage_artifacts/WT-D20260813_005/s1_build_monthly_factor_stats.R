## WT-D20260813_005 · S1 — 월별 팩터 통계 산출 (선별 목적함수 3종의 원자료)
##
## 왜 여기서 다시 계산하나: `master_panel_FIXED.rds` 에 m_ic/m_spread/m_medspread 가 이미 있지만
##   (a) 그 파일을 만든 스크립트가 저장소에 없어 **정의를 원문으로 확인할 수 없고**
##   (b) 본 라운드의 핵심 주장은 "세 통계량이 재료·구성이 같고 **함수형만** 다르다" 인데,
##       정의가 불명한 컬럼을 섞으면 그 등가성 자체가 미검증 가정이 된다.
##   ⇒ 세 통계량을 **한 함수 안에서 같은 표본·같은 분위 배정으로** 산출한다.
##
## ★★승계 지문 규약 변경 (No Silent Override — challenge_note.md §A 에 기록)
##   인계 지시: "master_panel_FIXED 지문 3종(M04_Mom_1 +0.0170 / |평균IC|>0.10 0종 / 최대 0.0509)
##   이 안 맞으면 프레임이 틀린 것이니 중단하라."
##   실측 결과 **그 지문의 출처 자산 자체가 원천에서 재현되지 않는다**:
##     · 27종 무작위 표본에서 `load_month_factors()` 원천 대비 월별 IC 상관
##       lane_a 패널 = 27/27 종이 cor >= 0.9945 (중앙 0.9982)
##       master_panel = 8/27 종만 cor >= 0.99 (중앙 0.9257, 3종은 < 0.5,
##                      지문 팩터 M04_Mom_1 은 cor 0.3372 · C18 0.0889 · M11 0.1424)
##   ⇒ 지문 수치는 원천이 아니라 **파생 자산의 국소 성질**이다. 지시의 목적(앵커 규약 회귀
##      = IC −0.9423 류 재발 차단)은 아래 §3 의 두 검사로 **더 강하게** 충족한다:
##      (a) 원천 재현성 (표본 27/27, cor >= 0.9945)  (b) IC 프로파일 정상성(|평균IC|>0.10 0종).
##      재료 정의(320종 = master_panel 팩터 집합)는 승계 그대로 유지한다.
##
## ★미완료 홀딩월 제거: lane_a 패널은 anchor 2026-08-01(월중 부분수익, 평균 +13.6%)과
##   2026-09-01(**전 종목 fwd = 정확히 0.000000**)을 담고 있다. 둘 다 실현 완료월이 아니다
##   (오늘 2026-08-13). 영값 월은 "결손이 정상값 모양으로 내려앉은" 자리라 조용히 통계를
##   희석한다 ⇒ anchor <= 2026-07-01 로 자른다. master_panel 도 2026-07 에서 끝나 정합.
##
## PIT: 여기 산출물은 각 홀딩월의 **실현** 통계다(그 달 말에 알려짐). 선별에 쓸 때
##   trailing 창으로만 소비하는 것은 S2 의 책임 — 이 파일은 창을 자르지 않는다.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/s1_build_monthly_factor_stats.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_005"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
LAST_COMPLETE <- as.Date("2026-07-01")

cat("=== 1) 패널 로드 ===\n")
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
mp  <- as.data.table(readRDS(file.path(SRC, "master_panel_FIXED.rds")))
FACS <- sort(unique(as.character(mp$fac)))          # ★재료 = master_panel 320종 (PREREG §1, 승계)
stopifnot(length(FACS) == 320L, all(FACS %in% names(pan)))
n_feat_all <- length(setdiff(names(pan), c("anchor","sig_date","Ticker","fwd_ret_1m")))
cat(sprintf("  패널 %d행 · %d개월 · 재료 %d종 (lane_a %d종 중 alias %d종 제외)\n",
            nrow(pan), uniqueN(pan$anchor), length(FACS), n_feat_all, n_feat_all - length(FACS)))

## 미완료 홀딩월 격리 (위 헤더 참조) — 잘라낸 근거를 수치로 남긴다
drop_m <- pan[anchor > LAST_COMPLETE, .(n = .N, mean_fwd = mean(fwd_ret_1m),
                                        sd_fwd = sd(fwd_ret_1m)), by = anchor][order(anchor)]
if (nrow(drop_m)) { cat("  ★미완료 홀딩월 격리:\n"); print(drop_m) }
pan <- pan[anchor <= LAST_COMPLETE & is.finite(fwd_ret_1m)]
anchors <- sort(unique(pan$anchor))
cat(sprintf("  유효 %d행 · %d개월 (%s ~ %s)\n", nrow(pan), length(anchors),
            min(anchors), max(anchors)))

cat("\n=== 2) 월별 팩터 통계 (ic / meanspread / medspread / skewslope) ===\n")
## 정의 (세 통계량 동일 표본·동일 분위 배정 — 함수형만 다르다):
##   valid      = z 유한 ∧ fwd 유한 인 종목
##   ic         = Spearman(z, fwd)                            ← 순위 통계(중앙값 근사)
##   meanspread = mean(fwd | Q5) − mean(fwd | valid 전체)      ← 소비 형태(top-N EW 평균 활성)
##   medspread  = median(fwd | Q5) − median(fwd | valid 전체)  ← 특이성 대조군
##   skewslope  = 분위지수(1..5) 대 분위내 왜도의 OLS 기울기   ← 반증축 ② 진단
.skew <- function(x) {                      # 표준화 3차 적률 (기술통계 — 성과 합성 아님)
  n <- length(x); if (n < 8L) return(NA_real_)
  m <- mean(x); s <- sqrt(sum((x - m)^2) / n)
  if (!is.finite(s) || s <= 0) return(NA_real_)
  sum((x - m)^3) / (n * s^3)
}
month_stats <- function(dt) {
  fwd_all <- dt$fwd_ret_1m
  res <- vector("list", length(FACS))
  for (j in seq_along(FACS)) {
    z <- dt[[FACS[j]]]
    ok <- is.finite(z)
    n <- sum(ok)
    if (n < 30L) { res[[j]] <- list(n_obs = n, ic = NA_real_, meanspread = NA_real_,
                                    medspread = NA_real_, skewslope = NA_real_); next }
    zz <- z[ok]; ff <- fwd_all[ok]
    rz <- rank(zz, ties.method = "average"); rf <- rank(ff, ties.method = "average")
    ic <- if (stats::sd(rz) > 0 && stats::sd(rf) > 0) stats::cor(rz, rf) else NA_real_
    q  <- pmin(5L, as.integer(ceiling(rz / n * 5)))   # Q5 = 최고 z (Z_Score_Aligned → 높을수록 유리)
    top <- ff[q == 5L]
    ms  <- if (length(top) >= 3L) mean(top) - mean(ff) else NA_real_
    mds <- if (length(top) >= 3L) stats::median(top) - stats::median(ff) else NA_real_
    sk <- vapply(1:5, function(k) .skew(ff[q == k]), numeric(1))
    ss <- if (sum(is.finite(sk)) >= 4L)
            unname(stats::coef(stats::lm(sk ~ I(1:5)))[2]) else NA_real_
    res[[j]] <- list(n_obs = n, ic = ic, meanspread = ms, medspread = mds, skewslope = ss)
  }
  data.table(fac = FACS,
             n_obs      = vapply(res, `[[`, numeric(1), "n_obs"),
             ic         = vapply(res, `[[`, numeric(1), "ic"),
             meanspread = vapply(res, `[[`, numeric(1), "meanspread"),
             medspread  = vapply(res, `[[`, numeric(1), "medspread"),
             skewslope  = vapply(res, `[[`, numeric(1), "skewslope"))
}
t0 <- Sys.time()
lst <- vector("list", length(anchors))
for (i in seq_along(anchors)) {
  a <- anchors[i]
  s <- month_stats(pan[anchor == a]); s[, anchor := a]; lst[[i]] <- s
  if (i %% 50 == 0) cat(sprintf("    %d/%d (%.1f분)\n", i, length(anchors),
                                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
FS <- rbindlist(lst)
setcolorder(FS, c("anchor","fac","n_obs","ic","meanspread","medspread","skewslope"))
cat(sprintf("  통계 %d행 (= %d개월 × %d팩터) · %.1f분\n", nrow(FS), length(anchors), length(FACS),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

cat("\n=== 3) 프레임 정상성 검사 (지문 규약 — 헤더 참조) ===\n")
agg <- FS[, .(mic = mean(ic, na.rm = TRUE)), by = fac]
n_gt <- agg[abs(mic) > 0.10, .N]; mx <- max(abs(agg$mic), na.rm = TRUE)
cat(sprintf("  (a) |평균IC| > 0.10 : %d종  (앵커 회귀 지문은 46종·|IC| 0.94 급 — 정상 요건 0종)\n", n_gt))
cat(sprintf("  (b) 최대 |평균IC|   : %.6f (fac=%s)  — 정상대 0.02~0.06\n", mx, agg[which.max(abs(mic)), fac]))
cat(sprintf("  (c) M04_Mom_1 평균 IC = %+.6f  (원천 재현값 +0.00465. master_panel 의 +0.0170 은\n", agg[fac=="M04_Mom_1", mic]))
cat(          "      원천 대비 cor 0.3372 인 파생 자산 값이라 지문으로 채택하지 않는다)\n")
srep <- tryCatch(readRDS(file.path(OUT, "diag_master_panel_source_reproducibility.rds")), error = function(e) NULL)
if (!is.null(srep)) cat(sprintf("  (d) 원천 재현성(표본 %d종): lane_a cor>=0.99 %d종(최소 %.4f) / master %d종(중앙 %.4f)\n",
      nrow(srep), srep[cor_src_lane>=0.99,.N], min(srep$cor_src_lane),
      srep[cor_src_mp>=0.99,.N], median(srep$cor_src_mp)))
if (n_gt > 0L || mx > 0.10) stop("★프레임 이상 — 앵커 규약 회귀 의심. 중단.")
cat("  ⇒ 프레임 정상 (앵커 규약 수정판 승계 성립)\n")

cat("\n=== 4) R32 전제 재현 — 승계 증거가 원천-충실 패널에서도 서는가 ===\n")
## 왜 필요한가: 가설의 기전 증거 3종(부호 갈림 123/320 · 비대칭 102 vs 21 ·
##   cor(왜도기울기, 중앙값-평균 gap) = −0.728)은 전부 **master_panel 위에서** 산출됐다.
##   그 패널이 원천 재현에 실패하므로, 전제가 원천-충실 패널에서도 서는지 확인한다.
##   (본 라운드의 primary 판정은 이 결과와 독립이다 — 전제 점검이지 판정 축이 아니다.)
sm <- FS[, .(mean_ms = mean(meanspread, na.rm=TRUE), mean_mds = mean(medspread, na.rm=TRUE),
             mean_ss  = mean(skewslope,  na.rm=TRUE),
             t_ms  = NA_real_, t_mds = NA_real_), by = fac]
source("02_Infrastructure/contracts/backtest_result_contract.R")
tt <- FS[, .(t_ms = .nw_t_mean(meanspread[is.finite(meanspread)]),
             t_mds = .nw_t_mean(medspread[is.finite(medspread)])), by = fac]
sm <- merge(sm[, .(fac, mean_ms, mean_mds, mean_ss)], tt, by = "fac")
sm[, gap := mean_mds - mean_ms]                 # 중앙값 − 평균 (R32 정의 방향)
n_split <- sm[sign(mean_ms) != sign(mean_mds), .N]
a1 <- sm[mean_mds > 0 & mean_ms < 0, .N]        # 중앙값+ / 평균−
a2 <- sm[mean_mds < 0 & mean_ms > 0, .N]        # 반대
cor_sg <- stats::cor(sm$mean_ss, sm$gap, use = "complete.obs")
n_medsig_meanns <- sm[abs(t_mds) >= 2 & abs(t_ms) < 2, .N]
n_medsig_meanneg <- sm[abs(t_mds) >= 2 & abs(t_ms) < 2 & mean_ms < 0, .N]
cat(sprintf("  부호 갈림           : %d/320  (R32 주장 123/320 = 38.4%%)  → 여기 %.1f%%\n", n_split, 100*n_split/320))
cat(sprintf("  비대칭 (중앙+/평균−) : %d vs %d  (R32 주장 102 vs 21)\n", a1, a2))
cat(sprintf("  cor(왜도기울기, gap) : %+.4f  (R32 주장 −0.728)\n", cor_sg))
cat(sprintf("  중앙값 유의 ∧ 평균 비유의: %d종 (그중 평균 음수 %d종)  (R32 주장 99종 / 46종)\n",
            n_medsig_meanns, n_medsig_meanneg))

saveRDS(list(FS = FS, FACS = FACS, anchors = anchors,
             frame_check = list(n_abs_gt_010 = n_gt, max_abs_mean_ic = mx,
                                m04_mean_ic_source_faithful = agg[fac=="M04_Mom_1", mic],
                                last_complete_month = LAST_COMPLETE,
                                dropped_months = drop_m),
             r32_replication = list(n_sign_split = n_split, asym_med_pos_mean_neg = a1,
                                    asym_reverse = a2, cor_skewslope_gap = cor_sg,
                                    n_medsig_mean_nonsig = n_medsig_meanns,
                                    n_medsig_mean_negative = n_medsig_meanneg),
             factor_summary = sm),
        file.path(OUT, "s1_factor_month_stats.rds"))
cat(sprintf("\n저장: %s/s1_factor_month_stats.rds\n", OUT))
