#==============================================================================
# a5_repair_design.R — 수리 설계의 전제를 먼저 실측한다 (가정하고 재기 시작 금지)
#
# 물음 4개:
#  Q1 릴리스 달력이 시대에 걸쳐 안정한가 (4/6/9/12월 월초). 안 그러면 달력-하드코딩
#     epoch 은 옛 구간에서 깨진다.
#  Q2 .cons_quarters() 를 그대로 쓸 수 있는가 — 두 축에서 확인:
#     (a) 동률 병합: 인접 분기 값이 정확히 같으면 런이 합쳐져 **카운트를 과소**한다
#     (b) 결번 교량: 런 기반은 결번 분기를 안 끊는다 (streak 에는 치명)
#  Q3 stale 앵커: 현재 epoch 에 관측이 없는 종목에 streak 을 내야 하는가.
#     실제 배출 행수(원장)와 대조해 무엇이 실제로 소비되는지 본다.
#  Q4 후보 수리안 3종의 산출 차이
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

epoch_id <- function(d) {
  y <- year(d); m <- month(d)
  yy <- fifelse(m <= 3L, y - 1L, y)
  ss <- fifelse(m <= 3L, 3L, fifelse(m <= 5L, 0L, fifelse(m <= 8L, 1L,
        fifelse(m <= 11L, 2L, 3L))))
  as.integer(yy) * 4L + as.integer(ss)
}

# ── Q1 릴리스 달력 시대 안정성 ────────────────────────────────────────────────
h <- copy(SUE); setorderv(h, c("Ticker", "Date"))
h[, prev_v := shift(value), by = Ticker]
h[, changed := !is.na(prev_v) & abs(value - prev_v) > 1e-12]
ch <- h[changed == TRUE]
ch[, era := fifelse(year(Date) < 2007L, "2001-2006",
            fifelse(year(Date) < 2013L, "2007-2012",
            fifelse(year(Date) < 2019L, "2013-2018", "2019-2026")))]
ch[, dom := mday(Date)]
q1 <- ch[, .(n = .N,
             frac_m4691 = mean(month(Date) %in% c(4L, 6L, 9L, 12L)),
             frac_dom_le5 = mean(dom <= 5L),
             frac_on_epoch_boundary = mean(month(Date) %in% c(4L, 6L, 9L, 12L) & dom <= 5L)),
         by = era][order(era)]
cat("== Q1 릴리스 달력 시대 안정성 ==\n"); print(q1)
fwrite(q1, file.path(OUT, "a5_q1_calendar_stability.csv"))

# ── Q2 동률 병합률 + 결번 교량 (전 패널) ──────────────────────────────────────
hh <- copy(SUE); hh[, ep := epoch_id(Date)]
setorderv(hh, c("Ticker", "ep", "Date"))
ee <- hh[, .(value = value[.N]), by = .(Ticker, ep)]
setorderv(ee, c("Ticker", "ep"))
ee[, prev_v := shift(value), by = Ticker]
ee[, prev_ep := shift(ep), by = Ticker]
adj <- ee[!is.na(prev_ep) & (ep - prev_ep) == 1L]
tie_rate <- mean(abs(adj$value - adj$prev_v) < 1e-12)
gap_rate <- mean(ee[!is.na(prev_ep), (ep - prev_ep) != 1L])
cat(sprintf("\n== Q2 ==\n 인접 epoch 쌍 %s개 중 값이 정확히 같은 비율(동률 병합 위험) = %.4f\n",
            format(nrow(adj), big.mark = ","), tie_rate))
cat(sprintf(" epoch 결번(커버리지 공백) 비율 = %.4f  ⇒ 런 기반은 이 지점을 안 끊는다\n", gap_rate))
# 양수-양수 인접쌍만 (streak 에 실제로 영향)
adjp <- adj[value > 0 & prev_v > 0]
cat(sprintf(" 양수-양수 인접쌍 중 동률 = %.4f (n=%s)  ⇒ 런 기반 streak 과소 카운트율\n",
            mean(abs(adjp$value - adjp$prev_v) < 1e-12), format(nrow(adjp), big.mark = ",")))
fwrite(data.table(tie_rate_all = tie_rate, gap_rate = gap_rate,
                  tie_rate_pospos = mean(abs(adjp$value - adjp$prev_v) < 1e-12),
                  n_adj = nrow(adj), n_adj_pospos = nrow(adjp)),
       file.path(OUT, "a5_q2_tie_gap.csv"))

# ── Q3/Q4 후보 3종 + 실제 배출 행수 대조 ─────────────────────────────────────
led <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))
c11led <- led[Factor_Name == "C11_Earnings_Streak"]

