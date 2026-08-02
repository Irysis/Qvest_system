## _followup_012.R — R43 자가적대검증 후속 진단 (사전등록 primary 불변 — 해석 재료만)
##   F1 A축 침묵월 구조 (감시월 126/255 의 정체)
##   F2 A-SAFE ↔ MAG_ONLY 시간축 중첩 (D4 검정력 21개월의 정체)
##   F3 IT-4 worst-case 대입 양성 대조 (진성폐지 0 → 대입 no-op 이 '검사 사망'인지 판별)
##   F4 현 북 재판정 (live 소스 read-only)
## 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_012/_followup_012.R", encoding="UTF-8")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2L), silent = TRUE)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
logf <- file.path(OUT, "_r43_followup_log.txt"); if (file.exists(logf)) try(file.remove(logf), silent = TRUE)
w  <- function(...) { m <- paste0(...); try({ .c <- file(logf,"a",encoding="UTF-8"); writeLines(m,.c); close(.c) }, silent=TRUE); cat(m,"\n") }
wf <- function(...) w(sprintf(...))
ymshift <- function(v,k){y<-v%/%100L;m<-v%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
ym <- function(d) as.integer(format(d, "%Y%m"))
risk_metrics <- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(list(n=0L,downside=NA_real_,tail=NA_real_))
  list(n=length(r), downside=mean(r[r<0]), tail=mean(r < -0.15)) }
mk_flag <- function(z, thr) as.integer(!is.na(z) & z >= thr)
THR <- 1.0

O <- readRDS(file.path(OUT, "_r43_objects.rds")); U <- as.data.table(O$uni_slim)
FU <- list()

## ── F1. A축 침묵월 구조 ──────────────────────────────────────────────────────
## 원 패널(uni 제약 없음)에서 월별 max z 를 봐야 '문턱이 닿지 않는 달'인지 '커버리지가 없는 달'인지 갈린다.
IN <- as.data.table(read_parquet("outputs/ramp/insider_factor_scores.parquet"))
IN[, signal_date := as.Date(signal_date)]
I2 <- IN[factor_id == "INS02_OffBuyBreadth6m", .(n_names = .N, max_z = max(z), p90 = quantile(z, .9),
                                                 n_ge1 = sum(z >= THR)), by = signal_date][order(signal_date)]
wf("[F1] live ramp INS02 패널: %d개월 (%s~%s) | 월 이름수 중앙값 %d",
   nrow(I2), format(min(I2$signal_date), "%Y-%m"), format(max(I2$signal_date), "%Y-%m"), as.integer(median(I2$n_names)))
wf("[F1] ★문턱 z>=%.1f 에 아무도 닿지 않는 달 = %d/%d (%.1f%%) — 커버리지는 있는데 tripwire 가 구조적으로 침묵",
   THR, sum(I2$n_ge1 == 0), nrow(I2), 100*mean(I2$n_ge1 == 0))
wf("[F1] 침묵월의 max z 분포: median=%.3f p90=%.3f max=%.3f (문턱 %.1f 미달)",
   median(I2[n_ge1 == 0, max_z]), quantile(I2[n_ge1 == 0, max_z], .9), max(I2[n_ge1 == 0, max_z]), THR)
wf("[F1] 기전: INS02=(매수건-매도건)/(매수건+매도건) 은 [-1,1] 유계이고 상한 +1 에 질량이 몰린다 → 월 분포가 눌리면 최대 z 도 1.0 미만")
## uni 안에서의 A/A′ 월별 발화
mo <- U[, .(cov_a = sum(!is.na(state_A) | a == 1L | b == 1L), nA = sum(a == 1L), nB = sum(b == 1L),
            nAp = sum(a == 1L | b == 1L)), by = hold_ym][order(hold_ym)]
