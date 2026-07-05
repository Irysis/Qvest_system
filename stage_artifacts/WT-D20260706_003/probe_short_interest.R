# Phase 0 feasibility probe — short interest / lending balance data obtainability
# Bounded effort: recent dates, small probe. Two paths.
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
KRX_API_KEY <- Sys.getenv("KRX_API_KEY")
if (KRX_API_KEY == "") {
  env_lines <- readLines(file.path(PROJECT_ROOT, ".env"), warn = FALSE)
  key_line <- grep("^KRX_API_KEY=", env_lines, value = TRUE)
  if (length(key_line) > 0) KRX_API_KEY <- sub("^KRX_API_KEY=", "", key_line[1])
}
cat("KRX_API_KEY:", ifelse(nchar(KRX_API_KEY) > 0, "SET", "MISSING"), "\n\n")

# Use a recent business day likely to have data (a few days back)
probe_dates <- c("20260630", "20260701", "20260702")

# ── PATH A: KRX Open API (data-dbg.krx.co.kr) short-selling endpoints ──
# Documented endpoints in KRX Open API catalog for short selling:
#   /svc/apis/srt/sslt_bydd_trd   (공매도 거래 by day)
#   /svc/apis/srt/sbst_bydd_trd   (공매도 잔고 by day)
# Try a few candidate paths.
KRX_API_BASE <- "https://data-dbg.krx.co.kr/svc/apis"
krx_api_probe <- function(endpoint, params) {
  url <- paste0(KRX_API_BASE, endpoint)
  resp <- tryCatch(
    POST(url, body = toJSON(params, auto_unbox = TRUE),
         add_headers(`AUTH_KEY` = trimws(KRX_API_KEY),
                     `Content-Type` = "application/json",
                     `Accept` = "application/json"),
         encode = "raw", content_type_json(), timeout(20)),
    error = function(e) { cat("  [ERR]", conditionMessage(e), "\n"); NULL })
  if (is.null(resp)) return(NULL)
  sc <- status_code(resp)
  txt <- content(resp, "text", encoding = "UTF-8")
  cat(sprintf("  [%s] HTTP %d  bytes=%d\n", endpoint, sc, nchar(txt)))
  if (sc == 200) {
    parsed <- tryCatch(fromJSON(txt), error = function(e) NULL)
    if (!is.null(parsed)) {
      blk <- if (!is.null(parsed$OutBlock_1)) parsed$OutBlock_1 else if (!is.null(parsed$output)) parsed$output else parsed
      dt <- tryCatch(as.data.table(blk), error = function(e) NULL)
      if (!is.null(dt) && nrow(dt) > 0) {
        cat("    -> rows:", nrow(dt), " cols:", paste(names(dt), collapse=","), "\n")
        cat("    -> sample:\n"); print(head(dt, 2))
        return(dt)
      } else {
        cat("    -> parsed but 0 rows. raw head:", substr(txt, 1, 300), "\n")
      }
    }
  } else {
    cat("    -> raw:", substr(txt, 1, 200), "\n")
  }
  NULL
}

cat("=== PATH A: KRX Open API short-selling endpoints ===\n")
endpoints_A <- c("/srt/sslt_bydd_trd", "/srt/sbst_bydd_trd", "/sto/sslt_bydd_trd")
for (ep in endpoints_A) {
  for (d in probe_dates) {
    cat(sprintf("Trying %s @ %s\n", ep, d))
    r <- krx_api_probe(ep, list(basDd = d))
    if (!is.null(r) && nrow(r) > 0) { cat(">>> PATH A SUCCESS:", ep, "@", d, "\n"); break }
    Sys.sleep(0.5)
  }
}

cat("\nDONE PATH A\n")
