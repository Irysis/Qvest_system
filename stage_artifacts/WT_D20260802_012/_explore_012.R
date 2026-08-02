## _explore_012.R — WT-D20260802_012 착수 전 재료 정합 확인 (측정 아님, 구조 점검만)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
wf <- function(...) cat(sprintf(...), "\n")

o36 <- readRDS("stage_artifacts/WT_D20260715_005/_r36_objects.rds")
uni <- as.data.table(o36$uni)
wf("[uni] rows=%d cols=%s", nrow(uni), paste(names(uni), collapse=","))
wf("[uni] hold_ym range=%d~%d months=%d tickers=%d", min(uni$hold_ym), max(uni$hold_ym),
   uniqueN(uni$hold_ym), uniqueN(uni$Ticker))
wf("[uni] INS02 non-NA=%d (%.1f%%) | Ret_1m non-NA=%d | exc non-NA=%d",
   sum(!is.na(uni$INS02_OffBuyBreadth6m)), 100*mean(!is.na(uni$INS02_OffBuyBreadth6m)),
   sum(is.finite(uni$Ret_1m)), sum(is.finite(uni$exc)))
wf("[uni] INS02 z summary: %s", paste(sprintf("%.3f", quantile(uni$INS02_OffBuyBreadth6m, c(0,.25,.5,.75,.9,.95,1), na.rm=TRUE)), collapse=" "))
wf("[uni] sz_tercile: %s", paste(sprintf("%s=%d", names(table(uni$sz_tercile)), table(uni$sz_tercile)), collapse=" "))

PAN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_007/insider_axes_panel.parquet"))
wf("[pan] rows=%d cols=%s", nrow(PAN), paste(names(PAN), collapse=","))
wf("[pan] sig_ym range=%s~%s | MAGQ3 finite=%d | BREADTH6 finite=%d",
   min(PAN$sig_ym), max(PAN$sig_ym), sum(is.finite(PAN$INS_MAGQ3)), sum(is.finite(PAN$INS02_BREADTH6)))

## sig_ym -> hold_ym = sig+1 (R36 ins 규약과 동일: ins hold_ym = ym(signal_date)+1)
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
PAN[, hold_ym := ymshift(as.integer(sig_ym), 1L)]
ov <- merge(uni[, .(hold_ym, Ticker, ins02=INS02_OffBuyBreadth6m, Ret_1m)],
            PAN[, .(hold_ym, Ticker, mag=INS_MAGQ3, br6=INS02_BREADTH6)],
            by=c("hold_ym","Ticker"), all.x=TRUE)
wf("[join] uni rows=%d | mag 부착=%d (%.1f%%) | br6 부착=%d", nrow(ov), sum(is.finite(ov$mag)),
   100*mean(is.finite(ov$mag)), sum(is.finite(ov$br6)))
wf("[join] INS02(ramp z) non-NA=%d ∧ br6(panel raw) non-NA=%d 교집합=%d",
   sum(!is.na(ov$ins02)), sum(is.finite(ov$br6)), sum(!is.na(ov$ins02) & is.finite(ov$br6)))
## 두 소스 breadth 값 정합 (ramp z vs panel raw — rank 상관이어야 함)
cc <- ov[!is.na(ins02) & is.finite(br6), .(r=suppressWarnings(cor(ins02, br6, method="spearman")), n=.N), by=hold_ym][n>=10]
wf("[parity] ramp INS02 z vs panel INS02_BREADTH6 raw 월별 Spearman: mean=%.4f min=%.4f n_mo=%d",
   mean(cc$r, na.rm=TRUE), min(cc$r, na.rm=TRUE), nrow(cc))

## MAGQ3 커버리지: uni 월별 이름수
mm <- ov[, .(n_uni=.N, n_ins02=sum(!is.na(ins02)), n_mag=sum(is.finite(mag))), by=hold_ym][order(hold_ym)]
wf("[cov] 월별 중앙값: uni=%d ins02=%d mag=%d | mag 결측월=%d",
   as.integer(median(mm$n_uni)), as.integer(median(mm$n_ins02)), as.integer(median(mm$n_mag)),
   sum(mm$n_mag==0))
print(head(mm, 4)); print(tail(mm, 4))

RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"
wf("[pin] %s exists=%s", RAW_P, file.exists(RAW_P))
wf("[pin] mtime=%s", as.character(file.info(RAW_P)$mtime))
