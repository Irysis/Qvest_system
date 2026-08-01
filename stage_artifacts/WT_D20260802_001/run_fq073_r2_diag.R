# =============================================================================
# run_fq073_r2_diag.R — WT-D20260802_001 R2 / FQ-073
#   ① 유효 횡단면 해상도 (materiality 가 firm-level 분해능을 실제로 올렸나)
#   ② rank-IC 계열 (ADVISORY)
#   ③ 동적 PIT 검정 — lag1 스트레스 + strict-PIT A/B  (SOT §4 HARD, 정적 PASS 면제 없음)
#   ④ 부기간 안정성
#   ⑤ 반증 검정 재집행 — materiality 가중 신호로 '수출→컨센 실적기대' 링크 재측정
#   ⑥ materiality 자체의 시총 관계 (판별 해석의 근거)
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[r2diag] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector")))
RAW[, Date := as.Date(Date)]; RAW <- RAW[Date >= as.Date("2014-11-01")]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[, .(Date, Ticker, Size)]

msr <- function(sc, top_n = 25L, bps = 15) {
  sc <- as.data.table(sc)[is.finite(score)]
  if (!nrow(sc)) return(NULL)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = top_n, cost_bps_oneway = bps,
                      liq_dt = liq_dt, liq_min = 2e8, diag_dual_basis = TRUE, size_dt = size_dt)
}

PAN <- function(fid) as.data.table(read_parquet(file.path(OUT, sprintf("alpha_scores_%s.parquet", fid))))
G1 <- PAN("R2_G1_mat_surprise"); G5 <- PAN("R2_G5_mat_sue_sm6"); G4 <- PAN("R2_G4_mat_sue_sm3")
B0 <- PAN("F1_export_surprise")
D <- list()

# ── ① 유효 횡단면 해상도 ──────────────────────────────────────────────────
res_ratio <- function(p, tag) {
  tie <- p[!is.na(value), .(n = .N, d = uniqueN(round(value, 10))), by = Date]
  r <- list(metric_type = "diagnostic", n_firms_scored_avg = round(tie[, mean(n)], 1),
            n_distinct_scores_avg = round(tie[, mean(d)], 1),
            distinct_ratio = round(tie[, mean(d/n)], 4))
  say("유효 횡단면 %-24s: %5.1f종목 중 distinct %5.1f (비율 %.4f)", tag,
      r$n_firms_scored_avg, r$n_distinct_scores_avg, r$distinct_ratio); r
}
D$effective_cross_section <- list(
  B0_R1_F1 = res_ratio(B0, "B0 (R1 F1)"),
  R2_G1_mat_surprise = res_ratio(G1, "R2 G1 materiality"),
  R2_G5_mat_sue_sm6 = res_ratio(G5, "R2 G5 mat x SUE sm6"),
  note = "distinct_ratio 1.0 = 모든 종목이 서로 다른 값(진짜 firm-level). R1 은 0.644 로 동일 HS4 버킷 동점이 36%.")

# ── ② rank-IC (ADVISORY) ─────────────────────────────────────────────────
ic_of <- function(p, tag) {
  m <- merge(p[!is.na(value)], returns_dt, by = c("Date","Ticker"))
  ic <- m[, if (.N >= 10L && sd(value) > 0 && sd(Ret_1m) > 0)
              .(ic = cor(value, Ret_1m, method = "spearman")) else .(ic = NA_real_), by = Date]
  ic <- ic[is.finite(ic)]
  mu <- ic[, mean(ic)]; sd_ <- ic[, sd(ic)]
  r <- list(metric_type = "advisory", rank_ic = round(mu, 5), icir = round(mu/sd_, 4),
            ic_t_stat = round(mu/(sd_/sqrt(nrow(ic))), 3), n_months = nrow(ic))
  say("rank-IC %-24s: IC=%+.5f ICIR=%+.4f t=%+.3f n=%d", tag, mu, mu/sd_,
      mu/(sd_/sqrt(nrow(ic))), nrow(ic)); r
}
D$rank_ic <- list(B0_R1_F1 = ic_of(B0, "B0"), R2_G1 = ic_of(G1, "R2 G1"),
                  R2_G4 = ic_of(G4, "R2 G4"), R2_G5 = ic_of(G5, "R2 G5"))

