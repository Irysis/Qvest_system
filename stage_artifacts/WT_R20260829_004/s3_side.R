# S3 — F3(DM2016 옵션성의 승자 레그 이식) · F4(agent 실재: 투자자 주체별 순매수 국면대비)
# 둘 다 성과와 독립인 부수 관측이며 진단 전용(거래 규칙 유입 금지 — DM 의 I~_U 는 동시대 변수).
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(arrow)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
P <- readRDS(file.path(OUT, "panel.rds")); O2 <- readRDS(file.path(OUT, "s2_objects.rds"))
fwd <- P$fwd; H0 <- O2$H0; SIG <- O2$SIG; hmap <- O2$hmap
R <- as.data.table(fwd$returns_dt)[!is.na(Ret_1m)]; BENCH <- as.data.table(fwd$bench_dt)

## -- A0 월간 순수익 (top-25 EW · 15bps delta) — F3 회귀의 좌변 --
W <- H0[, .(Ticker, w = 1/.N), by = Date]
WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
WR[is.na(Ret_1m), Ret_1m := 0]
port <- WR[, .(gross = sum(w*Ret_1m)), by = Date][order(Date)]
dts <- port$Date; traded <- numeric(length(dts)); prev <- data.table(Ticker=character(0), w=numeric(0))
for (i in seq_along(dts)) {
  cur <- W[Date == dts[i], .(Ticker, w)]
  m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_cur","_prev"))
  m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
  traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
}
port[, traded := traded][, ret_net := gross - traded*15/1e4]
PR <- merge(port[, .(Date, ret_net)], BENCH[, .(Date, BM_Ret)], by="Date")
PR[, signal_ym := format(Date, "%Y-%m")]
PR <- merge(PR, SIG[, .(signal_ym, I_B, vol_hi, panic, holding_ym)], by="signal_ym", all.x=TRUE)
setorder(PR, Date)
cat(sprintf("[S3] A0 months=%d · panic months=%d · I_B months=%d\n",
            nrow(PR), sum(PR$panic, na.rm=TRUE), sum(PR$I_B, na.rm=TRUE)))

## -- F3: DM2016 eq(3) — r = (a0 + aB*I_B) + (b0 + bB*I_B + bBU*I_B*I~_U)*Rm + e --
D <- PR[is.finite(ret_net) & is.finite(BM_Ret) & is.finite(I_B)]
D[, IU := as.integer(BM_Ret > 0)]           # 동시대 up-market dummy — 진단 전용
D[, `:=`(x1 = BM_Ret, x2 = I_B*BM_Ret, x3 = I_B*IU*BM_Ret)]
fit3 <- lm(ret_net ~ I_B + x1 + x2 + x3, data = D)
ct3 <- coeftest(fit3, vcov = NeweyWest(fit3, lag = 3, prewhite = FALSE))
getc <- function(nm) c(est = unname(ct3[nm,1]), t = unname(ct3[nm,3]))
f3 <- list(
  n = nrow(D), n_IB = sum(D$I_B), n_IB_up = sum(D$I_B == 1L & D$IU == 1L),
  alpha0_monthly = getc("(Intercept)")[["est"]], alpha0_t = getc("(Intercept)")[["t"]],
  alpha_B_monthly = getc("I_B")[["est"]], alpha_B_t = getc("I_B")[["t"]],
  beta0 = getc("x1")[["est"]], beta0_t = getc("x1")[["t"]],
  beta_B = getc("x2")[["est"]], beta_B_t = getc("x2")[["t"]],
  beta_BU = getc("x3")[["est"]], beta_BU_t = getc("x3")[["t"]],
  us_anchor_dm2016 = list(winner_decile_up_increment = -0.215, loser_decile_up_increment = 0.600,
                          wml_beta_BU = -0.815, note="DM2016 Table 4 Panel A — 롱숏 WML/데실. 우리는 승자만 보유"),
  verdict_rule = "beta_BU >= 0 이면 '반등월 beta 부족' 경로는 KR 롱온리에 이식되지 않음(path 의 beta 성분 기각)",
  verdict = NA_character_)
f3$verdict <- if (!is.finite(f3$beta_BU)) "UNDETERMINED" else if (f3$beta_BU >= 0) "REJECT_BETA_PATH" else "BETA_PATH_PRESENT"

## -- F4: 투자자 주체별 순매수 국면 대비 (A0 보유종목, 홀딩월 집계 / ADV20 정규화) --
INV <- tryCatch(as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet")),
                error = function(e) NULL)
