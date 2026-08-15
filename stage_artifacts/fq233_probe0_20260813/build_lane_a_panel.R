## Lane A 공용 피처 패널 빌드 (arm A/B/C 공유 입력)
##
## 왜 지금: arm A 는 xgboost 부재(도훈 결정 대기)로 막혀 있지만, **피처 패널은 어느 ML
##   라이브러리를 쓰든 동일**하다. 결정과 무관한 전제이므로 미리 만들어 다음 착수가
##   데이터 조립이 아니라 모델링부터 시작하게 한다.
##   (선행 세션이 master_panel_FIXED.rds 생성 스크립트를 안 남겨 R33 에서 경로를 재작성한
##    전례 — 자산과 스크립트를 함께 남긴다.)
##
## ★PIT 규약 (R33 과 동일, 검증된 경로):
##   · 팩터는 load_month_factors() 경유 + Z_Score_Aligned 만 사용 (C15/C13)
##   · sig_date T = T월 말 관측 → forward 짝짓기용 Date 는 **T+1개월 스탬프** (앵커 규약)
##   · 유니버스 = K200∪KQ150, 플래그(K200==1 ∪ KQ150==1) 기준, **ym 키**로 조인
##     (정확일치 join 은 259→165개월로 자른다 — R33 에서 실측한 함정)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/fq233_probe0_20260813/build_lane_a_panel.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")                      # ★연결자 프레임깊이 가정 회피(선로드)
source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/fq233_probe0_20260813"

cat("=== 1) sig_date ===\n")
avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
yms <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)); yms <- yms[yms >= "200501"]
sd0 <- as.Date(paste0(substr(yms,1,4), "-", substr(yms,5,6), "-01"))
sig_dates <- as.Date(vapply(sd0, function(d)
  as.character(seq(as.Date(d), by="month", length.out=2)[2]-1), character(1)))
cat(sprintf("  %d개월 %s ~ %s\n", length(sig_dates), min(sig_dates), max(sig_dates)))

cat("\n=== 2) 유니버스 (플래그 참 · ym 키) ===\n")
.mem <- function(f, flag) { d <- as.data.table(read_parquet(f))
  d <- d[get(flag) %in% c(TRUE, 1L, 1, "1", "Y")]
  d[, .(ym = format(as.Date(Date), "%Y%m"), Ticker = as.character(Ticker))] }
uni <- unique(rbindlist(list(.mem(".cache/universe_support/us_k200.parquet",  "K200"),
                             .mem(".cache/universe_support/us_kq150.parquet", "KQ150"))))
setkey(uni, ym, Ticker)
cat(sprintf("  %d행 · %d개월 · 월중앙 %d종목\n", nrow(uni), uniqueN(uni$ym),
            as.integer(median(uni[, .N, by=ym]$N))))

cat("\n=== 3) 팩터 long 패널 (전 팩터 · 월 1회 읽기) ===\n")
t0 <- Sys.time()
lst <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  x <- tryCatch(load_month_factors(d), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) next
  x <- as.data.table(x)
  if (!"Z_Score_Aligned" %in% names(x)) next
  x <- x[is.finite(Z_Score_Aligned), .(Ticker = as.character(Ticker),
                                       fac = as.character(Factor_Name),
                                       z = as.numeric(Z_Score_Aligned))]
  x[, ym := format(d, "%Y%m")]
  x <- x[uni, on = .(ym, Ticker), nomatch = 0]          # 유니버스 제한
  x[, sig_date := d]
  lst[[i]] <- x
  if (i %% 30 == 0) cat(sprintf("    %d/%d (%.1f분)\n", i, length(sig_dates),
                                as.numeric(difftime(Sys.time(), t0, units="mins"))))
}
long <- rbindlist(lst, fill = TRUE)
cat(sprintf("  long %d행 · %d개월 · %d팩터 · 월중앙 %d종목\n", nrow(long),
            uniqueN(long$sig_date), uniqueN(long$fac),
            as.integer(median(unique(long[, .(sig_date, Ticker)])[, .N, by=sig_date]$N))))

## ★조인 손실 감시 — R33 에서 밟은 함정(그럴듯한 종목수 뒤에 절반 잘린 기간)
stopifnot(uniqueN(long$sig_date) >= 0.95 * length(sig_dates))

cat("\n=== 4) wide 변환 + forward 표적 결합 ===\n")
wide <- dcast(long, sig_date + Ticker ~ fac, value.var = "z")
inp <- readRDS(file.path(OUT, "r33_inputs.rds"))          # frd = Date/Ticker/Ret_1m (정본 빌더 산출)
frd <- as.data.table(inp$frd)[, .(anchor = as.Date(Date), Ticker = as.character(Ticker),
                                  fwd_ret_1m = as.numeric(Ret_1m))]
nextm <- function(d) as.Date(cut(as.Date(d) + 40L, "month"))
wide[, anchor := nextm(sig_date)]
pan <- merge(wide, frd, by = c("anchor", "Ticker"))
cat(sprintf("  wide %d행 × %d열 · 표적 결합 후 %d행 · %d개월\n",
            nrow(wide), ncol(wide), nrow(pan), uniqueN(pan$sig_date)))
stopifnot(uniqueN(pan$sig_date) >= 0.95 * uniqueN(wide$sig_date))

fp <- file.path(OUT, "lane_a_feature_panel.parquet")
write_parquet(pan, fp)
cat(sprintf("\n저장: %s (%.1f MB)\n", fp, file.size(fp)/1e6))
cat(sprintf("  피처 %d종 · 표적 fwd_ret_1m · 결측률 중앙 %.1f%%\n",
            ncol(pan) - 4,
            100*median(sapply(setdiff(names(pan), c("anchor","sig_date","Ticker","fwd_ret_1m")),
                              function(c) mean(is.na(pan[[c]]))))))
