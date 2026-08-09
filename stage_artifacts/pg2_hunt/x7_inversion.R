## x7 — jump_JM_State **반전 파킹**(OFF 월 보유)이 직교성 레버인가
## x6 관측: jump_JM_State ON 월은 북과 **더** 상관(8/8 백분위>50, p 0.0039).
##
## ★함정 선언 (측정 전): "ON rho 가 높으면 OFF rho 는 낮다" 는 **거의 산술적 항등**이다.
##   전체 상관은 ON·OFF 의 가중 혼합이므로 한쪽이 높으면 다른 쪽은 낮다.
##   ⇒ "반전 파킹이 rho 를 낮춘다" 를 확인하는 것은 **정보가 0** 이다(오늘 반복된 항등변환 계통).
## ★비-항등 질문 = **ΔIR 이 나아지는가**. ΔIR 은 낮은 rho **와** 높은 IR 을 동시에 요구하므로,
##   반전이 rho 를 낮추면서 IR 도 함께 무너지면 순이득이 없다. 그것이 실제 질문이다.
##
## ★사전등록: 1급 = 반전 ΔIR vs **같은 발화율 무작위 타이밍** 200회 (구조 vs 라벨 분리).
##   2급 = 반전 ΔIR vs 정상 파킹. argmax 금지 · 전 재료 보고.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x7] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]

f2 <- list.files(".", pattern="^regime_jump_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
J <- as.data.table(read_parquet(f2))
dc <- names(J)[which(tolower(names(J)) %in% c("date","ym"))[1]]
J[, .dd := as.Date(as.character(get(dc)))]
mo <- J[!is.na(.dd)][order(.dd)][, .(v = last(JM_State)), by = .(m = mi(.dd))]
mo[, m_apply := m + 1L]                                       # ★익월 적용 (PIT)
dom <- names(sort(table(mo$v), decreasing=TRUE))[1]
LAB <- data.table(m = mo$m_apply, on = mo$v == dom)[m %in% inc$m]
say("=== 라벨 === jump_JM_State · %d개월 · ON %d (%.1f%%) · 에피소드 %d",
    nrow(LAB), sum(LAB$on), 100*mean(LAB$on), sum(rle(as.integer(LAB$on[order(LAB$m)]))$values == 1L))

pr_of <- function(f) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net, benchmark_ret)]
  PR[, m := mi(date) + 2L]
  merge(PR, LAB, by = "m")
}
run_rule <- function(Z, hold_vec) {
  X <- copy(Z)[, hold := hold_vec]
  X[, sw := c(0L, abs(diff(as.integer(hold))))]
  X[, r2 := ifelse(hold, ret_net, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc, bootstrap = FALSE)
  if (is.null(o$delta_ir)) return(NULL)
  c(rho = o$correlation_with_incumbent, ir = o$sleeve_standalone_ir, d = o$delta_ir, n = o$n_overlap)
}

TB <- fread(file.path(OUT,"c6_full_table.csv"))
top <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
set.seed(7); rnd <- sample(setdiff(unique(A$Factor_Name), top), 4)
FS <- c(top, rnd)
say("=== 재료 %d종 · 3-arm (정상 파킹 / **반전 파킹** / 동일발화율 무작위 60회) ===", length(FS))
say("  %-24s %8s %7s %8s | %8s %7s %8s | %9s %8s",
    "factor","정상 ΔIR","rho","IR","반전 ΔIR","rho","IR","무작위중앙","반전 백분위")
set.seed(20260809); rows <- list()
for (f in FS) {
  Z <- pr_of(f); if (is.null(Z) || nrow(Z) < 60) next
  a <- run_rule(Z, Z$on)             # 정상: ON 보유
  b <- run_rule(Z, !Z$on)            # ★반전: OFF 보유
  if (is.null(a) || is.null(b)) next
  k <- sum(!Z$on); n <- nrow(Z)
  rr <- vapply(seq_len(60L), function(i) {
    v <- rep(FALSE, n); v[sample.int(n, k)] <- TRUE
    o <- run_rule(Z, v); if (is.null(o)) NA_real_ else o["d"] }, numeric(1))
  rr <- rr[is.finite(rr)]
  say("  %-24s %+8.4f %+7.3f %+8.3f | %+8.4f %+7.3f %+8.3f | %+9.4f %7.0f%%",
      substr(f,1,24), a["d"], a["rho"], a["ir"], b["d"], b["rho"], b["ir"],
      median(rr), 100*mean(rr < b["d"]))
  rows[[length(rows)+1L]] <- data.table(factor=f, grp=if (f %in% top) "근접" else "무작위",
    a_d=a["d"], a_rho=a["rho"], a_ir=a["ir"], b_d=b["d"], b_rho=b["rho"], b_ir=b["ir"],
    rnd_med=median(rr), pct=100*mean(rr < b["d"]))
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
say("  [항등 확인] 반전이 rho 를 낮추는가: %d/%d (★이건 정보 0 — 산술적으로 기대됨)",
    sum(R$b_rho < R$a_rho), nrow(R))
say("  ★1급 = 반전 ΔIR vs 동일발화율 무작위: 95 백분위 초과 **%d/%d** · 백분위 중앙 %.0f%%",
    sum(R$pct > 95), nrow(R), median(R$pct))
say("  2급 = 반전 vs 정상: ΔIR 개선 %d/%d · 중앙 %+.4f", sum(R$b_d > R$a_d), nrow(R), median(R$b_d - R$a_d))
say("  IR 대가: 반전 IR − 정상 IR 중앙 %+.3f (rho 인하 대가로 IR 을 잃는가)",
    median(R$b_ir - R$a_ir))
say("  최고 반전 ΔIR %+.4f (%s) — 문턱 0.05 %s",
    max(R$b_d), R[which.max(b_d), factor], if (max(R$b_d) >= 0.05) "★통과" else "미달")
say("  ⇒ %s", if (sum(R$pct > 95) == 0)
  "★반전은 무작위 타이밍과 구분되지 않는다 — **라벨 정보 아님, 구조 효과**" else
  sprintf("★%d 재료에서 무작위 초과 — 라벨에 실질 정보(단 %d셀 다중검정 고려)", sum(R$pct>95), nrow(R)))
fwrite(R, file.path(OUT,"x7_inversion.csv"))
say("=== x7 완료 ===")
