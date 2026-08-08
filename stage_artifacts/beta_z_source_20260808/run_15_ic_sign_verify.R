## run_15 — next_probe ①: R05_Tail_Risk 의 forward-return IC 부호가 2016년에 실제로 뒤집혔는가
##
## 왜: live(IC-추종) 방향과 동결(고정) 방향이 2016~2026-04 에 11년 연속 반전 상태다(run_14).
##     어느 쪽이 옳은지의 현 근거는 SR 우열(1.8589 vs 1.8092)뿐 = 간접. 데이터에 직접 묻는다.
## 설계: 정렬 **이전**의 raw Z_Score 를 쓴다(정렬은 방향을 이미 입히므로 순환논증이 된다).
##       월별 횡단면 Spearman IC = cor(z_raw(t), forward 1M return(t→t+1)).
##       구간별 평균 IC 부호로 판정: 2016 이후 부호가 뒤집혔으면 live 방향이 데이터 정합.
## ★이 측정은 진단용 IC 다 — 전략 신호가 아니라 방향 규약의 사후 검증(PIT 대상 아님, 라벨 diagnostic).
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(R)

## ── 1) 월별 forward 1M 수익률 (월말 Close 기준)
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Close")))
raw[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
setorder(raw, Ticker, Date)
mo <- raw[, .(Close = last(Close)), by = .(Ticker, ym)]
setorder(mo, Ticker, ym)
mo[, fwd_ret := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]
mo <- mo[is.finite(fwd_ret)]
cat(sprintf("[수익률] %d행 · %s ~ %s · 티커 %d\n", nrow(mo), min(mo$ym), max(mo$ym), uniqueN(mo$Ticker)))

## ── 2) 월별 raw R05 z (정렬 전) — factor_db vintage 그대로
fdb <- sort(list.files(".cache/factor_db", pattern = "^factor_db_[0-9]{6}\\.parquet$", full.names = TRUE))
yms <- sub(".*factor_db_([0-9]{4})([0-9]{2})\\.parquet$", "\\1-\\2", fdb)
keep <- yms >= "2004-01" & yms <= "2026-07"
fdb <- fdb[keep]; yms <- yms[keep]
cat(sprintf("[팩터DB] %d개월 (%s ~ %s)\n\n", length(fdb), min(yms), max(yms)))

ic <- rbindlist(lapply(seq_along(fdb), function(k) {
  f <- tryCatch(as.data.table(read_parquet(fdb[k], col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)
  z <- f[Factor_Name == "R05_Tail_Risk" & Coverage == TRUE & !is.na(Z_Score), .(Ticker, z_raw = Z_Score)]
  if (nrow(z) < 30) return(NULL)
  ## 팩터 vintage ym 의 신호 → 그 다음 달 수익 (mo 의 fwd_ret 은 ym→ym+1 이므로 같은 ym 조인)
  m <- merge(z, mo[ym == yms[k], .(Ticker, fwd_ret)], by = "Ticker")
  if (nrow(m) < 30) return(NULL)
  data.table(ym = yms[k], n = nrow(m),
             ic = suppressWarnings(cor(m$z_raw, m$fwd_ret, method = "spearman", use = "complete.obs")))
}))
ic <- ic[is.finite(ic)]
ic[, yr := as.integer(substr(ym, 1, 4))]
ic[, era := ifelse(yr <= 2015, "2004-2015", "2016-2026")]
cat(sprintf("[IC] 산출 %d개월\n\n", nrow(ic)))

cat("=== 구간별 raw z 의 forward-return IC ===\n")
sm <- ic[, .(n_month = .N, ic_mean = mean(ic), ic_med = median(ic),
             pos_share = mean(ic > 0),
             t_stat = mean(ic) / (sd(ic) / sqrt(.N))), by = era]
print(sm[, .(era, n_month, ic_mean = round(ic_mean, 5), ic_med = round(ic_med, 5),
             pos_share = round(pos_share, 3), t_stat = round(t_stat, 3))])

cat("\n=== 연도별 ===\n")
print(ic[, .(n = .N, ic_mean = round(mean(ic), 5), pos = sum(ic > 0)), by = yr])

cat("\n[판정]\n")
a <- sm[era == "2004-2015"]; b <- sm[era == "2016-2026"]
if (nrow(a) && nrow(b)) {
  cat(sprintf("  2004-2015 평균 IC %+.5f (t=%+.2f) · 2016-2026 평균 IC %+.5f (t=%+.2f)\n",
              a$ic_mean, a$t_stat, b$ic_mean, b$t_stat))
  if (sign(a$ic_mean) != sign(b$ic_mean) && abs(b$t_stat) > 2) {
    cat("  ★부호 반전 확정(2016+ 유의) — live(IC-추종) 방향이 데이터 정합.\n")
    cat("    ⇒ 동결 고정방향 위에 놓인 계약 rds 앵커 269개월은 2016+ 구간에서 반대 부호 기준이다.\n")
  } else if (sign(a$ic_mean) != sign(b$ic_mean)) {
    cat("  부호는 반전했으나 2016+ 유의성 약함(|t|<2) — live 우위 '시사'이나 확정 아님.\n")
  } else {
    cat("  ★부호 반전 없음 — 11년 반전의 원인은 IC 부호가 아니다(정렬 절차/레지스트리 쪽 재조사 필요).\n")
  }
}
fwrite(ic, "stage_artifacts/beta_z_source_20260808/ic_sign_verify.csv")
cat("\n[저장] ic_sign_verify.csv\n")