# 후보 정의
#  R0 현행           : 연속 양수 **행** (앵커 = 최신 관측)
#  R1 epoch+contig   : epoch 리샘플 · 결번 끊음 · 앵커 = 종목의 최신 관측 epoch
#  R2 R1+현재앵커    : R1 + "현재 epoch 에 관측 있어야" (stale 종목 NA)
#  R3 런 dedup       : .cons_quarters 와 같은 창 (동률 병합 · 결번 안 끊음)
streaks_all <- function(sd_) {
  x <- SUE[Date <= sd_]
  setorderv(x, c("Ticker", "Date"), c(1L, -1L))
  r0 <- x[, {
    s <- 0L
    for (i in seq_len(.N)) { if (!is.na(value[i]) && value[i] > 0) s <- s + 1L else break }
    list(R0 = as.numeric(s))
  }, by = Ticker]

  y <- copy(x); y[, ep := epoch_id(Date)]
  setorderv(y, c("Ticker", "ep", "Date"), c(1L, 1L, 1L))
  e <- y[, .(value = value[.N]), by = .(Ticker, ep)]
  setorderv(e, c("Ticker", "ep"), c(1L, -1L))
  r1 <- e[, {
    s <- 0L; pe <- NA_integer_
    for (i in seq_len(.N)) {
      if (i > 1L && (pe - ep[i]) != 1L) break
      if (value[i] > 0) { s <- s + 1L; pe <- ep[i] } else break
    }
    list(R1 = as.numeric(s), top_ep = ep[1L])
  }, by = Ticker]
  cur_ep <- epoch_id(sd_)
  r1[, R2 := fifelse(top_ep == cur_ep, R1, NA_real_)]

  z <- copy(x); setorderv(z, c("Ticker", "Date"), c(1L, 1L))
  z[, newrun := is.na(shift(value)) | Ticker != shift(Ticker) |
                abs(value - shift(value)) > 1e-12]
  z[, runid := cumsum(newrun)]
  rt <- z[, .(Ticker = Ticker[1L], value = value[1L], run_start = min(Date)), by = runid]
  setorderv(rt, c("Ticker", "run_start"), c(1L, -1L))
  r3 <- rt[, {
    s <- 0L
    for (i in seq_len(.N)) { if (value[i] > 0) s <- s + 1L else break }
    list(R3 = as.numeric(s))
  }, by = Ticker]

  merge(merge(r0, r1, by = "Ticker"), r3, by = "Ticker")
}

SIG <- as.Date(c("2005-06-30", "2008-12-31", "2014-03-31", "2020-06-30", "2026-06-30"))
YM  <- c(200506L, 200812L, 201403L, 202006L, 202606L)
out <- list()
for (k in seq_along(SIG)) {
  m <- streaks_all(SIG[k])
  led_rows <- c11led[ym == YM[k], n_rows]
  out[[k]] <- data.table(
    sig_date = SIG[k], ym = YM[k],
    n_panel = nrow(m),
    ledger_emitted = if (length(led_rows)) led_rows[1] else NA_integer_,
    n_R2_nonNA = sum(!is.na(m$R2)),
    R1_eq_R3 = mean(m$R1 == m$R3),
    R1_gt_R3 = mean(m$R1 > m$R3),   # 동률 병합으로 R3 과소
    R1_lt_R3 = mean(m$R1 < m$R3),   # 결번 교량으로 R3 과대
    max_R0 = max(m$R0), max_R1 = max(m$R1), max_R3 = max(m$R3),
    rho_R0_R1 = suppressWarnings(cor(m$R0, m$R1, method = "spearman")))
}
Q <- rbindlist(out); print(Q); fwrite(Q, file.path(OUT, "a5_q34_candidates.csv"))

cat("\n---- 읽는 법 ----\n")
cat(" Q1 frac_on_epoch_boundary 가 전 시대 ~1.0  ⇒ 달력 epoch 하드코딩 안전\n")
cat(" Q2 tie_rate_pospos > 0                    ⇒ .cons_quarters(런) 은 streak 을 과소 카운트\n")
cat(" Q2 gap_rate > 0                           ⇒ .cons_quarters(런) 은 결번을 안 끊음\n")
cat("    ⇒ 둘 중 하나라도 > 0 이면 .cons_quarters 재사용 불가, 별도 창 정의 필요\n")
cat(" Q3 ledger_emitted vs n_R2_nonNA           ⇒ 현재앵커 규칙이 배출을 얼마나 줄이는가\n")
