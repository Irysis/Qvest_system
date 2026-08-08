## run_10 — 북 z 원천을 live(factor_db)로 통일했을 때의 영향 실측 (도훈 승인 "live 통일")
##
## 설계: **단일 축만 바꾼다** — z 원천(동결 패널 → live factor_db)만 교체하고
##       선별(top20 by score_eff, 유동성 없음)·문턱(expanding past-only q20, 과거≥12)·V5 매핑은 불변.
##       (선별까지 같이 바꾸면 어느 축이 변화를 냈는지 귀속 불가)
## 산식은 배포 레인(forward_weights_D3_M4gAE.R:106-117)과 동일하게 맞춘다:
##   factor_db_{sig_date-1일의 월}.parquet · Coverage==TRUE & !is.na(Z_Score)
##   · align_factor_direction(sig_date=해당월, min_ic_months=12L)   ← 배포와 동일 인자
## ★재정렬 금지 원칙: 여기서는 raw parquet 을 직접 읽으므로 align 1회가 정본(load_month_factors 경유 아님).
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
## ★connector 는 config.R 을 상대경로로 찾는다 — 루트에서 source 해야 한다(run_07 선례)
setwd(R)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- file.path(R, "stage_artifacts/beta_z_source_20260808")
asp <- as.data.table(read_parquet(file.path(R, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
frz <- as.data.table(read_parquet(file.path(R, "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")))
reg <- .load_registry()

dates <- sort(unique(asp$Date))
cat(sprintf("[대상] 신호일 %d개 (%s ~ %s)\n", length(dates), min(dates), max(dates)))

## ── live z 로더 (배포 산식 복제)
live_z <- function(sig) {
  ym  <- format(as.Date(sig) - 1L, "%Y%m")                      # 배포와 동일: 전월 vintage
  fp  <- file.path(R, sprintf(".cache/factor_db/factor_db_%s.parquet", ym))
  if (!file.exists(fp)) {
    fp <- file.path(R, sprintf(".cache/factor_db/factor_db_%s.parquet", format(as.Date(sig), "%Y%m")))
    if (!file.exists(fp)) return(NULL)
  }
  f <- tryCatch(as.data.table(read_parquet(fp, col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)
  r <- f[Factor_Name == "R05_Tail_Risk" & Coverage == TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(r)) return(NULL)
  r[, sig_date := as.Date(sig)]
  ra <- tryCatch(align_factor_direction(r, reg, sig_date = as.Date(sig), min_ic_months = 12L),
                 error = function(e) NULL)
  if (is.null(ra)) return(NULL)
  if ("Z_Score_Aligned" %in% names(ra)) ra[, Z_Score := Z_Score_Aligned]
  ra[, .(Ticker, z_live = Z_Score)]
}

## ── 월별 top20 (북 규약: score_eff 상위 20, 유동성 필터 없음)
mv <- asp[!is.na(score_eff)]
setorder(mv, Date, -score_eff)
top20 <- mv[, head(.SD, 20), by = Date]

rows <- vector("list", length(dates)); miss <- 0L
for (k in seq_along(dates)) {
  d  <- dates[k]
  lz <- live_z(d)
  pk <- top20[Date == d]
  zf <- merge(pk[, .(Ticker)], frz[Date == d, .(Ticker, zf = R05_Tail_Risk_Z)], by = "Ticker", all.x = TRUE)$zf
  zl <- if (is.null(lz)) NA_real_ else merge(pk[, .(Ticker)], lz, by = "Ticker", all.x = TRUE)$z_live
  if (is.null(lz)) miss <- miss + 1L
  rows[[k]] <- data.table(Date = d, regime = pk$regime_state[1],
                          n_pick = nrow(pk),
                          z_frozen = if (all(is.na(zf))) NA_real_ else mean(zf, na.rm = TRUE),
                          n_f = sum(!is.na(zf)),
                          z_live = if (all(is.na(zl))) NA_real_ else mean(zl, na.rm = TRUE),
                          n_l = sum(!is.na(zl)))
  if (k %% 50 == 0) cat(sprintf("  ... %d/%d\n", k, length(dates)))
}
s <- rbindlist(rows); setorder(s, Date)
cat(sprintf("[완료] factor_db 부재 신호일 %d건 · z_live 결측 %d건 · z_frozen 결측 %d건\n\n",
            miss, sum(is.na(s$z_live)), sum(is.na(s$z_frozen))))

## ── expanding past-only q20 (과거 관측 ≥12), 두 계열 각각 자기 역사로
exp_q20 <- function(v, need = 12L) {
  out <- rep(NA_real_, length(v))
  for (i in seq_along(v)) {
    past <- v[seq_len(i - 1L)]; past <- past[!is.na(past)]
    if (length(past) >= need) out[i] <- as.numeric(quantile(past, 0.20, na.rm = TRUE))
  }
  out
}
s[, q20_f := exp_q20(z_frozen)][, q20_l := exp_q20(z_live)]
s[, zlt_f := !is.na(z_frozen) & !is.na(q20_f) & z_frozen < q20_f]
s[, zlt_l := !is.na(z_live)   & !is.na(q20_l) & z_live   < q20_l]
bmap <- function(rg, zlt) fcase(rg == "CRISIS" & zlt, 0.30, rg == "CRISIS", 0.50,
                                rg == "CAUTION" & zlt, 0.50, rg == "CAUTION", 0.70,
                                rg %in% c("BULL","NORMAL") & zlt, 0.85, default = 1.0)
s[, beta_f := bmap(regime, zlt_f)][, beta_l := bmap(regime, zlt_l)]

cmp <- s[!is.na(q20_f) & !is.na(q20_l)]
cat("=== 원천 교체 영향 (문턱 산출 가능 구간) ===\n")
cat(sprintf("  대조 가능 월: %d\n", nrow(cmp)))
cat(sprintf("  발화(zlt) 동결 %d회 · live %d회 · 일치 %d/%d (%.1f%%)\n",
            sum(cmp$zlt_f), sum(cmp$zlt_l), sum(cmp$zlt_f == cmp$zlt_l), nrow(cmp),
            100 * mean(cmp$zlt_f == cmp$zlt_l)))
cat(sprintf("  β 동일 월: %d/%d (%.1f%%) · 평균 β 동결 %.4f vs live %.4f\n",
            sum(abs(cmp$beta_f - cmp$beta_l) < 1e-12), nrow(cmp),
            100 * mean(abs(cmp$beta_f - cmp$beta_l) < 1e-12), mean(cmp$beta_f), mean(cmp$beta_l)))
cat(sprintf("  β 차이 분포: live 가 더 낮춘 달 %d · 더 높인 달 %d\n",
            sum(cmp$beta_l < cmp$beta_f), sum(cmp$beta_l > cmp$beta_f)))
cat("\n[국면별 발화]\n")
print(cmp[, .(n = .N, zlt_frozen = sum(zlt_f), zlt_live = sum(zlt_l),
              beta_f = round(mean(beta_f), 3), beta_l = round(mean(beta_l), 3)), by = regime])
cat("\n[최근 12개월]\n")
print(tail(cmp[, .(Date, regime, z_frozen = round(z_frozen, 3), z_live = round(z_live, 3),
                   q20_f = round(q20_f, 3), q20_l = round(q20_l, 3),
                   beta_f, beta_l)], 12))

fwrite(s, file.path(OUT, "live_z_series_compare.csv"))
cat(sprintf("\n[저장] live_z_series_compare.csv (%d행)\n", nrow(s)))
