## WT-R20260829_006 Phase 6 — PIT 하드 게이트(detect_lookahead) + alpha_inheritance_cor
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/validation/lookahead_detector.R")
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
ART <- "stage_artifacts/WT_R20260829_006"

## ── 1. detect_lookahead — 전 엔진 파일 ────────────────────────────────────────
files <- list.files(file.path(ART,"engine"), pattern = "\\.R$", full.names = TRUE)
pit <- lapply(files, function(f) {
  r <- detect_lookahead(f, verbose = FALSE)
  list(file = basename(f), clean = r$clean, scanned = r$scanned,
       n_violations = r$n_violations,
       violations = lapply(r$violations, function(v) list(check=v$check, line=v$line, msg=v$msg)))
})
for (p in pit) cat(sprintf("[detect_lookahead] %-24s clean=%s scanned=%s n_viol=%d\n",
  p$file, as.character(p$clean), as.character(p$scanned), p$n_violations))
for (p in pit) if (p$n_violations > 0) { cat("  ---", p$file, "---\n")
  for (v in p$violations) cat(sprintf("   %s L%d: %s\n", v$check, v$line, v$msg)) }
all_clean <- all(vapply(pit, function(p) isTRUE(p$clean), logical(1)))
cat("[detect_lookahead] ALL CLEAN =", all_clean, "\n\n")

## ── 2. alpha_inheritance_cor — 기저 JT1993 6-6 모멘텀 신호 대비 ───────────────
M <- readRDS(file.path(OUT,"p1s_market.rds"))
SCP <- as.data.table(read_parquet(file.path(ART,"alpha_scores.parquet")))[layer=="history"]
R <- M$RET_DT[, .(Ticker, Date, r = Ret_1m)]
setorder(R, Ticker, Date)
dts <- sort(unique(R$Date))
RW <- dcast(R, Date ~ Ticker, value.var = "r"); setorder(RW, Date)
Rm <- as.matrix(RW[, -1, with = FALSE]); lg <- log1p(Rm)
cum6 <- matrix(NA_real_, nrow(Rm), ncol(Rm), dimnames = dimnames(Rm))
for (i in seq_len(nrow(Rm))) {                     # JT1993 6-6: 형성 6개월(스킵 없음)
  lo <- i-5L; if (lo < 1) next
  blk <- lg[lo:i, , drop = FALSE]
  ok <- colSums(!is.na(blk)) >= 5L
  s <- colSums(blk, na.rm = TRUE); s[!ok] <- NA_real_
  cum6[i, ] <- expm1(s)
}
MOM6 <- as.data.table(cum6); MOM6[, Date := RW$Date]
MOM6 <- melt(MOM6, id.vars="Date", variable.name="Ticker", value.name="mom6",
             variable.factor=FALSE)[!is.na(mom6)]
J <- merge(SCP[, .(Date, Ticker, score)], MOM6, by = c("Date","Ticker"))
cs <- J[, .(rho = suppressWarnings(cor(score, mom6, method="spearman")),
            rho_p = suppressWarnings(cor(score, mom6)), n = .N), by = Date][is.finite(rho)]
inh_spear <- mean(cs$rho); inh_pear <- mean(cs$rho_p, na.rm = TRUE)
cat(sprintf("[inheritance] 기저 JT1993 6-6 모멘텀 신호 대비 월평균 Spearman %.4f (Pearson %.4f, n_months %d)\n",
            inh_spear, inh_pear, nrow(cs)))
cat(sprintf("[inheritance] 월별 |rho| 최대 %.4f · 최소 %.4f\n", max(abs(cs$rho)), min(abs(cs$rho))))

res <- list(detect_lookahead = pit, all_clean = all_clean,
            alpha_inheritance = list(
              parent = "RP_20260829_122020_9192 (JT1993 6-6 개별주 모멘텀 · essence F)",
              proxy = "기저 정렬변수(6개월 누적수익, 스킵 없음)와 본 스코어의 월별 횡단면 상관 평균",
              spearman_mean = inh_spear, pearson_mean = inh_pear,
              n_months = nrow(cs), max_abs = max(abs(cs$rho)), min_abs = min(abs(cs$rho))))
saveRDS(res, file.path(OUT,"p6s_pit.rds"))
write(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=8, na="null"), file.path(OUT,"p6s_pit.json"))
cat("\n[done] phase6\n")
