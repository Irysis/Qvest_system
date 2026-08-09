#==============================================================================
# a4_mechanism.R — 행-카운트 streak 이 실제로 무엇을 재고 있는가
#
# a1 이 확인한 것: 단위가 분기가 아니라 행이다(비 41~70, unit_match 0.0000).
# a1 이 남긴 물음: rho(rows,qtr)=0.972~0.992 로 순위는 **거의** 보존된다.
#   z 는 winsorize 후 (x-mean)/sd = 아핀 불변이므로, s_rows = a*s_qtr + b 가
#   정확했다면 소비 영향은 0이어야 한다. 그런데 |Δz|>0.5 가 8~28% 다.
#   ⇒ 비아핀 잔차가 있다. **그 잔차가 무엇인지**를 재는 것이 이 스크립트다.
#
# 가설 H1: 잔차 = 애널리스트 커버리지 밀도. 같은 "연속 4분기 양수"라도 매일
#          갱신되는 대형주는 행이 250개, 드문드문 갱신되는 종목은 80개 →
#          streak 이 이익 지속성이 아니라 **커버리지**를 부분적으로 잰다.
# 가설 H2: 잔차 = 커버리지 공백 교량. 행 카운트는 결번 분기를 못 본다 —
#          2년 공백 뒤 재개해도 옛 양수 런이 그대로 이어붙는다.
# 가설 H3: 잔차 = staleness. 최신 관측이 오래된 종목도 streak 이 유지된다.
#
# 부수 확인 X1: (Ticker, Date) 중복행 (있으면 비가 60을 넘는 이유가 될 수 있다)
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")

SUE <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus/sue.parquet")))
SUE[, Date := as.Date(Date)]
SUE <- SUE[!is.na(sue), .(Ticker, Date, value = sue)]

# X1 중복행
dup <- SUE[, .N, by = .(Ticker, Date)][N > 1L]
cat(sprintf("[X1] (Ticker,Date) 중복행 그룹 = %d  (최대 중복도 %s)\n",
            nrow(dup), if (nrow(dup)) max(dup$N) else 0L))

epoch_id <- function(d) {
  y <- year(d); m <- month(d)
  yy <- fifelse(m <= 3L, y - 1L, y)
  ss <- fifelse(m <= 3L, 3L, fifelse(m <= 5L, 0L, fifelse(m <= 8L, 1L,
        fifelse(m <= 11L, 2L, 3L))))
  as.integer(yy) * 4L + as.integer(ss)
}

# 한 sig_date 에서 종목별 streak 진단 일괄
diag_one <- function(sd_) {
  h <- SUE[Date <= sd_]
  setorderv(h, c("Ticker", "Date"), c(1L, -1L))
  # 행 streak + 그 창의 시작일 + 창 안 고유 epoch 수
  d <- h[, {
    s <- 0L
    for (i in seq_len(.N)) {
      if (!is.na(value[i]) && value[i] > 0) s <- s + 1L else break
    }
    if (s == 0L) {
      list(s_rows = 0, win_start = as.Date(NA), n_ep_in_win = 0L,
           latest_date = Date[1L], n_rows_tot = .N)
    } else {
      list(s_rows = as.numeric(s), win_start = Date[s],
           n_ep_in_win = uniqueN(epoch_id(Date[1:s])),
           latest_date = Date[1L], n_rows_tot = .N)
    }
  }, by = Ticker]

  # epoch streak
  hh <- copy(h); hh[, ep := epoch_id(Date)]
  setorderv(hh, c("Ticker", "ep", "Date"), c(1L, 1L, 1L))
  ee <- hh[, .(value = value[.N]), by = .(Ticker, ep)]
  setorderv(ee, c("Ticker", "ep"), c(1L, -1L))
  q <- ee[, {
    s <- 0L; prev_ep <- NA_integer_
    for (i in seq_len(.N)) {
      if (i > 1L && (prev_ep - ep[i]) != 1L) break
      if (value[i] > 0) { s <- s + 1L; prev_ep <- ep[i] } else break
    }
    list(s_qtr = as.numeric(s))
  }, by = Ticker]

  m <- merge(d, q, by = "Ticker")
  m[, stale_days := as.integer(sd_ - latest_date)]
  m[, dens := fifelse(n_ep_in_win > 0L, s_rows / n_ep_in_win, NA_real_)]  # 창 내 epoch 당 행수
  m[, sig_date := sd_]
  m[]
}

