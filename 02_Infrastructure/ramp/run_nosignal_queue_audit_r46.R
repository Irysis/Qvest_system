## run_nosignal_queue_audit_r46.R — R46: 소비 큐(overlay_candidate_queue) 22건에 무신호 대조 게이트 적용
## 근거: measurement-graduation §3 무신호 대조 통과 의무(2026-08-22 신설).
##   제안서 반영 파급 절 — "제약형 롱온리 모듈이 screen-tier 라벨을 보유한 경우 재확인 권고".
## ★범위 한정: 14,112개 hurdle_result 전수가 아니라 **실제 소비되는 큐**만 본다.
##   등재만 되고 소비자가 없는 라벨은 파급이 없으므로 위험이 아니다(FR_RCMA 풀이 실 소비면).
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/no_signal_control.R")

Q <- fromJSON("06_Registry/overlay_candidate_queue.json", simplifyVector = FALSE)$candidates
cat(sprintf("소비 큐 후보 = %d건\n", length(Q)))

## 1) 각 후보의 월수익·벤치 추출
extract <- function(p) {
  if (is.null(p) || !nzchar(p) || !file.exists(p)) return(NULL)
  bt <- tryCatch(readRDS(p), error = function(e) NULL); if (is.null(bt)) return(NULL)
  pr <- bt$period_returns; br <- bt$benchmark_returns
  if (is.null(pr)) return(NULL)
  pr <- as.data.table(pr)
  ## ★2026-08-22 어댑터 확장: 10-component 계약이 아닌 산출물은 벤치를 **period_returns 안에**
  ##   싣는다(실측: LH_D2_loser_augment 의 forge_result 는 benchmark_returns=NULL 이고
  ##   period_returns 에 date/ret_net/benchmark_ret 3열). 뻣뻣한 추출기가 그걸 NOT_AUDITED 로
  ##   버리고 있었다 — 형식 분화는 결측이 아니라 **어댑터 갭**이다.
  if (is.null(br) && any(c("benchmark_ret","bm_ret") %in% names(pr))) {
    bcn <- intersect(c("benchmark_ret","bm_ret"), names(pr))[1]
    dcn <- intersect(c("date","Date"), names(pr))[1]
    if (!is.na(bcn) && !is.na(dcn)) br <- pr[, c(dcn, bcn), with = FALSE]
  }
  if (is.null(br)) return(NULL)
  br <- as.data.table(br)
  rc <- intersect(c("ret_net","ret","return"), names(pr))[1]
  bc <- intersect(c("benchmark_ret","bm_ret","ret"), names(br))[1]
  dc1 <- intersect(c("date","Date"), names(pr))[1]; dc2 <- intersect(c("date","Date"), names(br))[1]
  if (any(is.na(c(rc, bc, dc1, dc2)))) return(NULL)
  ## ★일별 계열일 수 있으므로 월 복리 집계 후 병합(카테시안 방지)
  P <- pr[, .(ym = format(as.Date(get(dc1)), "%Y-%m"), v = get(rc))][is.finite(v)]
  B <- br[, .(ym = format(as.Date(get(dc2)), "%Y-%m"), v = get(bc))][is.finite(v)]
  P <- P[, .(r = prod(1 + v) - 1), by = ym]
  B <- B[, .(b = prod(1 + v) - 1), by = ym]
  m <- merge(P, B, by = "ym")
  m <- m[is.finite(r) & is.finite(b)]; setorder(m, ym)
  if (nrow(m) < 36) return(NULL)
  m
}
SER <- list(); META <- list()
for (q in Q) {
  s <- extract(q$bt_result_path)
  if (is.null(s)) next
  SER[[q$id]] <- s
  META[[q$id]] <- list(name = q$strategy_name, route = q$screen_route,
                       grade = q$essence_grade %||% q$grade,
                       sharpe = q$signal_summary$sharpe, mdd = q$signal_summary$mdd_pct,
                       to = q$signal_summary$turnover_ann_pct)
}
cat(sprintf("월수익 추출 성공 = %d / %d\n", length(SER), length(Q)))
if (!length(SER)) { cat("추출 0건 — 계열 형식 재확인 필요\n"); quit(status = 0) }

## 2) 공통 월 그리드로 무신호 대조군 1회 구축 후 재사용
allym <- sort(unique(unlist(lapply(SER, function(x) x$ym))))
cat(sprintf("공통 그리드: %s ~ %s (%d개월)\n", allym[1], allym[length(allym)], length(allym)))
CTL <- build_no_signal_control(months = allym, n_stocks = 25L, cap = 0.20, freq = 3L, bps = 15)
cat(sprintf("대조군: 리밸 %d회 · 보유 중앙 %d종 · 최대비중 %.4f\n\n", CTL$n_rebal, CTL$holdings_n, CTL$max_w))

## 3) 게이트 적용
cat(sprintf("%-32s %-6s %5s %9s %9s %8s  %s\n","전략","grade","n","차이/yr","NW-t","t(alpha)","verdict"))
rows <- list()
for (id in names(SER)) {
  s <- SER[[id]]; i <- match(s$ym, allym)
  cv <- CTL$ret[i]
  k <- which(is.finite(s$r) & is.finite(cv) & is.finite(s$b))
  if (length(k) < 24) { cat(sprintf("%-32s (공통 관측 부족 %d)\n", substr(META[[id]]$name,1,32), length(k))); next }
  g <- tryCatch(no_signal_gate(s$r[k], cv[k], s$b[k]), error = function(e) NULL)
  if (is.null(g)) next
  cat(sprintf("%-32s %-6s %5d %+9.4f %+9.3f %+8.3f  %s\n",
      substr(META[[id]]$name, 1, 32), META[[id]]$grade, g$n, g$diff_ann, g$diff_nw_t,
      g$strategy[["t_alpha"]], g$verdict))
  rows[[length(rows)+1]] <- data.table(id = id, name = META[[id]]$name, grade = META[[id]]$grade,
    n = g$n, diff_ann = g$diff_ann, diff_nw_t = g$diff_nw_t,
    t_alpha = g$strategy[["t_alpha"]], beta = g$strategy[["beta"]],
    port_t = g$strategy[["port_t"]], beta_contrib = g$strategy[["beta_contrib_ann"]],
    verdict = g$verdict)
}
T <- rbindlist(rows)
cat("\n=== 판정 요약 ===\n")
print(T[, .N, by = verdict])
cat(sprintf("\n  SIGNAL_ADDS_VALUE  : %d건 — 무신호 대조를 유의하게 이김(신호 기여 실증)\n",
            sum(T$verdict == "SIGNAL_ADDS_VALUE")))
cat(sprintf("  INDISTINGUISHABLE  : %d건 — ★§3 신설 조항상 screen-tier 등재 근거 없음\n",
            sum(T$verdict == "INDISTINGUISHABLE_FROM_NO_SIGNAL")))
cat(sprintf("  SIGNAL_HURTS       : %d건\n", sum(T$verdict == "SIGNAL_HURTS")))
cat(sprintf("\n  β 오염 진단: PORT_t 양수인데 t(alpha) 비유의인 건 = %d\n",
            sum(T$port_t > 0 & abs(T$t_alpha) < 1.96)))
fwrite(T, "06_Registry/no_signal_queue_audit_r46_20260822.csv")
cat("\n산출: 06_Registry/no_signal_queue_audit_r46_20260822.csv\n")
cat("\nR46_DONE\n")
