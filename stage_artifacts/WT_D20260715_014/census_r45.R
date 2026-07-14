# R45 — stored Ret vs recompute(Close/shift(Close)-1) 불일치 근원 census
#   규율: 단일스레드 · arrow io(2) · read-only(pin) · rawdata/book/05_Production/factor_db 무변경.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
data.table::setDTthreads(1); arrow::set_io_thread_count(2)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_014")
PIN <- file.path(QM, ".cache/pin/rawdata_r9_pin_20260715.parquet")
PIN_TAG <- "rawdata_r9_pin_20260715 (R40 pin, byte-identical to live 2026-07-15)"
cat("== R45 stored-vs-recompute Ret census ==\n pin:", basename(PIN), "\n")

cols <- c("Date","Ticker","Close","Ret","K200","KQ150","Vol","Size","source","Market","Name","Open","High","Low")
raw <- as.data.table(read_parquet(PIN, col_select = tidyselect::all_of(cols)))
raw[, Date := as.Date(Date)]
cat(sprintf(" loaded: %s rows × %d cols\n", format(nrow(raw), big.mark=","), ncol(raw)))

# ── 중복(Ticker,Date) 점검 ────────────────────────────────────────────────
dup <- raw[, .N, by=.(Ticker,Date)][N>1]
cat(sprintf("\n[DUP] 중복 (Ticker,Date) 행: %d 키 (기대 0)\n", nrow(dup)))
if(nrow(dup)>0) print(head(dup[order(-N)],10))

# ── recompute Ret = Close/shift(Close)-1 ──────────────────────────────────
setorder(raw, Ticker, Date)
raw[, Ret_stored := Ret]
raw[, prevClose := shift(Close), by=Ticker]
raw[, prevDate  := shift(Date),  by=Ticker]
raw[, gapdays   := as.integer(Date - prevDate)]
raw[, Ret_recompute := Close/prevClose - 1]
raw[, dAbs := abs(Ret_recompute - Ret_stored)]

# universe flag (K200/KQ150 double coded)
raw[, in_univ := (!is.na(K200) & K200==1) | (!is.na(KQ150) & KQ150==1)]

# ── 불일치 census (|Δ|>0.01), 첫날/NA 제외 ───────────────────────────────
cmp <- raw[!is.na(Ret_stored) & !is.na(Ret_recompute)]
cat(sprintf("\n[BASE] 비교가능 종목-일(양쪽 non-NA): %s\n", format(nrow(cmp), big.mark=",")))
mism <- cmp[dAbs > 0.01]
cat(sprintf("[MISMATCH] |Δ|>0.01: %s 종목-일 (%.4f%% of comparable)\n",
            format(nrow(mism), big.mark=","), 100*nrow(mism)/nrow(cmp)))
# magnitude buckets
buck <- function(dt){
  data.table(
    bucket=c("0.01-0.05","0.05-0.10","0.10-0.30","0.30-1.0",">1.0"),
    n=c(dt[dAbs>0.01&dAbs<=0.05,.N], dt[dAbs>0.05&dAbs<=0.10,.N],
        dt[dAbs>0.10&dAbs<=0.30,.N], dt[dAbs>0.30&dAbs<=1.0,.N], dt[dAbs>1.0,.N]))
}
cat("\n[MAGNITUDE 분포]\n"); print(buck(mism))
cat(sprintf(" max|Δ|=%.4f\n", mism[,max(dAbs)]))

# universe penetration
cat(sprintf("\n[UNIVERSE] 불일치 중 유니버스內(K200∪KQ150): %d 종목-일 / 유니버스밖 %d\n",
            mism[in_univ==TRUE,.N], mism[in_univ==FALSE,.N]))
cat(sprintf(" 불일치 유니버스內 고유종목: %d\n", mism[in_univ==TRUE, uniqueN(Ticker)]))

# period distribution
mism[, yr := year(Date)]
cat("\n[PERIOD] 연도별 불일치 (top rows)\n")
print(mism[, .(n=.N, n_univ=sum(in_univ), max_d=round(max(dAbs),3)), by=yr][order(yr)])

