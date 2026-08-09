## m12 — 정렬 수리 자로 downstream 재측정: ①방향 규칙 ②bm_gap 예측력 ③STR_1698
## m11 확정: 파킹 OFF 월 벤치가 +1 어긋나 있었다(10/12). 순위는 Spearman 0.750 로 보존되나
##   **개별 라벨 부호가 뒤집힌 건이 2건**(Regime_Score_low · MSM_Crisis_Pro_low: 나쁨→좋음).
## ⇒ m7 의 bm_gap rho +0.815 와 m8 의 β 검정, m2/m3 의 STR_1698 수치는 **전부 구 정렬 위**다. 재측정.
## ★사전등록: bm_gap 예측력 재판정 FALSIFIER = |rho| < 0.5 → "라벨만으로 예측 불가" 로 보고.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m12] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds")); RATE <- 0.3562
M11 <- fread(file.path(OUT,"m11_realigned_ranking.csv"))

say("=== ① 방향 규칙 재판정 (수리 자) ===")
ax <- unique(sub("_(low|high)$", "", grep("_(low|high)$", M11$label, value=TRUE)))
say("  %-22s %10s %10s %s", "axis","low","high","우세")
nh <- 0L; nl <- 0L; nb <- 0L
for (a in ax) { lo <- M11[label == paste0(a,"_low"), d_rnd_new]; hi <- M11[label == paste0(a,"_high"), d_rnd_new]
  if (!length(lo) || !length(hi)) next
  v <- if (lo < -0.05 && hi < -0.05) { nb <<- nb+1L; "양방향 좋음" } else if (hi < lo) { nh <<- nh+1L; "high" } else { nl <<- nl+1L; "low" }
  say("  %-22s %+10.4f %+10.4f %s", a, lo, hi, v) }
say("  ⇒ high 우세 %d · low 우세 %d · 양방향 %d ⇒ **%s**", nh, nl, nb,
    if (nh >= 5L) "단일 방향 규칙 성립" else "★**단일 방향 규칙 없음** — 구 보고 '5/7 축이 같은 방향' 은 구 정렬 산물")

say("=== ② bm_gap 예측력 재측정 (벤치를 슬리브 월에 정렬) ===")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L0 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
AX <- c("MSM_Crisis_Prob","FRED_MRS","KTRI_Score","VEA_Score","Regime_Score","Regime_Score_smooth","Cash_Pct")
MO <- U[!is.na(.dd)][order(.dd)][, lapply(.SD, function(x) x[.N]), by=.(m = mi(.dd)), .SDcols=AX][, m_apply := m + 1L]
CM <- intersect(L0$m, MO$m_apply); MOc <- MO[m_apply %in% CM][order(m_apply)]
## ★핵심 수리: 벤치를 슬리브 월 공간(m-1)으로 옮겨 라벨과 같은 축에 놓는다
BMs <- inc[, .(m = m - 1L, bm = benchmark_ret)][m %in% CM][order(m)]
mkl <- function(v,d){ th <- if(d=="low") quantile(v,RATE,na.rm=TRUE) else quantile(v,1-RATE,na.rm=TRUE)
  o <- if(d=="low") v<=th else v>=th; o[is.na(o)] <- FALSE; o }
LABS <- list(mega_spread = L0[m %in% CM][order(m)]$on)
for (a in AX) for (d in c("low","high")) { v <- suppressWarnings(as.numeric(MOc[[a]]))
  if (all(!is.finite(v))) next; LABS[[paste0(substr(a,1,14),"_",d)]] <- mkl(v,d) }
G <- rbindlist(lapply(names(LABS), function(k) { on <- LABS[[k]]
  on <- on[seq_len(min(length(on), nrow(BMs)))]; b <- BMs$bm[seq_along(on)]
  if (all(on) || !any(on)) return(data.table(label=k, bm_gap=NA_real_))
  data.table(label=k, bm_gap = mean(b[on]) - mean(b[!on])) }))
GG <- merge(G, M11[, .(label, d_rnd_new, d_rnd_old)], by="label")
ok <- is.finite(GG$bm_gap) & is.finite(GG$d_rnd_new)
ct <- suppressWarnings(cor.test(GG$bm_gap[ok], GG$d_rnd_new[ok], method="spearman"))
say("  Spearman(bm_gap, d_rnd 수리) = **%+.3f** (p %.4f, n %d)", unname(ct$estimate), ct$p.value, sum(ok))
say("  구 보고값(구 정렬) = +0.815 ⇒ **%s**",
    if (abs(unname(ct$estimate)) >= 0.5) "예측력 유지" else "★**FALSIFIER 발동 — bm_gap 예측력은 구 정렬 산물**")

say("=== ③ STR_1698 재측정 (정렬 수리) ===")
nm <- "STR_1698_WT008_M08_Swap"; j <- which(INV$names == nm)[1]
S <- INV$ser[[j]]
kbest <- { cc <- vapply(-2:2, function(k){ Z <- merge(inc[,.(m,bm=benchmark_ret)], S[,.(m=m+k,r)], by="m")
  if (nrow(Z)<40) return(NA_real_); cor(Z$r, Z$bm, use="complete.obs") }, numeric(1)); as.integer((-2:2)[which.max(cc)]) }
say("  실측 오프셋 %+d (구: 0 가정)", kbest)
MOa <- U[!is.na(.dd)][order(.dd)][, .(rss = last(Regime_Score_smooth)), by=.(m = mi(.dd))]
LB <- data.table(m = MOa$m + 1L, on = MOa$rss >= quantile(MOa$rss, 1-RATE, na.rm=TRUE))[!is.na(on)]
X <- merge(inc[, .(m = m - kbest, date, benchmark_ret)], S[, .(m, r)], by="m")[order(m)]
W <- merge(X, LB, by="m")[order(m)]
W[, sw := c(0L, abs(diff(as.integer(on))))]
W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=TRUE, B_boot=3000)
ci <- o$delta_ir_ci
say("  n %d · rho %+.4f · 슬리브IR %+.4f · 부족분 **%+.4f**", nrow(W),
    o$correlation_with_incumbent, o$sleeve_standalone_ir, need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir)
say("  ΔIR **%+.4f** · 90%% CI [%+.4f, %+.4f] · P(>=0.05) %.1f%% · verdict_ci **%s**",
    o$delta_ir, ci$lo, ci$hi, 100*ci$p_above_threshold, o$verdict_ci)
say("  구 보고(구 정렬): ΔIR +0.0613 · CI [-0.0320, +0.1458] · UNRESOLVED")
nl <- subsample_null(x=W$r, y=W$benchmark_ret, subset=W$on, stat=function(a,b) cor(a,b), n_draw=1000)
say("  귀무 창: delta %+.4f · 백분위 %.1f%% · inside %s", nl$delta, nl$percentile, nl$inside)
fwrite(GG, file.path(OUT,"m12_bmgap_realigned.csv"))
say("=== m12 완료 ===")
