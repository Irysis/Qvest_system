## m8 — ①m7 ③ 재실행(setorder 표현식 오류 수리) ②★기전 반증: 라벨 이득이 **β 수확**에 불과한가
## m7 ② 관찰: 좋은 라벨 7종 전부 bm격차 **음수**(벤치 나쁜 달에 보유) · 나쁜 쪽은 대체로 양수.
##   MSM_Crisis_Prob 는 양방향 모두 bm격차 ~0 = **가를 것이 없다**(부호 문제가 아님).
## ★깎아야 할 대안설명: KR long-only 슬리브는 β~0.92 라(메모리 카드) 벤치가 나쁜 달만 보유하면
##   active = (β-1)*bm + α 에서 (β-1)<0 이므로 **bm<0 인 달만 고르는 것만으로 active 가 양수**가 된다.
##   ⇒ 라벨 skill 이 아니라 **저베타 갭의 기계적 수확**일 수 있다.
## ★사전등록 (측정 전 고정):
##   H0(β수확설): 파킹 이득은 β 조정 후 사라진다.
##   1급 지표 = Jensen α(파킹 계열을 벤치에 회귀한 절편, 연율) 의 **좋은라벨 − 무작위** 격차.
##   판정: 격차가 raw active 격차 대비 **<=30% 로 축소** → β수확설 채택 / **>=70% 보존** → 라벨 skill
##         그 사이 → 혼합(둘 다 기여)로 보고한다.
##   ★보조: 파킹 계열의 실현 β 자체를 보고한다(좋은라벨이 β를 낮추는가).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m8] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
P  <- fread(file.path(OUT,"m7_axis_properties.csv"))
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))

say("=== ③재 사전등록 판정 — 전략-무관 성질의 예측력 (Spearman) ===")
cand <- c("on_rate","n_episode","run_len","ac1","bm_gap","bm_volrat","inc_gap")
res <- rbindlist(lapply(cand, function(k) { x <- P[[k]]; ok <- is.finite(x) & is.finite(P$d_rnd)
  ct <- suppressWarnings(cor.test(x[ok], P$d_rnd[ok], method="spearman"))
  data.table(prop=k, rho=unname(ct$estimate), p=ct$p.value, n=sum(ok)) }))
res <- res[order(-abs(rho))]
for (i in seq_len(nrow(res))) say("  %-10s rho **%+.3f** (p %.4f, n %d)%s",
  res$prop[i], res$rho[i], res$p[i], res$n[i], if (abs(res$rho[i]) >= 0.5) "  ★예측력" else "")
B <- res[1]
say("  ⇒ %s", if (abs(B$rho) >= 0.5) sprintf("**예측 가능 — 최강 = %s (rho %+.3f)**", B$prop, B$rho) else
  "**FALSIFIER — 7종 전부 |rho|<0.5, 라벨만으로는 예측 불가**")
say("  ★MSM 위치: high bm_gap %+.4f · low %+.4f (17종 |bm_gap| 최소 2건 = %s)",
    P[label=="MSM_Crisis_Pro_high", bm_gap], P[label=="MSM_Crisis_Pro_low", bm_gap],
    paste(P[order(abs(bm_gap))][1:2, label], collapse=", "))

say("=== ★β 수확 반증 (사전등록 문턱: <=30%% 축소 = β수확설 / >=70%% 보존 = 라벨 skill) ===")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L0 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime)); RATE <- mean(L0$on)
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
MO <- U[!is.na(.dd)][order(.dd)][, .(rs = last(Regime_Score)), by=.(m = mi(.dd))][, m_apply := m + 1L]
CM <- intersect(L0$m, MO$m_apply); MOc <- MO[m_apply %in% CM]
GOOD <- data.table(m = MOc$m_apply, on = MOc$rs >= quantile(MOc$rs, 1-RATE, na.rm=TRUE))
set.seed(20260809)
RND <- lapply(1:20, function(i) { v <- rep(FALSE, length(CM)); v[sample.int(length(CM), round(RATE*length(CM)))] <- TRUE
                                  data.table(m = sort(CM), on = v) })
park <- function(X, LB) { W <- merge(X, LB, by="m")[order(m)]
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]; W }
stats <- function(W) { f <- lm(rp ~ benchmark_ret, data = W)
  list(beta = unname(coef(f)[2]), jensen = unname(coef(f)[1]) * 12,
       raw = mean(W$rp - W$benchmark_ret) * 12) }
TG <- fread(file.path(OUT,"s8_parked.csv"))$id
say("  %-28s %7s %7s | %7s %7s | %7s", "strategy","β_good","β_rnd","J_good","J_rnd","Δraw")
rows <- list()
for (nm in TG) { j <- which(INV$names == nm)[1]; if (is.na(j)) next
  X <- merge(inc[, .(m, date, benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")[m %in% CM][order(m)]
  if (nrow(X) < 60) next
  g <- stats(park(X, GOOD))
  rs <- lapply(RND, function(L) stats(park(X, L)))
  r_b <- median(vapply(rs, function(z) z$beta, 0)); r_j <- median(vapply(rs, function(z) z$jensen, 0))
  r_r <- median(vapply(rs, function(z) z$raw, 0))
  say("  %-28s %7.3f %7.3f | %+7.4f %+7.4f | %+7.4f", substr(nm,1,28), g$beta, r_b, g$jensen, r_j, g$raw - r_r)
  rows[[length(rows)+1L]] <- data.table(id=nm, b_g=g$beta, b_r=r_b, j_g=g$jensen, j_r=r_j,
                                        raw_g=g$raw, raw_r=r_r) }
R <- rbindlist(rows)
d_raw <- median(R$raw_g - R$raw_r); d_jen <- median(R$j_g - R$j_r)
keep <- if (abs(d_raw) > 1e-12) d_jen / d_raw else NA_real_
say("=== ★판정 ===")
say("  raw active 격차(좋은−무작위) 중앙 **%+.4f/yr** · Jensen α 격차 **%+.4f/yr**", d_raw, d_jen)
say("  **보존율 = %.1f%%** (사전등록: <=30%% β수확설 · >=70%% 라벨 skill)", 100*keep)
say("  실현 β: 좋은 라벨 %.3f vs 무작위 %.3f (Δ %+.3f) · 좋은<무작위 %d/%d",
    median(R$b_g), median(R$b_r), median(R$b_g - R$b_r), sum(R$b_g < R$b_r), nrow(R))
say("  ⇒ **%s**", if (is.na(keep)) "판정 불가" else if (keep <= 0.30) "β 수확설 채택 — 라벨 skill 아님" else
    if (keep >= 0.70) "라벨 skill 보존 — β 조정 후에도 이득 유지" else
    sprintf("혼합 — β 채널과 라벨 채널이 함께 기여(보존 %.0f%%)", 100*keep))
fwrite(R, file.path(OUT,"m8_beta_harvest.csv"))
say("=== m8 완료 ===")
