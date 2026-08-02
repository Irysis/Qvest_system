## run_02_build_gate.R — FQ-084 게이트 패널 구축 (외국인 활동 강도)
##   FA_share_3m(i, d0) = Σ|Foreign_netbuy| / Σ(Close*Vol),  직전 3 완결월(= month(d0) 포함)
##   PIT: 홀딩월은 month(d0)+1 → 게이트 관측 최종일 = d0 (t-1). 홀딩월 데이터 0 사용.
##   신호(score_eff)는 일절 건드리지 않는다 — 본 스크립트는 '적용 자격' 패널만 만든다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr); library(jsonlite)})
setDTthreads(4); try(arrow::set_io_thread_count(4), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
ymv <- function(d) as.integer(format(as.Date(d), "%Y")) * 100L + as.integer(format(as.Date(d), "%m"))
ymshift <- function(y, k) { yy <- y %/% 100L; mm <- y %% 100L; t <- (yy * 12L + (mm - 1L)) + k; (t %/% 12L) * 100L + (t %% 12L) + 1L }

## ── [0] PIT 점검 3: 파일 간 vintage 일치 (2026-07-17 실사고 재발 검사) ───────────
vint <- list()
for (f in c("investor_wide", "investor_all", "investor_foreign")) {
  ds <- arrow::open_dataset(sprintf(".cache/investor_stock/%s.parquet", f))
  mx <- ds |> summarise(mx = max(Date)) |> collect()
  vint[[f]] <- as.character(mx$mx[1])
}
cat("[PIT-3 vintage] "); print(unlist(vint))
vint_ok <- length(unique(unlist(vint))) == 1L
cat(sprintf("[PIT-3 vintage] 3파일 max(Date) 일치: %s\n", vint_ok))

## ── [1] 외국인 일간 순매수 → 월별 집계 ──────────────────────────────────────────
t0 <- Sys.time()
inv <- arrow::open_dataset(".cache/investor_stock/investor_wide.parquet") |>
  filter(Date >= as.Date("2003-01-01")) |>
  select(Date, Ticker, Foreign) |> collect() |> as.data.table()
inv[, Date := as.Date(Date)]
cat(sprintf("[inv] rows=%d tickers=%d  %.1fs\n", nrow(inv), uniqueN(inv$Ticker), as.numeric(Sys.time() - t0, units = "secs")))
cat(sprintf("[inv] Foreign 정확히 0인 행 비율 = %.4f  (NA 비율 %.4f)\n",
            mean(inv$Foreign == 0, na.rm = TRUE), mean(is.na(inv$Foreign))))
inv[, ym := ymv(Date)]
invm <- inv[, .(af = sum(abs(Foreign), na.rm = TRUE),
                nz = sum(Foreign != 0, na.rm = TRUE),
                nd_inv = .N), by = .(Ticker, ym)]
rm(inv); invisible(gc())

## ── [2] 거래대금(분모) 월별 집계 ────────────────────────────────────────────────
raw <- arrow::open_dataset(".cache/rawdata.parquet") |>
  filter(Date >= as.Date("2003-01-01")) |>
  select(Date, Ticker, Close, Vol) |> collect() |> as.data.table()
raw[, Date := as.Date(Date)]
raw <- raw[is.finite(Close) & Close > 0 & is.finite(Vol) & Vol >= 0]
raw[, tv := Close * Vol]
raw[, ym := ymv(Date)]
rawm <- raw[, .(tv = sum(tv, na.rm = TRUE), nd_raw = .N), by = .(Ticker, ym)]
cat(sprintf("[raw] rows=%d tickers=%d ym=%d\n", nrow(raw), uniqueN(raw$Ticker), uniqueN(raw$ym)))
rm(raw); invisible(gc())

## sanity: tv 규모 vs liqf adv (20d 평균 거래대금)
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
chk <- merge(rawm[ym == 202603L, .(Ticker, tv_m = tv / 20)], liqf[ymv(Date) == 202603L, .(Ticker, adv)], by = "Ticker")
cat(sprintf("[sanity] 202603 tv/20 vs adv: n=%d cor=%.4f median_ratio=%.3f\n",
            nrow(chk), chk[, cor(tv_m, adv, use = "complete.obs")], chk[, median(tv_m / adv, na.rm = TRUE)]))

## ── [3] 3개월 롤링 합 → FA_share_3m (lag0 = month(d0) 포함, lag1 = 1개월 추가 지연) ──
M <- merge(rawm, invm, by = c("Ticker", "ym"), all.x = TRUE)
M[is.na(af), `:=`(af = 0, nz = 0L, nd_inv = 0L)]
setkey(M, Ticker, ym)
roll3 <- function(dt, k) {  # k = 종료월 오프셋(0 = month(d0), 1 = 1개월 추가 지연)
  base <- dt[, .(Ticker, ym_anchor = ymshift(ym, k))]
  out <- dt[, .(Ticker, ym, af, tv, nz, nd_raw)]
  res <- NULL
  for (j in 0:2) {
    cur <- out[, .(Ticker, ym_anchor = ymshift(ym, k + j), af, tv, nz, nd_raw)]
    setnames(cur, c("af", "tv", "nz", "nd_raw"), paste0(c("af", "tv", "nz", "nd"), j))
    res <- if (is.null(res)) cur else merge(res, cur, by = c("Ticker", "ym_anchor"))
  }
  res[, `:=`(af3 = af0 + af1 + af2, tv3 = tv0 + tv1 + tv2, nz3 = nz0 + nz1 + nz2, nd3 = nd0 + nd1 + nd2)]
  res[tv3 > 0, .(Ticker, ym = ym_anchor, fa_share = af3 / tv3, fa_breadth = nz3 / pmax(nd3, 1L), tv3, nd3)]
}
G0 <- roll3(M, 0L); G1 <- roll3(M, 1L)
cat(sprintf("[gate] lag0 rows=%d  lag1 rows=%d\n", nrow(G0), nrow(G1)))
cat("[gate] fa_share 분포(lag0):\n"); print(round(quantile(G0$fa_share, c(0, .05, .25, .5, .75, .95, 1), na.rm = TRUE), 5))

## ── [4] d0 키로 매핑 + base 패널 유니버스와 조인 ────────────────────────────────
fwd <- as.data.table(SI$fwd_ret)
d0map <- data.table(d0 = sort(unique(fwd$Date))); d0map[, ym := ymv(d0)]
CL <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CL[, Date := as.Date(Date)]
CL[, ym := ymv(Date - 1)]                      # AS_OF(1일) - 1 = 직전월 = d0 의 ym
CLd <- merge(CL[is.finite(score_eff), .(ym, Ticker, score_eff)], d0map, by = "ym")
S <- CLd[, .(Date = d0, Ticker, score = score_eff)]
cat(sprintf("[base] score rows=%d months=%d\n", nrow(S), uniqueN(S$Date)))

S <- merge(S, G0[, .(ym, Ticker, fa_share, fa_breadth)], by.x = c("Ticker"), by.y = c("Ticker"),
           allow.cartesian = TRUE)[ymv(Date) == ym]
S[, ym := NULL]
setnames(S, c("fa_share", "fa_breadth"), c("fa_share_l0", "fa_breadth_l0"))
S <- merge(S, G1[, .(ym, Ticker, fa_share_l1 = fa_share)], by.x = c("Ticker"), by.y = c("Ticker"),
           allow.cartesian = TRUE, all.x = TRUE)
S <- S[is.na(ym) | ymv(Date) == ym]
S[, ym := NULL]
S <- unique(S, by = c("Date", "Ticker"))
cat(sprintf("[join] rows=%d  fa_share_l0 커버리지=%.4f  fa_share_l1 커버리지=%.4f\n",
            nrow(S), mean(is.finite(S$fa_share_l0)), mean(is.finite(S$fa_share_l1))))

## ── [5] 대조 변수 부착 (adv / Size) + 상관 진단 ─────────────────────────────────
S <- merge(S, liqf[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S <- merge(S, SIZE[, .(Date, Ticker, Size)], by = c("Date", "Ticker"), all.x = TRUE)
S <- S[is.finite(score)]
sub <- S[is.finite(fa_share_l0) & is.finite(adv) & is.finite(Size)]
cs <- sub[, .(r_adv = cor(frank(fa_share_l0), frank(adv)),
              r_size = cor(frank(fa_share_l0), frank(Size)),
              r_bre_size = cor(frank(fa_breadth_l0), frank(Size)), n = .N), by = Date]
cat(sprintf("\n[진단] 게이트 vs 대조변수 월별 Spearman 평균:\n  fa_share~adv  = %+.3f\n  fa_share~Size = %+.3f\n  fa_breadth~Size = %+.3f  (months=%d)\n",
            mean(cs$r_adv, na.rm = TRUE), mean(cs$r_size, na.rm = TRUE), mean(cs$r_bre_size, na.rm = TRUE), nrow(cs)))

write_parquet(S, file.path(TD, "gate_panel.parquet"))
saveRDS(list(vintage = vint, vintage_ok = vint_ok,
             cor_fa_adv = mean(cs$r_adv, na.rm = TRUE), cor_fa_size = mean(cs$r_size, na.rm = TRUE),
             cor_breadth_size = mean(cs$r_bre_size, na.rm = TRUE),
             coverage_l0 = mean(is.finite(S$fa_share_l0)), coverage_l1 = mean(is.finite(S$fa_share_l1)),
             n_rows = nrow(S), n_months = uniqueN(S$Date)),
        file.path(TD, "gate_build_diag.rds"))
cat("[SAVED] gate_panel.parquet\n[DONE]\n")
