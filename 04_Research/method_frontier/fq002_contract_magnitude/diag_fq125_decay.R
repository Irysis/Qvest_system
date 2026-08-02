# diag_fq125_decay.R — 부기간 감쇠 성격 진단 (WT-D20260802_023 후속, 기지불 데이터만)
#   질문: last12 IC 약화(0.1216→0.0395)가 ①커버리지 팽창 아티팩트인가
#         ②mega-cap 랠리 국면 연동인가 ③신호 산포 붕괴인가 — 확정 수치는 불변, 해석 진단만.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"

J  <- fromJSON(file.path(OUTD, "fq125_confirm_results.json"), simplifyVector = TRUE)
ic <- as.data.table(J$ic_series$A_size); ic[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "grid_bench.parquet"))); Bg[, Date := as.Date(Date)]

panelA <- as.data.table(read_parquet(file.path(OUTD, "panel_A.parquet")))
MEM <- as.data.table(read_parquet(file.path(OUTD, "grid_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
Lg  <- as.data.table(read_parquet(file.path(OUTD, "grid_liq.parquet")));  Lg[, Date := as.Date(Date)]
Rg  <- as.data.table(read_parquet(file.path(OUTD, "grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ  <- MEM[, .(Date, Ticker, Size)]
ym_of <- function(d) format(d, "%Y%m")
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]

# 스코어 재구성 (run_fq125_confirm.R 동일 로직 — 확정 수치 재판정 아님, 단면 특성 진단용)
S <- merge(me_dates, panelA[, .(ym, Ticker, w_amt)], by = "ym")
S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
S <- S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0]

D <- merge(ic, Bg, by = "Date")                       # ic + BM_Ret
disp <- S[, .(disp = sd(log(score))), by = Date]      # 단면 신호 산포
D <- merge(D, disp, by = "Date")
setorder(D, Date)
D[, half := rep(c("first12", "last12"), each = 12)]

# 신규 편입 종목 비중 (직전 3개월 미커버 → 당월 커버)
S[, k := paste(Ticker)]
cov_list <- split(S$Ticker, S$Date)
dates <- sort(unique(S$Date))
newshare <- data.table(Date = dates, new_share = NA_real_)
for (i in seq_along(dates)) {
  if (i <= 3) next
  prev <- unique(unlist(cov_list[(i-3):(i-1)]))
  cur  <- cov_list[[i]]
  newshare$new_share[i] <- mean(!(cur %in% prev))
}
D <- merge(D, newshare, by = "Date", all.x = TRUE)

r_ic_n     <- cor(D$ic, D$n)
r_ic_bench <- cor(D$ic, D$BM_Ret)
r_ic_disp  <- cor(D$ic, D$disp)
up_big <- D[BM_Ret > 0.05]; other <- D[BM_Ret <= 0.05]

cat(sprintf("[diag] corr(IC, n_cov)      = %+.3f  (first12 평균 n=%.0f / last12 n=%.0f)\n",
            r_ic_n, mean(D[half=="first12", n]), mean(D[half=="last12", n])))
cat(sprintf("[diag] corr(IC, BM_Ret)  = %+.3f\n", r_ic_bench))
cat(sprintf("[diag] bench>+5%% 월(%d개월) mean IC = %+.4f | 그 외(%d개월) = %+.4f\n",
            nrow(up_big), mean(up_big$ic), nrow(other), mean(other$ic)))
cat(sprintf("[diag] corr(IC, 산포)       = %+.3f  (산포 first12=%.3f / last12=%.3f)\n",
            r_ic_disp, mean(D[half=="first12", disp]), mean(D[half=="last12", disp])))
cat(sprintf("[diag] 신규편입 비중 first12=%.3f / last12=%.3f | corr(IC, new_share)=%+.3f\n",
            mean(D[half=="first12", new_share], na.rm=TRUE), mean(D[half=="last12", new_share], na.rm=TRUE),
            cor(D$ic, D$new_share, use="complete.obs")))

out <- list(
  measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "last12 감쇠 성격 진단 — 확정 수치(alpha_validation) 불변, 해석 전용",
  corr_ic_ncov = r_ic_n, corr_ic_bench = r_ic_bench, corr_ic_dispersion = r_ic_disp,
  corr_ic_newshare = cor(D$ic, D$new_share, use = "complete.obs"),
  ncov_first12 = mean(D[half=="first12", n]), ncov_last12 = mean(D[half=="last12", n]),
  disp_first12 = mean(D[half=="first12", disp]), disp_last12 = mean(D[half=="last12", disp]),
  newshare_first12 = mean(D[half=="first12", new_share], na.rm=TRUE),
  newshare_last12  = mean(D[half=="last12", new_share], na.rm=TRUE),
  ic_bench_up5 = list(n = nrow(up_big), mean_ic = mean(up_big$ic)),
  ic_bench_other = list(n = nrow(other), mean_ic = mean(other$ic)),
  monthly = D[, .(Date = as.character(Date), ic, n, BM_Ret, disp, new_share, half)]
)
write_json(out, file.path(OUTD, "fq125_decay_diag.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null")
cat("[diag] → ", file.path(OUTD, "fq125_decay_diag.json"), "\n")