# ── 원인 진단: 각 불일치의 stored vs recompute 특성 ───────────────────────
# ratio 지문: recompute=Close/prevClose-1 이 stored와 다를 때, stored가 어떤 값에 정합하나
mism[, ratio_recompute := 1 + Ret_recompute]
mism[, ratio_stored := 1 + Ret_stored]
# 가설군 분류
mism[, cause := "unknown"]
# (d) 날짜갭>20d (상폐/재상장 cross-gap): recompute이 gap 넘어 잘못 이어붙임
mism[gapdays > 20, cause := "date_gap_gt20d"]
# (b) source seam: 전일과 source 다름 (vintage mismatch)
raw[, prevSource := shift(source), by=Ticker]
mism <- merge(mism, raw[,.(Ticker,Date,prevSource)], by=c("Ticker","Date"), all.x=TRUE)
mism[cause=="unknown" & !is.na(prevSource) & source!=prevSource, cause := "source_seam"]
# (a) split/adj 지문: recompute ratio ≈ 정수배(분할전 raw jump) 이거나 1/정수, 그리고 stored는 작음(조정)
mism[cause=="unknown" & abs(Ret_recompute) > 0.30 & abs(Ret_stored) <= 0.31, cause := "split_adj_candidate(rawClose_jump_storedRet_adjusted)"]
# (a2) 반대: stored가 크고 recompute 작음
mism[cause=="unknown" & abs(Ret_stored) > 0.30 & abs(Ret_recompute) <= 0.31, cause := "storedRet_large_recompute_small"]
# penny/zero-div
mism[cause=="unknown" & !is.na(prevClose) & prevClose <= 10, cause := "penny_prevclose_le10"]
cat("\n[CAUSE 분해] (전체 불일치)\n")
print(mism[, .N, by=cause][order(-N)])
cat("\n[CAUSE 분해] (유니버스內만)\n")
print(mism[in_univ==TRUE, .N, by=cause][order(-N)])

# ── 최대 Δ 사례 상세 (top 15) ─────────────────────────────────────────────
cat("\n[TOP 15 |Δ| 사례 상세]\n")
top <- mism[order(-dAbs)][1:min(15,.N),
   .(Date,Ticker,Name,Market,in_univ,Close,prevClose,gapdays,
     Ret_stored=round(Ret_stored,4),Ret_recompute=round(Ret_recompute,4),
     dAbs=round(dAbs,4),source,prevSource,cause)]
print(top)

# 저장
fwrite(mism[order(-dAbs)], file.path(OUT,"mismatch_census_ALL.csv"))
fwrite(mism[in_univ==TRUE][order(-dAbs)], file.path(OUT,"mismatch_census_IN_UNIVERSE.csv"))

# ── source 컬럼 값 분포 (seam 이해) ───────────────────────────────────────
cat("\n[SOURCE 값 분포]\n"); print(raw[, .N, by=source][order(-N)])

# ── summary json ──────────────────────────────────────────────────────────
summ <- list(
  pin_tag=PIN_TAG, n_rows=nrow(raw), n_dup_keys=nrow(dup),
  n_comparable=nrow(cmp), n_mismatch_gt001=nrow(mism), max_dAbs=round(mism[,max(dAbs)],4),
  mismatch_in_universe=mism[in_univ==TRUE,.N], mismatch_out_universe=mism[in_univ==FALSE,.N],
  n_unique_univ_tickers=mism[in_univ==TRUE,uniqueN(Ticker)],
  magnitude=as.list(setNames(buck(mism)$n, buck(mism)$bucket)),
  cause_all=as.list(setNames(mism[,.N,by=cause][order(-N)]$N, mism[,.N,by=cause][order(-N)]$cause)),
  cause_univ=as.list(setNames(mism[in_univ==TRUE,.N,by=cause]$N, mism[in_univ==TRUE,.N,by=cause]$cause))
)
write_json(summ, file.path(OUT,"census_summary.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("\n[DONE] census_summary.json + mismatch_census_{ALL,IN_UNIVERSE}.csv 저장\n")
