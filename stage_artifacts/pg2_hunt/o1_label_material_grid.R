## o1 — 파킹 이득의 (라벨 x 재료) 교차표: 언제 작동하는가
## p1 발견: 같은 재료(STR_1698)가 라벨을 바꾸면 파킹 이득의 **부호가 뒤집힌다**.
## ⇒ 12전략 x 2라벨을 **동일 창**에서 교차 측정해 조건을 찾는다.
## ★창 통일 필수: mega_spread 는 2020-02~2026-02(73개월)뿐이므로 두 라벨 모두 그 창으로 자른다.
##   (창을 안 맞추면 라벨 효과와 창 효과가 섞인다 — 오늘 반복 확인한 함정)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[o1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))

## 라벨 2종
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L1 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
mo <- U[!is.na(.dd)][order(.dd)][, .(rs = last(Regime_Score)), by = .(m = mi(.dd))][, m_apply := m + 1L]
th <- quantile(mo$rs, 0.717, na.rm=TRUE)
L2 <- data.table(m = mo$m_apply, on = mo$rs <= th)[!is.na(on)]
## ★창 통일 = 두 라벨 공통 월
CM <- intersect(L1$m, L2$m)
L1 <- L1[m %in% CM]; L2 <- L2[m %in% CM]
say("=== 창 통일 === 공통 %d개월 · L1(mega) ON %d (%.1f%%) · L2(unified) ON %d (%.1f%%)",
    length(CM), sum(L1$on), 100*mean(L1$on), sum(L2$on), 100*mean(L2$on))
say("  두 라벨 ON 일치율 %.1f%% (무작위 기대 %.1f%%)",
    100*mean(L1[order(m)]$on == L2[order(m)]$on),
    100*(mean(L1$on)*mean(L2$on) + (1-mean(L1$on))*(1-mean(L2$on))))

TG <- fread(file.path(OUT,"s8_parked.csv"))$id
say("=== 12전략 x 2라벨 (동일 %d개월 창) ===", length(CM))
say("  %-30s %8s | %8s %8s | %8s %8s", "strategy","무처리","L1 파킹","Δ부족","L2 파킹","Δ부족")
rows <- list()
for (nm in TG) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")[m %in% CM][order(m)]
  if (nrow(X) < 60) next
  o0 <- bm_delta_ir(X[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  if (is.null(o0$delta_ir)) next
  s0 <- need_ir(o0$correlation_with_incumbent) - o0$sleeve_standalone_ir
  out <- c(s0)
  for (LB in list(L1, L2)) {
    W <- merge(X, LB, by="m")[order(m)]
    W[, sw := c(0L, abs(diff(as.integer(on))))]
    W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
    o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
    out <- c(out, if (is.null(o$delta_ir)) NA_real_ else
                  need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir)
  }
  say("  %-30s %+8.3f | %+8.3f %+8.3f | %+8.3f %+8.3f", substr(nm,1,30),
      out[1], out[2], out[2]-out[1], out[3], out[3]-out[1])
  rows[[length(rows)+1L]] <- data.table(id=nm, base=out[1], L1=out[2], L2=out[3],
                                        d1=out[2]-out[1], d2=out[3]-out[1])
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
say("  L1(mega_spread) 개선(Δ부족<0) **%d / %d** · 중앙 %+.4f", sum(R$d1<0, na.rm=TRUE), nrow(R), median(R$d1, na.rm=TRUE))
say("  L2(unified)     개선(Δ부족<0) **%d / %d** · 중앙 %+.4f", sum(R$d2<0, na.rm=TRUE), nrow(R), median(R$d2, na.rm=TRUE))
say("  ★두 라벨 효과 상관 cor(d1, d2) = %+.3f", cor(R$d1, R$d2, use="complete.obs"))
say("  ★같은 방향(둘 다 개선 또는 둘 다 악화) %d / %d",
    sum(sign(R$d1) == sign(R$d2), na.rm=TRUE), nrow(R))
t1 <- t.test(R$L1, R$base, paired=TRUE); t2 <- t.test(R$L2, R$base, paired=TRUE)
say("  paired t: L1 %+.3f (p %.5f) · L2 %+.3f (p %.5f)",
    t1$statistic, t1$p.value, t2$statistic, t2$p.value)
say("=== ★결론 ===")
say("  %s", if (sum(R$d1<0, na.rm=TRUE) > 0.7*nrow(R) && sum(R$d2<0, na.rm=TRUE) < 0.4*nrow(R))
  "★★라벨이 갈린다 — mega_spread 는 작동하고 unified 는 아니다. **파킹은 라벨 특이적**" else
  if (cor(R$d1, R$d2, use="complete.obs") > 0.5)
  "★두 라벨 효과가 함께 간다 — 재료 특이적(어떤 재료는 파킹이 듣고 어떤 재료는 안 듣는다)" else
  "★라벨·재료 둘 다 관여 — 단일 축으로 설명 안 됨")
fwrite(R, file.path(OUT,"o1_grid.csv"))
say("=== o1 완료 ===")
