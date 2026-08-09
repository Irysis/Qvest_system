#==============================================================================
# v3_guard_adjudicate.R — epoch 가드 5일이 옳은가 (내 설계 주장의 반증 시험)
#
# 나는 주석에 "가드는 월말 sig_date 에서 무영향"이라고 썼는데 v2 실측이 반증했다
# (frac_same 0.45~0.70, maxdiff 3~5). 주장을 고치기 전에 **어느 쪽이 옳은지**를
# 기준값 대조로 판정한다.
#
# 기준값(ground truth): 분기 E 의 공표값 = 경계일 B_E 로부터 **충분히 지난 뒤**의
#   관측값. 릴리스는 100% dom<=5 이므로 B_E + 10일 이후 첫 관측을 기준으로 삼는다.
#   (그 관측은 어느 가드 선택과도 무관하게 그 분기 값이다.)
#
# 판정: epoch 리샘플이 각 분기에 붙인 값이 기준값과 같은가.
#   guard=0 : 경계 4/1·6/1·9/1·12/1. 완료된 분기의 마지막 관측 = 다음 경계 직전.
#   guard=5 : 경계가 5일 뒤로 밀려 **다음 분기 릴리스 직후 관측(1~5일)** 이 이 분기의
#             마지막 관측이 된다 → 다음 분기 값이 이 분기에 붙는지 확인.
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")

SUE <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus/sue.parquet")))
SUE[, Date := as.Date(Date)]
SUE <- SUE[!is.na(sue), .(Ticker, Date, value = sue)]

ep_of <- function(d, guard) {
  dd <- d - guard
  y <- as.integer(year(dd)); m <- as.integer(month(dd))
  yy <- fifelse(m <= 3L, y - 1L, y)
  ss <- fifelse(m <= 3L, 3L, fifelse(m <= 5L, 0L, fifelse(m <= 8L, 1L,
        fifelse(m <= 11L, 2L, 3L))))
  yy * 4L + ss
}
# epoch 정수 -> 경계일 (guard 무관한 달력 경계)
ep_start <- function(ep) {
  y <- ep %/% 4L; s <- ep %% 4L
  mth <- c(4L, 6L, 9L, 12L)[s + 1L]
  as.Date(sprintf("%d-%02d-01", y, mth))
}

# 기준값: 경계 + 10일 이후 첫 관측
h <- copy(SUE)
h[, ep0 := ep_of(Date, 0L)]
setorderv(h, c("Ticker", "ep0", "Date"))
truth <- h[Date >= (ep_start(ep0) + 10L), .(truth_val = value[1L], truth_date = Date[1L]),
           by = .(Ticker, ep0)]

res <- list()
for (g in c(0L, 5L)) {
  hh <- copy(SUE); hh[, ep := ep_of(Date, g)]
  setorderv(hh, c("Ticker", "ep", "Date"))
  asg <- hh[, .(assigned = value[.N], assigned_date = Date[.N]), by = .(Ticker, ep)]
  setnames(asg, "ep", "ep0")
  m <- merge(asg, truth, by = c("Ticker", "ep0"))
  # 완료된 분기만 (다음 경계가 패널 최대일 이전)
  m <- m[ep_start(ep0 + 1L) < max(SUE$Date)]
  res[[as.character(g)]] <- data.table(
    guard = g, n = nrow(m),
    frac_match_truth = mean(abs(m$assigned - m$truth_val) < 1e-12),
    frac_assigned_from_next_epoch =
      mean(m$assigned_date >= ep_start(m$ep0 + 1L)),
    median_assigned_dom = median(mday(m$assigned_date)))
}
R <- rbindlist(res)
print(R); fwrite(R, file.path(OUT, "v3_guard_adjudicate.csv"))
cat("\n---- 판정 ----\n")
cat(" frac_match_truth 이 높은 쪽이 옳다.\n")
cat(" frac_assigned_from_next_epoch > 0 = 그 분기 값을 **다음 분기 관측**에서 가져왔다는 뜻.\n")
