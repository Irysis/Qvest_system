## P2 — 축 I 문턱 민감도 (정정 재측정)
##
## ★p1 의 민감도 표는 무효였다: axis_I$detail 은 이미 rho_warn 에서 잘린 집합이라
##   0.99/0.995 행이 0.999 집합을 다시 센 것에 불과했다. 문턱을 **낮춰서** 다시 잰다.
##   (필터된 산출물 위에서 문턱을 훑으면 항상 "문턱 무관"이라는 그럴듯한 평평한 표가 나온다.)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/emission_guard_identity_axes_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/emission_guard.R")

DEDUP <- emission_dedup_pairs("02_Infrastructure/factor_db/factor_registry.json")
IDB   <- emission_load_identity_baseline("02_Infrastructure/factor_db/emission_declared_identity.json")
MONTHS <- as.Date(c("2005-06-30", "2014-06-30", "2022-06-30", "2026-06-30"))

acc <- list()
for (d in MONTHS) {
  d <- as.Date(d, origin = "1970-01-01")
  z <- load_month_factors(d, coverage_min = 0)
  ymf <- sub("^factor_db_([0-9]{6})[.]parquet$", "\\1", attr(z, "factor_db_file"))
  zt <- as.data.table(z)
  res <- zt[, .(Ticker, Factor_Name, Raw_Value = Z_Score_Aligned,
                Z_Score = Z_Score_Aligned, Coverage = TRUE)]
  r <- factor_identity_check(res, ymf, dedup_pairs = DEDUP, identity_baseline = IDB,
                             rho_warn = 0.95)          # ★낮춰서 전 분포를 본다
  acc[[ymf]] <- copy(r$axis_I$detail)[, ym := ymf]
  say("%s: |rho| >= 0.95 인 쌍 %d개", ymf, nrow(r$axis_I$detail))
}
IS <- rbindlist(acc)
fwrite(IS, file.path(OUT, "p2_axisI_full_distribution.csv"))
nm <- uniqueN(IS$ym)

say("")
say("=== 축 I 문턱 민감도 (월평균 건수) ===")
say("  %-9s %9s %9s %9s   %s", "|rho|>=", "총", "선언", "미선언", "판단")
for (th in c(0.95, 0.98, 0.99, 0.995, 0.999, 0.9999)) {
  s <- IS[abs_rho >= th]
  u <- s[declared == FALSE, .N] / nm
  say("  %-9.4f %9.1f %9.1f %9.1f   %s", th, nrow(s) / nm,
      s[declared == TRUE, .N] / nm, u,
      if (u > 15) "소음 — 무시된다" else if (u > 8) "경계" else "실행가능")
}
say("")
say("=== 미선언 쌍의 |rho| 분포 (문턱을 어디에 둘지의 근거) ===")
u <- IS[declared == FALSE, .(n_months = .N, max_rho = max(abs_rho), min_rho = min(abs_rho)),
        by = .(factor_a, factor_b)][order(-max_rho)]
say("  미선언 고유 쌍 %d개 · max_rho 분위: %s", nrow(u),
    paste(sprintf("%.4f", quantile(u$max_rho, c(0, .25, .5, .75, .9, 1))), collapse = " "))
print(head(u, 14))
say("")
say("=== 선언(registry dedup) 쌍이 실제로 침묵되는가 ===")
say("  |rho|>=0.999 인 쌍 중 선언 %.1f건/월 · 미선언 %.1f건/월 → 대조가 경보를 %.1f배 줄인다",
    IS[abs_rho >= 0.999 & declared == TRUE, .N] / nm,
    IS[abs_rho >= 0.999 & declared == FALSE, .N] / nm,
    IS[abs_rho >= 0.999, .N] / max(IS[abs_rho >= 0.999 & declared == FALSE, .N], 1))
