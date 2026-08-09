## P1 — 배선한 3축의 실경보량 dry-run + 문턱 민감도
##
## 입력 재구성 (재빌드 금지 · parquet 직접 read 금지):
##   커버된 행 = load_month_factors(coverage_min=0)  → 커넥터는 Coverage==TRUE &
##               !is.na(Z_Score) 만 반환하므로(factor_db_connector.R:261) 이게 곧 소비면.
##   죽은 행   = emission_ledger.csv 의 n_rows>0 인데 커넥터 비가시인 팩터 → Coverage=FALSE 로 합성.
##   ⇒ 빌더가 write 직전에 쥐는 `result` 와 (Factor_Name, Ticker, Z_Score, Coverage) 면에서 동형.
##
## ★값 면 주의: 커넥터는 Z_Score_Aligned(= Z_Score * ic_sign 후 재표준화)를 준다.
##   부호 반전과 양수 스칼라 배는 **랭크와 동률 구조를 보존**하므로 축 T(modal_frac)·
##   축 I(|rho|) 의 계산값은 빌더의 Z_Score 위에서와 동일하다. 축 D 는 Coverage 만 본다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/emission_guard_identity_axes_20260809")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
t0 <- Sys.time()

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/emission_guard.R")

REGISTRY  <- "02_Infrastructure/factor_db/factor_registry.json"
IDBASE    <- "02_Infrastructure/factor_db/emission_declared_identity.json"
DEDUP     <- emission_dedup_pairs(REGISTRY)
IDB       <- emission_load_identity_baseline(IDBASE)
say("registry 선언 중복 쌍 %s개 · 정체 선언 래칫 %d항목 (미조사 %d)",
    format(length(DEDUP), big.mark = ","), nrow(IDB), sum(!IDB$diagnosed))

MONTHS <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30",
                    "2018-06-30", "2022-06-30", "2026-06-30"))
led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))

build_result <- function(d) {
  z  <- load_month_factors(d, coverage_min = 0)
  ymf <- sub("^factor_db_([0-9]{6})[.]parquet$", "\\1", attr(z, "factor_db_file"))
  zt <- as.data.table(z)
  live <- zt[, .(Ticker, Factor_Name, Raw_Value = Z_Score_Aligned,
                 Z_Score = Z_Score_Aligned, Coverage = TRUE)]
  ls_ <- led[ym == ymf & n_rows > 0, .(Factor_Name, n_rows, n_tickers)]
  invis <- ls_[!Factor_Name %in% unique(zt$Factor_Name)]
  tick <- unique(zt$Ticker)
  deadrows <- if (nrow(invis) == 0L) live[0L] else rbindlist(lapply(seq_len(nrow(invis)), function(i) {
    n <- min(invis$n_tickers[i], length(tick))
    data.table(Ticker = tick[seq_len(max(n, 1L))], Factor_Name = invis$Factor_Name[i],
               Raw_Value = 1.0, Z_Score = NA_real_, Coverage = FALSE)
  }))
  list(ym = ymf, result = rbindlist(list(live, deadrows), use.names = TRUE))
}

reps <- list(); Tstat <- list(); Istat <- list(); Dstat <- list()
for (d in MONTHS) {
  d <- as.Date(d, origin = "1970-01-01")
  br <- build_result(d)
  tt <- Sys.time()
  r  <- factor_identity_check(br$result, br$ym, dedup_pairs = DEDUP, identity_baseline = IDB)
  el <- as.numeric(difftime(Sys.time(), tt, units = "secs"))
  reps[[br$ym]] <- r
  say("%s | 행 %s · 팩터 %d | D: 미선언 %d (선언 %d) · T: warn %d / watch %d · I: hit %d 중 미선언 %d | %.2fs · %s",
      br$ym, format(nrow(br$result), big.mark = ","), uniqueN(br$result$Factor_Name),
      length(r$axis_D$dead), length(r$axis_D$dead_declared),
      length(r$axis_T$tie_warn), length(r$axis_T$tie_watch),
      r$axis_I$n_pairs_hit, nrow(r$axis_I$undeclared), el, r$verdict)
  if (length(r$axis_D$dead)) say("     D 미선언 → %s", paste(r$axis_D$dead, collapse = ", "))
  if (length(r$axis_T$tie_warn)) say("     T warn  → %s", paste(r$axis_T$tie_warn, collapse = ", "))
  if (nrow(r$axis_I$undeclared)) say("     I 미선언 → %s",
      paste(sprintf("%s~%s(%.6f)", r$axis_I$undeclared$factor_a, r$axis_I$undeclared$factor_b,
                    r$axis_I$undeclared$abs_rho), collapse = ", "))
  if (nrow(r$axis_T$detail)) Tstat[[br$ym]] <- copy(r$axis_T$detail)[, ym := br$ym]
  if (nrow(r$axis_I$detail)) Istat[[br$ym]] <- copy(r$axis_I$detail)[, ym := br$ym]
  Dstat[[br$ym]] <- copy(r$axis_D$detail)[, ym := br$ym]
}
TS <- rbindlist(Tstat); IS <- rbindlist(Istat); DS <- rbindlist(Dstat)
fwrite(TS, file.path(OUT, "p1_axisT_modal_frac.csv"))
fwrite(IS, file.path(OUT, "p1_axisI_pairs.csv"))
fwrite(DS, file.path(OUT, "p1_axisD_coverage.csv"))

say("")
say("=== 문턱 민감도 — 축 T (월평균 경보 건수) ===")
for (th in c(0.90, 0.95, 0.99, 0.995)) {
  n <- TS[modal_frac >= th, .N] / uniqueN(TS$ym)
  fl <- sort(unique(TS[modal_frac >= th, Factor_Name]))
  say("  modal_frac >= %.3f : 월평균 %.2f건 · 고유 팩터 %d종%s", th, n, length(fl),
      if (length(fl) && length(fl) <= 6) sprintf(" (%s)", paste(fl, collapse = ",")) else "")
}
say("")
say("=== 문턱 민감도 — 축 I (선언 대조 유/무. ★대조 없으면 소음이 된다) ===")
say("  %-10s %10s %10s %10s", "|rho| >=", "총 hit", "선언", "미선언")
for (th in c(0.99, 0.995, 0.999, 0.9999)) {
  s <- IS[abs_rho >= th]
  say("  %-10.4f %10.1f %10.1f %10.1f", th, nrow(s) / uniqueN(IS$ym),
      s[declared == TRUE, .N] / uniqueN(IS$ym), s[declared == FALSE, .N] / uniqueN(IS$ym))
}
say("")
say("=== 축 I 미선언 쌍 전체 (월 등장 횟수) ===")
und <- IS[declared == FALSE, .(n_months = .N, max_rho = max(abs_rho), min_rho = min(abs_rho),
                               yms = paste(ym, collapse = " ")), by = .(factor_a, factor_b)]
setorder(und, -n_months, -max_rho)
print(und)
say("")
say("=== 축 D 팩터별 (미선언만) ===")
print(DS[dead == TRUE & !Factor_Name %in% IDB[axis == "D", factor],
         .(n_months = .N, med_rows = as.numeric(median(n_rows)), yms = paste(ym, collapse = " ")),
         by = Factor_Name])
say("")
say("=== 계측 생존 (stat_liveness = 팩터간 modal_frac 의 sd. 0 이면 계측 사망) ===")
for (y in names(reps)) say("  %s  axis_T sd(modal_frac) = %.6f · status %s",
                           y, reps[[y]]$axis_T$stat_liveness, reps[[y]]$axis_T$status)
say("총 %.1fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))
