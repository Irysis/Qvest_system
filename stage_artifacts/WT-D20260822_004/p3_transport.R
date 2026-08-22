## WT-D20260822_004 · P3 — 반증 축 R1(수송 STOP 게이트) · R2(매개) · R3(연결) · R5(첨도 이질)
## ★성과(arm PORT_t/paired t) 미출력. 사전등록 PREREG.json falsification_thresholds 기준.
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_004"; SRC <- "stage_artifacts/fq233_probe0_20260813"
B <- readRDS(file.path(OUT, "p1_arms.rds"))
sel_rank <- B$sel_rank; K <- B$K; TOPN <- B$TOPN; CLIP <- B$CLIP
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]; pan <- pan[anchor %in% B$anchors & is.finite(fwd_ret_1m)]
months <- names(sel_rank)

pctrank <- function(v) { ok <- is.finite(v); r <- rep(NA_real_, length(v))
  if (sum(ok) >= 2L) r[ok] <- (data.table::frank(v[ok], ties.method = "average") - 0.5)/sum(ok); r }
comb <- list(
  C0 = function(Z) rowMeans(Z, na.rm = TRUE),
  C1 = function(Z) rowMeans(apply(Z, 2L, pctrank), na.rm = TRUE),
  C2 = function(Z) rowMeans(pmax(pmin(Z, CLIP), -CLIP), na.rm = TRUE),
  C3 = function(Z) apply(Z, 1L, function(x) if (all(!is.finite(x))) NA_real_ else max(x, na.rm = TRUE)))

## ── advocate + leave-advocate-out (FQ-116 귀속 규칙: argmax z) ──────────────
cat("=== R1/R2 — solo-advocate 편입 (leave-advocate-out) ===\n")
res <- vector("list", length(months)); det <- vector("list", length(months)); kur <- vector("list", length(months))
for (m in seq_along(months)) {
  nm <- months[m]; fs <- sel_rank[[nm]]
  d  <- pan[anchor == as.Date(nm)]
  Z  <- as.matrix(d[, ..fs]); rownames(Z) <- as.character(d$Ticker)
  nv <- rowSums(is.finite(Z)); Z <- Z[nv >= 1L, , drop = FALSE]
  tk <- rownames(Z); fw <- d[match(tk, as.character(d$Ticker)), fwd_ret_1m]
  # advocate = argmax_k z (결측은 -Inf)
  Zi <- Z; Zi[!is.finite(Zi)] <- -Inf
  adv_idx <- max.col(Zi, ties.method = "first"); adv <- fs[adv_idx]
  # 첨도 이질 (R5) — 월별 K 팩터 횡단면 초과첨도
  exk <- apply(Z, 2L, function(x) { x <- x[is.finite(x)]; if (length(x) < 30) return(NA_real_)
    mean((x-mean(x))^4)/ (mean((x-mean(x))^2))^2 - 3 })
  kur[[m]] <- data.table(anchor = as.Date(nm), iqr_exkurt = IQR(exk, na.rm = TRUE),
                         min_exkurt = min(exk, na.rm = TRUE), max_exkurt = max(exk, na.rm = TRUE))
  row <- list(anchor = as.Date(nm))
  for (a in names(comb)) {
    sc <- comb[[a]](Z)
    ordr <- order(-sc, tk); top <- tk[ordr][seq_len(min(TOPN, length(tk)))]
    ti <- match(top, tk)
    # leave-advocate-out: advocate 팩터 제거 후 같은 결합 규칙으로 재랭킹
    solo <- vapply(ti, function(i) {
      keep <- setdiff(seq_along(fs), adv_idx[i]); if (!length(keep)) return(TRUE)
      Zk <- Z[, keep, drop = FALSE]
      sck <- comb[[a]](Zk)
      rk <- rank(-sck, ties.method = "first")
      rk[i] > TOPN
    }, logical(1))
    row[[paste0("solo_", a)]] <- mean(solo)
    if (a == "C0") {
      det[[m]] <- data.table(anchor = as.Date(nm), Ticker = top, adv = adv[ti],
                             solo = solo, fwd = fw[ti])
    }
  }
  res[[m]] <- as.data.table(row)
  if (m %% 60 == 0) cat(sprintf("   %d/%d\n", m, length(months)))
}
R <- rbindlist(res); DET <- rbindlist(det); KUR <- rbindlist(kur)

cat("\n--- R1a: C0 solo-advocate 편입 비율 (문턱 중앙 >= 0.20) ---\n")
r1a <- median(R$solo_C0)
cat(sprintf("  중앙 %.4f  평균 %.4f  (= 25 slot 중 중앙 %.1f 개)  [문턱 0.20]  ⇒ %s\n",
            r1a, mean(R$solo_C0), r1a*TOPN, if (r1a >= 0.20) "수송 확인 (진행)" else "★STOP — MECHANISM_NOT_TRANSPORTED"))

cat("\n--- R2: 처치의 매개변수 억제 (문턱 <= 0.8 x C0) ---\n")
for (a in c("C1","C2","C3")) { v <- median(R[[paste0("solo_",a)]])
  cat(sprintf("  %-3s 중앙 %.4f  (C0 대비 %.3f 배)  [문턱 <=0.800]  ⇒ %s\n", a, v, v/r1a,
              if (v <= 0.8*r1a) "억제 확인" else "★NO_MEDIATOR_MOVEMENT")) }

