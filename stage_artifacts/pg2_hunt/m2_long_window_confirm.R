## m2 — m1 최고 라벨(Regime_Score_high 계열)을 **긴 창**에서 확인 + 막힌 길 재개통
## ★사전등록 (측정 전 고정):
##   가설 H: Regime_Score_smooth_high(상위 35.6% 월만 보유) 파킹이 73개월 창 밖에서도 작동한다.
##   1급 지표 = 부족분 개선 전략수(개선 = need_ir - IR 이 무처리보다 작아짐)
##   FALSIFIER: ①개선 <= n/2 (동전) 또는 ②동일 발화율 무작위 대비 Δ중앙 >= 0  → 기각
##   ★이건 **시간축 확장 확인**이다. m1 에서 17종 중 1위로 뽑았으므로 같은 73개월 재검정은 순환 —
##     판정은 **73개월 밖 구간을 포함한 긴 창**에서만 읽는다.
##   ★대조 3종 동시: 무처리 / 동일발화율 무작위 20draw / mega_spread(가능한 전략만)
##   ★귀무 창 게이트(subsample_null): ON 창이 우연히 특별한 구간인지
## ★핵심 목적: mega_spread 는 73개월뿐이라 STR_1698(2024-04 종료, 겹침 51<60)을 못 쟀다.
##   Regime_Score 는 243개월이라 **칩 task_b065b34d(계열 연장) 없이도 측정 가능**하다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[m2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
RATE <- 0.3562  ## m1 과 동일 발화율 (mega_spread 실측치)

f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
MO <- U[!is.na(.dd)][order(.dd)][, .(rs = last(Regime_Score), rss = last(Regime_Score_smooth)), by=.(m = mi(.dd))][, m_apply := m + 1L]
say("=== 라벨 원천 창 %d개월 (%d ~ %d) ===", nrow(MO), min(MO$m_apply), max(MO$m_apply))
LB  <- data.table(m = MO$m_apply, on = MO$rss >= quantile(MO$rss, 1-RATE, na.rm=TRUE))[!is.na(on)]
LBr <- data.table(m = MO$m_apply, on = MO$rs  >= quantile(MO$rs,  1-RATE, na.rm=TRUE))[!is.na(on)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LM  <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
say("  Regime_Score_smooth_high ON %d/%d (%.1f%%) · mega_spread 창 %d개월",
    sum(LB$on), nrow(LB), 100*mean(LB$on), nrow(LM))

short_of <- function(X, LBx) {
  if (is.null(LBx)) { W <- X; W[, rp := r] } else {
    W <- merge(X, LBx, by="m")[order(m)]; if (nrow(W) < 60) return(c(NA_real_, NA_real_))
    W[, sw := c(0L, abs(diff(as.integer(on))))]
    W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4] }
  o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  if (is.null(o$delta_ir)) return(c(NA_real_, NA_real_))
  c(need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir, nrow(W))
}
## ★대상 = 12전략 + STR_1698(mega_spread 로는 못 쟀던 계열)
TG <- unique(c(fread(file.path(OUT,"s8_parked.csv"))$id,
               grep("STR_1698", INV$names, value=TRUE)))
set.seed(20260809)
say("=== 긴 창 4-arm (전략별 최대 겹침) ===")
say("  %-30s %5s %8s %8s %8s %9s", "strategy","n월","무처리","RSsm_hi","무작위","mega")
rows <- list()
for (nm in TG) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")[order(m)]
  if (nrow(X) < 60) next
  b <- short_of(X, NULL); a <- short_of(X, LB); a2 <- short_of(X, LBr)
  CMx <- intersect(X$m, LB$m)
  RND <- lapply(1:20, function(i) { v <- rep(FALSE, length(CMx)); v[sample.int(length(CMx), round(RATE*length(CMx)))] <- TRUE
                                    data.table(m = sort(CMx), on = v) })
  rr <- median(vapply(RND, function(L) short_of(X, L)[1], numeric(1)), na.rm=TRUE)
  mg <- short_of(X, LM)[1]
  say("  %-30s %5.0f %+8.3f %+8.3f %+8.3f %+9s", substr(nm,1,30), a[2], b[1], a[1], rr,
      if (is.na(mg)) "  창부족" else sprintf("%+8.3f", mg))
  rows[[length(rows)+1L]] <- data.table(id=nm, n=a[2], base=b[1], rs_sm=a[1], rs_raw=a2[1], rnd=rr, mega=mg)
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★사전등록 판정 ===")
nn <- sum(!is.na(R$rs_sm))
imp <- sum(R$rs_sm < R$base, na.rm=TRUE); dR <- median(R$rs_sm - R$rnd, na.rm=TRUE)
say("  개선 **%d / %d** (falsifier: <= %d 이면 기각) · Δ vs 무작위 중앙 **%+.4f** (falsifier: >= 0)",
    imp, nn, floor(nn/2), dR)
say("  Δ vs 무처리 중앙 %+.4f · raw(비평활) 판본 개선 %d/%d",
    median(R$rs_sm - R$base, na.rm=TRUE), sum(R$rs_raw < R$base, na.rm=TRUE), nn)
VER <- if (imp > nn/2 && dR < 0) "**생존 — 긴 창에서도 작동**" else "**기각**"
say("  ⇒ %s", VER)
say("=== ★막힌 길: STR_1698 계열 ===")
S98 <- R[grepl("STR_1698", id)]
if (nrow(S98)) for (k in seq_len(nrow(S98))) say("  %-30s n=%3.0f 무처리 %+.3f → 파킹 %+.3f (Δ %+.3f) %s",
  substr(S98$id[k],1,30), S98$n[k], S98$base[k], S98$rs_sm[k], S98$rs_sm[k]-S98$base[k],
  if (!is.na(S98$rs_sm[k]) && S98$rs_sm[k] < 0) " ★부족분 음수 = 문턱 충족" else "")
say("  ★mega_spread 로는 겹침 51<60 이라 **측정 자체가 불가**했다(칩 task_b065b34d).")
say("=== 귀무 창 게이트 (ON 창이 우연히 특별한가) ===")
best <- R[!is.na(rs_sm)][which.min(rs_sm)]
j <- which(INV$names == best$id)[1]
X <- merge(inc[, .(m, date, benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")[order(m)]
W <- merge(X, LB, by="m")[order(m)]
nl <- subsample_null(x = W$r, y = W$benchmark_ret, subset = W$on,
                     stat = function(a,b) cor(a,b), n_draw = 1000)
say("  최고 전략 %s: Δrho %+.4f · 백분위 %.1f%% · inside %s",
    substr(best$id,1,26), nl$observed - nl$null_mean, 100*nl$percentile, nl$inside)
fwrite(R, file.path(OUT,"m2_long_window.csv"))
say("=== m2 완료 ===")