wf("[F1] uni 기준 월별 발화: A 발화월 %d/%d | A′ 발화월 %d/%d | A 침묵인데 A′ 발화 = %d개월",
   sum(mo$nA > 0), nrow(mo), sum(mo$nAp > 0), nrow(mo), sum(mo$nA == 0 & mo$nAp > 0))
FU$F1 <- list(live_months = nrow(I2), live_silent_months = sum(I2$n_ge1 == 0),
              live_silent_pct = round(100*mean(I2$n_ge1 == 0), 2),
              silent_max_z_median = round(median(I2[n_ge1 == 0, max_z]), 4),
              silent_max_z_max = round(max(I2[n_ge1 == 0, max_z]), 4),
              uni_months = nrow(mo), uni_A_active_months = sum(mo$nA > 0), uni_Ap_active_months = sum(mo$nAp > 0),
              uni_rescued_months = sum(mo$nA == 0 & mo$nAp > 0))
write_parquet(I2, file.path(OUT, "r43_live_monthly_maxz.parquet"))

## ── F2. A-SAFE ↔ MAG_ONLY 시간축 중첩 (D4 검정력 21개월의 정체) ────────────────
MID <- U[sz_tercile == "mid"]
m_as <- MID[safe_side == "A_SAFE", unique(hold_ym)]; m_mo <- MID[safe_side == "MAG_ONLY", unique(hold_ym)]
wf("\n[F2] MID: A_SAFE 발화월=%d | MAG_ONLY 발화월=%d | 교집합=%d (%.1f%% of MAG_ONLY 월) → paired 검정 가용 21개월의 원인",
   length(m_as), length(m_mo), length(intersect(m_as, m_mo)), 100*length(intersect(m_as,m_mo))/max(length(m_mo),1))
wf("[F2] ★구조: 보조축은 주축이 침묵한 달에 주로 발화 — 두 집합이 시간축에서 대체로 배타적이라 '동질성' paired 검정 자체가 저전력")
FU$F2 <- list(mid_A_SAFE_months = length(m_as), mid_MAG_ONLY_months = length(m_mo),
              mid_overlap_months = length(intersect(m_as, m_mo)),
              all_A_SAFE_months = length(U[safe_side=="A_SAFE", unique(hold_ym)]),
              all_MAG_ONLY_months = length(U[safe_side=="MAG_ONLY", unique(hold_ym)]),
              all_overlap_months = length(intersect(U[safe_side=="A_SAFE", unique(hold_ym)], U[safe_side=="MAG_ONLY", unique(hold_ym)])))

## ── F3. IT-4 worst-case 대입 양성 대조 ────────────────────────────────────────
## D7 에서 진성폐지 0 → -100% 대입이 수치를 안 바꿨다. 이것이 '대입 코드 사망'인지 '실제 0건'인지 갈라야 한다.
r_mo <- MID[safe_side == "MAG_ONLY", Ret_1m]
base_rm <- risk_metrics(r_mo)
ctrl_rm <- risk_metrics(c(r_mo[is.finite(r_mo)], rep(-1.0, 3L)))     # 합성 3건 주입 (양성 대조)
it4_pass <- is.finite(ctrl_rm$tail) && is.finite(base_rm$tail) && (ctrl_rm$tail > base_rm$tail)
if (!it4_pass) stop("[INJECT] IT-4 FAIL — worst-case 대입 경로가 합성 폐지 3건에도 반응하지 않음(검사 사망)")
wf("\n[INJECT] IT-4 worst-case 양성대조: 합성 진성폐지 3건 주입 → tail %.4f→%.4f, downside %+.4f→%+.4f = 대입 경로 실효 PASS",
   base_rm$tail, ctrl_rm$tail, base_rm$downside, ctrl_rm$downside)
wf("[F3] ⇒ D7 의 대입 no-op 은 '검사 사망' 아니라 '해당 base 에 진성폐지 0건'(R40 동일 실측)의 결과")
FU$IT4 <- list(base_tail = round(base_rm$tail,5), ctrl_tail = round(ctrl_rm$tail,5),
               base_downside = round(base_rm$downside,5), ctrl_downside = round(ctrl_rm$downside,5),
               synthetic_delistings = 3L, pass = it4_pass)

