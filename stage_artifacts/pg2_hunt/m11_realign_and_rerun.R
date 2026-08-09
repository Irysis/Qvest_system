## m11 — ①inc 내부 조인 확인 ②슬리브↔벤치 정렬 수리 ③**정렬 고친 자로 m1 라벨 순위 재측정**
## m9 확정: 슬리브 r 과 inc$benchmark_ret 이 offset0 에서 상관 ~0, **+1 에서 0.42~0.75**(10/12).
##   ⇒ 파킹의 OFF 월 대체값(`ifelse(on, r, benchmark_ret)`)이 **한 달 어긋난 벤치**였다.
## ★영향: m1/m2/m3/m7/m8 + 어제 n1/o1/p1/s8 의 파킹 구성 전부. 순위가 살아남는지가 관건이다.
## ★사전등록: 정렬 수리 후에도 ①좋음/나쁨 이봉이 유지되고 ②Regime_Score_high 계열이 상위권이면 생존.
##   FALSIFIER: 수리 후 Spearman(구순위, 신순위) < 0.5 → **구 결론 철회**.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m11] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
PG2 <- file.path(ROOT, "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results")

say("=== ① inc 내부 조인 확인 (같은 계약 디렉터리 · exact-date join) ===")
A <- fread(file.path(PG2, "03_period_returns.csv")); B <- fread(file.path(PG2, "05_benchmark_returns.csv"))
A2 <- data.table(m = mi(as.Date(A$date)), ra = as.numeric(A$ret_net))
B2 <- data.table(m = mi(as.Date(B$date)), rb = as.numeric(B$benchmark_ret))
A2 <- A2[, .(ra = ra[1]), by=m]; B2 <- B2[, .(rb = rb[1]), by=m]
cs <- vapply(-3:3, function(k) { Z <- merge(A2, B2[, .(m = m+k, rb)], by="m")
  if (nrow(Z) < 40) return(NA_real_); cor(Z$ra, Z$rb, use="complete.obs") }, numeric(1))
say("  오프셋 상관: %s", paste(sprintf("%+d:%.3f", -3:3, cs), collapse=" · "))
say("  ⇒ 최대 = %+d ⇒ **%s**", (-3:3)[which.max(cs)],
    if (which.max(cs) == 4L) "inc 내부 정렬 정상 (β 0.706 은 vol 오버레이 북의 실제 성질)" else "★inc 조인 결함")

say("=== ② 슬리브 정렬 규약 규명 (날짜 문자열 실측) ===")
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
TG <- fread(file.path(OUT,"s8_parked.csv"))$id
inc <- bm_load_incumbent(); inc[, m := mi(date)]
say("  inc 날짜 예시: %s (일자 = %s)", paste(head(as.character(inc$date),3), collapse=", "),
    paste(unique(format(inc$date,"%d"))[1:3], collapse="/"))
for (nm in TG[1:3]) { j <- which(INV$names == nm)[1]; S <- INV$ser[[j]]
  dt <- if ("date" %in% names(S)) head(as.character(S$date),3) else "date 열 없음"
  say("  %-28s 월 %d~%d · 날짜 %s", substr(nm,1,28), min(S$m), max(S$m), paste(dt, collapse=", ")) }

say("=== ③ ★정렬 수리 후 라벨 재측정 (벤치를 슬리브 월에 맞춰 이동) ===")
RATE <- 0.3562
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L0 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
AX <- c("MSM_Crisis_Prob","FRED_MRS","KTRI_Score","VEA_Score","Regime_Score","Regime_Score_smooth","Cash_Pct")
MO <- U[!is.na(.dd)][order(.dd)][, lapply(.SD, function(x) x[.N]), by=.(m = mi(.dd)), .SDcols=AX][, m_apply := m + 1L]
CM <- intersect(L0$m, MO$m_apply); MOc <- MO[m_apply %in% CM][order(m_apply)]
mkl <- function(v, d) { th <- if (d=="low") quantile(v, RATE, na.rm=TRUE) else quantile(v, 1-RATE, na.rm=TRUE)
  o <- if (d=="low") v <= th else v >= th; o[is.na(o)] <- FALSE; o }
