## s6 — s4 실패 지점 계측 (추측 금지 · 각 단계 실측)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s6] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
say("=== 라벨 === %d개월 · m 범위 [%d, %d] = %s ~ %s", nrow(LB), min(LB$m), max(LB$m),
    sprintf("%04d-%02d", (min(LB$m)-1)%/%12, (min(LB$m)-1)%%12+1),
    sprintf("%04d-%02d", (max(LB$m)-1)%/%12, (max(LB$m)-1)%%12+1))
say("=== PG2 === m 범위 [%d, %d]", min(inc$m), max(inc$m))

j <- which(INV$names == "STR_1698_WT008_M08_Swap")[1]
say("=== 대상 인덱스 %d ===", j)
S <- INV$ser[[j]]
say("  전략 계열 %d행 · m 범위 [%d, %d] · r 유한 %d", nrow(S), min(S$m), max(S$m), sum(is.finite(S$r)))
X <- merge(inc[, .(m, date, benchmark_ret)], S[, .(m, r)], by="m")
say("  X = inc ⋈ S : **%d행**", nrow(X))
W <- merge(X, LB, by="m")
say("  W = X ⋈ LB : **%d행** (가드 문턱 40)", nrow(W))
if (nrow(W) < 40) { say("  ★여기서 실패 — 파킹 창 겹침 부족"); quit(status=0) }
say("  W 날짜 예시: %s", paste(head(as.character(W$date),3), collapse=", "))
say("  W$r 유한 %d · W$benchmark_ret 유한 %d · on TRUE %d", sum(is.finite(W$r)),
    sum(is.finite(W$benchmark_ret)), sum(W$on))

a <- bm_delta_ir(W[, .(date, ret_net = r)], weight=0.20, incumbent=inc, bootstrap=FALSE)
say("=== A arm 결과 ===")
say("  status %s · align_offset %s · n_overlap %s",
    a$status, if (is.null(a$align_offset)) "NULL" else a$align_offset,
    if (is.null(a$n_overlap)) "NULL" else a$n_overlap)
say("  delta_ir %s", if (is.null(a$delta_ir)) "**NULL ← 여기가 실패 지점**" else sprintf("%+.4f", a$delta_ir))
if (!is.null(a$note)) say("  note: %s", substr(a$note, 1, 160))

W2 <- copy(W)[order(m)][, sw := c(0L, abs(diff(as.integer(on))))]
W2[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
say("=== P arm 입력 === rp 유한 %d · 전환 %d회", sum(is.finite(W2$rp)), sum(W2$sw))
p <- bm_delta_ir(W2[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
say("  status %s · n_overlap %s · delta_ir %s", p$status,
    if (is.null(p$n_overlap)) "NULL" else p$n_overlap,
    if (is.null(p$delta_ir)) "**NULL**" else sprintf("%+.4f", p$delta_ir))
if (!is.null(p$note)) say("  note: %s", substr(p$note, 1, 160))
say("=== ★진단 ===")
say("  ★s4 는 `if (is.null(a$delta_ir) || is.null(p$delta_ir)) next` 로 **조용히 건너뛰었다**.")
say("     실패 지점을 로그로 남기지 않은 것이 결함 — 0 은 정지 신호여야 한다.")
