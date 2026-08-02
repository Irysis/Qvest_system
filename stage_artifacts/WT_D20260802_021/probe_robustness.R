# probe_robustness.R — Self-Adversarial C1/C2 강건성: advocate 귀속 규칙 민감도
#   (1) argmax → 양의 z 비례 배분 귀속으로 교체 시 NEG share 유지되는가
#   (2) V06_EB를 POS로 재분류 시 NEG share
#   (3) d_net 부기간 (post-2017)
suppressPackageStartupMessages({ library(data.table); library(arrow)
  library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_021")
R21 <- readRDS(file.path(OUT, "wt021_results.rds"))
say <- function(fmt, ...) cat(sprintf(paste0("[probe] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# 재구성 최소 재현 (동일 규칙 — run_wt021_decompose.R §1~5와 동일 소스)
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
fwd <- build_monthly_forward_returns(RAWME, MEND[MEND >= min(SIG)])
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
liq_dt <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
TUNED_F <- c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB")
score_of <- function(fname) {
  sc <- if (fname %in% BASE$Factor_Name) BASE[Factor_Name == fname, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == fname, .(Date, Ticker, score = score)]
  merge(sc, UNIV, by = c("Date", "Ticker"))
}
zl <- rbindlist(lapply(TUNED_F, function(f) {
  s <- score_of(f); s[, z := as.numeric(scale(score)), by = Date]
  s[, .(Date, Ticker, Factor_Name = f, z)]
}))
cov <- zl[!is.na(z), .N, by = .(Date, Factor_Name)]
ZL_T <- merge(zl, cov, by = c("Date", "Factor_Name"))[N >= 100L][, N := NULL]
SC_EW <- ZL_T[!is.na(z), { if (.N >= 3L) .(score = mean(z)) else .(score = NA_real_) },
              by = .(Date, Ticker)][!is.na(score)]
SC_M01 <- score_of("M01_PATHQ")[!is.na(score)]
select_top <- function(sc, top_n = 25L) {
  S <- as.data.table(sc)[!is.na(score)]
  S <- merge(S, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)]) }, by = Date]
}
W_EW <- select_top(SC_EW); W_M01 <- select_top(SC_M01)
SETS <- merge(W_EW[, .(Date, Ticker, inC = TRUE)], W_M01[, .(Date, Ticker, inS = TRUE)],
              by = c("Date", "Ticker"), all = TRUE)
SETS[is.na(inC), inC := FALSE][is.na(inS), inS := FALSE]
SETS <- merge(SETS, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
SETS[is.na(Ret_1m), Ret_1m := 0]
ZW <- dcast(ZL_T[!is.na(z)], Date + Ticker ~ Factor_Name, value.var = "z")
SETS <- merge(SETS, ZW, by = c("Date", "Ticker"), all.x = TRUE)
OUTBAR <- SETS[!inC & inS, .(r_out_bar = mean(Ret_1m)), by = Date]
INS <- merge(SETS[inC & !inS], OUTBAR, by = "Date")
INS[, contrib := (Ret_1m - r_out_bar) / 25]
nm <- length(unique(SETS$Date))

# (1) 양의 z 비례 배분 귀속
zc <- intersect(TUNED_F, names(INS))
zm <- as.matrix(INS[, ..zc]); zm[!is.finite(zm)] <- 0; zm[zm < 0] <- 0
rs <- rowSums(zm); rs[rs == 0] <- NA
shares <- zm / rs
prop <- sapply(seq_along(zc), function(j)
  sum(INS$contrib * shares[, j], na.rm = TRUE) / nm * 12 * 100)
names(prop) <- zc
say("비례 귀속(%%/yr): %s", paste(names(prop), sprintf("%+.2f", prop), collapse = " "))
NEG_F <- c("D03_EWMA", "Q01_EB", "V06_EB")
tot <- sum(INS$contrib) / nm * 12 * 100
say("비례 NEG share: %.0f%% (argmax 75%%) | V06 POS 재분류 시(argmax): %.0f%% / (비례): %.0f%%",
    100 * sum(prop[NEG_F]) / tot,
    100 * (R21$m1$attr[advocate %in% c("D03_EWMA", "Q01_EB"), sum(contrib_ann_pct)]) / tot,
    100 * sum(prop[c("D03_EWMA", "Q01_EB")]) / tot)

# (3) d_net 부기간
G <- R21$d_series
say("d_net: full t=%+.2f | post2017 t=%+.2f (%+.2f%%/yr) | pre2017 t=%+.2f",
    nw_t(G$d_net), G[Date >= "2017-01-01", nw_t(d_net)],
    100 * G[Date >= "2017-01-01", mean(d_net)] * 12, G[Date < "2017-01-01", nw_t(d_net)])
saveRDS(list(prop_attr = prop, neg_share_prop = sum(prop[NEG_F]) / tot,
             neg_share_strict_argmax = R21$m1$attr[advocate %in% c("D03_EWMA","Q01_EB"), sum(contrib_ann_pct)] / tot,
             neg_share_strict_prop = sum(prop[c("D03_EWMA","Q01_EB")]) / tot,
             d_net_post2017_t = G[Date >= "2017-01-01", nw_t(d_net)]),
        file.path(OUT, "probe_robustness.rds"))
say("완료")
