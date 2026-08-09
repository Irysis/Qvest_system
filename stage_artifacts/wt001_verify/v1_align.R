# v1_align.R — WT-D20260808_001 PIT 검증 1: 입력 형태 실측 + forward return 정렬 + 양성대조
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/wt001_verify")
W1  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[v1] ", fmt, "\n"), ...))

TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date := as.Date(Date)]
say("TUNED nrow=%d n_date=%d %s~%s  factors=%s", nrow(TUNED), uniqueN(TUNED$Date),
    min(TUNED$Date), max(TUNED$Date), paste(sort(unique(TUNED$Factor_Name)), collapse=","))
say("BASE  nrow=%d n_date=%d %s~%s  factors=%s", nrow(BASE), uniqueN(BASE$Date),
    min(BASE$Date), max(BASE$Date), paste(sort(unique(BASE$Factor_Name)), collapse=","))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Ret","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
say("RAWDATA nrow=%d 관측단위=DAILY n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]
say("월말 거래일 %d개", length(MEND))

fwd <- readRDS(file.path(W1,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bch <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date), BM_Ret)]
say("fwd returns nrow=%d n_date=%d %s~%s | bench n=%d", nrow(ret), uniqueN(ret$Date),
    min(ret$Date), max(ret$Date), nrow(bch))

# ── T2: forward 정렬 직접 검증 ────────────────────────────────────────────────
say("=== T2 forward return 정렬 직접 검증 ===")
dts <- sort(unique(ret$Date))
CL <- RAWME[, .(Date, Ticker, Close)]
nxt <- data.table(Date=dts, Date_next=c(dts[-1], NA))
# tuned 패널 날짜가 정확히 월말 거래일인가
say("tuned Date ⊂ 월말거래일: %s (불일치 %d개)",
    all(unique(TUNED$Date) %in% MEND), sum(!unique(TUNED$Date) %in% MEND))
chk <- merge(ret, nxt, by="Date")
chk <- merge(chk, CL, by=c("Date","Ticker"))
setnames(chk,"Close","C0")
chk <- merge(chk, CL[, .(Date_next=Date, Ticker, C1=Close)], by=c("Date_next","Ticker"))
chk[, fwd_calc := C1/C0 - 1]
say("FORWARD 대조 n=%d  max|Ret_1m - C1/C0+1| = %.3e  cor=%.6f",
    nrow(chk), max(abs(chk$Ret_1m - chk$fwd_calc)), cor(chk$Ret_1m, chk$fwd_calc))
# 반증 시도: 만약 trailing 이라면?
prv <- data.table(Date=dts, Date_prev=c(NA, dts[-length(dts)]))
ch2 <- merge(ret, prv, by="Date")
ch2 <- merge(ch2, CL, by=c("Date","Ticker")); setnames(ch2,"Close","C0")
ch2 <- merge(ch2, CL[, .(Date_prev=Date, Ticker, Cm1=Close)], by=c("Date_prev","Ticker"))
ch2[, trail_calc := C0/Cm1 - 1]
say("TRAILING 대조 n=%d  cor(Ret_1m, trailing) = %+.6f  (0 근방이어야 정상)",
    nrow(ch2), cor(ch2$Ret_1m, ch2$trail_calc))

# ── 유니버스 멤버십 시변성 (C6 survivorship 사전확인) ─────────────────────────
say("=== C6 유니버스 멤버십 시변성 ===")
mem <- RAWME[, .(n_k200=sum(K200==TRUE, na.rm=TRUE), n_kq=sum(KQ150==TRUE, na.rm=TRUE),
                 n_all=.N), by=Date][order(Date)]
say("K200 종목수: 첫 %d / 중간 %d / 마지막 %d  (고정이면 survivorship 의심)",
    mem$n_k200[1], mem$n_k200[round(nrow(mem)/2)], mem$n_k200[nrow(mem)])
tk <- RAWME[K200==TRUE | KQ150==TRUE, .(n_month=uniqueN(Date)), by=Ticker]
say("유니버스 등장 종목 총 %d / 전기간(%d월) 상주 %d / 중앙 재임월수 %.0f",
    nrow(tk), length(MEND), sum(tk$n_month==length(MEND)), median(tk$n_month))

# ── T3 양성대조: 누출 신호를 계측이 잡는가 ────────────────────────────────────
say("=== T3 양성대조 (누출 주입) ===")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  f<-lm(x~1); as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f, lag=lag, prewhite=FALSE))[1,3]) }
ic_bat <- function(D){
  ic <- D[, if(.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  mono <- D[, { if(.N>=20L && sd(score)>0){ q <- cut(frank(score), breaks=5, labels=FALSE)
      as.list(setNames(sapply(1:5, function(k) mean(Ret_1m[q==k], na.rm=TRUE)), paste0("m",1:5)))
    } else as.list(setNames(rep(NA_real_,5), paste0("m",1:5))) }, by=Date]
  qm <- sapply(paste0("m",1:5), function(k) mean(mono[[k]], na.rm=TRUE))
  list(n=nrow(ic), rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), harvey_t=nw_t(ic$ic),
       mono=mean(diff(qm)>0), q_ann=100*12*qm)
}
LEAK <- copy(ret)[, score := Ret_1m]
b <- ic_bat(LEAK)
say("  누출신호(score=Ret_1m): rank_IC %+.4f  Harvey-t %+.2f  mono %.2f  Q1..Q5 %s",
    b$rank_ic, b$harvey_t, b$mono, paste(sprintf("%+.1f", b$q_ann), collapse=" "))
say("  → 계측 살아있음 확인 (IC≈1, mono=1.00 이어야 함)")

saveRDS(list(mend=MEND, ret=ret, bch=bch, mem=mem), file.path(OUT,"v1.rds"))
say("=== v1 완료 ===")
