# =============================================================================
# ap4_c11_lag_impact.R — WT-D20260803_005 자기적대검증 AP-4
#   ast_spec_gate 의 PIT 정적검증이 REGISTRY[D32_Beta_VIX] 를 FAIL_LOOKAHEAD 로 잡았다:
#   availability.rule = "C11_publication_lag" → 보수 avail = t + 35d.
#   sig_date 2026-06-30 → avail 2026-08-04 > decision_ts 2026-08-03.
#
#   두 가지를 분리해 처리한다:
#   (1) *패키지 선언* 문제 — decision_ts 를 '마지막 신호월이 최대 보수 지연까지 반영돼
#       실행 가능해지는 최초 시점'으로 정정 (본 라운드는 자본 결정을 하지 않으므로 정직 선언).
#   (2) *측정 자체* 문제 — 보수 35d 지연 리프를 sig_date t 에 썼다면, 그 factor 들의
#       월별 신호는 최대 ~1개월 늦게 가용했을 수 있다. 이 factor 를 풀에서 제외하면
#       본 라운드 판정이 바뀌는가? (바뀌면 재측정, 안 바뀌면 정량 기록)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/ap4_c11_lag_impact.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005AP4] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/backtest_result_contract.R")
nw_t <- function(x, lag = 3L) .nw_t_mean(x, lag = lag)
P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
REG <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
POOL <- P1R$pool; A <- P1R$A; GRIDS <- P1R$grids

rule_of <- function(f) { a <- REG[[f]]$availability; if (is.null(a$rule)) NA_character_ else as.character(a$rule)[1] }
RL <- data.table(Factor_Name = POOL, rule = vapply(POOL, rule_of, character(1)))
print(RL[, .N, by = rule][order(-N)])
LAGGED <- RL[rule == "C11_publication_lag", Factor_Name]
say("보수 35d 지연 리프(C11_publication_lag) factor: %d / %d — %s",
    length(LAGGED), length(POOL), paste(head(LAGGED, 20), collapse = ", "))

make_bounds <- function(n, W) { b <- list(); e <- n
  while (e-W+1L >= 1L) { b[[length(b)+1L]] <- c(e-W+1L, e); e <- e-W }; rev(b) }
win_t <- function(v, bnd, mo) vapply(bnd, function(ix) { x <- v[ix[1]:ix[2]]; xv <- x[is.finite(x)]
  if (length(xv) < mo || length(xv)/(ix[2]-ix[1]+1L) < 0.90) return(NA_real_); nw_t(xv) }, numeric(1))
pairs_of <- function(TT) rbindlist(lapply(seq_len(nrow(TT)-1L), function(k) {
  tk <- TT[k,]; tn <- TT[k+1L,]; ok <- is.finite(tk) & is.finite(tn)
  if (!any(ok)) return(NULL)
  data.table(Factor_Name = colnames(TT)[ok], k = k, t_k = tk[ok], t_next = tn[ok]) }))

res <- rbindlist(lapply(names(GRIDS), function(nm) {
  g <- GRIDS[[nm]]
  full <- P1R$PR[[nm]]
  keep <- setdiff(POOL, LAGGED)
  sub  <- full[Factor_Name %in% keep]
  data.table(grid = nm,
    p_all = mean(sign(full$t_k) == sign(full$t_next)), n_all = nrow(full),
    p_ex  = mean(sign(sub$t_k)  == sign(sub$t_next)),  n_ex = nrow(sub),
    topbin_all = full[abs(t_k) >= 2, mean(sign(t_k) == sign(t_next))],
    topbin_ex  = sub[abs(t_k)  >= 2, mean(sign(t_k) == sign(t_next))])
}))
res[, `:=`(d_p = p_ex - p_all, d_top = topbin_ex - topbin_all)]
print(res)
say("★ AP-4 판정: C11 지연 factor %d종 제외 시 P_persist Δ 최대 %+.4f / 최상위 bin Δ 최대 %+.4f → %s",
    length(LAGGED), res[which.max(abs(d_p)), d_p], res[which.max(abs(d_top)), d_top],
    ifelse(max(abs(res$d_p)) < 0.01 && max(abs(res$d_top)) < 0.03,
           "판정 불변(정량 확인)", "판정 변동 — 재측정 필요"))

# lag1(1개월 지연) 적용 시 해당 factor 창 부호가 바뀌는가 — 35d 지연의 실질 상한 근사
LAGA <- A[, intersect(LAGGED, colnames(A)), drop = FALSE]
say("C11 factor 창-부호 lag1 민감도 (active 시계열 1개월 shift):")
sens <- rbindlist(lapply(colnames(LAGA), function(f) {
  v <- LAGA[, f]; vl <- c(NA_real_, v[-length(v)])
  bnd <- make_bounds(length(v), GRIDS$primary$W)
  t0 <- win_t(v, bnd, GRIDS$primary$min_obs); t1 <- win_t(vl, bnd, GRIDS$primary$min_obs)
  data.table(Factor_Name = f, n_win = sum(is.finite(t0) & is.finite(t1)),
             sign_same = sum(sign(t0) == sign(t1), na.rm = TRUE),
             max_abs_dt = max(abs(t1 - t0), na.rm = TRUE)) }))
print(sens)
say("C11 factor lag1: 창 부호 유지 %d / %d 셀 | 최대 |Δt| %.3f",
    sum(sens$sign_same), sum(sens$n_win), max(sens$max_abs_dt))

saveRDS(list(rule_census = RL[, .N, by = rule], lagged = LAGGED, impact = res, lag1_sens = sens,
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "ap4_c11.rds"))
say("저장 — ap4_c11.rds")
