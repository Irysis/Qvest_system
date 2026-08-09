## m3 — STR_1698 + Regime_Score_smooth_high 파킹이 **부족분 -0.085(문턱 통과)** 를 냈다.
## ★오늘 아크 51라운드 만의 첫 문턱 통과 ⇒ **최대 의심**으로 적대 배터리를 건다.
## ★m2 에서 귀무 창 게이트가 **아무것도 출력 안 함** = 침묵 실패. 먼저 계측한다.
## 배터리 6축 (하나라도 실패 시 통과 주장 불가):
##   A. 침묵 실패 원인 규명 + 귀무 창 게이트 실측
##   B. **C5 오버레이 PIT** — assert_overlay_pit + lag 스트레스(0/+1/+2). 동월 누출이면 전부 무효
##   C. ΔIR **부트스트랩 CI** — 점추정 통과는 통과가 아니다(계약 verdict_ci)
##   D. **하네스 적격(AX-002)** — 계약 미준수면 통계와 무관하게 차단(STR_1675 선례)
##   E. **선택 편의** — 방향을 12전략에서 골랐다. 나머지 12는 아무도 0을 안 넘는데 왜 이것만?
##   F. **양성/음성 대조** — 반대 방향(low)은 나빠야 하고, 무작위는 중간이어야 한다
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[m3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
source("02_Infrastructure/contracts/harness_compliance.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
RATE <- 0.3562; TGT <- "STR_1698_WT008_M08_Swap"
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
MO <- U[!is.na(.dd)][order(.dd)][, .(rss = last(Regime_Score_smooth), dd = max(.dd)), by=.(m = mi(.dd))]
TH <- quantile(MO$rss, 1-RATE, na.rm=TRUE)
j <- which(INV$names == TGT)[1]
X <- merge(inc[, .(m, date, benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")[order(m)]
mk <- function(lag) data.table(m = MO$m + lag, on = MO$rss >= TH)[!is.na(on)]
run <- function(LBx, boot=FALSE, B=1000) {
  W <- merge(X, LBx, by="m")[order(m)]; if (nrow(W) < 60) return(NULL)
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=boot, B_boot=B)
  o$W <- W; o$short <- need_ir(o$correlation_with_incumbent) - o$sleeve_standalone_ir; o }

say("=== A. 침묵 실패 원인 + 귀무 창 게이트 ===")
o1 <- run(mk(1L)); W <- o1$W
say("  W 행 %d · on %d (%.1f%%) · r NA %d · bm NA %d",
    nrow(W), sum(W$on), 100*mean(W$on), sum(is.na(W$r)), sum(is.na(W$benchmark_ret)))
nl <- tryCatch(subsample_null(x = W$r, y = W$benchmark_ret, subset = W$on,
                              stat = function(a,b) cor(a,b), n_draw = 1000),
               error = function(e) { say("  ★침묵 원인 = subsample_null 예외: %s", conditionMessage(e)); NULL })
if (!is.null(nl)) say("  Δrho %+.4f · 백분위 %.1f%% · inside %s ⇒ %s",
    nl$observed - nl$null_mean, 100*nl$percentile, nl$inside,
    if (isTRUE(nl$inside)) "ON 창 특별하지 않음(정상)" else "★ON 창이 극단 = 우연 구간 의심")

say("=== B. C5 오버레이 PIT + lag 스트레스 (핵심 관문) ===")
pg <- tryCatch({ source("02_Infrastructure/validation/overlay_pit_guard.R")
  hs <- min(W$date); cut <- MO[m == min(W$m) - 1L, dd]
  say("  신호 컷오프 %s → 홀딩월 시작 %s (간격 %d일)", cut, hs, as.integer(hs - cut))
  r <- tryCatch(assert_overlay_pit(cut, hs), error=function(e) conditionMessage(e)); r },
  error=function(e) paste("guard 로드 실패:", conditionMessage(e)))
say("  assert_overlay_pit: %s", if (isTRUE(pg)) "PASS" else as.character(pg)[1])
for (L in c(0L,1L,2L,3L)) { o <- run(mk(L))
  say("  lag %+d : rho %+.3f · IR %+.3f · 부족분 **%+.4f**%s", L,
      o$correlation_with_incumbent, o$sleeve_standalone_ir, o$short,
      if (L==1L) "  ← 채택 판본" else if (L==0L) "  ← 동월(누출 판본)" else "") }

say("=== C. ΔIR 부트스트랩 CI (계약 verdict_ci) ===")
ob <- run(mk(1L), boot=TRUE, B=2000)
say("  ΔIR 점추정 %+.4f · CI [%+.4f, %+.4f]", ob$delta_ir, ob$delta_ir_ci[1], ob$delta_ir_ci[2])
say("  ★verdict_ci = **%s** (문턱 0.05)", ob$verdict_ci)

say("=== D. 하네스 적격 (AX-002) ===")
hc <- tryCatch(harness_compliance(TGT), error=function(e) list(tier=paste("ERR:",conditionMessage(e))))
say("  tier = **%s**%s", hc$tier, if (!is.null(hc$note)) sprintf(" (%s)", substr(hc$note,1,70)) else "")

say("=== E. 선택 편의 — 왜 이것만 넘는가 ===")
say("  무처리 부족분 %+.4f 가 13전략 중 **최소**였다(2위 WT-S20260504_004 +0.002)",
    need_ir(bm_delta_ir(X[, .(date, ret_net=r)], weight=0.20, incumbent=inc, bootstrap=FALSE)$correlation_with_incumbent) -
    bm_delta_ir(X[, .(date, ret_net=r)], weight=0.20, incumbent=inc, bootstrap=FALSE)$sleeve_standalone_ir)
say("  ⇒ 파킹 Δ(-0.171)는 13전략 중앙(-0.117)과 유사 — **파킹이 특별한 게 아니라 출발점이 가장 좋았다**")

say("=== F. 양성/음성 대조 ===")
oL <- run(data.table(m = MO$m + 1L, on = MO$rss <= quantile(MO$rss, RATE, na.rm=TRUE))[!is.na(on)])
set.seed(20260809); CMx <- intersect(X$m, MO$m + 1L)
rr <- median(vapply(1:50, function(i) { v <- rep(FALSE, length(CMx)); v[sample.int(length(CMx), round(RATE*length(CMx)))] <- TRUE
  o <- run(data.table(m = sort(CMx), on = v)); if (is.null(o)) NA_real_ else o$short }, numeric(1)), na.rm=TRUE)
say("  high(채택) %+.4f  <  무작위 %+.4f  <  low(음성대조) %+.4f  ⇒ %s",
    o1$short, rr, oL$short,
    if (o1$short < rr && rr < oL$short) "**서열 정합 — 축이 정보를 담음**" else "★서열 깨짐 = 축 해석 재검토")
saveRDS(list(nl=nl, boot=ob, hc=hc, lag=sapply(0:3, function(L) run(mk(as.integer(L)))$short)),
        file.path(OUT,"m3_adversarial.rds"))
say("=== m3 완료 ===")