f4 <- list(available = !is.null(INV))
if (!is.null(INV)) {
  INV[, Date := as.Date(Date)]
  hold <- merge(hmap[, .(sig, hs, he, holding_ym)], H0, by.x = "sig", by.y = "Date",
                allow.cartesian = TRUE)
  adv <- fwd$liq_dt[, .(sig = Date, Ticker, adv)]
  hold <- merge(hold, adv, by = c("sig","Ticker"), all.x = TRUE)
  setkey(INV, Ticker, Date)
  agg <- rbindlist(lapply(seq_len(nrow(hmap)), function(i) {
    hh <- hold[sig == hmap$sig[i]]
    x <- INV[Ticker %chin% hh$Ticker & Date > hmap$hs[i] & Date <= hmap$he[i]]
    if (!nrow(x)) return(NULL)
    s <- x[, .(ind = sum(Individual, na.rm=TRUE), frn = sum(Foreign, na.rm=TRUE),
               ins = sum(Institutional, na.rm=TRUE)), by = Ticker]
    s <- merge(s, hh[, .(Ticker, adv)], by = "Ticker")
    s <- s[is.finite(adv) & adv > 0]
    if (!nrow(s)) return(NULL)
    data.table(sig = hmap$sig[i], holding_ym = hmap$holding_ym[i],
               ind_adv = mean(s$ind/s$adv), frn_adv = mean(s$frn/s$adv),
               ins_adv = mean(s$ins/s$adv), n_names = nrow(s))
  }))
  agg[, signal_ym := format(sig, "%Y-%m")]
  agg <- merge(agg, SIG[, .(signal_ym, panic, I_B)], by = "signal_ym", all.x = TRUE)
  agg <- agg[is.finite(panic)]
  nw_t2 <- function(y, g) {
    d <- data.table(y=y, g=g)[is.finite(y) & is.finite(g)]
    if (length(unique(d$g)) < 2 || nrow(d) < 20) return(c(diff=NA_real_, t=NA_real_))
    m <- lm(y ~ g, data=d); ct <- coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))
    c(diff = unname(ct[2,1]), t = unname(ct[2,3]))
  }
  ti <- nw_t2(agg$ind_adv, agg$panic); tf <- nw_t2(agg$frn_adv, agg$panic); tn <- nw_t2(agg$ins_adv, agg$panic)
  f4 <- list(
    available = TRUE, n_months = nrow(agg), n_panic = sum(agg$panic),
    unit = "홀딩월 종목별 순매수대금 / 신호일 20일평균거래대금(ADV20 t-1) 의 보유종목 평균 (= ADV 일수)",
    individual = list(mean_nonpanic = mean(agg[panic==0]$ind_adv), mean_panic = mean(agg[panic==1]$ind_adv),
                      diff = unname(ti["diff"]), nw_t = unname(ti["t"])),
    foreign    = list(mean_nonpanic = mean(agg[panic==0]$frn_adv), mean_panic = mean(agg[panic==1]$frn_adv),
                      diff = unname(tf["diff"]), nw_t = unname(tf["t"])),
    institutional = list(mean_nonpanic = mean(agg[panic==0]$ins_adv), mean_panic = mean(agg[panic==1]$ins_adv),
                      diff = unname(tn["diff"]), nw_t = unname(tn["t"])),
    verdict_rule = "패닉월 주체별 순매수 대비가 비패닉월과 부호·크기 모두에서 구별되지 않으면 agent 기전 기각(확증은 불가 — 배제만 가능)",
    diagnostic_only = TRUE)
  f4$verdict <- if (any(abs(c(ti["t"], tf["t"], tn["t"])) >= 2, na.rm=TRUE)) "DISTINGUISHABLE" else "INDISTINGUISHABLE"
  saveRDS(agg, file.path(OUT, "s3_investor_agg.rds"))
}

res <- list(meta = list(wt_id="WT-R20260829_004", metric_type="canonical_screen",
                        note="F3/F4 는 부수 관측 진단 — 신호·선별·비중에 진입 금지"),
            F3_dm_optionality_winner_leg = f3, F4_agent_reality = f4)
write_json(res, file.path(OUT, "s3_side.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
saveRDS(list(PR=PR, port=port, W=W, WR=WR), file.path(OUT, "s3_objects.rds"))

cat("\n===== F3 (DM eq3, A0 승자 롱온리 슬리브) =====\n")
cat(sprintf("beta0=%+.3f(t %+.2f) beta_B=%+.3f(t %+.2f) beta_BU=%+.3f(t %+.2f) | n=%d n_IB=%d n_IB_up=%d\n",
            f3$beta0, f3$beta0_t, f3$beta_B, f3$beta_B_t, f3$beta_BU, f3$beta_BU_t, f3$n, f3$n_IB, f3$n_IB_up))
cat(sprintf("US 앵커 승자 데실 up 증분 = -0.215 | verdict = %s\n", f3$verdict))
cat("===== F4 (투자자 주체 국면대비) =====\n")
if (isTRUE(f4$available)) {
  for (nm in c("individual","foreign","institutional"))
    cat(sprintf("  %-14s nonpanic=%+.4f panic=%+.4f diff=%+.4f NW-t=%+.3f\n", nm,
                f4[[nm]]$mean_nonpanic, f4[[nm]]$mean_panic, f4[[nm]]$diff, f4[[nm]]$nw_t))
  cat(sprintf("  verdict=%s (n=%d, panic=%d)\n", f4$verdict, f4$n_months, f4$n_panic))
} else cat("  investor_wide.parquet 미가용\n")
