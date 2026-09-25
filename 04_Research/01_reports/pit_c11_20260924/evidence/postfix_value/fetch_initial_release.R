# 읽기 전용: FRED API output_type=4(Initial Release Only) — 관측별 최초 공표 빈티지(realtime_start)·값. 키(.env FRED_API_KEY)는 출력·저장하지 않는다.
# 사용: SER=PERMIT,INDPRO OUT=initial_release.csv Rscript fetch_initial_release.R   (postfix 2026-09-24 · B1·B2 값 대조 증거)
suppressWarnings(suppressMessages({ library(httr); library(jsonlite); library(data.table) }))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
ln <- readLines(file.path(ROOT, ".env"), warn = FALSE)
k <- sub("^FRED_API_KEY=", "", trimws(grep("^FRED_API_KEY=", ln, value = TRUE)[1]))
stopifnot(nchar(k) >= 10)
get1 <- function(s) {
  r <- GET("https://api.stlouisfed.org/fred/series/observations",
           query = list(series_id = s, api_key = k, file_type = "json", output_type = 4,
                        realtime_start = "1776-07-04", realtime_end = "9999-12-31",
                        observation_start = "1999-01-01"), timeout(90))
  if (status_code(r) != 200) stop(s, " HTTP ", status_code(r))
  j <- fromJSON(content(r, "text", encoding = "UTF-8"))
  d <- as.data.table(j$observations)
  d[, .(series = s, obs = as.Date(date), first_release = as.Date(realtime_start), value = value)]
}
out <- rbindlist(lapply(strsplit(Sys.getenv("SER", "PERMIT,INDPRO"), ",")[[1]], get1))
fwrite(out, Sys.getenv("OUT", "initrel.csv"))
print(out[, .N, by = series]); print(out[obs >= as.Date("2025-06-01")], nrows = 80)
