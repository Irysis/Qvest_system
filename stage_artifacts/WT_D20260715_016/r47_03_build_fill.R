#==============================================================================
# R47 STEP 03: fill_rows 구성 (rawdata 무변경 — WT dir에만 저장, 병합 전 검수용)
#   각 fill (Ticker,Date): OHLCV=KRX 캐시 / meta·flags=티커 04-29 template carry-forward
#   / BM_Ret=Date canonical / Ret=chained(pre-gap Close부터) / source=krx_api_backfill_20260717
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RAWDATA_CACHE <- file.path(ROOT, ".cache", "RAWDATA.parquet")
KRX_CACHE_DIR <- file.path(ROOT, ".cache", "krx")
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
SRC_TAG <- "krx_api_backfill_20260717"
log <- function(...) cat(sprintf(...), "\n")

fill_set <- fread(file.path(WT, "r47_fill_set.csv"))
fill_set[, Date := as.Date(Date)]
fill_tickers <- unique(fill_set$Ticker)
need_dates <- sort(unique(fill_set$Date))
log("[in] fill_set: %d rows | %d tickers | %d dates", nrow(fill_set), length(fill_tickers), length(need_dates))

# ── 1. KRX transform (krx_transform_daily 정합) for 64 gap days, target tickers only ──
.num <- function(x) as.numeric(gsub(",", "", x))
krx_rows <- rbindlist(lapply(need_dates, function(d) {
  ds <- format(d, "%Y%m%d")
  out <- list()
  for (mk in c("stk_ohlcv","ksq_ohlcv")) {
    f <- file.path(KRX_CACHE_DIR, mk, sprintf("%s_%s.parquet", mk, ds))
    if (!file.exists(f)) next
    x <- as.data.table(read_parquet(f))
    x[, Ticker := paste0("A", ISU_CD)]
    x <- x[Ticker %in% fill_tickers]
    if (nrow(x) == 0) next
    out[[mk]] <- x[, .(Date = d, Ticker,
        Name_krx = ISU_NM,
        Market_krx = fifelse(is.na(Market)|Market=="", MKT_NM, Market),
        Sector_krx = fifelse(is.na(SECT_TP_NM)|SECT_TP_NM=="", NA_character_, SECT_TP_NM),
        Open = .num(TDD_OPNPRC), High = .num(TDD_HGPRC), Low = .num(TDD_LWPRC),
        Close = .num(TDD_CLSPRC), Vol = .num(ACC_TRDVOL), Size = .num(MKTCAP))]
  }
  rbindlist(out, fill=TRUE)
}), fill=TRUE)
krx_rows <- krx_rows[!is.na(Close) & Close > 0]           # 미거래(Close 0/NA) 제외 = 정직 잔여 hole
# ★APPEND-ONLY 게이트: fill_set(진짜 부재 (Ticker,Date))로만 제한 — 기존 행 collision 원천차단
krx_rows <- merge(krx_rows, fill_set, by=c("Ticker","Date"))   # inner join = fill_set ∩ KRX-traded
log("[krx] transformed target rows (traded days, fill_set-restricted): %d / %d fill_set (%.1f%%)",
    nrow(krx_rows), nrow(fill_set), 100*nrow(krx_rows)/nrow(fill_set))

# fill_set과 실제 KRX 확보의 차 = 미거래 잔여 hole
got <- merge(fill_set, krx_rows[, .(Ticker, Date, got=TRUE)], by=c("Ticker","Date"), all.x=TRUE)
residual_holes <- got[is.na(got)]
log("[krx] 미거래 잔여 (KRX에도 없음): %d (ticker: %s)", nrow(residual_holes),
    paste(unique(residual_holes$Ticker), collapse=", "))

# ── 2. template rows (per fill ticker: last rawdata row at Date<=prevDate) ────
ds_raw <- open_dataset(RAWDATA_CACHE, format="parquet")
tmpl <- as.data.table(ds_raw |> dplyr::filter(Ticker %in% fill_tickers, Date <= as.Date("2026-07-01")) |>
  dplyr::select(Date, Ticker, UnfaithfulDisc, AdminStock, TradingHalt, KQ150, K200, Float,
                Sector_Lv2, Sector, Name, Market, Close) |> dplyr::collect())
tmpl[, Date := as.Date(Date)]
setorder(tmpl, Ticker, Date)
# per ticker last row before/at each gap start; use the single most-recent pre-gap row as template
templ <- tmpl[, .SD[.N], by=Ticker,
              .SDcols=c("UnfaithfulDisc","AdminStock","TradingHalt","KQ150","K200","Float",
                        "Sector_Lv2","Sector","Name","Market")]
log("[tmpl] template rows: %d tickers | K200==1: %d | KQ150==1: %d (MUST be 0 — non-universe)",
    nrow(templ), sum(templ$K200==1, na.rm=TRUE), sum(templ$KQ150==1, na.rm=TRUE))

# ── 3. BM_Ret canonical per fill Date (from existing rawdata) ────────────────
bm <- as.data.table(ds_raw |> dplyr::filter(Date %in% need_dates) |>
        dplyr::select(Date, BM_Ret) |> dplyr::collect())
bm[, Date := as.Date(Date)]
bm_map <- bm[!is.na(BM_Ret), .(BM_Ret = BM_Ret[1]), by=Date]   # per-date constant benchmark
log("[bm] BM_Ret map dates: %d / %d need_dates", nrow(bm_map), length(need_dates))

