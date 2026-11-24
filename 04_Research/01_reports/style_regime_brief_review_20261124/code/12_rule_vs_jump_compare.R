## 12_rule_vs_jump_compare.R — 같은 시험 구간에서 세 판독 비교: 옛 부호 규칙 · 새 t 규칙(|t|≥등록부 문턱) · 점프 모형(6개월마다 재선택)
##   지표: 상태 바뀜/년 · 판독 지속 중앙값 · 다음 21 · 63일 부호 적중(단정한 날만) · 가상 롱숏 샤프(Shu · Mulvey §3.2 과 같은 2일 지연 · 5bp —
##   t 규칙은 단정 = ±100% · 불분명 = 0, 부호 규칙 = 부호대로 ±100%). 판독은 모두 그날까지의 자료(as-of)로만 만들어졌다.
##   인자: <04 산출 replay_daily.rds> <style_jump_test_paths.rds> <출력 csv> <운영 루트(등록부)>
suppressMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
RP <- readRDS(a[1]); JP <- readRDS(a[2]); OUTF <- a[3]; QM <- a[4]
T_SIG <- as.numeric(fromJSON(file.path(QM, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation[["grade_b_min_portfolio_alpha_t"]])
RP <- as.data.table(RP); setorder(RP, Date)
fwd <- function(x, h) { n <- length(x); cs <- c(0, cumsum(log1p(x))); o <- rep(NA_real_, n); i <- seq_len(n - h); o[i] <- exp(cs[i + h + 1] - cs[i + 1]) - 1; o }
ls_sharpe <- function(pos, r) { pl <- shift(pos, 2L, fill = 0); x <- pl * r - 5e-4 * abs(pl - shift(pl, 1L, fill = 0))
  x <- x[is.finite(x)]; if (sd(x) == 0) NA_real_ else mean(x) / sd(x) * sqrt(252) }
met <- function(rule, f, st, r, dates) {
  ok <- !is.na(st); st <- st[ok]; r <- r[ok]; dates <- dates[ok]
  yrs <- as.numeric(diff(range(dates))) / 365.25; rl <- rle(st)
  f21 <- fwd(r, 21); f63 <- fwd(r, 63); dec <- st != 0
  data.table(factor = f, rule = rule, from = min(dates), to = max(dates),
             changes_per_year = round(sum(diff(st) != 0) / yrs, 2), median_run_days = median(rl$lengths),
             claim_share = round(mean(dec), 3),
             hit21_claims = round(mean(sign(f21[dec]) == st[dec], na.rm = TRUE), 3),
             hit63_claims = round(mean(sign(f63[dec]) == st[dec], na.rm = TRUE), 3),
             ls_sharpe = round(ls_sharpe(st, r), 2), hold_sharpe = round(ls_sharpe(rep(1, length(r)), r), 2))
}
out <- list()
for (f in names(JP)) {
  te <- as.data.table(JP[[f]]$test); d0 <- min(te$Date)
  R <- RP[Date >= d0]
  w <- R[[paste0("w_", f)]]; sdv <- frollapply(RP[[f]], 252, sd, align = "right")[RP$Date >= d0]
  t <- w / (sdv * sqrt(21) / sqrt(12))
  out[[length(out) + 1]] <- met("옛 부호", f, sign(w), R[[f]], R$Date)
  out[[length(out) + 1]] <- met(sprintf("t 규칙(|t|>=%.1f)", T_SIG), f, ifelse(abs(t) >= T_SIG, sign(t), 0), R[[f]], R$Date)
  out[[length(out) + 1]] <- met("점프 모형", f, te$state, te$r, te$Date)
}
O <- rbindlist(out); print(O); fwrite(O, OUTF)
