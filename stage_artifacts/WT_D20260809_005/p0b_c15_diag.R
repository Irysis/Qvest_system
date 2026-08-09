## P0b — C15 부재 진단 + C10/C13 커버리지 동일성 진단
## ★C15 규칙 준수: factor DB 는 load_month_factors() 경유만. 직접 parquet read 안 함.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[p0b] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

## [1] 커넥터가 실제로 내주는 팩터 목록 (factor_names 미지정 = 전량)
say("================ [1] 커넥터 전량 로드 — 실제 산출 팩터명 ================")
probe_dates <- as.Date(c("2005-06-30","2012-06-29","2019-06-28","2026-07-31"))
for (d in probe_dates) {
  d <- as.Date(d, origin="1970-01-01")
  z <- tryCatch(load_month_factors(d), error=function(e) { say("  %s ERROR %s", d, conditionMessage(e)); NULL })
  if (is.null(z)) next
  fn <- sort(unique(as.character(z$Factor_Name)))
  cs <- grep("^C[0-9]", fn, value=TRUE)
  say("  %s: 총 %d종 · C-계열 %d종 = %s", format(d,"%Y-%m"), length(fn), length(cs), paste(cs, collapse=" "))
  say("     C15 존재=%s · C10 존재=%s · C13 존재=%s · C18 존재=%s",
      "C15_Forecast_Error_Trend" %in% fn, "C10_SUE_Persistence" %in% fn,
      "C13_Revision_Breadth_3m" %in% fn, "C18_Earnings_CAR_3d" %in% fn)
}

## [2] C15 가 registry 에 등재되어 있는가 (커넥터 필터 원인 후보)
say("================ [2] factor registry 등재 확인 ================")
reg_paths <- Sys.glob("06_Registry/factor_registry*.csv")
say("registry 후보 파일: %s", paste(basename(reg_paths), collapse=", "))
for (rp in reg_paths) {
  r <- tryCatch(fread(rp), error=function(e) NULL); if (is.null(r)) next
  nmcol <- intersect(c("Factor_Name","factor_name","name"), names(r))[1]
  if (is.na(nmcol)) { say("  %s: 이름 컬럼 미상 (%s)", basename(rp), paste(names(r),collapse=",")); next }
  tgt <- c("C10_SUE_Persistence","C13_Revision_Breadth_3m","C15_Forecast_Error_Trend","C18_Earnings_CAR_3d")
  say("  %s (%d행): %s", basename(rp), nrow(r),
      paste(sprintf("%s=%s", sub("^C([0-9]+).*","C\\1",tgt), tgt %in% r[[nmcol]]), collapse=" "))
}

## [3] 빌더 블록 실제 조건 — C15 만 다른 이유
say("================ [3] compute_consensus.R C15 블록 조건 ================")
src <- readLines("02_Infrastructure/factor_db/compute_consensus.R", warn=FALSE)
i15 <- grep("C15_Forecast_Error_Trend", src)
say("  C15 언급 행: %s", paste(i15, collapse=","))
rng <- max(1, min(i15)-22):min(length(src), max(i15)+3)
cat(paste0(sprintf("%5d| ", rng), src[rng]), sep="\n")

## [4] C10 vs C01 / C13 vs C04 값 동일성 — 커버리지가 바이트 동일했다
say("================ [4] 값 동일성 (커버리지 동일 → 실제 값도 같은가) ================")
for (d in as.Date(c("2005-06-30","2015-06-30","2025-06-30"))) {
  d <- as.Date(d, origin="1970-01-01")
  z <- tryCatch(load_month_factors(d, factor_names=c("C01_SUE","C10_SUE_Persistence",
                                                     "C04_ESBR","C13_Revision_Breadth_3m")),
                error=function(e) NULL)
  if (is.null(z) || !nrow(z)) { say("  %s 로드 실패", format(d,"%Y-%m")); next }
  w <- dcast(as.data.table(z), Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  rw <- dcast(as.data.table(z), Ticker ~ Factor_Name, value.var="Raw_Value")
  f <- function(a,b,tb) {
    if (!all(c(a,b) %in% names(tb))) return("컬럼부재")
    x <- tb[[a]]; y <- tb[[b]]; ok <- is.finite(x) & is.finite(y)
    sprintf("n=%d · 동일값비율 %.4f · spearman %+.4f · pearson %+.4f",
            sum(ok), mean(x[ok]==y[ok]), cor(x[ok],y[ok],method="spearman"), cor(x[ok],y[ok]))
  }
  say("  %s  C01 vs C10  [z]   %s", format(d,"%Y-%m"), f("C01_SUE","C10_SUE_Persistence",w))
  say("  %s  C01 vs C10  [raw] %s", format(d,"%Y-%m"), f("C01_SUE","C10_SUE_Persistence",rw))
  say("  %s  C04 vs C13  [z]   %s", format(d,"%Y-%m"), f("C04_ESBR","C13_Revision_Breadth_3m",w))
  say("  %s  C04 vs C13  [raw] %s", format(d,"%Y-%m"), f("C04_ESBR","C13_Revision_Breadth_3m",rw))
}
say("완료")
