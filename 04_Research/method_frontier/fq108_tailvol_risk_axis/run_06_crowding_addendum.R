# =============================================================================
# FQ-108 run_06 (addendum): crowding — 고변동 끝(high-vol end) 재측정
#   run_05 는 Z_Score_Aligned 상위(=정렬상 'better' = 저변동 끝) 20종만 봤다.
#   위험모델 배선 판단에 필요한 건 '고변동 끝'의 군집도 → exposure 부호 반전 재측정.
#   + 하위성분 도달가능성(floor reachability) 진단 — '0'이 측정값인지 바닥인지 구분.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

RAW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
FACT <- c("D35_RealVol_63d", "D45_Downside_Dev", "D05_MaxRet")
rows <- list()
for (sd_chr in c("2016-05-31", "2021-05-31", "2026-05-29")) {
  lmf <- load_month_factors(as.Date(sd_chr), coverage_min = 0.05, factor_names = FACT)
  fe <- as.data.table(lmf)[, .(Ticker, factor_name = Factor_Name, exposure = -Z_Score_Aligned)]
  cs <- as.data.table(crowding_score_per_factor(fe, sig_date = as.Date(sd_chr),
                                                RAWDATA = RAW, top_n = 20L))
  rows[[length(rows) + 1L]] <- cbind(data.table(sig_date = sd_chr, end = "high_vol"), cs)
}
HI <- rbindlist(rows, fill = TRUE)
print(HI)

# ---- 하위성분 도달가능성 진단 -----------------------------------------------
#   vol_concentration = clamp((vol_share - top_n/N)/(1 - top_n/N), 0, 1)
#   → vol_share <= neutral 이면 항상 정확히 0 (한쪽 바닥). '측정 0' 아님.
rd <- RAW[Date <= as.Date("2026-05-29")]
rd_last <- rd[order(Ticker, Date), .SD[.N], by = Ticker, .SDcols = c("Vol", "Size")]
N <- nrow(rd_last); neutral <- 20 / N
reach <- list(
  n_universe = N, neutral_share = neutral,
  note = paste0("vol_concentration 은 top-20 거래량 점유가 중립비(", signif(neutral, 3),
                ")를 넘어야 0 초과. 관측 9/9 셀이 정확히 0 = '중립비 이하' 라는 뜻이지 ",
                "'군집 없음'의 측정값이 아니다(한쪽 바닥 clamp). passive_overlap_proxy 도 ",
                "benchmark_tickers=NULL 폴백(size 상위 200 겹침)이라 소형 편향 팩터에선 구조적 0."),
  interpretation = "crowding_score 는 하위 4성분 중 2성분이 바닥에 붙은 상태의 가중평균 = 하향 편향(floor-biased). 절대수준으로 'not crowded' 단정 금지, 시점 간 상대 변화만 유효.")

write_json(list(id = "FQ-108", stage = "run_06_crowding_addendum",
                built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                high_vol_end = HI, floor_reachability = reach),
           file.path(OUT_DIR, "fq108_crowding_addendum.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("[done] run_06 crowding addendum\n")