SIG <- as.Date(c("2008-12-31", "2014-03-31", "2020-06-30", "2026-06-30"))
alld <- rbindlist(lapply(SIG, diag_one))
fwrite(alld, file.path(OUT, "a4_per_ticker_diag.csv"))

summ <- list()
for (sd_ in SIG) {
  m <- alld[sig_date == sd_]
  pos <- m[s_rows > 0]
  # H2: 창 안 epoch 수 > s_qtr  ⇒ 행 창이 결번 epoch 을 가로질렀다
  bridged <- pos[n_ep_in_win > s_qtr]
  # H1: 같은 s_qtr 안에서 s_rows 가 커버리지 밀도로 갈리는가
  h1 <- pos[s_qtr >= 2L]
  rho_dens <- if (nrow(h1) > 20L)
    suppressWarnings(cor(h1$s_rows - 63 * h1$s_qtr, h1$dens, method = "spearman")) else NA_real_
  # 같은 s_qtr 그룹 내 s_rows 변동계수 (아핀이면 0)
  cvtab <- pos[s_qtr >= 1L, .(n = .N, cv = if (.N >= 5L) sd(s_rows) / mean(s_rows) else NA_real_),
               by = s_qtr][!is.na(cv)]
  # H3
  summ[[as.character(sd_)]] <- data.table(
    sig_date = sd_, n = nrow(m), n_pos = nrow(pos),
    frac_bridged = if (nrow(pos)) nrow(bridged) / nrow(pos) else NA_real_,
    bridged_extra_ep_med = if (nrow(bridged)) median(bridged$n_ep_in_win - bridged$s_qtr) else NA_real_,
    dens_med = median(pos$dens, na.rm = TRUE),
    dens_p10 = as.numeric(quantile(pos$dens, .10, na.rm = TRUE)),
    dens_p90 = as.numeric(quantile(pos$dens, .90, na.rm = TRUE)),
    rho_resid_dens = rho_dens,
    cv_within_sqtr_med = median(cvtab$cv, na.rm = TRUE),
    stale_p50 = median(m$stale_days), stale_p90 = as.numeric(quantile(m$stale_days, .90)),
    frac_stale_gt_400 = mean(m$stale_days > 400))
}
S <- rbindlist(summ)
fwrite(S, file.path(OUT, "a4_mechanism_summary.csv"))
print(S)

# 타이-면역 불일치: s_qtr 이 **엄격히 다른** 쌍만 보고 순위가 뒤집히는 비율
cat("\n== 타이-면역 불일치 (s_qtr 엄격 차이 쌍만) ==\n")
disc <- list()
for (sd_ in SIG) {
  m <- alld[sig_date == sd_]
  set.seed(42L)
  idx <- if (nrow(m) > 700L) sample.int(nrow(m), 700L) else seq_len(nrow(m))
  x <- m$s_qtr[idx]; y <- m$s_rows[idx]
  n <- length(x)
  i <- rep(seq_len(n), each = n); j <- rep(seq_len(n), times = n)
  keep <- i < j
  i <- i[keep]; j <- j[keep]
  dq <- sign(x[i] - x[j]); dr <- sign(y[i] - y[j])
  sel <- dq != 0                       # s_qtr 이 엄격히 다른 쌍만
  disc[[as.character(sd_)]] <- data.table(
    sig_date = sd_, n_pairs_strict = sum(sel),
    frac_flip = mean(dr[sel] != dq[sel] & dr[sel] != 0),
    frac_tie_in_rows = mean(dr[sel] == 0))
}
D <- rbindlist(disc); fwrite(D, file.path(OUT, "a4_discordance.csv")); print(D)

cat("\n---- 판정 규칙 ----\n")
cat(" frac_bridged > 0            ⇒ H2 성립: 행 창이 결번 분기를 가로지른다 (정의 위반)\n")
cat(" dens_p90/dens_p10 >> 1      ⇒ H1 성립: 같은 분기수라도 커버리지로 값이 갈린다\n")
cat(" cv_within_sqtr_med >> 0     ⇒ 아핀 아님 ⇒ z 가 실제로 달라진다\n")
cat(" frac_flip > 0               ⇒ 타이 아닌 실제 순위 역전 (소비 영향 확정)\n")
