# pi0_current.R — 현행 암묵 정책의 재현 (양성 대조)
#   1) 블록 순서 = entry 에 기록된 순서(없으면 격자 순서 B1>B2>B3>B5>B4)
#   2) 그 블록에서 코드 번호순 첫 빈 칸부터 <=W, **같은 블록만**
#   3) 스스로 멈추지 않는다 — 합법 칸이 없거나 예산이 끝나면 엔진이 멈춘다
#
# 대응 코드: reinforce_auto_parallel.R:247-272 (블록 정렬 + 같은 블록 접두 배치)
#            rf_spec_sig.R:108-111 (.rf_free_cells — 코드 기준 커서)

rf_policy_fn <- function(view) {
  lg <- view$legal()
  if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  ord <- view$meta$block_order
  if (!length(ord)) ord <- c("B1", "B2", "B3", "B5", "B4")
  rk <- match(lg$block, ord); rk[is.na(rk)] <- 99L
  # 코드 안 숫자로 정렬 — 문자열 정렬은 B1_10 을 B1_2 앞에 둔다
  num <- suppressWarnings(as.integer(sub("^B[0-9]+_", "", lg$cell_code)))
  lg <- lg[order(rk, num, lg$cell_code), , drop = FALSE]
  first_block <- lg$block[1]
  sel <- lg$node_id[lg$block == first_block]
  list(batch = head(sel, view$meta$W), stop = FALSE)
}
