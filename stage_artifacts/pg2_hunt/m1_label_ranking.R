## m1 — 라벨 8종을 **무작위 대비**로 줄 세워 '좋은 라벨' 의 성질을 찾는다
## n1 확정: 파킹 이득 = 구조 58% + 라벨정보 42%. **무작위 대조가 라벨 평가의 원점**이다.
##   mega_spread 는 무작위보다 0.202 좋고 unified(Regime_Score) 는 0.64 나쁘다.
## ⇒ 라벨 후보를 늘려 같은 자로 줄 세운다. 발화율은 **전부 35.6%로 통일**(n1: 발화율 무관 확인).
## ★후보: unified 파일의 연속 축 7종 + jump_JM_State + mega_spread = 9
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[m1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L0 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
RATE <- mean(L0$on)

f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
AX <- c("MSM_Crisis_Prob","FRED_MRS","KTRI_Score","VEA_Score","Regime_Score","Regime_Score_smooth","Cash_Pct")
AX <- intersect(AX, names(U))
MO <- U[!is.na(.dd)][order(.dd)][, c(list(m = mi(.dd)), lapply(.SD, function(x) x)), .SDcols = AX]
MO <- MO[, lapply(.SD, function(x) x[.N]), by = m, .SDcols = AX][, m_apply := m + 1L]
f2 <- list.files(".", pattern="^regime_jump_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
JJ <- as.data.table(read_parquet(f2)); jd <- names(JJ)[which(tolower(names(JJ)) %in% c("date","ym"))[1]]
JJ[, .dd := as.Date(as.character(get(jd)))]
JM <- JJ[!is.na(.dd)][order(.dd)][, .(v = last(JM_State)), by = .(m = mi(.dd))][, m_apply := m + 1L]

CM <- Reduce(intersect, list(L0$m, MO$m_apply, JM$m_apply))
say("=== 공통 창 %d개월 · 발화율 통일 %.1f%% (ON %d) ===", length(CM), 100*RATE, round(RATE*length(CM)))
L0 <- L0[m %in% CM]
MOc <- MO[m_apply %in% CM]; JMc <- JM[m_apply %in% CM]
LABS <- list(mega_spread = L0)
for (a in AX) for (dir in c("low","high")) {
  v <- suppressWarnings(as.numeric(MOc[[a]])); if (all(!is.finite(v))) next
  th <- if (dir=="low") quantile(v, RATE, na.rm=TRUE) else quantile(v, 1-RATE, na.rm=TRUE)
  on <- if (dir=="low") v <= th else v >= th; on[is.na(on)] <- FALSE
  LABS[[paste0(substr(a,1,14), "_", dir)]] <- data.table(m = MOc$m_apply, on = on)
}
dom <- names(sort(table(JMc$v), decreasing=TRUE))[1]
LABS[["jump_JM_dom"]] <- data.table(m = JMc$m_apply, on = JMc$v == dom)
LABS[["jump_JM_inv"]] <- data.table(m = JMc$m_apply, on = JMc$v != dom)
say("  라벨 후보 %d종", length(LABS))

TG <- fread(file.path(OUT,"s8_parked.csv"))$id
SER <- list()
for (nm in TG) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")[m %in% CM][order(m)]
  if (nrow(X) >= 60) SER[[nm]] <- X
}
say("  전략 %d종", length(SER))
short_of <- function(X, LB) {
  if (is.null(LB)) { o <- bm_delta_ir(X[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  } else {
    W <- merge(X, LB, by="m")[order(m)]; if (nrow(W) < 60) return(NA_real_)
    W[, sw := c(0L, abs(diff(as.integer(on))))]
    W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
    o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE) }
  if (is.null(o$delta_ir)) return(NA_real_)
  need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir
}
BASE <- vapply(SER, function(X) short_of(X, NULL), numeric(1))
set.seed(20260809)
RND <- lapply(1:20, function(i) { v <- rep(FALSE, length(CM)); v[sample.int(length(CM), round(RATE*length(CM)))] <- TRUE
                                  data.table(m = sort(CM), on = v) })
RB <- vapply(SER, function(X) median(vapply(RND, function(L) short_of(X, L), numeric(1)), na.rm=TRUE), numeric(1))
say("=== ★라벨 줄 세우기 (무작위 대비 · %d전략 중앙) ===", length(SER))
say("  %-24s %6s %10s %10s %10s %8s", "label", "ON%", "Δ vs base", "Δ vs 무작위", "개선/n", "부호")
rows <- list()
for (k in names(LABS)) {
  s <- vapply(SER, function(X) short_of(X, LABS[[k]]), numeric(1))
  dB <- median(s - BASE, na.rm=TRUE); dR <- median(s - RB, na.rm=TRUE)
  say("  %-24s %5.1f%% %+10.4f %+10.4f %6d/%-3d %8s", substr(k,1,24),
      100*mean(LABS[[k]]$on), dB, dR, sum(s < BASE, na.rm=TRUE), length(s),
      if (dR < -0.05) "★좋음" else if (dR > 0.05) "★나쁨" else "무작위급")
  rows[[length(rows)+1L]] <- data.table(label=k, rate=mean(LABS[[k]]$on), d_base=dB, d_rnd=dR,
    n_improve=sum(s < BASE, na.rm=TRUE), n=length(s))
}
R <- rbindlist(rows); setorder(R, d_rnd)
say("=== ★판정 ===")
say("  무작위보다 좋은 라벨(Δ<-0.05): **%d / %d**", sum(R$d_rnd < -0.05), nrow(R))
say("  무작위급(|Δ|<=0.05)          : %d", sum(abs(R$d_rnd) <= 0.05))
say("  무작위보다 나쁜 라벨(Δ>0.05) : **%d**", sum(R$d_rnd > 0.05))
say("  최고: %s (Δ vs 무작위 %+.4f) · 최악: %s (%+.4f)",
    R$label[1], R$d_rnd[1], R$label[nrow(R)], R$d_rnd[nrow(R)])
say("  ★좋은 라벨의 발화율 범위 %.1f~%.1f%% vs 나쁜 라벨 %.1f~%.1f%%",
    100*min(R[d_rnd < -0.05, rate], na.rm=TRUE), 100*max(R[d_rnd < -0.05, rate], na.rm=TRUE),
    100*min(R[d_rnd > 0.05, rate], na.rm=TRUE), 100*max(R[d_rnd > 0.05, rate], na.rm=TRUE))
fwrite(R, file.path(OUT,"m1_label_ranking.csv"))
say("=== m1 완료 ===")