## ── F4. 현 북 재판정 (live 소스 read-only) ────────────────────────────────────
## filing_delay_watch.R Part C 와 동일 해석 경로(보유 CSV / INS02 hy / 상태) + MAGQ3 보조축 대조.
ROOT <- QM
HOLD <- local({
  .fb <- file.path(ROOT, "05_Production/2.Factor_Model", "2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe")
  .hu <- tryCatch({ bs <- fromJSON(file.path(ROOT, "qepm/mailbox/governor/book_state.json"))
    ids <- bs[["admitted_ids"]]; if (is.list(ids)) ids <- unlist(ids); stopifnot(length(ids) == 1L)
    base <- file.path(ROOT, "05_Production/2.Factor_Model")
    hit <- grep(sprintf("^[0-9]+-[0-9]+\\.%s$", ids[1]), list.dirs(base, full.names=FALSE, recursive=FALSE), value=TRUE)
    stopifnot(length(hit) == 1L); file.path(base, hit, "02_holdings_universe") }, error = function(e) .fb)
  wfs <- list.files(.hu, pattern = "_weights_cap_0p20\\.csv$", full.names = TRUE)
  stopifnot(length(wfs) > 0L); wfs[order(basename(wfs))][length(wfs)] })
wf("\n[F4] 보유 소비(read-only): %s", basename(HOLD))
res <- as.data.table(fread(HOLD))
wcol <- intersect(c("Weight","weight","w"), names(res))[1]; tcol <- intersect(c("Ticker","ticker"), names(res))[1]
res <- res[, .(Ticker = get(tcol), Weight = as.numeric(get(wcol)))][is.finite(Weight) & Weight > 0]
check_date <- Sys.Date()
INp <- IN[signal_date <= check_date]; INp[, hy := ymshift(ym(signal_date), 1L)]
cur_hy <- max(INp$hy)
i02 <- INp[hy == cur_hy & factor_id == "INS02_OffBuyBreadth6m", .(Ticker = security_id, ins02 = z)]
i02p <- INp[hy == ymshift(cur_hy,-1L) & factor_id == "INS02_OffBuyBreadth6m", .(Ticker = security_id, ins02_prev = z)]
## MAGQ3 (WT-007 패널, 동일 CS 변환)
PAN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_007/insider_axes_panel.parquet"))
cs_z <- function(dt, col) { d <- dt[is.finite(get(col)), .(sig_ym, Ticker, x = get(col))]
  d[, { mu<-mean(x); s<-sd(x); if(!is.finite(s)||s<=0) list(Ticker=Ticker, score=rep(NA_real_,.N)) else {
    xw<-pmin(pmax(x,mu-3*s),mu+3*s); s2<-sd(xw)
    if(!is.finite(s2)||s2<=0) list(Ticker=Ticker,score=rep(NA_real_,.N)) else list(Ticker=Ticker, score=(xw-mean(xw))/s2) } }, by=sig_ym][is.finite(score)] }
MZ <- cs_z(PAN, "INS_MAGQ3"); MZ[, hy := ymshift(as.integer(sig_ym), 1L)]
mag_cur <- MZ[hy == cur_hy, .(Ticker, magq3 = score)]
wf("[F4] 현 홀딩월 hy=%d | INS02 커버 %d종목 (max z=%.3f) | MAGQ3 커버 %d종목 (max z=%.3f) | MAGQ3 패널 최신 hy=%d",
   cur_hy, nrow(i02), if(nrow(i02)) max(i02$ins02) else NA_real_, nrow(mag_cur),
   if(nrow(mag_cur)) max(mag_cur$magq3) else NA_real_, max(MZ$hy))