# ── 4. assemble fill rows ────────────────────────────────────────────────────
fill <- merge(krx_rows, templ, by="Ticker", all.x=TRUE)
fill <- merge(fill, bm_map, by="Date", all.x=TRUE)
fill[is.na(BM_Ret), BM_Ret := 0]                              # sentinel (krx_merge 정합)
# meta 우선순위: template(연속성) → KRX fallback
fill[, `:=`(
  Name   = fifelse(is.na(Name)|Name=="", Name_krx, Name),
  Market = fifelse(is.na(Market)|Market=="", Market_krx, Market),
  Sector = fifelse(is.na(Sector)|Sector=="", Sector_krx, Sector)
)]

# ── 5. Ret chained: per ticker combine pre-gap Close series + fill Close ─────
# pre-gap closes (Date<=prevDate per ticker) — 실제로는 04-29 및 이전; 마지막값이 첫 fill의 prev
pre <- tmpl[, .(Ticker, Date, Close)]
comb <- rbindlist(list(
  pre[, .(Ticker, Date, Close, is_fill=FALSE)],
  fill[, .(Ticker, Date, Close, is_fill=TRUE)]
))
setorder(comb, Ticker, Date)
comb[, Ret := Close / shift(Close) - 1, by=Ticker]
fill_ret <- comb[is_fill==TRUE, .(Ticker, Date, Ret)]
fill <- merge(fill, fill_ret, by=c("Ticker","Date"), all.x=TRUE)

# ── 5b. ret_sanity_firewall 정합: |Ret|>1.0 = 물리불가 단일일 수익(정지-재개 재평가) ──
#   → Close(참값 KRX)는 보존, Ret만 정직 NA (R44/R46 HARD 규칙 + April fix '정직 NA' 선례)
na_mask <- !is.na(fill$Ret) & abs(fill$Ret) > 1.0
if (sum(na_mask) > 0) {
  log("[firewall] |Ret|>1.0 (정지-재개 재평가) %d행 → Ret:=NA (Close 보존):", sum(na_mask))
  print(fill[na_mask, .(Ticker, Date, Close, Ret)])
  fill[na_mask, Ret := NA_real_]
}

# ── 6. final schema (RAWDATA 21-col 정합) ────────────────────────────────────
fill[, source := SRC_TAG]
rawdata_cols <- c("Date","Ticker","UnfaithfulDisc","AdminStock","TradingHalt","KQ150","K200",
                  "Float","Sector_Lv2","Sector","Name","Market","BM_Ret","Open","High","Low",
                  "Close","Vol","Size","Ret","source")
fill_out <- fill[, ..rawdata_cols]

# ── 7. sanity + Ret 분포 진단 ───────────────────────────────────────────────
log("\n[fill] rows=%d | tickers=%d | dates=%d", nrow(fill_out), uniqueN(fill_out$Ticker), uniqueN(fill_out$Date))
log("[fill] K200==1: %d | KQ150==1: %d (MUST be 0)", sum(fill_out$K200==1,na.rm=TRUE), sum(fill_out$KQ150==1,na.rm=TRUE))
log("[fill] Ret NA: %d | |Ret|>0.31: %d | |Ret|>1.0(물리불가): %d",
    sum(is.na(fill_out$Ret)), sum(abs(fill_out$Ret)>0.31,na.rm=TRUE), sum(abs(fill_out$Ret)>1.0,na.rm=TRUE))
log("[fill] Close range: %.0f ~ %.0f | any Close<=0: %d", min(fill_out$Close), max(fill_out$Close), sum(fill_out$Close<=0))
q <- quantile(fill_out$Ret, c(0,0.01,0.5,0.99,1), na.rm=TRUE)
log("[fill] Ret quantiles 0/1/50/99/100: %.3f / %.3f / %.3f / %.3f / %.3f", q[1],q[2],q[3],q[4],q[5])
# 물리불가 케이스 표시 (있으면)
bad <- fill_out[abs(Ret)>1.0]
if (nrow(bad)>0) { log("[fill][WARN] |Ret|>1.0 rows:"); print(bad[, .(Ticker,Date,Close,Ret)]) }

write_parquet(fill_out, file.path(WT, "r47_fill_rows.parquet"))
fwrite(residual_holes[, .(Ticker, Date)], file.path(WT, "r47_residual_holes.csv"))
writeLines(jsonlite::toJSON(list(
  fill_rows=nrow(fill_out), fill_tickers=uniqueN(fill_out$Ticker), fill_dates=uniqueN(fill_out$Date),
  residual_holes=nrow(residual_holes), residual_tickers=unique(residual_holes$Ticker),
  ret_na=sum(is.na(fill_out$Ret)), ret_gt031=sum(abs(fill_out$Ret)>0.31,na.rm=TRUE),
  ret_gt1=sum(abs(fill_out$Ret)>1.0,na.rm=TRUE),
  k200_eq1=sum(fill_out$K200==1,na.rm=TRUE), kq150_eq1=sum(fill_out$KQ150==1,na.rm=TRUE)
), auto_unbox=TRUE, pretty=TRUE), file.path(WT, "r47_fill_build.json"))
log("\n[done] fill_rows.parquet written (NOT merged into rawdata yet).")
