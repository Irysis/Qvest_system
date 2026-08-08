# p25_fq130_precheck.R — FQ-130 착수 전 사전 확인
# 제안: cap-tier 분해에서 나온 **MEGA t +2.76** 이 축약 스펙(n=10/월·vol 통제 불가)의 산물인지,
#   pooled panel + 월 고정효과 + vol 통제 **full-spec** 에서 살아남는지.
#   살아남으면 "cap-tier 벽의 예외" 1건이라 값이 크다(mega 는 신호-dead 가 반복 실측).
# 신호 = MAX5 (Bali et al. 계열): 과거 1개월 내 **상위 5개 일간수익의 평균** — 복권형 수요 대리.
# 사전 확인 3축: ①MEGA tier n 이 실제로 몇인가(검정력) ②vol 통제 전/후 계수 ③월 FE 하 t
# ★PIT: 신호는 decision 이전 월, 수익은 익월.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret","Size","Close","Vol")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, `:=`(ymd = as.Date(paste0(format(Date,"%Y-%m"),"-01")), TV = Close*Vol)]
MO <- raw[, .(ret_m = prod(1+Ret)-1, vol_m = sd(Ret, na.rm=TRUE),
              max5 = mean(head(sort(Ret, decreasing=TRUE), 5)),
              size = last(Size[is.finite(Size)]), adv = mean(TV, na.rm=TRUE), nd = .N),
          by=.(Ticker, ymd)][nd >= 15 & is.finite(ret_m) & is.finite(max5)]
setorder(MO, Ticker, ymd)
MO[, fwd := shift(ret_m, -1), by=Ticker]
E <- MO[is.finite(fwd) & is.finite(adv) & adv >= 2e8 & is.finite(size)]
E[, cap := cut(frank(-size)/.N, c(0,0.1,0.5,1), labels=c("MEGA","MID","SMALL")), by=ymd]
E <- E[!is.na(cap)]
cat(sprintf("[패널] %s행 · %d개월 | tier별 월평균 n: %s\n", format(nrow(E), big.mark=","), uniqueN(E$ymd),
  paste(E[, .N, by=.(cap, ymd)][, .(n=round(mean(N))), by=cap][order(cap)][, sprintf("%s %d", cap, n)], collapse=" · ")))

zs <- function(x) { s <- sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) return(rep(0, length(x))); (x - mean(x, na.rm=TRUE))/s }
E[, `:=`(z_max5 = zs(max5), z_vol = zs(vol_m), z_size = zs(log(pmax(size,1)))), by=.(ymd, cap)]

fmb <- function(sub, ctrl) {
  f <- if (ctrl) fwd ~ z_max5 + z_vol + z_size else fwd ~ z_max5
  co <- sub[, { m <- tryCatch(lm(f, data=.SD), error=function(e) NULL)
                if (is.null(m) || !("z_max5" %in% rownames(coef(summary(m))))) NA_real_
                else coef(summary(m))["z_max5","Estimate"] }, by=ymd]$V1
  co <- co[is.finite(co)]
  if (length(co) < 24) return(c(NA, NA, length(co)))
  c(mean(co), mean(co)/(sd(co)/sqrt(length(co))), length(co))
}
res <- rbindlist(lapply(c("MEGA","MID","SMALL"), function(tt) {
  s <- E[cap == tt]
  a <- fmb(s, FALSE); b <- fmb(s, TRUE)
  data.table(tier=tt, 월평균n=round(nrow(s)/uniqueN(s$ymd)),
             단순_계수=round(a[1],5), 단순_t=round(a[2],2),
             통제_계수=round(b[1],5), 통제_t=round(b[2],2), 개월=b[3])
}))
cat("\n===== FMB (월별 횡단면 회귀 → 계수 시계열 t) =====\n"); print(res)
mg <- res[tier=="MEGA"]
cat(sprintf("\n[MEGA 검정력] 월평균 %d종목 — 큐가 지적한 n=10/월 우려 %s\n", mg$월평균n,
            ifelse(mg$월평균n <= 15, "재확인(저검정력)", "해소(충분)")))
cat(sprintf("[vol 통제 효과] MEGA 단순 t=%.2f → 통제 t=%.2f (%s)\n", mg$단순_t, mg$통제_t,
            ifelse(abs(mg$통제_t) < abs(mg$단순_t)*0.6, "★통제 후 크게 약화 = 축약 스펙 산물 의심", "통제 후에도 유지")))
cat(sprintf("\n[사전 확인 판정] MEGA 통제 t=%.2f → %s\n", mg$통제_t,
  ifelse(abs(mg$통제_t) >= 2, "★cap-tier 벽의 예외 후보 — 라운드 착수 가치 있음",
         "전제 약함 — 축약 스펙 t +2.76 은 통제/검정력 산물일 가능성, 착수 EV 낮음")))
fwrite(res, "stage_artifacts/tilt_realign_20260808/p25_fq130_precheck.csv")