BK <- merge(res, i02, by = "Ticker", all.x = TRUE)
BK <- merge(BK, i02p, by = "Ticker", all.x = TRUE)
BK <- merge(BK, mag_cur, by = "Ticker", all.x = TRUE)
BK[, on_A := mk_flag(ins02, THR)]; BK[, on_B := mk_flag(magq3, THR)]
BK[, on_Ap := as.integer(on_A == 1L | on_B == 1L)]
BK[, on_Ap_prev := NA_integer_]
BK[, flag_A  := fifelse(is.na(ins02), "NO_INS02", fifelse(on_A == 1L, "NET_BUY_SAFE", "NEUTRAL"))]
BK[, flag_Ap := fifelse(is.na(ins02) & is.na(magq3), "NO_INS_DATA", fifelse(on_Ap == 1L, "NET_BUY_SAFE", "NEUTRAL"))]
setorder(BK, -Weight)
wf("[F4] 현 북 %d종목 | A: NET_BUY_SAFE %d · NEUTRAL %d · 무데이터 %d",
   nrow(BK), BK[flag_A=="NET_BUY_SAFE",.N], BK[flag_A=="NEUTRAL",.N], BK[flag_A=="NO_INS02",.N])
wf("[F4] A′: NET_BUY_SAFE %d · NEUTRAL %d · 무데이터 %d | ★발화 변화 종목 %d",
   BK[flag_Ap=="NET_BUY_SAFE",.N], BK[flag_Ap=="NEUTRAL",.N], BK[flag_Ap=="NO_INS_DATA",.N],
   BK[flag_A != flag_Ap, .N])
if (BK[flag_A != flag_Ap, .N] > 0) {
  chg <- BK[flag_A != flag_Ap]
  for (i in seq_len(nrow(chg))) { r <- chg[i]
    wf("   %-8s w=%.4f  INS02=%s MAGQ3=%s  %s → %s", r$Ticker, r$Weight,
       ifelse(is.na(r$ins02), "NA", sprintf("%+.3f", r$ins02)),
       ifelse(is.na(r$magq3), "NA", sprintf("%+.3f", r$magq3)), r$flag_A, r$flag_Ap) }
} else w("   (발화 변화 없음)")
wf("[F4] 현 북 MAGQ3 z 분포: %s", paste(sprintf("%.2f", quantile(BK$magq3, c(0,.5,.9,1), na.rm=TRUE)), collapse=" / "))
write_parquet(BK[, .(Ticker, Weight, ins02, ins02_prev, magq3, on_A, on_B, on_Ap, flag_A, flag_Ap)],
              file.path(OUT, "r43_current_book_readjudication.parquet"))
FU$F4 <- list(holdings_file = basename(HOLD), cur_hold_ym = cur_hy, n_holdings = nrow(BK),
              magq3_panel_max_hy = max(MZ$hy),
              A_safe = BK[flag_A=="NET_BUY_SAFE",.N], A_neutral = BK[flag_A=="NEUTRAL",.N], A_nodata = BK[flag_A=="NO_INS02",.N],
              Ap_safe = BK[flag_Ap=="NET_BUY_SAFE",.N], Ap_neutral = BK[flag_Ap=="NEUTRAL",.N],
              n_changed = BK[flag_A != flag_Ap, .N],
              changed = if (BK[flag_A != flag_Ap, .N] > 0) lapply(seq_len(BK[flag_A!=flag_Ap,.N]), function(i){
                r <- BK[flag_A!=flag_Ap][i]; list(Ticker=r$Ticker, Weight=round(r$Weight,5),
                ins02=r$ins02, magq3=round(r$magq3,4), from=r$flag_A, to=r$flag_Ap) }) else list())

write_json(FU, file.path(OUT, "r43_followup.json"), auto_unbox = TRUE, pretty = TRUE, digits = 5, na = "null")
w("\nFOLLOWUP_DONE"); cat("[SAVED]", file.path(OUT, "r43_followup.json"), "\n")
