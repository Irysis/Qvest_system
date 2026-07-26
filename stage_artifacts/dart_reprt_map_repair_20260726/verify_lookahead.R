#==============================================================================
# verify_lookahead.R — 수리 검증 (전수 실측)
#   ① Factor_Date vs 실접수일: 구/신 매핑 A/B (동일 raw)
#   ② thstrm_amount 의미 규명 (인접 결함 정량 — 누적 vs 단일분기)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "config.R"))

RAW <- file.path(CACHE_DIR, "dart", "dart_raw_quarterly.parquet")
raw <- as.data.table(read_parquet(RAW, mmap = FALSE))

# ── ① Factor_Date vs 실접수일 (filing key 전수) ──────────────────────────────
rc <- raw[!is.na(rcept_no), .(rcept_date = min(as.Date(substr(rcept_no, 1, 8), "%Y%m%d"), na.rm = TRUE)),
          by = .(Ticker, bsns_year, reprt_code)]
rc <- rc[!is.na(rcept_date)]

OLDQ <- c("11014" = 1L, "11012" = 2L, "11013" = 3L, "11011" = 4L)
NEWQ <- c("11013" = 1L, "11012" = 2L, "11014" = 3L, "11011" = 4L)
fdate <- function(q, y) as.Date(fifelse(q == 1L, sprintf("%d-05-15", y),
                        fifelse(q == 2L, sprintf("%d-08-15", y),
                        fifelse(q == 3L, sprintf("%d-11-15", y), sprintf("%d-03-31", y + 1L)))))

rc[, q_old := OLDQ[reprt_code]][, q_new := NEWQ[reprt_code]]
rc[, fd_old := fdate(q_old, bsns_year)][, fd_new := fdate(q_new, bsns_year)]
rc[, la_old := as.numeric(fd_old - rcept_date)][, la_new := as.numeric(fd_new - rcept_date)]

rep1 <- rc[, .(n = .N,
               OLD_med = as.numeric(median(la_old)), OLD_neg = sum(la_old < 0),
               OLD_pct = round(100 * mean(la_old < 0), 1),
               NEW_med = as.numeric(median(la_new)), NEW_neg = sum(la_new < 0),
               NEW_pct = round(100 * mean(la_new < 0), 1)), by = reprt_code][order(reprt_code)]
cat("=== ① Factor_Date − 실접수일 (filing key 전수, 음수 = look-ahead) ===\n")
print(rep1)
cat(sprintf("TOTAL n=%d | OLD med=%.0f neg=%d (%.1f%%) | NEW med=%.0f neg=%d (%.1f%%)\n",
            nrow(rc), median(rc$la_old), sum(rc$la_old < 0), 100 * mean(rc$la_old < 0),
            median(rc$la_new), sum(rc$la_new < 0), 100 * mean(rc$la_new < 0)))

# NEW 잔여 look-ahead 의 크기 분포 (규약 자체의 성질인가, 매핑 잔재인가)
res <- rc[la_new < 0]
cat(sprintf("\nNEW 잔여 look-ahead %d건 크기: 중앙 %.0f일 | 1일이내 %.1f%% | 7일이내 %.1f%% | 90일초과 %d건\n",
            nrow(res), median(res$la_new), 100 * mean(res$la_new >= -1),
            100 * mean(res$la_new >= -7), sum(res$la_new < -90)))
cat("  90일 초과 잔여 = 정정공시(재접수) 여부 확인용 code별 분포:\n")
print(res[la_new < -90, .N, by = reprt_code][order(-N)])

# ── ② thstrm_amount 의미 규명 (인접 결함) ────────────────────────────────────
# 가설 H1: 분기·반기 IS 의 thstrm_amount = **단일 3개월** (누적 아님).
#          그렇다면 dart_extract_individual_quarters 의 누적차분은 이중차감이다.
# 검사: 같은 (Ticker, bsns_year) 에서 Revenue(11012 반기) / Revenue(11013 1분기)
#       누적이면 비율 ~2, 단일분기면 ~1.
rev <- raw[account_nm %in% c("매출액", "수익(매출액)", "영업수익") & sj_div %in% c("IS", "CIS"),
           .(amt = suppressWarnings(as.numeric(gsub(",", "", thstrm_amount)))[1],
             add = suppressWarnings(as.numeric(gsub(",", "", thstrm_add_amount)))[1]),
           by = .(Ticker, bsns_year, reprt_code)]
w <- dcast(rev, Ticker + bsns_year ~ reprt_code, value.var = "amt")
w <- w[is.finite(`11013`) & is.finite(`11012`) & `11013` > 0]
cat(sprintf("\n=== ② thstrm_amount 의미 (n=%d ticker-year) ===\n", nrow(w)))
cat(sprintf("  Revenue(11012 반기) / Revenue(11013 1분기) 중앙 비율 = %.3f\n",
            median(w$`11012` / w$`11013`)))
cat("    → ~2.0 이면 누적(현 코드 전제) · ~1.0 이면 단일 3개월(차분 전제 붕괴)\n")
addcov <- rev[reprt_code %in% c("11013","11012","11014"), .(n = .N, add_present = sum(is.finite(add)),
              pct = round(100 * mean(is.finite(add)), 1)), by = reprt_code][order(reprt_code)]
cat("  thstrm_add_amount(누적 필드) 존재율:\n"); print(addcov)
w2 <- w[is.finite(`11011`) & `11011` > 0]
cat(sprintf("  Revenue(11011 연간) / Revenue(11013 1분기) 중앙 비율 = %.3f (n=%d)\n",
            median(w2$`11011` / w2$`11013`), nrow(w2)))
cat("\n[done]\n")