# ── ③ 동적 PIT — lag1 스트레스 + strict-PIT A/B ───────────────────────────
#   신호를 한 달 더 늦춰 적용한다. base 가 lag1 대비 크게 높으면 동월 누출 의심.
dyn <- function(p, tag) {
  base <- msr(p[!is.na(value), .(Date, Ticker, score = value)])
  q <- copy(p)[!is.na(value)]; setorder(q, Ticker, Date)
  q[, score := shift(value, 1L, type = "lag"), by = Ticker]
  lag1 <- msr(q[, .(Date, Ticker, score)])
  infl <- base$portfolio_alpha_t_nw_lag3 - lag1$portfolio_alpha_t_nw_lag3
  say("동적 PIT %-20s: base=%+.4f  lag1(strict)=%+.4f  인플레=%+.4f  →  %s", tag,
      base$portfolio_alpha_t_nw_lag3, lag1$portfolio_alpha_t_nw_lag3, infl,
      if (infl > 0.5) "INFLATION_SUSPECTED" else "NO_INFLATION")
  list(metric_type = "canonical_screen",
       base_port_t = round(base$portfolio_alpha_t_nw_lag3, 4),
       lag1_strict_port_t = round(lag1$portfolio_alpha_t_nw_lag3, 4),
       inflation_base_minus_strict = round(infl, 4),
       n_months_base = base$n_months, n_months_lag1 = lag1$n_months,
       verdict = if (infl > 0.5) "INFLATION_SUSPECTED" else "NO_INFLATION")
}
D$dynamic_pit <- list(R2_G1 = dyn(G1, "G1 materiality"),
                      R2_G4 = dyn(G4, "G4 mat x SUE sm3"),
                      R2_G5 = dyn(G5, "G5 mat x SUE sm6"),
                      note = "lag1 = 신호를 추가 1개월 지연(strict lane). 본 라운드 후보는 부호가 0 근방이라 누출 인플레 여지는 애초 작다 — 확인 목적.")

# ── ④ 부기간 (advisory) ──────────────────────────────────────────────────
subp <- function(p, tag) {
  o <- list()
  for (w in list(c("2016-01-01","2019-12-31"), c("2020-01-01","2022-12-31"),
                 c("2023-01-01","2026-12-31"))) {
    s <- p[!is.na(value) & Date >= as.Date(w[1]) & Date <= as.Date(w[2]),
           .(Date, Ticker, score = value)]
    rr <- tryCatch(msr(s), error = function(e) NULL)
    o[[paste(w, collapse = "_")]] <- if (is.null(rr)) NA_real_ else round(rr$portfolio_alpha_t_nw_lag3, 3)
  }
  say("부기간 %-20s: %s", tag, paste(names(o), unlist(o), sep = "=", collapse = " | ")); o
}
D$subperiod_port_t <- list(R2_G1 = subp(G1, "G1"), R2_G5 = subp(G5, "G5"))

# ── ⑤ 반증 재집행 — materiality 가중 신호로 '수출→컨센' 링크 ────────────
CP <- ".cache/consensus/op_profit_fy1.parquet"
fals <- NULL
if (file.exists(CP)) {
  CO <- as.data.table(read_parquet(CP))
  setnames(CO, names(CO), sub("^security_id$", "Ticker", names(CO)))
  vcol <- setdiff(names(CO), c("Date","Ticker"))[1]
  CO[, Date := as.Date(Date)]; setnames(CO, vcol, "op_fy1")
  CO <- CO[is.finite(op_fy1) & op_fy1 != 0]; setkey(CO, Ticker, Date)
  asof_val <- function(dates, tickers) {
    q <- data.table(Ticker = tickers, Date = dates); setkey(q, Ticker, Date)
    CO[q, roll = TRUE, on = .(Ticker, Date)]$op_fy1
  }
  run_f <- function(p, H) {
    X <- copy(p)[!is.na(value)]
    X[, v0 := asof_val(Date, Ticker)]; X[, v1 := asof_val(Date + H, Ticker)]
    X <- X[is.finite(v0) & is.finite(v1) & v0 > 0 & v1 > 0]
    X[, rev_log := log(v1/v0)]; X <- X[abs(rev_log) < log(10)]
    X[, q := cut(frank(value, ties.method = "average")/.N, breaks = seq(0,1,0.2),
                 labels = 1:5, include.lowest = TRUE), by = Date]
    bym <- X[!is.na(q), .(rev = mean(rev_log)), by = .(Date, q)]
    sp <- dcast(bym, Date ~ q, value.var = "rev"); setnames(sp, c("Date", paste0("Q",1:5)))
    sp <- sp[is.finite(Q1) & is.finite(Q5)]; sp[, d := Q5 - Q1]
    mu <- sp[, mean(d)]; tt <- mu/(sp[, sd(d)/sqrt(.N)])
    list(horizon_days = H, q5_minus_q1_logrev = round(mu,5), t_stat = round(tt,3),
         n_months = nrow(sp), q5_mean = round(sp[, mean(Q5)],5), q1_mean = round(sp[, mean(Q1)],5),
         n_obs = nrow(X), metric_type = "diagnostic_falsification")
  }
  fals <- list()
  for (nm in c("B0_R1_F1","R2_G1_mat_surprise","R2_G5_mat_sue_sm6")) {
    p <- switch(nm, B0_R1_F1 = B0, R2_G1_mat_surprise = G1, R2_G5_mat_sue_sm6 = G5)
    fals[[nm]] <- list(H63d = run_f(p, 63L), H126d = run_f(p, 126L))
    say("반증 %-22s: H63d Q5-Q1=%+.5f t=%+.3f | H126d %+.5f t=%+.3f", nm,
        fals[[nm]]$H63d$q5_minus_q1_logrev, fals[[nm]]$H63d$t_stat,
        fals[[nm]]$H126d$q5_minus_q1_logrev, fals[[nm]]$H126d$t_stat)
  }
  t1 <- fals$R2_G1_mat_surprise$H63d$t_stat
  fals$verdict <- if (is.finite(t1) && t1 >= 2 && fals$R2_G1_mat_surprise$H63d$q5_minus_q1_logrev > 0)
    "MECHANISM_SUPPORTED — materiality 가중 상위군의 후속 컨센 상향이 유의. 링크1(수출→실적기대) 성립, 단절은 링크2(→가격)."
  else "MECHANISM_NOT_SUPPORTED — 사전등록 문턱(t>=2) 미달. materiality 가중으로도 링크1이 유의 수준에 이르지 못한다."
  say("반증 판정: %s", fals$verdict)
}
D$falsification <- fals

