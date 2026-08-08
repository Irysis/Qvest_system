## run_14 — 동결 기준 vs live 기준의 부호 역전이 언제 시작됐나 (연도별 스윕)
## 동기: 앵커된 역사 269개월(계약 rds)이 어느 기준 위에 있는지가 결정 ①(rds 재도출 여부)의 근거다.
## ★정본 사용법: raw parquet 직접 읽기 → align 1회.
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(R)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"))
reg <- .load_registry()

live_one <- function(sig) {
  fp <- file.path(R, sprintf(".cache/factor_db/factor_db_%s.parquet", format(as.Date(sig) - 1L, "%Y%m")))
  if (!file.exists(fp)) return(NULL)
  f <- as.data.table(read_parquet(fp, col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
  r <- f[Factor_Name == "R05_Tail_Risk" & Coverage == TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(r)) return(NULL)
  r[, sig_date := as.Date(sig)]
  ra <- align_factor_direction(r, reg, sig_date = as.Date(sig), min_ic_months = 12L)
  if ("Z_Score_Aligned" %in% names(ra)) ra[, Z_Score := Z_Score_Aligned]
  ra[, .(Ticker, z_live = Z_Score)]
}

## 동결 패널이 실제로 가진 신호일 중 매년 2개(1월·7월 근사) 표집
fd <- sort(unique(frz$Date))
pick <- unlist(lapply(split(fd, format(fd, "%Y")), function(v) as.character(v[unique(c(1, ceiling(length(v)/2)))])))
sigs <- as.Date(unique(pick))
cat(sprintf("[표집] %d개 신호일 (%s ~ %s)\n\n", length(sigs), min(sigs), max(sigs)))

res <- rbindlist(lapply(sigs, function(s) {
  fz <- frz[Date == s, .(Ticker, zf = R05_Tail_Risk_Z)]
  lz <- live_one(s)
  if (is.null(lz) || nrow(fz) < 3) return(NULL)
  m <- merge(fz, lz, by = "Ticker")
  if (nrow(m) < 3) return(NULL)
  data.table(Date = s, n_f = nrow(fz), n_m = nrow(m),
             rank = suppressWarnings(cor(m$zf, m$z_live, method = "spearman", use = "complete.obs")))
}))
res[, yr := as.integer(format(Date, "%Y"))]
cat("=== 연도별 per-ticker rank 상관 (동결 vs live) ===\n")
print(res[, .(n_obs = .N, rank_min = round(min(rank), 3), rank_med = round(median(rank), 3),
              rank_max = round(max(rank), 3), n_frozen_med = median(n_f)), by = yr])

cat("\n[부호 전환 지점]\n")
setorder(res, Date)
flips <- which(diff(sign(res$rank)) != 0)
if (length(flips)) {
  for (k in flips) cat(sprintf("  %s (%+.3f) → %s (%+.3f)\n",
                               res$Date[k], res$rank[k], res$Date[k+1], res$rank[k+1]))
} else cat("  전환 없음\n")

pos <- res[rank > 0]; neg <- res[rank < 0]
cat(sprintf("\n[요약] 양(+) %d건 · 음(−) %d건\n", nrow(pos), nrow(neg)))
if (nrow(neg)) cat(sprintf("  음의 구간: %s ~ %s\n", min(neg$Date), max(neg$Date)))
cat(sprintf("\n[함의] 계약 rds 앵커 범위 = 2004-02 ~ 2026-06. 그중 동결≡live 인 구간과\n"))
cat(sprintf("       기준이 반대인 구간이 섞여 있으면, 앵커된 역사는 **단일 기준이 아니다**.\n"))
fwrite(res, "stage_artifacts/beta_z_source_20260808/basis_flip_sweep.csv")
cat("\n[저장] basis_flip_sweep.csv\n")