LABS <- list(mega_spread = data.table(m = CM, on = L0[m %in% CM][order(m)]$on))
for (a in AX) for (d in c("low","high")) { v <- suppressWarnings(as.numeric(MOc[[a]]))
  if (all(!is.finite(v))) next; LABS[[paste0(substr(a,1,14),"_",d)]] <- data.table(m = MOc$m_apply, on = mkl(v,d)) }
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
## ★슬리브별 정렬 오프셋을 **실측으로 결정**하고 선언 필드로 남긴다
OFF <- vapply(TG, function(nm) { j <- which(INV$names == nm)[1]; if (is.na(j)) return(NA_integer_)
  S <- INV$ser[[j]]
  cc <- vapply(-2:2, function(k) { Z <- merge(inc[, .(m, bm = benchmark_ret)], S[, .(m = m+k, r)], by="m")
    if (nrow(Z) < 40) return(NA_real_); cor(Z$r, Z$bm, use="complete.obs") }, numeric(1))
  as.integer((-2:2)[which.max(cc)]) }, integer(1))
say("  슬리브 오프셋 실측: %s", paste(sprintf("%+d:%d건", as.integer(names(table(OFF))), table(OFF)), collapse=" · "))
short_of <- function(nm, LBx) { j <- which(INV$names == nm)[1]; k <- OFF[[nm]]
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m = m - k, date, benchmark_ret)], S[, .(m, r)], by="m")[m %in% CM][order(m)]
  if (nrow(X) < 60) return(NA_real_)
  W <- if (is.null(LBx)) copy(X)[, on := TRUE] else merge(X, LBx, by="m")[order(m)]
  if (nrow(W) < 60) return(NA_real_)
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  if (is.null(o$delta_ir)) return(NA_real_)
  need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir }
BASE <- vapply(TG, function(nm) short_of(nm, NULL), numeric(1))
set.seed(20260809)
RND <- lapply(1:20, function(i) { v <- rep(FALSE, length(CM)); v[sample.int(length(CM), round(RATE*length(CM)))] <- TRUE
                                  data.table(m = sort(CM), on = v) })
RB <- vapply(TG, function(nm) median(vapply(RND, function(L) short_of(nm, L), numeric(1)), na.rm=TRUE), numeric(1))
rows <- list()
for (k in names(LABS)) { s <- vapply(TG, function(nm) short_of(nm, LABS[[k]]), numeric(1))
  rows[[length(rows)+1L]] <- data.table(label=k, d_rnd_new = median(s - RB, na.rm=TRUE),
                                        n_improve_new = sum(s < BASE, na.rm=TRUE), n = sum(is.finite(s))) }
N <- rbindlist(rows)[order(d_rnd_new)]
O <- fread(file.path(OUT,"m1_label_ranking.csv"))[, .(label, d_rnd_old = d_rnd, n_improve_old = n_improve)]
M <- merge(N, O, by="label")
say("  %-22s %11s %11s %8s %8s", "label","d_rnd(수리)","d_rnd(구)","개선(수리)","개선(구)")
for (i in seq_len(nrow(M[order(d_rnd_new)]))) { z <- M[order(d_rnd_new)][i]
  say("  %-22s %+11.4f %+11.4f %6d/%-2d %8d", substr(z$label,1,22), z$d_rnd_new, z$d_rnd_old,
      z$n_improve_new, z$n, z$n_improve_old) }
say("=== ★사전등록 판정 ===")
rr <- suppressWarnings(cor(M$d_rnd_new, M$d_rnd_old, method="spearman", use="complete.obs"))
say("  Spearman(구순위, 신순위) = **%+.3f** (FALSIFIER: <0.5 이면 구 결론 철회)", rr)
say("  좋음 %d / 나쁨 %d / 무작위급 %d (구: 7 / 10 / 0)",
    sum(M$d_rnd_new < -0.05, na.rm=TRUE), sum(M$d_rnd_new > 0.05, na.rm=TRUE),
    sum(abs(M$d_rnd_new) <= 0.05, na.rm=TRUE))
top <- M[order(d_rnd_new)][1:3, label]
say("  수리 후 상위3 = %s", paste(top, collapse=" · "))
say("  ⇒ **%s**", if (is.finite(rr) && rr >= 0.5) "구 결론 생존 — 정렬 결함은 수준을 흔들되 순위는 보존" else
    "★★구 결론 철회 — 정렬 수리로 순위가 뒤집힘")
fwrite(M, file.path(OUT,"m11_realigned_ranking.csv"))
say("=== m11 완료 ===")