cat("\n--- R3: 연결 — solo vs consensus 편입 종목의 fwd_ret_1m 격차 (C0, NW3 t; 문턱 t <= -1.5) ---\n")
G <- DET[, .(m_solo = mean(fwd[solo], na.rm=TRUE), m_cons = mean(fwd[!solo], na.rm=TRUE),
             n_solo = sum(solo), n_cons = sum(!solo)), by = anchor][is.finite(m_solo) & is.finite(m_cons)]
G[, gap := m_solo - m_cons]
t_gap <- .nw_t_mean(G$gap, lag = 3L)
cat(sprintf("  n=%d개월 · 월평균 격차 %+.5f (연 %+.3f%%p) · NW3 t %+.4f  [FQ-116 대응 -2.01]  ⇒ %s\n",
            nrow(G), mean(G$gap), mean(G$gap)*12*100, t_gap,
            if (t_gap <= -1.5) "연결 성립" else "★연결 절단 — 손실 원천 재귀속 필요"))

cat("\n--- R5: 팩터 간 횡단면 z 초과첨도 이질 (문턱 IQR 중앙 >= 1.0) ---\n")
r5 <- median(KUR$iqr_exkurt, na.rm = TRUE)
cat(sprintf("  IQR(초과첨도) 중앙 %.4f · 월별 min/max 초과첨도 중앙 %.3f / %.3f  ⇒ %s\n",
            r5, median(KUR$min_exkurt,na.rm=TRUE), median(KUR$max_exkurt,na.rm=TRUE),
            if (r5 >= 1.0) "friction3 전제 성립" else "★friction3 강등"))

cat("\n=== R1b — advocate 팩터의 standalone canonical PORT_t (선별 풀 전수) ===\n")
fwd <- pan[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)]
returns_dt <- fwd[, .(Date, Ticker, Ret_1m = fwd)]
bench_dt <- B$bench_dt
FAC_POOL <- sort(unique(unlist(sel_rank)))
cat(sprintf("  선별 풀 팩터 %d종 standalone 측정 시작...\n", length(FAC_POOL)))
t0 <- Sys.time()
hold <- as.Date(months)
SA <- rbindlist(lapply(seq_along(FAC_POOL), function(i) {
  f <- FAC_POOL[i]
  s <- pan[anchor %in% hold, .(Date = anchor, Ticker = as.character(Ticker), score = get(f))][is.finite(score)]
  setorder(s, Date, Ticker)
  r <- try(canonical_screen_bt(s, returns_dt, bench_dt, top_n = TOPN, cost_bps_oneway = 15,
                               run_id = paste0("FQ244_sa_", f), strategy_id = paste0("FQ244_sa_", f),
                               diag_dual_basis = FALSE), silent = TRUE)
  if (inherits(r, "try-error")) return(data.table(fac = f, port_t = NA_real_, n_months = NA_integer_))
  if (i %% 20 == 0) cat(sprintf("   %d/%d (%.1f분)\n", i, length(FAC_POOL),
                                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  data.table(fac = f, port_t = r$portfolio_alpha_t_nw_lag3, n_months = r$n_months)
}))
cat(sprintf("  완료 %.1f분 · 유효 %d/%d\n", as.numeric(difftime(Sys.time(),t0,units="mins")),
            sum(is.finite(SA$port_t)), nrow(SA)))
setkey(SA, fac)
DET[, adv_port_t := SA[.(DET$adv), port_t]]
pool_med  <- median(SA$port_t, na.rm = TRUE)
solo_med  <- median(DET[solo == TRUE]$adv_port_t, na.rm = TRUE)
cons_med  <- median(DET[solo == FALSE]$adv_port_t, na.rm = TRUE)
cat(sprintf("\n  선별 풀 전체 standalone PORT_t 중앙  %+.4f\n", pool_med))
cat(sprintf("  solo-advocate 종목의 advocate PORT_t 중앙  %+.4f\n", solo_med))
cat(sprintf("  consensus 종목의 advocate PORT_t 중앙      %+.4f\n", cons_med))
cat(sprintf("  ⇒ R1b %s (문턱: solo 중앙 < 풀 중앙)\n",
            if (is.finite(solo_med) && solo_med < pool_med) "성립 — 전이-음성 집중 확인" else "★미성립 — 기전 강등(전이-음성 집중 미확인)"))
neg_share_solo <- mean(DET[solo == TRUE]$adv_port_t < 0, na.rm = TRUE)
neg_share_cons <- mean(DET[solo == FALSE]$adv_port_t < 0, na.rm = TRUE)
cat(sprintf("  advocate 가 전이-음성(PORT_t<0)인 비율: solo %.3f vs consensus %.3f\n", neg_share_solo, neg_share_cons))

saveRDS(list(R = R, DET = DET, KUR = KUR, SA = SA, G = G,
             r1a = r1a, t_gap = t_gap, r5 = r5, pool_med = pool_med,
             solo_med = solo_med, cons_med = cons_med,
             neg_share_solo = neg_share_solo, neg_share_cons = neg_share_cons),
        file.path(OUT, "p3_transport.rds"))
cat("\n[saved] p3_transport.rds\n")
