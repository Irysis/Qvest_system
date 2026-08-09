## n1 — 파킹이 듣는 이유: **발화율**인가 **선별의 질**인가
## o1: L1 mega_spread(ON 35.6%) 11/12 개선 vs L2 unified(ON 82.2%) 0/12. 라벨이 결정.
## ★그런데 두 라벨은 발화율도 선별도 다르다. 교락돼 있다.
## ⇒ unified 를 **L1과 같은 발화율(35.6%)** 로 조인 판본 L2' 를 만들어 3-arm 비교.
##    L2' 가 L1 처럼 작동 → **발화율이 결정** / L2' 도 실패 → **선별의 질이 결정**
## ★대조: 같은 발화율 **무작위 라벨**도 넣어 구조 효과를 분리한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n1] ", fmt, "\n"), ...)); flush.console() }
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
L1 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
mo <- U[!is.na(.dd)][order(.dd)][, .(rs = last(Regime_Score)), by = .(m = mi(.dd))][, m_apply := m + 1L]
CM <- intersect(L1$m, mo$m_apply)
L1 <- L1[m %in% CM]
P1 <- mean(L1$on)
moc <- mo[m_apply %in% CM]
L2  <- data.table(m = moc$m_apply, on = moc$rs <= quantile(moc$rs, 0.717, na.rm=TRUE))
L2p <- data.table(m = moc$m_apply, on = moc$rs <= quantile(moc$rs, P1, na.rm=TRUE))
say("=== 라벨 3종 (공통 %d개월) ===", length(CM))
say("  L1  mega_spread     ON %d (%.1f%%)", sum(L1$on), 100*mean(L1$on))
say("  L2  unified 71.7%%   ON %d (%.1f%%)", sum(L2$on), 100*mean(L2$on))
say("  L2' unified %.1f%%   ON %d (%.1f%%)  ← 발화율 정합", 100*P1, sum(L2p$on), 100*mean(L2p$on))
say("  L1 vs L2' ON 일치율 %.1f%% (무작위 기대 %.1f%%)",
    100*mean(L1[order(m)]$on == L2p[order(m)]$on),
    100*(P1^2 + (1-P1)^2))

TG <- fread(file.path(OUT,"s8_parked.csv"))$id
set.seed(20260809)
RND <- lapply(1:20, function(i) { v <- rep(FALSE, length(CM)); v[sample.int(length(CM), sum(L1$on))] <- TRUE
                                  data.table(m = sort(CM), on = v) })
say("=== 12전략 x 4-arm (동일 창) ===")
say("  %-28s %8s %8s %8s %8s %9s", "strategy","무처리","L1","L2","L2'","무작위중앙")
short_of <- function(X, LB) {
  if (is.null(LB)) {
    o <- bm_delta_ir(X[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  } else {
    W <- merge(X, LB, by="m")[order(m)]
    if (nrow(W) < 60) return(NA_real_)
    W[, sw := c(0L, abs(diff(as.integer(on))))]
    W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
    o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  }
  if (is.null(o$delta_ir)) return(NA_real_)
  need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir
}
rows <- list()
for (nm in TG) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")[m %in% CM][order(m)]
  if (nrow(X) < 60) next
  s0 <- short_of(X, NULL); s1 <- short_of(X, L1); s2 <- short_of(X, L2); s2p <- short_of(X, L2p)
  sr <- median(vapply(RND, function(L) short_of(X, L), numeric(1)), na.rm=TRUE)
  say("  %-28s %+8.3f %+8.3f %+8.3f %+8.3f %+9.3f", substr(nm,1,28), s0, s1, s2, s2p, sr)
  rows[[length(rows)+1L]] <- data.table(id=nm, base=s0, L1=s1, L2=s2, L2p=s2p, rnd=sr)
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
for (k in c("L1","L2","L2p","rnd")) {
  d <- R[[k]] - R$base
  say("  %-4s 개선 %2d/%d · Δ부족 중앙 %+.4f%s", k, sum(d<0, na.rm=TRUE), nrow(R), median(d, na.rm=TRUE),
      if (k=="L2p") "  ← 발화율 정합 unified" else if (k=="rnd") "  ← 동일 발화율 무작위" else "")
}
say("  ★L2'(발화율 정합) vs L1: %s",
    if (sum(R$L2p - R$base < 0, na.rm=TRUE) >= 0.7*nrow(R))
      "**발화율이 결정** — 조이니 unified 도 작동" else
      "**선별의 질이 결정** — 발화율을 맞춰도 unified 는 실패")
say("  ★L1 vs 무작위(동일 발화율): Δ 중앙 %+.4f · L1 이 더 좋은 전략 %d/%d",
    median(R$L1 - R$rnd, na.rm=TRUE), sum(R$L1 < R$rnd, na.rm=TRUE), nrow(R))
say("  ⇒ 무작위도 개선하면 **구조(적게 보유) 효과**, L1 만 개선하면 **라벨 정보**")
fwrite(R, file.path(OUT,"n1_rate_quality.csv"))
say("=== n1 완료 ===")
