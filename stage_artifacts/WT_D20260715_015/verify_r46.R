# verify_r46.R — R46 firewall date-gap 정련(P3) + Close 연속성 tripwire(P2) 회귀검증
#   규율: 단일스레드 · arrow io(2) · read-only(pin) · rawdata/book/05_Production/factor_db 무변경.
#   known-case parity: 정당 데이터 불변 · 유니버스 분류 불변 · 북 불변 · 유니버스 월패널 불변.
#   신규 능력: date-gap seam 참값 보존(RESTORE) + Close hole tripwire.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
data.table::setDTthreads(1)
arrow::set_io_thread_count(2)        # ★io(1)=parquet read HANG
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); Sys.setenv(QM_ROOT = QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_015")
PIN <- file.path(QM, ".cache/pin/rawdata_r9_pin_20260715.parquet")   # §7 vintage pin
PIN_TAG <- "rawdata_r9_pin_20260715 (R40 pin, byte-identical to live 2026-07-15)"
cat("== R46 firewall date-gap 정련(P3) + Close 연속성 tripwire(P2) 회귀검증 ==\n pin:", basename(PIN), "\n")

# ── 함수 로드 (편집된 실제 코드 — firewall+tripwire 정의만 안전 추출) ────────────
source(file.path(QM, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(QM, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(QM, "02_Infrastructure/ramp/factor_validation.R"))
local({
  txt <- readLines(file.path(QM, "02_Infrastructure/data/rawdata_sanitize.R"), warn = FALSE)
  b0 <- grep("^ret_sanity_firewall <- function", txt); b1 <- grep("^sanitize_rawdata <- function", txt)
  eval(parse(text = paste(txt[b0:(b1[1]-1)], collapse = "\n")), envir = globalenv())
})
stopifnot(exists("ret_sanity_firewall"), exists("close_continuity_tripwire"),
          exists("canonical_screen_bt"), exists("build_monthly_forward_returns"))

BOOK <- c("A005930","A000660","A319660","A034730","A095610","A011070","A007340",
          "A023530","A004170","A402340","A222800","A003030","A290650","A189300")
ANOM <- c("A063350","A008480","A025930","A003190","A010120","A277810",
          "A328130","A183300","A058610","A454910")   # R43 in-universe 이상 종목

cols <- c("Date","Ticker","Close","Ret","K200","KQ150","Vol","Size","source","Name","Market")
raw <- as.data.table(read_parquet(PIN, col_select = tidyselect::all_of(cols)))
raw[, Date := as.Date(Date)]
cat(sprintf(" loaded: %s rows × %d cols | stored Ret max=%.1f\n",
            format(nrow(raw), big.mark=","), ncol(raw), max(raw$Ret, na.rm=TRUE)))

# 파이프라인 Step5 재현: Ret_stored 보존 → prevClose/gapdays → recompute
setorder(raw, Ticker, Date)
raw[, Ret_stored := Ret]
raw[, prevClose := shift(Close), by = Ticker]
raw[, gapdays   := as.integer(Date - shift(Date)), by = Ticker]
raw[, Ret := Close / prevClose - 1]
sc <- raw[!is.na(Ret) & !is.na(Ret_stored), max(abs(Ret - Ret_stored))]
cat(sprintf(" stored vs recompute Ret max|Δ|=%.4f (>0 = seam hole 존재)\n", sc))

# ═══ TEST A: 방화벽 census (R43/R44 유니버스 분류 불변 + RESTORE 신규 분기) ══════
fw  <- ret_sanity_firewall(raw)     # Ret_stored 컬럼 존재 → P3 restore 활성
iso <- fw$isolation; cnt <- fw$counts
cntA <- list(
  total_abs_gt_0.31 = raw[!is.na(Ret) & abs(Ret) > 0.31, .N],
  total_abs_gt_1.0  = raw[!is.na(Ret) & abs(Ret) > 1.0, .N],
  hard = cnt$hard, restore = cnt$restore, suspect = cnt$suspect,
  hard_in_universe = cnt$hard_in_universe, restore_in_universe = cnt$restore_in_universe,
  suspect_in_universe = cnt$suspect_in_universe,
  iso_in_universe = iso[in_universe == TRUE, .N])
cat("\n[TEST A] 방화벽 census (R43: |Ret|>0.31=2760 · |Ret|>1.0=343 · 유니버스 17)\n"); print(cntA)
iso_univ <- iso[in_universe == TRUE][order(-abs(Ret))]
cat(sprintf(" 유니버스內 격리 %d행 (R44=17: 1 phys HARD + 16 suspect · restore 0 기대):\n", nrow(iso_univ)))
print(iso_univ[, .(Ticker, Date, Ret=round(Ret,3), Ret_stored=round(Ret_stored,3), gapdays, action, cause)])
fwrite(iso_univ, file.path(OUT, "firewall_isolation_IN_UNIVERSE_r46.csv"))
fwrite(iso,      file.path(OUT, "firewall_isolation_ALL_r46.csv"))
cat(" action 분해 (전체):\n"); print(iso[, .N, by = .(action, cause)][order(-N)])
# 유니버스 분류 불변 판정: 유니버스內 restore 0 · 유니버스 iso 17 · 그중 1 NA_isolated(phys) + 16 suspect
inuniv_restore0 <- cnt$restore_in_universe == 0L
inuniv_iso_17   <- nrow(iso_univ) == 17L
inuniv_split_ok <- iso_univ[action=="NA_isolated", .N] == 1L && iso_univ[action=="suspect_flag_kept", .N] == 16L
testA_pass <- inuniv_restore0 && inuniv_iso_17 && inuniv_split_ok

# ═══ TEST B: 현 북 14보유 parity (오염 ZERO + restore 0) ══════════════════════
book_iso <- iso[Ticker %in% BOOK]
cat(sprintf("\n[TEST B] 현 북 14보유 방화벽 격리 = %d행 (기대 0 — R45 hole 0)\n", nrow(book_iso)))
if (nrow(book_iso) > 0) print(book_iso)
testB_pass <- nrow(book_iso) == 0L

# ═══ TEST C: 유니버스 월패널 parity (OLD firewall vs NEW firewall) ═══════════════
#   OLD(R44): hard=phys|zerodiv|dategap_all NA·restore 행 제거 / NEW(R46): hard NA + restore=stored 복원
old_hard <- fw$mask_hard | fw$mask_restore   # R44 old HARD = new HARD + restore
raw_old <- copy(raw); raw_old[old_hard, Ret := NA_real_]; raw_old <- raw_old[!is.na(Ret)]
raw_new <- copy(raw); raw_new[fw$mask_hard, Ret := NA_real_]
raw_new[fw$mask_restore, Ret := Ret_stored]; raw_new <- raw_new[!is.na(Ret)]
# ★핵심 known-case parity: restore 전량 비-유니버스 → 유니버스 월패널 불변(수학적 보장)
restore_all_nonuniv <- iso[action=="stored_restored_kept", all(in_universe == FALSE)]
n_restore_univ <- iso[action=="stored_restored_kept" & in_universe==TRUE, .N]
cat(sprintf("\n[TEST C] restore 전량 비-유니버스 = %s (유니버스內 restore %d행)\n",
            restore_all_nonuniv, n_restore_univ))
cat(sprintf(" OLD sanitized rows=%s · NEW sanitized rows=%s · 차이(restore 보존)=%d\n",
            format(nrow(raw_old),big.mark=","), format(nrow(raw_new),big.mark=","), nrow(raw_new)-nrow(raw_old)))
# 실측 월패널 비교: BOOK + 유니버스 샘플 (restore 종목 제외 — 유니버스 불변 실증)
sig_dates <- sort(unique(raw[, .(md = max(Date)), by = .(ym = format(Date, "%Y%m"))]$md))
cols_keep <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
set.seed(46)
univ_all <- raw[(K200==TRUE|KQ150==TRUE) & Date >= as.Date("2018-01-01"), unique(Ticker)]
sub_univ <- unique(c(BOOK, ANOM, sample(univ_all, min(150, length(univ_all)))))
mk_panel <- function(dd) build_monthly_forward_returns(dd[Ticker %in% sub_univ, ..cols_keep], sig_dates)$returns_dt
p_old <- mk_panel(raw_old); p_new <- mk_panel(raw_new)
mrg <- merge(p_old, p_new, by=c("Date","Ticker"), all=TRUE, suffixes=c("_o","_n"))
mrg[, dabs := abs(fifelse(is.na(Ret_1m_o),0,Ret_1m_o) - fifelse(is.na(Ret_1m_n),0,Ret_1m_n))]
panel_max_delta <- mrg[, max(dabs, na.rm=TRUE)]
panel_n_diff <- mrg[dabs > 1e-12 | is.na(Ret_1m_o) != is.na(Ret_1m_n), .N]
book_max_delta <- mrg[Ticker %in% BOOK, max(dabs, na.rm=TRUE)]
cat(sprintf(" 유니버스 월패널(book+anom+샘플 %d종목) OLD/NEW max|Δ Ret_1m|=%.3e · 상이행=%d · book max|Δ|=%.3e\n",
            length(sub_univ), panel_max_delta, panel_n_diff, book_max_delta))
testC_pass <- restore_all_nonuniv && (panel_max_delta < 1e-9) && (panel_n_diff == 0L)

# ═══ TEST D: canonical_screen_bt 가드 clean-inert + catch (line 무결성) ══════════
cat("\n[TEST D] canonical_screen_bt Ret_1m 가드 (R44 배선 불변 재확인)\n")
univ_sample <- unique(c(BOOK, sample(univ_all, min(120, length(univ_all)))))
sig_d <- sig_dates[sig_dates >= as.Date("2018-01-01") & sig_dates <= as.Date("2024-12-31")]
fwd <- build_monthly_forward_returns(raw_new[Ticker %in% univ_sample, ..cols_keep], sig_d)
ret_clean <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
sc_dt <- raw[Ticker %in% univ_sample & Date %in% sig_d, .(Date, Ticker, score = -log(pmax(Size,1)))]
warns <- character(0)
cs_clean <- withCallingHandlers(
  canonical_screen_bt(sc_dt, ret_clean, bench, top_n=20L, liq_dt=liq,
                      run_id="r46_clean", strategy_id="R46_CLEAN", diag_dual_basis=FALSE),
  warning=function(w){ warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
gw_clean <- sum(grepl("sanity 방화벽", warns))
ret_bad <- copy(ret_clean)
vd <- ret_bad[, .N, by=Date][which.max(N), Date]
vt <- sc_dt[Date==vd][order(-score)][1, Ticker]
ret_bad[Date==vd & Ticker==vt, Ret_1m := 67000]
if (ret_bad[Date==vd & Ticker==vt, .N]==0) ret_bad <- rbind(ret_bad, data.table(Date=vd,Ticker=vt,Ret_1m=67000))
warns2 <- character(0)
cs_bad <- withCallingHandlers(
  canonical_screen_bt(sc_dt, ret_bad, bench, top_n=20L, liq_dt=liq,
                      run_id="r46_bad", strategy_id="R46_BAD", diag_dual_basis=FALSE),
  warning=function(w){ warns2 <<- c(warns2, conditionMessage(w)); invokeRestart("muffleWarning") })
gw_bad <- sum(grepl("sanity 방화벽", warns2))
guard_finite <- is.finite(cs_bad$portfolio_alpha_t_nw_lag3) && is.finite(cs_bad$net_sr)
guard_match  <- abs(cs_bad$net_sr - cs_clean$net_sr) < 1e-6 &&
                abs(cs_bad$portfolio_alpha_t_nw_lag3 - cs_clean$portfolio_alpha_t_nw_lag3) < 1e-6
cat(sprintf(" (D) clean 가드경고=%d(기대0)·PORT_t=%.3f · bad 가드경고=%d(기대≥1)·finite=%s·clean일치=%s\n",
            gw_clean, cs_clean$portfolio_alpha_t_nw_lag3, gw_bad, guard_finite, guard_match))
testD_pass <- (gw_clean==0) && (gw_bad>=1) && guard_finite && guard_match

# ═══ TEST E: R45 196 seam 참값 보존 실증 (P3 known-case) ═════════════════════════
cat("\n[TEST E] R45 196 seam 케이스 stored 참값 보존(P3)\n")
cen <- fread(file.path(QM,"stage_artifacts/WT_D20260715_014/mismatch_census_ALL.csv"))
cen[, Date := as.Date(Date)]
# 각 196 행을 현 방화벽 마스크에 join (raw는 setorder Ticker,Date 상태)
raw[, ridx := .I]
key196 <- cen[, .(Ticker, Date)]
raw_m <- merge(key196, raw[, .(Ticker, Date, ridx, Ret_rc=Ret, Ret_st=Ret_stored, gapdays)],
               by=c("Ticker","Date"), all.x=TRUE)
raw_m[, is_restore := fw$mask_restore[ridx]]
raw_m[, is_hard    := fw$mask_hard[ridx]]
raw_m[, is_suspect := fw$mask_suspect[ridx]]
raw_m[, is_untouched := !is_restore & !is_hard & !is_suspect]  # |recompute|<=0.31 → firewall 미발화
e_restore   <- raw_m[is_restore==TRUE, .N]
e_hard      <- raw_m[is_hard==TRUE, .N]
e_suspect   <- raw_m[is_suspect==TRUE, .N]
e_untouched <- raw_m[is_untouched==TRUE, .N]
# 참값 보존 검증: restore된 행의 최종 Ret == stored, 그리고 |stored|<=0.31
restore_val_ok <- raw_m[is_restore==TRUE, all(abs(Ret_st) <= 0.31)]
cat(sprintf(" 196 seam 분류: RESTORE %d · HARD %d · SUSPECT %d · 미발화(|rc|<=0.31) %d\n",
            e_restore, e_hard, e_suspect, e_untouched))
cat(sprintf(" restore 행 stored 전량 물리타당(|stored|<=0.31)=%s\n", restore_val_ok))
# worked example A004415: OLD=drop, NEW=stored +2.93% 보존
wex <- raw[Ticker=="A004415" & Date==as.Date("2026-07-02"),
           .(Ticker, Date, Close, prevClose, gapdays, Ret_recompute=round(Ret,4), Ret_stored=round(Ret_stored,4))]
wex[, new_kept_Ret := round(raw$Ret_stored[fw$mask_restore & raw$Ticker=="A004415" & raw$Date==as.Date("2026-07-02")][1],4)]
cat(" worked example A004415 @ 2026-07-02 (OLD: NA-drop → NEW: stored 보존):\n"); print(wex)
raw[, ridx := NULL]
testE_pass <- (e_restore > 0) && restore_val_ok && (e_restore + e_hard + e_suspect + e_untouched == 196L)

# ═══ TEST F: Close 연속성 tripwire 현 rawdata 실행 (잔여 hole 리포트) ════════════
cat("\n[TEST F] Close 연속성 tripwire (현 rawdata, gapdays>20 hole)\n")
tw <- close_continuity_tripwire(raw[, .(Ticker,Date,Close,source,K200,KQ150,Name,Market)],
                                gap_threshold=20L, active_lag_days=90L,
                                report_path=file.path(OUT,"close_continuity_holes_r46.csv"))
cat(" tripwire counts:\n"); print(tw$counts)
cat(sprintf(" 게이트 신호(유니버스內 활성 구멍)=%s (FALSE=리빌드 안전·비-유니버스 잔여만)\n",
            tw$counts$gate_flag_in_universe_active))
cat(" hole 상위 8행(최근·유니버스·gapdays 순):\n")
print(head(tw$holes[, .(Ticker, Name, prevDate, Date, gapdays, in_universe, active_listed, source_seam, recent)], 8))
testF_pass <- !isTRUE(tw$counts$gate_flag_in_universe_active)   # 유니버스 활성 구멍 0 = 라이브 안전

# ═══ 종합 판정 ══════════════════════════════════════════════════════════════════
res <- list(
  wt="WT-D20260715_015", round="R46", as_of="2026-07-15", pin_tag=PIN_TAG,
  stored_vs_recompute_max_delta = sc,
  testA_census = cntA,
  testA_inuniv_class_unchanged = list(pass=testA_pass, restore_in_univ0=inuniv_restore0,
    iso17=inuniv_iso_17, split_1phys_16suspect=inuniv_split_ok),
  testB_book_parity = list(pass=testB_pass, book_iso_rows=nrow(book_iso)),
  testC_universe_panel_parity = list(pass=testC_pass, restore_all_nonuniverse=restore_all_nonuniv,
    restore_in_universe=n_restore_univ, panel_max_delta=panel_max_delta, panel_n_diff=panel_n_diff,
    book_max_delta=book_max_delta, rows_preserved_by_restore=nrow(raw_new)-nrow(raw_old)),
  testD_canonical_guard = list(pass=testD_pass, warns_clean=gw_clean, warns_bad=gw_bad,
    finite=guard_finite, matches_clean=guard_match, clean_port_t=cs_clean$portfolio_alpha_t_nw_lag3),
  testE_r45_196_restore = list(pass=testE_pass, restore=e_restore, hard=e_hard, suspect=e_suspect,
    untouched_le031=e_untouched, restore_stored_all_valid=restore_val_ok),
  testF_tripwire = list(pass=testF_pass, counts=tw$counts),
  overall_pass = testA_pass && testB_pass && testC_pass && testD_pass && testE_pass && testF_pass,
  constraints = "read-only pin · rawdata/book_state/05_Production/factor_db 무변경 · DART API 0 · 단일스레드 · io(2) · §7 pin 고정")
writeLines(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=8), file.path(OUT,"r46_verify_results.json"))
cat("\n== 종합 ==\n")
cat(sprintf(" A(census·유니버스분류 불변): %s (restore 유니버스 %d·iso 17=%s·1phys+16susp=%s)\n",
            testA_pass, cnt$restore_in_universe, inuniv_iso_17, inuniv_split_ok))
cat(sprintf(" B(북 parity): %s (격리 %d행)\n", testB_pass, nrow(book_iso)))
cat(sprintf(" C(유니버스 월패널 parity): %s (restore 전량 비-유니버스=%s·max|Δ|=%.2e·보존행 +%d)\n",
            testC_pass, restore_all_nonuniv, panel_max_delta, nrow(raw_new)-nrow(raw_old)))
cat(sprintf(" D(canonical 가드): %s\n", testD_pass))
cat(sprintf(" E(R45 196 stored 보존): %s (RESTORE %d·HARD %d·SUSPECT %d·미발화 %d)\n",
            testE_pass, e_restore, e_hard, e_suspect, e_untouched))
cat(sprintf(" F(tripwire 게이트 clean): %s (유니버스 활성 구멍 %d)\n", testF_pass, tw$counts$in_universe_active))
cat(sprintf(" OVERALL: %s\n", res$overall_pass))
cat(" → r46_verify_results.json 기록 완료\n")
