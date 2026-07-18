##=============================================================================
## ff5_kr_tracker.R — KR Fama-French 5-factor 월간 트래커 (시장 국면 리뷰 전용)
##
## ★용도 라벨: monitoring/diagnostic. FF 팩터는 학술 long-short 스프레드 —
##   본 산출의 L/S 수치는 시장 스타일 국면 서술용이며 전략 판정·자본 인용 금지
##   (no-longshort mandate 정합). metric_type=diagnostic_monitoring.
##
## 구성 (FF2015 충실 + KR 적응, 선택 명시):
##   - 유니버스: 전체 상장(월말 Size>0·sanity |ret|<=5,>=-1) — 시장 서술 목적
##   - formation: 매년 5월말(연간 재무 C4 확정 후 = FF June-formation의 KR 등가),
##     보유 6월~익년 5월. 2×3 VW(월별 직전월말 시총 가중)
##   - Size 분할: 전체 상장 시총 median / 2nd 변수 30~70 분위(전체 상장)
##   - HML: V01_BM(高=Value) / RMW: Q01_GPA(高=Robust, ★FF OP/BE 아닌 GPA proxy 라벨)
##     / CMA: Q06_Asset_Growth(低=Conservative)
##   - 팩터값: load_month_factors(C15 경유) → Z_raw = Z_Score_Aligned × ic_sign 복원
##     (IC-정렬 해제 → 원값 단조 방향, 경제 부호는 본 스크립트가 FF 정의로 부여)
##   - MKT: VW 전체시장 − CD91(월평균/12). CD91 이전 구간 MKT_excess=NA(정직)
##   - SMB = 3-sort 평균(FF2015). 자체합성 금지 정합: 월간 스프레드 산술만,
##     복리 NAV 산출 없음(차트도 rolling 평균만)
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT_DIR <- "outputs/ff5_kr"
dir.create(file.path(OUT_DIR, "charts"), recursive = TRUE, showWarnings = FALSE)
RUNTAG <- format(Sys.Date(), "%Y%m%d")
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
nwt <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(lmtest::coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3]) }
t0 <- Sys.time()

