## WT-D20260813_005 후속 · D5 — 기전 시간구조 진단 (next_probe P1 의 1차 증거)
##
## 왜: primary 의 이득이 sp1(2008-2014) 집중 · sp3(2020+) 소멸이었다. 두 설명이 경쟁한다.
##   (a) **연료 감쇠** — 기전이 먹는 구조(분위-조건부 우측 왜도 / 평균-중앙값 갈림)가 최근에 줄었다
##   (b) **프레임 공통 감쇠** — 두 arm 모두 약해졌다(선별 축과 무관한 재료·시장 감쇠)
##
## ★판정 축 아님. 성과 선택에 쓰지 않는다 — 구조 관측(팩터-레벨 통계의 연도별 궤적) + 수준 분해.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d5_mechanism_timeline.R")'

suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
OUT  <- "stage_artifacts/WT-D20260813_005"
DOUT <- file.path(OUT, "depth_aligned")
S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
D1 <- readRDS(file.path(DOUT, "d1_depth_stats.rds"))
D2 <- readRDS(file.path(DOUT, "d2_result.rds"))
RES <- D2$RES

cat("=== A) 연료 궤적 — 320종 팩터-레벨 구조 통계의 연도별 평균 (성과 아님) ===\n")
DS <- copy(D1$DS); DS[, yr := as.integer(format(anchor, "%Y"))]
FS <- copy(S1$FS); FS[, yr := as.integer(format(anchor, "%Y"))]
J <- merge(DS[, .(anchor, fac, yr, meandepth, meddepth, skewtop)],
           FS[, .(anchor, fac, ic, meanspread, medspread)], by = c("anchor","fac"))
J[, gap_depth := meandepth - meddepth]                 # 같은 깊이에서 평균 vs 중앙값 갈림
yr <- J[, .(n_cells = .N,
            skewtop      = mean(skewtop, na.rm = TRUE),          # 상위25 우측 꼬리 (연료)
            gap_depth    = mean(gap_depth, na.rm = TRUE),        # 평균−중앙값 갈림 (연료)
            sd_meandepth = sd(meandepth, na.rm = TRUE),
            split_share  = mean(sign(meandepth) != sign(ic), na.rm = TRUE)),  # rank 와 부호 갈림 비중
         by = yr][order(yr)]
yr[, blk := ifelse(yr < 2015, "sp1", ifelse(yr < 2020, "sp2", "sp3"))]
print(yr[, .(yr, skewtop = round(skewtop,4), gap_depth = round(gap_depth,5),
             sd_meandepth = round(sd_meandepth,4), split_share = round(split_share,3))])
blk <- yr[yr >= 2008, .(years = .N, skewtop = mean(skewtop), gap_depth = mean(gap_depth),
                        sd_meandepth = mean(sd_meandepth), split_share = mean(split_share)), by = blk][order(blk)]
cat("\n  블록 평균 (홀딩 기간 2008+):\n"); print(blk)
sl <- function(v) unname(coef(lm(v ~ I(seq_along(v))))[2])
ys <- yr[yr >= 2008]
cat(sprintf("\n  연도 추세 기울기: skewtop %+.5f/yr · gap_depth %+.6f/yr · split_share %+.5f/yr\n",
            sl(ys$skewtop), sl(ys$gap_depth), sl(ys$split_share)))
cat(sprintf("  ⇒ 연료(우측꼬리·갈림) 감쇠 여부: skewtop %s · gap %s · split %s\n",
            if (sl(ys$skewtop)   < 0) "감소" else "증가/유지",
            if (sl(ys$gap_depth) < 0) "감소" else "증가/유지",
            if (sl(ys$split_share) < 0) "감소" else "증가/유지"))

cat("\n=== B) 수준 분해 — 두 arm 이 함께 약해졌나(프레임 공통) vs 한쪽만(선별 축) ===\n")
act <- function(a) { p <- as.data.table(RES[[a]]$period_returns)
                     p[, .(date, active = ret_net - benchmark_ret)] }
AN <- c("OBJ_RANK","OBJ_MEAN_Q5","OBJ_MEAN_DEPTH","OBJ_MED_DEPTH")
L <- rbindlist(lapply(AN, function(a) { x <- act(a)
  x[, blk := ifelse(date < as.Date("2015-01-01"), "sp1", ifelse(date < as.Date("2020-01-01"), "sp2", "sp3"))]
  x[, .(arm = a, n = .N, mean_active = mean(active), nw3_t = .nw_t_mean(active, lag = 3L)), by = blk] }))
print(dcast(L, blk ~ arm, value.var = "mean_active")[, lapply(.SD, function(z) if (is.numeric(z)) round(z,5) else z)])
cat("\n  (NW3 t)\n"); print(dcast(L, blk ~ arm, value.var = "nw3_t")[, lapply(.SD, function(z) if (is.numeric(z)) round(z,3) else z)])
w <- dcast(L, blk ~ arm, value.var = "mean_active")
cat(sprintf("\n  sp1→sp3 변화: RANK %+.5f→%+.5f (Δ %+.5f) · DEPTH %+.5f→%+.5f (Δ %+.5f)\n",
            w[blk=="sp1", OBJ_RANK], w[blk=="sp3", OBJ_RANK], w[blk=="sp3", OBJ_RANK]-w[blk=="sp1", OBJ_RANK],
            w[blk=="sp1", OBJ_MEAN_DEPTH], w[blk=="sp3", OBJ_MEAN_DEPTH],
            w[blk=="sp3", OBJ_MEAN_DEPTH]-w[blk=="sp1", OBJ_MEAN_DEPTH]))
both_down <- (w[blk=="sp3", OBJ_RANK] < w[blk=="sp1", OBJ_RANK]) &&
             (w[blk=="sp3", OBJ_MEAN_DEPTH] < w[blk=="sp1", OBJ_MEAN_DEPTH])
cat(sprintf("  ⇒ 두 arm 동반 약화: %s\n", if (both_down) "예 (프레임 공통 성분 존재)" else "아니오 (선별 축 특이)"))

RESULT <- list(fuel_by_year = yr, fuel_by_block = blk,
  fuel_trend = list(skewtop_per_yr = sl(ys$skewtop), gap_depth_per_yr = sl(ys$gap_depth),
                    split_share_per_yr = sl(ys$split_share)),
  level_by_block = L, both_arms_declined = both_down,
  label = "진단 전용 — 판정 축 아님. 성과 선택·사후 문턱 조정에 사용 금지.")
saveRDS(RESULT, file.path(DOUT, "d5_mechanism_timeline.rds"))
write_json(RESULT, file.path(DOUT, "d5_mechanism_timeline.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
cat(sprintf("\n저장: %s/d5_mechanism_timeline.{rds,json}\n", DOUT))
