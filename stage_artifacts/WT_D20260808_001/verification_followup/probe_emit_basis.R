# probe_emit_basis.R — ④ 수리 전 basis 확정: 유동성 정의가 둘이다(liq_dt vs rawdata 재계산).
#   어느 자로 걸러야 고지문의 검증 절차(rawdata frollmean)에서 미달 0 이 나오는가를 **먼저 잰다**.
#   ★basis 를 못 박지 않으면 생성기와 검사기가 다른 자를 쓰게 된다(08-08 상한 0.20 사건과 동류).
suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(f,...) cat(sprintf(paste0("[basis] ",f,"\n"),...))

# 1. 24-seed 플라시보 측정 객체가 실재하는가 (손코딩 리터럴 8값의 출처)
say("=== 1. 측정 객체 재고 ===")
for (f in c("fq122_part1.rds","fq122_part2.rds","wt122_results.rds","wt122_addendum.rds","repair_battery.rds","precheck_results.rds")) {
  p <- file.path(OUT,f)
  if (file.exists(p)) { o <- readRDS(p); say("  %-24s names: %s", f, paste(names(o), collapse=", ")) }
  else say("  %-24s (부재)", f)
}
p2 <- readRDS(file.path(OUT,"fq122_part2.rds"))
say("  part2$PLC:"); print(p2$PLC)
say("  part2 내 24-seed 객체 존재: %s",
    any(grepl("24|seed", names(p2), ignore.case=TRUE)))

# 2. 유동성 두 정의 대조
say("=== 2. 유동성 basis 대조 ===")
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
LQ_fwd <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date), Ticker, adv_fwd=adv)]
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close","Vol")))[,Date:=as.Date(Date)]
setorder(R, Ticker, Date)
R[, adv20 := frollmean(Vol*Close, n=20L, align="right"), by=Ticker]
R[, ym := format(Date,"%Y-%m")]
LQ_raw <- R[, .(adv_raw = last(adv20)), by=.(Ticker, ym)]
rm(R); gc(verbose=FALSE)
LQ_fwd[, ym := format(Date,"%Y-%m")]
M <- merge(LQ_fwd, LQ_raw, by=c("Ticker","ym"), all.x=TRUE)
say("  liq_dt %d행 · rawdata 매칭 실패 %d행 (%.3f%%)", nrow(M), sum(is.na(M$adv_raw)), 100*mean(is.na(M$adv_raw)))
MM <- M[is.finite(adv_fwd) & is.finite(adv_raw)]
say("  두 정의 상관 %.6f · 최대 상대차 %.3e · 완전일치 비율 %.4f",
    cor(MM$adv_fwd, MM$adv_raw), max(abs(MM$adv_fwd-MM$adv_raw)/pmax(MM$adv_raw,1)),
    mean(abs(MM$adv_fwd-MM$adv_raw) < 1e-6))
say("  판정 불일치(한쪽만 2e8 통과): %d행 (%.4f%%)",
    sum((MM$adv_fwd>=2e8) != (MM$adv_raw>=2e8)), 100*mean((MM$adv_fwd>=2e8)!=(MM$adv_raw>=2e8)))

# 3. eligible_set(E) 자체가 rawdata 자로 깨끗한가
say("=== 3. eligible_set 을 고지문 검증절차(rawdata)로 재검 ===")
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
RAWU <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","K200","KQ150")))[,Date:=as.Date(Date)]
RAWU[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAWU[, .(Date=max(Date)), by=ym]$Date)
UNIV <- RAWU[Date %in% MEND & (K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; rm(RAWU); gc(verbose=FALSE)
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker)]
SC <- merge(BASE[Factor_Name=="M01_PATHQ" & !is.na(z), .(Date,Ticker,score=z)], UNIV, by=c("Date","Ticker"))
E <- merge(SC, LQ_fwd[,.(Date,Ticker,adv_fwd)], by=c("Date","Ticker"), all.x=TRUE)
E_orig <- E[is.na(adv_fwd) | adv_fwd>=2e8]
E_orig <- E_orig[Date %in% returns_dt$Date]
say("  원 E 정의(NA 관용): %d행 / %d개월 — 원 보고 82,566 과 대조", nrow(E_orig), uniqueN(E_orig$Date))
say("  그 중 adv_fwd NA: %d행", sum(is.na(E_orig$adv_fwd)))
E_orig[, ym := format(Date,"%Y-%m")]
EC <- merge(E_orig, LQ_raw, by=c("Ticker","ym"), all.x=TRUE)
say("  rawdata 자 재검: 미달 %d행 (%.4f%%) · 매칭실패 %d행",
    sum(EC$adv_raw < 2e8, na.rm=TRUE), 100*mean(EC$adv_raw < 2e8, na.rm=TRUE), sum(is.na(EC$adv_raw)))
say("  ⇒ %s", if (sum(EC$adv_raw < 2e8, na.rm=TRUE)==0 && sum(is.na(EC$adv_raw))==0)
      "원 eligible_set 은 두 자 모두에서 청정 — 이 정의를 발행 basis 로 채택 가능"
      else "★원 eligible_set 도 rawdata 자에서 미달 존재 — 더 엄격한 교집합 basis 필요")
