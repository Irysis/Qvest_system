## FQ-232 P2 — (d) 기본동작 parity 를 **값 수준**에서 확정 + 자 불일치의 시대 분포
##  P1 에서 liq_identical=FALSE 가 나왔다. 값이 다른가 속성(attr)만 다른가를 분리 측정한다.
##  ★"다르다"를 기전 확인 없이 보고하지 않는다 — 두 원인은 함의가 정반대다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq232_liquidity_ruler_restore_20260810")
SC  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/731a7a86-b8bf-4640-9de7-b5e7830e4ad8/scratchpad"
say <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }

RAWPATH <- ".cache/RAWDATA.parquet"; fi <- file.info(RAWPATH)
say("vintage pin: %s | %.0f bytes | mtime %s", RAWPATH, fi$size, format(fi$mtime))
RAW <- as.data.table(read_parquet(RAWPATH,
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("★입력 실측: %d행 · %d 거래일 · 일간", nrow(RAW), uniqueN(RAW$Date))
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]

## ── 1. 값 수준 parity ────────────────────────────────────────────────────────
suppressMessages(suppressWarnings(source(file.path(SC, "fv_old.R"))))
o <- suppressWarnings(build_monthly_forward_returns(RAWME, ME))
suppressMessages(source("02_Infrastructure/ramp/factor_validation.R"))
n <- suppressWarnings(build_monthly_forward_returns(RAWME, ME))
lo <- o$liq_dt; ln <- n$liq_dt
say("=== (d) 값 수준 parity ===")
say("  liq 행수: old %d · new %d · 동일 = %s", nrow(lo), nrow(ln), nrow(lo) == nrow(ln))
say("  컬럼: old [%s] · new [%s]", paste(names(lo), collapse=","), paste(names(ln), collapse=","))
key_same <- identical(as.character(lo$Date), as.character(ln$Date)) &&
            identical(lo$Ticker, ln$Ticker)
val_max  <- max(abs(lo$adv - ln$adv), na.rm = TRUE)
val_na   <- identical(is.na(lo$adv), is.na(ln$adv))
say("  키 순서 동일 = %s · max|Δadv| = %.17g · NA패턴 동일 = %s", key_same, val_max, val_na)
say("  attr(old): [%s]", paste(setdiff(names(attributes(lo)), c("names","row.names","class",".internal.selfref")), collapse=","))
say("  attr(new): [%s]", paste(setdiff(names(attributes(ln)), c("names","row.names","class",".internal.selfref")), collapse=","))
say("  ★판정: 값 동일 = %s / 차이는 %s",
    (key_same && val_max == 0 && val_na),
    if (key_same && val_max == 0 && val_na) "신규 attr('liq_ruler_source') 뿐 — 동작 무변경" else "값 자체")
## 반환 list 의 신규 필드도 명시
say("  반환 필드: old [%s]", paste(names(o), collapse=", "))
say("             new [%s]", paste(names(n), collapse=", "))

## ── 2. canonical_screen_bt 값 parity (신규 필드 append 만인가) ───────────────
A <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260808_002/alpha_scores.parquet")))
A[, Date := as.Date(Date)]
S_raw <- A[, .(Date, Ticker, score = M26_Revenue_Mom)]
size_dt <- RAWME[, .(Date, Ticker, Size)]
suppressMessages(source(file.path(SC, "csb_old.R")))
r_old <- suppressWarnings(canonical_screen_bt(S_raw, o$returns_dt, o$bench_dt, top_n = 25L,
          cost_bps_oneway = 15, liq_dt = lo, liq_min = 2e8, run_id = "par", strategy_id = "par",
          diag_dual_basis = TRUE, size_dt = size_dt))
suppressMessages(source("02_Infrastructure/contracts/canonical_screen_bt.R"))
r_new <- suppressWarnings(canonical_screen_bt(S_raw, n$returns_dt, n$bench_dt, top_n = 25L,
          cost_bps_oneway = 15, liq_dt = ln, liq_min = 2e8, run_id = "par", strategy_id = "par",
          diag_dual_basis = TRUE, size_dt = size_dt))
common <- intersect(names(r_old), names(r_new))
diffs <- common[!vapply(common, function(k) isTRUE(all.equal(r_old[[k]], r_new[[k]])), logical(1))]
say("=== canonical_screen_bt parity ===")
say("  공통 필드 %d개 · 불일치 %d개 [%s]", length(common), length(diffs), paste(diffs, collapse=","))
say("  신규 필드: [%s]", paste(setdiff(names(r_new), names(r_old)), collapse=", "))
say("  PORT_t: old %+.6f · new %+.6f · Δ %.3g", r_old$portfolio_alpha_t_nw_lag3,
    r_new$portfolio_alpha_t_nw_lag3,
    r_new$portfolio_alpha_t_nw_lag3 - r_old$portfolio_alpha_t_nw_lag3)

## ── 3. 자 불일치의 시대 분포 (어느 측정창이 면역인가) ────────────────────────
ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
res <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
CMP <- merge(ln[, .(Date, Ticker, adv_deg = adv)], res$liq_dt[, .(Date, Ticker, adv_res = adv)],
             by = c("Date","Ticker"), all = TRUE)
LM <- 2e8
CMP[, `:=`(p_deg = is.na(adv_deg) | adv_deg >= LM, p_res = is.na(adv_res) | adv_res >= LM)]
CMP[, era := fifelse(Date < as.Date("2005-01-01"), "~2004",
              fifelse(Date < as.Date("2010-01-01"), "2005-09",
               fifelse(Date < as.Date("2017-01-01"), "2010-16", "2017~")))]
ERA <- CMP[, .(n = .N, disagree = sum(p_deg != p_res), pct = 100*mean(p_deg != p_res),
               only_deg = sum(p_deg & !p_res), only_res = sum(!p_deg & p_res)), by = era][order(era)]
print(ERA); fwrite(ERA, file.path(OUT, "p2_era_disagreement.csv"))
MZERO <- CMP[, .(dis = sum(p_deg != p_res)), by = Date]
say("자 불일치 0인 달 %d / %d (%.1f%%) = 구조적 면역", sum(MZERO$dis == 0), nrow(MZERO),
    100*mean(MZERO$dis == 0))

## 멤버십 변동의 시대 분포 (M26 raw, P1 산출 재사용)
MD <- fread(file.path(OUT, "p1_membership_delta_m26raw.csv"))
MD[, Date := as.Date(Date)]
MD[, era := fifelse(Date < as.Date("2005-01-01"), "~2004",
             fifelse(Date < as.Date("2010-01-01"), "2005-09",
              fifelse(Date < as.Date("2017-01-01"), "2010-16", "2017~")))]
MDE <- MD[, .(months = .N, changed = sum(n_changed > 0), pct = 100*mean(n_changed > 0),
              mean_swap = mean(n_changed)), by = era][order(era)]
print(MDE); fwrite(MDE, file.path(OUT, "p2_era_membership.csv"))

saveRDS(list(liq_value_parity = list(key_same = key_same, max_abs = val_max, na_same = val_na),
             csb_diffs = diffs, csb_new_fields = setdiff(names(r_new), names(r_old)),
             era = ERA, era_memb = MDE,
             immune_months = sum(MZERO$dis == 0), total_months = nrow(MZERO)),
        file.path(OUT, "p2_results.rds"))
say("완료")
