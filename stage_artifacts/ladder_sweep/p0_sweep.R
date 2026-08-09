## 사다리 일괄 적용 — PORT_t 갭의 비-신호 채널 비중이 재료 공통인가
## 근거: 오늘 두 재료에서 같은 구조가 나왔다.
##   M26     : net 1.544 → 비용제거 2.041 → EW-basis 2.818  (갭의 대부분 설명, 그래도 미달)
##   계약규칙 : net 2.204 → 2.379 → **2.966**              (설명 102%, 문턱 통과)
## ⇒ 이게 재료 공통이면 '전이 벽' 의 상당분이 **측정 basis + 비용**이지 신호 문제가 아니다.
##   병목 지도의 갭 귀속이 바뀐다.
## ★진단 라운드 — 반사실(0bps)·EW-basis 는 자본 주장 불가 라벨.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/ladder_sweep")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")

## FQ-169 패널 재사용 (11팩터 × 282개월, 이미 계약 경로로 적재)
W <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ169/panel.rds")))
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; bd <- as.data.table(P$bench); liq <- as.data.table(P$liq)
size_dt <- as.data.table(P$size_dt)
say("=== 입력 실측 === 패널 %d행 · %d개월 · %s ~ %s", nrow(W), uniqueN(W$Date), min(W$Date), max(W$Date))

FN <- c("M26_Revenue_Mom","M01_Mom_12_1","D03_RealVol","D35_RealVol_63d","D50_MaxDrawdown",
        "D45_Downside_Dev","D41_Vol_of_Vol","D34_RealVol_21d")
FN <- intersect(FN, names(W))
say("  대상 %d재료: %s", length(FN), paste(FN, collapse=", "))

pt <- function(S, cost, ew) {
  r <- suppressWarnings(canonical_screen_bt(S, ret, bd, top_n = 25L, cost_bps_oneway = cost,
        liq_dt = liq, liq_min = 2e8, run_id = "L", strategy_id = "L",
        diag_dual_basis = ew, size_dt = size_dt))
  if (ew) {
    d <- r$diag_ew_universe
    if (!is.null(d) && !is.null(d$portfolio_alpha_t_nw_lag3)) return(d$portfolio_alpha_t_nw_lag3)
    return(NA_real_)
  }
  r$portfolio_alpha_t_nw_lag3
}

say("=== ★사다리 (net 15bps → gross 0bps → EW-유니버스 basis) ===")
say("  %-18s %8s %8s %8s | %8s %8s | 문턱까지", "재료", "net", "gross", "EW", "Δ비용", "Δ벤치")
rows <- list()
for (k in FN) {
  S <- W[!is.na(get(k)), .(Date, Ticker, score = get(k))]
  n1 <- pt(S, 15, FALSE); n2 <- pt(S, 0, FALSE); n3 <- pt(S, 0, TRUE)
  say("  %-18s %+8.3f %+8.3f %+8.3f | %+8.3f %+8.3f | net %+.3f · 제거후 %+.3f",
      k, n1, n2, n3, n2-n1, n3-n2, 2.95-n1, n3-2.95)
  rows[[length(rows)+1L]] <- data.table(factor=k, net=n1, gross=n2, ew=n3,
    d_cost=n2-n1, d_bench=n3-n2, gap=2.95-n1, explained=n3-n1,
    explained_pct=100*(n3-n1)/(2.95-n1), crosses=n3>=2.95)
}
R <- rbindlist(rows)
say("=== ★요약 ===")
say("  갭 설명률(비-신호 채널 / 문턱까지 갭) 중앙 %.0f%% · 범위 %.0f~%.0f%%",
    median(R$explained_pct), min(R$explained_pct), max(R$explained_pct))
say("  두 채널 제거 후 문턱 통과: **%d / %d**", sum(R$crosses), nrow(R))
if (any(R$crosses)) say("    통과 재료: %s", paste(R[crosses==TRUE, factor], collapse=", "))
say("  채널 크기: Δ비용 중앙 %+.3f · Δ벤치 중앙 %+.3f (벤치가 %.1f배)",
    median(R$d_cost), median(R$d_bench), median(R$d_bench)/median(R$d_cost))
say("=== ★외부 대조 (오늘 별도 측정) ===")
say("  M26(WT-D20260809_001)  : net 1.544 → 2.041 → 2.818 · 설명 91%% · 미통과")
say("  계약 국면규칙(FQ-191)   : net 2.204 → 2.379 → 2.966 · 설명 102%% · **통과**")
say("=== 판정 ===")
say("  ★설명률이 재료 공통으로 높으면 = 전이 벽의 상당분이 **측정 basis + 비용**")
say("    단 두 채널 모두 **고정 축** — 자본 주장 불가. 병목 귀속 재판정 근거일 뿐.")
fwrite(R, file.path(OUT, "ladder.csv")); saveRDS(R, file.path(OUT, "p0.rds"))
say("=== 완료 ===")
