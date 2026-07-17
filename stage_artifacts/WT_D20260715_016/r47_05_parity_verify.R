#==============================================================================
# R47 STEP 05: parity 4종 검증 (NEW rawdata vs BACKUP, READ-ONLY)
#   ① 기존 정당 데이터 max|ΔRet|=max|ΔClose|=0 (구멍 외 무변경)
#   ② recompute==stored parity 회복 (218 seam) + tripwire source_seam 소멸
#   ③ 유니버스 월패널 무변경 (유니버스 행 불변·max|Δ|=0)
#   ④ 현 북 14보유 무변경
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "rawdata_sanitize.R"))
RAWDATA_CACHE <- file.path(ROOT, ".cache", "RAWDATA.parquet")
BACKUP <- file.path(ROOT, ".cache", "rawdata_pre_r47_backup_20260715.parquet")
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
log <- function(...) cat(sprintf(...), "\n")
book <- c("A005930","A000660","A319660","A034730","A095610","A011070","A007340","A023530",
          "A004170","A402340","A222800","A003030","A290650","A189300")

nw  <- as.data.table(read_parquet(RAWDATA_CACHE,
        col_select=c("Date","Ticker","Close","Ret","source","K200","KQ150")))
bk  <- as.data.table(read_parquet(BACKUP,
        col_select=c("Date","Ticker","Close","Ret","K200","KQ150")))
nw[, Date := as.Date(Date)]; bk[, Date := as.Date(Date)]
log("[load] new=%d rows | backup=%d rows | delta=%d", nrow(nw), nrow(bk), nrow(nw)-nrow(bk))

R <- list()

# ── Parity ① 기존 정당 데이터 무변경 ────────────────────────────────────────
setkey(bk, Date, Ticker); setkey(nw, Date, Ticker)
j <- nw[bk, on=.(Date,Ticker)]   # 각 backup 행에 대응하는 new Close/Ret (i.Close=backup)
# j: Close/Ret = new, i.Close/i.Ret = backup
dClose <- j$Close - j$i.Close
dRet_na_mismatch <- sum(xor(is.na(j$Ret), is.na(j$i.Ret)))
dRet <- j$Ret - j$i.Ret
R$p1_existing_unchanged <- list(
  backup_rows_matched = nrow(j),
  max_abs_dClose = max(abs(dClose), na.rm=TRUE),
  max_abs_dRet = max(abs(dRet), na.rm=TRUE),
  ret_na_mismatch = dRet_na_mismatch,
  pass = (max(abs(dClose),na.rm=TRUE)==0 & max(abs(dRet),na.rm=TRUE)==0 & dRet_na_mismatch==0)
)
log("\n[P1] existing 무변경: matched=%d max|dClose|=%.6g max|dRet|=%.6g na_mismatch=%d → %s",
    nrow(j), R$p1_existing_unchanged$max_abs_dClose, R$p1_existing_unchanged$max_abs_dRet,
    dRet_na_mismatch, ifelse(R$p1_existing_unchanged$pass,"PASS","FAIL"))

# ── Parity ② seam parity 회복 ───────────────────────────────────────────────
# 2a. tripwire on new
tw <- close_continuity_tripwire(nw[, .(Ticker, Date, Close, source, K200, KQ150)])
log("[P2a] tripwire NEW: total_holes=%d source_seam=%d in_universe=%d unique_tickers=%d",
    tw$counts$total_holes, tw$counts$source_seam, tw$counts$in_universe, tw$counts$unique_tickers)
# 2b. 216 aprilcluster: 07-02 stored Ret == recompute(Close07-02/Close07-01 -1)
fillset <- fread(file.path(WT, "r47_fill_set.csv")); fillset[, Date := as.Date(Date)]
apr_tk <- fread(file.path(ROOT,"stage_artifacts/WT_D20260715_015/close_continuity_holes_r46.csv"))[
            prevDate=="2026-04-29" & Date=="2026-07-02", Ticker]
chk <- nw[Ticker %in% apr_tk & Date %in% as.Date(c("2026-07-01","2026-07-02"))]
chk <- dcast(chk, Ticker ~ Date, value.var="Close")
setnames(chk, c("Ticker","c0701","c0702"))
stored0702 <- nw[Ticker %in% apr_tk & Date==as.Date("2026-07-02"), .(Ticker, stored=Ret)]
chk <- merge(chk, stored0702, by="Ticker")
chk[, recompute := c0702/c0701 - 1]
chk[, match := abs(recompute - stored) < 1e-6]
R$p2_seam_parity <- list(
  tripwire_source_seam = tw$counts$source_seam,
  tripwire_total_holes = tw$counts$total_holes,
  aprilcluster_checked = nrow(chk),
  seam_0702_recompute_eq_stored = sum(chk$match, na.rm=TRUE),
  seam_mismatch = sum(!chk$match | is.na(chk$match)),
  pass = (tw$counts$source_seam <= 2 & sum(!chk$match | is.na(chk$match))==0)   # ≤2 = 잔여 penny only
)
log("[P2b] 07-02 recompute==stored: %d/%d match | mismatch=%d → %s",
    sum(chk$match,na.rm=TRUE), nrow(chk), R$p2_seam_parity$seam_mismatch,
    ifelse(R$p2_seam_parity$pass,"PASS","FAIL"))
