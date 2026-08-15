## R33 — D03_RealVol 5점 분위 프로파일을 **수정 프레임**에서 재산출 (혹형 여부 확정)
##
## 왜 이 파일이 저장소 안에 있나: 선행 세션이 master_panel_FIXED.rds 를 만든 스크립트를
## 남기지 않아 재산출 경로를 처음부터 다시 써야 했다. 라운드 산출물은 수치뿐 아니라
## **그 수치를 만든 경로**도 남긴다.
##
## ★앵커 규약(인계 §0): 팩터 sig_date T 는 T월 말 관측이다. build_monthly_forward_returns 의
##   앵커는 "sig_date 이하 최종 거래일" 이므로, 팩터를 T 로 넘기면 앵커가 T월 말이 되어
##   forward 가 T월 수익 = 팩터가 채점 대상 월을 본다. 수정 = 넘길 Date 를 T+1개월로 스탬프.
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/fq233_probe0_20260813/r33_profile.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
## ★config.R 를 **먼저** 로드한다. factor_db_connector.R:38 의 `.fdc_self_dir <- dirname(sys.frame(1)$ofile)`
##   은 "연결자가 최상위에서 source 된다"는 프레임 깊이 가정이라, 다른 스크립트 안에서 부르면
##   ofile 이 **호출자**를 가리켜 config.R 을 엉뚱한 디렉터리에서 찾는다(실측: stage_artifacts/config.R).
##   연결자 51행이 `if (!exists("CACHE_DIR"))` 가드를 두고 있으므로 선로드로 우회 가능하고,
##   FACTOR_DB_DIR 은 CACHE_DIR 파생(54행)이라 이후 경로는 정상이다.
##   ※이 실패는 조용하지 않다(파일 없음으로 즉사) — 침묵 실패 계열은 아님.
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")

FAC <- "D03_RealVol"
OUT <- "stage_artifacts/fq233_probe0_20260813"

cat("=== 1) sig_date 목록 ===\n")
avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
yms <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail))
yms <- yms[yms >= "200501"]
sd0 <- as.Date(paste0(substr(yms, 1, 4), "-", substr(yms, 5, 6), "-01"))
sig_dates <- as.Date(vapply(sd0, function(d)
  as.character(seq(as.Date(d), by = "month", length.out = 2)[2] - 1), character(1)))
cat(sprintf("  %d개월  %s ~ %s\n", length(sig_dates), min(sig_dates), max(sig_dates)))

cat("\n=== 2) 팩터 로드 (load_month_factors 경유 = C15) ===\n")
fl <- rbindlist(lapply(sig_dates, function(d) {
  x <- tryCatch(load_month_factors(d, factor_names = FAC), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  # ★C13: NEGATE/FLIP 금지 — 연결자가 낸 Z_Score_Aligned 만 쓴다(방향 정렬 완료분).
  x <- as.data.table(x)[Factor_Name == FAC & is.finite(Z_Score_Aligned)]
  if (!nrow(x)) return(NULL)
  data.table(sig_date = as.Date(d), Ticker = as.character(x$Ticker),
             z = as.numeric(x$Z_Score_Aligned))
}), fill = TRUE)
cat(sprintf("  로드 %d행 · %d개월 · 월중앙 %d종목\n", nrow(fl), uniqueN(fl$sig_date),
            as.integer(median(fl[, .N, by = sig_date]$N))))

cat("\n=== 3) forward return (정본 빌더 · ★팩터 Date +1개월 스탬프) ===\n")
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
raw[, Date := as.Date(Date)]
nextm <- function(d) as.Date(cut(as.Date(d) + 40L, "month"))
fl[, anchor := nextm(sig_date)]
fr <- build_monthly_forward_returns(raw, sort(unique(fl$anchor)))
str_head <- function(x) paste(utils::head(names(x), 10), collapse = ", ")
frd <- if (is.data.frame(fr)) as.data.table(fr) else as.data.table(fr[[1]])
cat("  forward 컬럼:", str_head(frd), "\n")
saveRDS(list(fl = fl, frd = frd), file.path(OUT, "r33_inputs.rds"))
cat("  [중간 저장] r33_inputs.rds\n")