## ── 1) 월말 패널 + 월간 실현수익 (전체 상장) ────────────────────────────────
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
mgrid <- seq(as.Date("2004-06-01"), max(ud), by = "1 month")
me <- unique(as.Date(vapply(mgrid, function(d) { m0 <- as.Date(cut(d, "month")); e <- seq(m0, by = "1 month", length.out = 2)[2] - 1
  v <- ud[ud <= e & ud >= m0]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
pn <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |>
        select(all_of(c("Date", "Ticker", "Close", "Size"))) |> collect())
pn[, Date := as.Date(Date)]
pn <- pn[!is.na(Close) & Close > 0]
setorder(pn, Ticker, Date)
me_idx <- data.table(Date = me, i = seq_along(me))
pn <- merge(pn, me_idx, by = "Date")
pn[, `:=`(Close_p = shift(Close), Size_p = shift(Size), i_p = shift(i)), by = Ticker]
rets <- pn[!is.na(Close_p) & i_p == i - 1 & !is.na(Size_p) & Size_p > 0]
rets[, ret := Close / Close_p - 1]
rets <- rets[ret <= 5.0 & ret >= -1.0]                     # R44 sanity
rets[, ym := format(Date, "%Y-%m")]
wf("returns panel: %d rows, %d months (%s..%s)", nrow(rets), uniqueN(rets$ym), min(rets$ym), max(rets$ym))

## ── 2) formation별 버킷 배정 ────────────────────────────────────────────────
recover_raw_z <- function(sig_d, fnames) {
  f <- as.data.table(load_month_factors(sig_d, factor_names = fnames))
  dm <- tryCatch(.load_ic_direction_cached(sig_d, 36L), error = function(e) NULL)
  if (!is.null(dm) && nrow(dm)) f <- merge(f, dm[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
  else f[, ic_sign := NA_integer_]
  reg <- tryCatch(.load_registry(), error = function(e) NULL)
  if (!is.null(reg)) {
    rd <- data.table(Factor_Name = names(reg),
                     reg_sign = sapply(reg, function(x) if ((x$direction %||% "higher_better") == "lower_better") -1L else 1L))
    f <- merge(f, rd, by = "Factor_Name", all.x = TRUE)
    f[is.na(ic_sign), ic_sign := reg_sign]; f[, reg_sign := NULL]
  }
  f[is.na(ic_sign), ic_sign := 1L]
  f[, z_raw := Z_Score_Aligned * ic_sign]                  # 원값 단조 방향 복원
  dcast(f, Ticker ~ Factor_Name, value.var = "z_raw")
}

fy_years <- 2005:2025
assign_rows <- list()
for (y in fy_years) {
  sig <- me[format(me, "%Y-%m") == sprintf("%d-05", y)]
  if (!length(sig)) next
  fz <- recover_raw_z(sig, c("V01_BM", "Q01_GPA", "Q06_Asset_Growth"))
  sz <- pn[Date == sig & !is.na(Size) & Size > 0, .(Ticker, Size)]
  fz <- merge(fz, sz, by = "Ticker")
  if (nrow(fz) < 200) { wf("  [skip] fy=%d n=%d", y, nrow(fz)); next }
  fz[, size_grp := fifelse(Size <= median(Size), "S", "B")]
  mk3 <- function(v, flip = FALSE) {                        # flip=TRUE: 낮을수록 상위(CMA)
    q <- quantile(v, c(0.3, 0.7), na.rm = TRUE)
    g <- fifelse(v <= q[1], "L", fifelse(v >= q[2], "H", "M"))
    if (flip) g <- chartr("LH", "HL", g)                    # C(=low growth)를 H로 라벨
    g
  }
  fz[, `:=`(g_bm = mk3(V01_BM), g_op = mk3(Q01_GPA), g_inv = mk3(Q06_Asset_Growth, flip = TRUE))]
  assign_rows[[as.character(y)]] <- fz[, .(Ticker, fy = y, size_grp, g_bm, g_op, g_inv)]
  if (y %% 5 == 0) wf("  formation fy=%d n=%d (%.1f min)", y, nrow(fz), as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
ASG <- rbindlist(assign_rows)
wf("formations: %d years, %d assignments", uniqueN(ASG$fy), nrow(ASG))

## ── 3) 월간 VW 버킷 수익 → 팩터 ────────────────────────────────────────────
rets[, fy := fifelse(month(Date) >= 6, year(Date), year(Date) - 1L)]
rw <- merge(rets[, .(ym, Ticker, ret, w = Size_p, fy)], ASG, by = c("Ticker", "fy"))
vw <- function(r, w) sum(r * w) / sum(w)
fac_rows <- list()
for (sv in c("g_bm", "g_op", "g_inv")) {
  b <- rw[!is.na(get(sv)), .(pr = vw(ret, w), n = .N), by = .(ym, size_grp, g = get(sv))]
  wide <- dcast(b, ym ~ size_grp + g, value.var = "pr")
  need <- c("S_H", "S_M", "S_L", "B_H", "B_M", "B_L")
  if (!all(need %in% names(wide))) { wf("  [warn] %s missing buckets some months", sv) }
  wide[, smb_part := (S_H + S_M + S_L) / 3 - (B_H + B_M + B_L) / 3]
  wide[, hml_like := (S_H + B_H) / 2 - (S_L + B_L) / 2]
  fac_rows[[sv]] <- wide[, .(ym, sort = sv, smb_part, hml_like)]
}
FC <- rbindlist(fac_rows)
FF <- dcast(FC, ym ~ sort, value.var = c("smb_part", "hml_like"))
FF[, SMB := (smb_part_g_bm + smb_part_g_op + smb_part_g_inv) / 3]
FF[, `:=`(HML = hml_like_g_bm, RMW = hml_like_g_op, CMA = hml_like_g_inv)]
mkt <- rw[, .(mkt_vw = vw(ret, w)), by = ym]
ecos <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
rf <- ecos[Series == "KR_CD91"][, .(rf_m = mean(Value, na.rm = TRUE) / 100 / 12), by = .(ym = format(as.Date(Date), "%Y-%m"))]
FF <- merge(FF, mkt, by = "ym", all.x = TRUE)
FF <- merge(FF, rf, by = "ym", all.x = TRUE)
FF[, MKT := mkt_vw - rf_m]
FF <- FF[, .(ym, MKT, SMB, HML, RMW, CMA, mkt_vw, rf_m)][order(ym)]
wf("FF5 series: %d months (%s..%s), MKT non-NA=%d", nrow(FF), min(FF$ym), max(FF$ym), FF[!is.na(MKT), .N])
write_parquet(FF, file.path(OUT_DIR, "ff5_kr_monthly.parquet"))
fwrite(FF, file.path(OUT_DIR, sprintf("ff5_kr_monthly_%s.csv", RUNTAG)))

## ── 4) 기간 요약 + 사후 정합 게이트 ─────────────────────────────────────────
per <- list(c("2005-06", "2009-12"), c("2010-01", "2014-12"), c("2015-01", "2015-12"),
            c("2016-01", "2019-12"), c("2020-01", "2021-12"), c("2022-01", "2023-12"), c("2024-01", "2026-12"))
tab <- list()
for (p in per) {
  s <- FF[ym >= p[1] & ym <= p[2]]
  if (!nrow(s)) next
  tab[[p[1]]] <- data.table(period = paste(p[1], p[2], sep = "~"), n = nrow(s),
    MKT = mean(s$MKT, na.rm = TRUE), SMB = mean(s$SMB, na.rm = TRUE), SMB_t = nwt(s$SMB),
    HML = mean(s$HML, na.rm = TRUE), HML_t = nwt(s$HML), RMW = mean(s$RMW, na.rm = TRUE), RMW_t = nwt(s$RMW),
    CMA = mean(s$CMA, na.rm = TRUE), CMA_t = nwt(s$CMA))
}
TAB <- rbindlist(tab)
print(TAB[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)])
## 사후 정합 게이트 (기존 독립 실측과 부호 대조 — 구성 오류 검출용)
g1 <- TAB[period == "2024-01~2026-12", HML] < 0     # 밸류-vs-mega 역전 실측(R26~FQ-046) 정합
g2 <- TAB[period == "2024-01~2026-12", SMB] < 0     # sml 프로브(2024-26 음) 정합
g3 <- TAB[period == "2016-01~2019-12", SMB] < TAB[period == "2010-01~2014-12", SMB]  # 2015 반전
wf("[정합게이트] HML 2024+ 음(밸류역전 정합): %s | SMB 2024+ 음(sml 정합): %s | SMB 2016-19 < 2010-14: %s",
   g1, g2, g3)
if (!all(g1, g2, g3, na.rm = TRUE)) wf("[!!] 부호/구성 재점검 필요 — 기존 실측과 불일치")

## ── 5) 차트 (rolling 12m 평균 — 복리 NAV 없음) ─────────────────────────────
FFc <- copy(FF)
for (cc in c("MKT", "SMB", "HML", "RMW", "CMA")) FFc[, (paste0("r12_", cc)) := frollmean(get(cc), 12)]
FFc[, d := as.Date(paste0(ym, "-01"))]
png(file.path(OUT_DIR, "charts", "ff5_rolling12.png"), width = 1150, height = 640)
par(mfrow = c(2, 1), mar = c(3, 4, 2.5, 1))
plot(FFc$d, FFc$r12_MKT, type = "l", lwd = 2, col = "black", main = "KR FF5 rolling 12m mean — MKT(excess)",
     xlab = "", ylab = "월평균"); abline(h = 0, lty = 3)
cols <- c(SMB = "firebrick", HML = "steelblue", RMW = "darkgreen", CMA = "purple")
plot(FFc$d, FFc$r12_SMB, type = "l", lwd = 2, col = cols["SMB"], ylim = range(FFc[, .(r12_SMB, r12_HML, r12_RMW, r12_CMA)], na.rm = TRUE),
     main = "SMB / HML / RMW / CMA rolling 12m mean", xlab = "", ylab = "월평균")
for (cc in c("HML", "RMW", "CMA")) lines(FFc$d, FFc[[paste0("r12_", cc)]], lwd = 2, col = cols[cc])
abline(h = 0, lty = 3); legend("topright", names(cols), col = cols, lwd = 2, cex = 0.9)
dev.off()
wf("chart written: ff5_rolling12.png")

## 최근 12개월 상세
rec <- FF[(.N - 11):.N]
wf("최근 12개월:"); print(rec[, .(ym, MKT = round(MKT, 4), SMB = round(SMB, 4), HML = round(HML, 4), RMW = round(RMW, 4), CMA = round(CMA, 4))])

write_json(list(runtag = RUNTAG, metric_type = "diagnostic_monitoring",
                usage_label = "시장 국면 리뷰 전용 — L/S 스프레드, 전략 판정/자본 인용 금지",
                construction = "annual May formation·VW 2x3·전체상장·RMW=GPA proxy·CMA=low Q06_Asset_Growth",
                n_months = nrow(FF), period_table = TAB, recent12 = rec,
                sanity_gates = list(hml_2024_neg = g1, smb_2024_neg = g2, smb_regime_flip = g3),
                runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")),
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, sprintf("ff5_kr_summary_%s.json", RUNTAG)), auto_unbox = TRUE, pretty = TRUE, digits = 5)
wf("=== ff5_kr_tracker done %.1f min ===", as.numeric(difftime(Sys.time(), t0, units = "mins")))