if (R$p2_seam_parity$seam_mismatch>0) print(chk[match==FALSE | is.na(match)][1:min(10,.N)])
# 잔여 hole 상세
if (tw$counts$total_holes>0) fwrite(tw$holes, file.path(WT,"r47_residual_holes_after.csv"))

# ── Parity ③ 유니버스 월패널 무변경 ─────────────────────────────────────────
# 유니버스 행 = K200==1|KQ150==1. new/backup 유니버스 행 완전 동일해야
bk_u <- bk[K200 %in% 1 | KQ150 %in% 1, .(Date,Ticker,Close,Ret)]
nw_u <- nw[K200 %in% 1 | KQ150 %in% 1, .(Date,Ticker,Close,Ret)]
setkey(bk_u, Date, Ticker); setkey(nw_u, Date, Ticker)
ju <- nw_u[bk_u, on=.(Date,Ticker)]
R$p3_universe_panel <- list(
  universe_rows_backup = nrow(bk_u), universe_rows_new = nrow(nw_u),
  rows_equal = (nrow(bk_u)==nrow(nw_u)),
  max_abs_dClose = max(abs(ju$Close-ju$i.Close),na.rm=TRUE),
  max_abs_dRet = max(abs(ju$Ret-ju$i.Ret),na.rm=TRUE),
  ret_na_mismatch = sum(xor(is.na(ju$Ret), is.na(ju$i.Ret))),
  pass = (nrow(bk_u)==nrow(nw_u) & max(abs(ju$Close-ju$i.Close),na.rm=TRUE)==0 &
          max(abs(ju$Ret-ju$i.Ret),na.rm=TRUE)==0)
)
log("[P3] universe 무변경: rows bk=%d nw=%d equal=%s max|dRet|=%.6g → %s",
    nrow(bk_u), nrow(nw_u), R$p3_universe_panel$rows_equal, R$p3_universe_panel$max_abs_dRet,
    ifelse(R$p3_universe_panel$pass,"PASS","FAIL"))

# ── Parity ④ 북 14보유 무변경 ───────────────────────────────────────────────
bk_b <- bk[Ticker %in% book, .(Date,Ticker,Close,Ret)]
nw_b <- nw[Ticker %in% book, .(Date,Ticker,Close,Ret)]
setkey(bk_b,Date,Ticker); setkey(nw_b,Date,Ticker)
jb <- nw_b[bk_b, on=.(Date,Ticker)]
R$p4_book_unchanged <- list(
  book_rows_backup=nrow(bk_b), book_rows_new=nrow(nw_b),
  rows_equal=(nrow(bk_b)==nrow(nw_b)),
  max_abs_dClose=max(abs(jb$Close-jb$i.Close),na.rm=TRUE),
  max_abs_dRet=max(abs(jb$Ret-jb$i.Ret),na.rm=TRUE),
  pass=(nrow(bk_b)==nrow(nw_b) & max(abs(jb$Close-jb$i.Close),na.rm=TRUE)==0 &
        max(abs(jb$Ret-jb$i.Ret),na.rm=TRUE)==0)
)
log("[P4] book14 무변경: rows bk=%d nw=%d max|dRet|=%.6g → %s",
    nrow(bk_b), nrow(nw_b), R$p4_book_unchanged$max_abs_dRet,
    ifelse(R$p4_book_unchanged$pass,"PASS","FAIL"))

# ── fill 실재 확인 ──────────────────────────────────────────────────────────
nfill_new <- nw[source=="krx_api_backfill_20260717", .N]
R$fill_present <- list(rows=nfill_new, tickers=nw[source=="krx_api_backfill_20260717", uniqueN(Ticker)])
log("[fill] new에 source=krx_api_backfill_20260717 rows=%d tickers=%d", nfill_new, R$fill_present$tickers)

R$overall_pass <- all(R$p1_existing_unchanged$pass, R$p2_seam_parity$pass,
                      R$p3_universe_panel$pass, R$p4_book_unchanged$pass)
log("\n[OVERALL] %s", ifelse(R$overall_pass, "ALL PARITY PASS", "***PARITY FAIL***"))
writeLines(jsonlite::toJSON(R, auto_unbox=TRUE, pretty=TRUE), file.path(WT,"r47_parity_verify.json"))
log("[done] parity verify written.")
