## ★ 홀딩스 패널(alpha_scores_r05_panel) PIT 타이밍 검증 — 공격형 오버레이 착수 전 필수
## 확인: Date D의 Ret_1m이 실제로 어느 캘린더 월 수익인가 → regime 신호 clean 컷오프 확정
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
PG("=== 패널 개요 ===")
PG("컬럼: %s", paste(names(sp), collapse=" | "))
PG("Date 범위 %s ~ %s  월수=%d  종목/월평균=%.0f", as.character(min(sp$Date)), as.character(max(sp$Date)), uniqueN(sp$Date), nrow(sp)/uniqueN(sp$Date))
dts <- sort(unique(sp$Date))
PG("Date 예시(첫 6개): %s", paste(as.character(head(dts,6)), collapse=", "))
if("regime_state" %in% names(sp)) PG("regime_state 값: %s", paste(names(table(sp$regime_state)), table(sp$regime_state), collapse=" / "))

## EW 유니버스 수익 = mean(Ret_1m) per Date
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date][order(Date)]
ew[, ym := format(Date, "%Y-%m")]

## benchmark 월수익
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym:=format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]

## β-scan: Date의 ym + offset → 벤치월과 상관 (Ret_1m이 어느 월 수익인지)
PG("\n=== β-scan: Ret_1m이 어느 캘린더 월인가 (offset별 cor) ===")
for(off in -2:3){ e2<-copy(ew); e2[, key:=format(as.Date(paste0(ym,"-01")) %m+% months(off), "%Y-%m")]
  mm<-merge(e2, bmm[,.(key=ym, bm_ret)], by="key"); cc<-if(nrow(mm)>50) cor(mm$ew, mm$bm_ret) else NA
  PG("  offset %+d: cor=%.3f  (Date의 ym+%d월 벤치)", off, cc, off) }
PG("→ 최고 cor의 offset = Ret_1m의 캘린더 월. 그 월 '시작 전'이 신호 clean 컷오프.")

## 만약 offset=k면: Date D 행의 홀딩월 = month(D)+k. 신호 컷오프 = first-day(month(D)+k)
## 검증: score_eff(t) → Ret_1m(t) IC가 양수여야 (신호가 forward 수익 예측 = 올바른 PIT 방향)
ic <- sp[is.finite(score_eff)&is.finite(Ret_1m), .(ic=cor(score_eff, Ret_1m, method="spearman")), by=Date]
PG("\n=== score_eff → Ret_1m rank-IC (양수=신호가 forward 예측=PIT 방향 정상) ===")
PG("  평균 rank-IC=%.4f  (t≈%.2f, n=%d월)", mean(ic$ic,na.rm=T), mean(ic$ic,na.rm=T)/(sd(ic$ic,na.rm=T)/sqrt(nrow(ic))), nrow(ic))
PG("[DONE] holdings timing verify")
