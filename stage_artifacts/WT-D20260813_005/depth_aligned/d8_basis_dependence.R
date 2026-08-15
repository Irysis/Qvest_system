## D8 — sp3 붕괴의 basis 의존성 정량 + EW-basis paired primary (자기적발 정정의 근거)
## ★cap-w 가 자본 basis(판정 불변). EW 는 v8.3 dual-basis 의무 진단이며 se_shrink 채널 포함 → 알파 증거 아님.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/backtest_result_contract.R")
DOUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"
R <- readRDS(file.path(DOUT, "d2_result.rds")); AN <- c("OBJ_RANK","OBJ_MEAN_Q5","OBJ_MEAN_DEPTH","OBJ_MED_DEPTH")
getact <- function(a, basis) {
  p <- as.data.table(if (basis == "capw") R$RES[[a]]$period_returns else R$RES[[a]]$diag_ew_universe$period_returns)
  if (basis == "capw") data.table(date = as.Date(p$date), act = p$ret_net - p$benchmark_ret)
  else                 data.table(date = as.Date(p$date), act = p$active_ew)
}
cat("=== 1) sp3 부호: basis 별 ===\n")
S <- rbindlist(lapply(c("capw","ew"), function(b) rbindlist(lapply(AN, function(a) {
  x <- getact(a, b)[date >= as.Date("2020-01-01")]
  data.table(basis = b, arm = a, n = nrow(x), mean = mean(x$act), t = .nw_t_mean(x$act, lag = 3L)) }))))
print(dcast(S, arm ~ basis, value.var = c("mean","t")))
cat(sprintf("\n  cap-w sp3 음수 arm 수 = %d/4 · EW sp3 음수 arm 수 = %d/4\n",
            S[basis=="capw" & mean < 0, .N], S[basis=="ew" & mean < 0, .N]))

cat("\n=== 2) paired primary (DEPTH − RANK) 를 basis 별로 ===\n")
P <- rbindlist(lapply(c("capw","ew"), function(b) {
  j <- merge(getact("OBJ_MEAN_DEPTH", b), getact("OBJ_RANK", b), by = "date", suffixes = c("_d","_r"))
  stopifnot(nrow(j) == 221)
  d <- j$act_d - j$act_r
  s3 <- d[j$date >= as.Date("2020-01-01")]
  data.table(basis = b, n = length(d), mean = mean(d), t = .nw_t_mean(d, lag = 3L),
             sp3_n = length(s3), sp3_mean = mean(s3), sp3_t = .nw_t_mean(s3, lag = 3L)) }))
print(P)
cat("\n  ★primary 는 cap-w basis 로 사전등록됐다(PREREG §8). EW 수치는 진단 병기이며 판정 대체 아님.\n")

cat("\n=== 3) basis 전환 채널 (계약 산출) ===\n")
for (a in AN) { bc <- R$RES[[a]]$diag_ew_universe$basis_channels
  cat(sprintf("  %-16s t배율 %.3f · mean이동 기여 %.3f · se축소 기여 %.3f · 지배채널 %s\n",
      a, bc$t_magnification, bc$mean_shift_t_contrib, bc$se_shrink_t_contrib, bc$dominant_channel)) }

write_json(list(sp3_by_basis = S, paired_by_basis = P,
  reading = "sp3 활성 소멸은 basis 의존적이다 — cap-w 에서 4/4 음수, EW-유니버스에서 1/4 음수. 따라서 '재료가 죽었다' 는 확립되지 않는다. 다만 paired 차이(DEPTH−RANK)의 sp3 소멸은 두 basis 모두에서 유지된다.",
  caution = "EW t 는 se_shrink 채널을 포함하므로 알파 증거가 아니다(계약 interpretation_note). 자본 자격 주장은 cap-w 로만."),
  file.path(DOUT, "d8_basis_dependence.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