# ── ⑥ materiality 자체 진단 — 왜 tier 가 안 움직였나의 근거 ──────────────
MP <- as.data.table(read_parquet(file.path(OUT, "fq073_export_materiality.parquet")))
MP[, Date := as.Date(Date)]; MP[, avail := as.Date(avail_ts)]
SZ <- copy(size_dt)[!is.na(Size)]; setorder(SZ, Date, -Size)
SZ[, cap_rank := seq_len(.N), by = Date]
SZ[, tier := fifelse(cap_rank <= 10L,"MEGA", fifelse(cap_rank <= 30L,"MID","OTHER"))]
U2 <- RAWME[(K200==TRUE|KQ150==TRUE), .(Ticker, edt = Date)]
U2 <- merge(U2, SZ[, .(Ticker, edt = Date, cap_rank, tier)], by = c("Ticker","edt"))
setkey(MP, Ticker, avail); setkey(U2, Ticker, edt)
J <- MP[U2, on = .(Ticker, avail <= edt), mult = "last", nomatch = 0L,
        .(edt = i.edt, Ticker, M = x.value, Mcred = x.value_cred,
          cap_rank = i.cap_rank, tier = i.tier)]
J[, Mclip := pmin(pmax(M, 0), 1)]
cor_of <- function(v) round(J[, .(c = cor(get(v), -cap_rank, method = "spearman")), by = edt][, mean(c)], 4)
D$materiality_profile <- list(
  metric_type = "diagnostic", n_rows = nrow(J), n_months = uniqueN(J$edt),
  spearman_vs_neg_cap_rank = list(M_raw = cor_of("M"), M_clip = cor_of("Mclip"), M_cred = cor_of("Mcred")),
  by_tier = as.list(setNames(
    lapply(split(J, J$tier), function(g) list(
      n = nrow(g), M_raw_mean = round(mean(g$M),3), M_clip_mean = round(mean(g$Mclip),3),
      M_cred_mean = round(mean(g$Mcred),3), share_M_gt_1 = round(mean(g$M > 1),3))),
    names(split(J, J$tier)))),
  interpretation = paste0(
    "M_raw 는 소형주에서 오히려 크다(단일 소형사가 거대 HS4 버킷에 매핑되면 분모가 작아 폭발) ",
    "= 귀속 실패의 지문. CLIP(0,1) 로 경제적 상한을 걸어도 시총과의 관계는 여전히 약한 음(-)이며, ",
    "credibility 보정(min(R,1/R))에서만 시총 중립이 된다. 어느 정규화도 신호를 대형 tier 로 ",
    "이동시키지 않는다 — 대형주 편입은 정규화가 만들 수 있는 것이 아니었다."))
say("materiality Spearman(M, -cap_rank): raw=%s clip=%s cred=%s",
    D$materiality_profile$spearman_vs_neg_cap_rank$M_raw,
    D$materiality_profile$spearman_vs_neg_cap_rank$M_clip,
    D$materiality_profile$spearman_vs_neg_cap_rank$M_cred)

write_json(D, file.path(OUT, "fq073_r2_diagnostics.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", digits = 6)
say("→ fq073_r2_diagnostics.json")
