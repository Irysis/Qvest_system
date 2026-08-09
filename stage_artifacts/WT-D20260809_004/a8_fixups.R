## A8 — (a) F4 λ=1.0 백분위 재산출(as.character(1.0)=="1" 조회 실패 수리)
##      (b) 상속 상관 — base 패널 Date 는 월초 라벨이라 ym 키로 결합
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A8] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
S <- readRDS(file.path(OUT, "stress.rds")); L <- readRDS(file.path(OUT, "layers.rds"))
SC <- L$SC

say("=== (a) F4 백분위 재산출 ===")
for (lam in c(0.5, 1.0)) {
  p <- S$PL[[sprintf("b12_l%.1f", lam)]]
  o <- if (lam == 0.5) S$i05$ann else S$i10$ann
  say("  λ=%.1f 실측 %+.3f%% · 플라시보 평균 %+.3f%% sd %.3f · 백분위 %.1f%% · 95분위 %+.3f%% → %s",
      lam, o, mean(p$ann), sd(p$ann), 100*mean(p$ann < o), quantile(p$ann, .95),
      if (o > quantile(p$ann, .95)) "95분위 초과" else "95분위 이하")
  say("       플라시보 t 분포: 평균 %+.2f · 95분위 %+.2f · 실측 t %+.2f",
      mean(p$t), quantile(p$t, .95), if (lam == 0.5) S$i05$t else S$i10$t)
}

say("")
say("=== (b) 상속 상관 (ym 키 결합) ===")
BASE <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
BASE[, ym := format(as.Date(Date), "%Y%m")]
MY <- copy(SC)[, ym := format(sig_date, "%Y%m")]
say("  base ym %d개 (%s~%s) · my ym %d개 (%s~%s)",
    uniqueN(BASE$ym), min(BASE$ym), max(BASE$ym), uniqueN(MY$ym), min(MY$ym), max(MY$ym))
safe_ic <- function(a, b, minn = 30L) {
  ok <- is.finite(a) & is.finite(b); if (sum(ok) < minn) return(NA_real_)
  suppressWarnings(stats::cor(a[ok], b[ok], method = "spearman"))
}
MM <- merge(MY[, .(ym, Ticker, growth)], BASE[, .(ym, Ticker, score_eff)], by = c("ym","Ticker"))
say("  교집합 %s행 · %d월 · 월평균 %.0f종목",
    format(nrow(MM), big.mark=","), uniqueN(MM$ym), nrow(MM)/uniqueN(MM$ym))
cs <- MM[, .(rho = safe_ic(growth, score_eff)), by = ym][!is.na(rho)]
say("  growth vs score_eff 월별 횡단면 Spearman: 평균 %+.4f · sd %.3f · n=%d월 → 0.95 문턱 %s",
    mean(cs$rho), sd(cs$rho), nrow(cs), if (abs(mean(cs$rho)) < 0.95) "PASS" else "FAIL")
ov <- MM[, { a <- Ticker[frank(-growth, ties.method="first") <= 25]
             b <- Ticker[frank(-score_eff, ties.method="first") <= 25]
             .(ov = length(intersect(a,b))) }, by = ym]
say("  top-25 이름 중복 평균 %.2f / 25 (중앙 %d · 최대 %d)", mean(ov$ov), as.integer(median(ov$ov)), max(ov$ov))
say("  ⚠ base 패널 = 저장 파생 패널(production_parity 미검증). 상속-중복 판별 진단 전용,")
say("     book-marginal 주장 금지 (2026-07-14 동월 look-ahead 계통).")
saveRDS(list(inh_mean = mean(cs$rho), inh_sd = sd(cs$rho), inh_n = nrow(cs),
             top25_overlap = mean(ov$ov)), file.path(OUT, "inherit.rds"))
