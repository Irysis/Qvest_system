#!/usr/bin/env Rscript
#==============================================================================
# rf_weight_arms.R — B2(비중) 셀을 **카탈로그에서 선정** (도훈 지시 2026-08-30)
#
# ★왜 바꾸나 — 같은 병을 내가 한 번 더 밟았다:
#   `weight_catalog.R`(2026-08-24 신설) 헤더가 이미 진단해 뒀다 —
#   "세 갈래는 계약이 달라서 안 붙은 게 아니라 **다리가 없어서** 안 붙었다.
#    R1 lean 23종 · R2 QEPM 14종 · R3 어댑터. 7개월간 R2 실호출 1건. 이유는 계약 충돌이 아니라
#    **아무도 한 줄을 안 썼기 때문**이다."
#   그런데 2026-08-30 무인 격자를 짜면서 나는 **카탈로그를 안 쓰고 5종을 새로 구현**했다.
#   등록 52종 중 5종만 쓴 셈이고, 안 건드린 축이 tail_aware·entropy·risk_parity·optimizer 전부다.
#   ★그리고 B1 계열이 낙폭 55~62%에 갇혀 있었는데 **꼬리·엔트로피 계열이 정확히 그 축을 겨눈다.**
#
# 이 파일이 하는 일: 카탈로그에서 arm 을 뽑아 **계열 다양성**을 강제하며 B2 5칸을 고른다.
#   판단이 아니라 규칙이다 — probe_ok 통과분에서 계열당 1개씩, 미측정 우선.
#
# 사용: rf_pick_weight_arms(n = 5) → list(cells = [...])  (격자 B2 cells 형식)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFW_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

#' 카탈로그에서 B2 비중 arm n개 선정
#' @param n 뽑을 개수 (격자 B2 칸 수)
#' @param exclude 이미 측정한 label (중복 회피)
rf_pick_weight_arms <- function(n = 5L, exclude = character(0)) {
  suppressMessages(source(file.path(.RFW_ROOT, "02_Infrastructure/portfolio/weight_catalog.R")))
  A <- tryCatch(as.data.table(weight_catalog_arms()), error = function(e) NULL)
  if (is.null(A) || !nrow(A)) return(NULL)

  # ① 실행 가능한 것만 — probe 가 실패한 arm 은 셀이 통째로 죽는다
  if ("probe_ok" %in% names(A)) A <- A[probe_ok %in% c(TRUE, NA)]
  if ("status" %in% names(A))   A <- A[!status %in% c("retracted", "withdrawn", "failed")]
  A <- A[!(label %in% exclude)]
  if (!nrow(A)) return(NULL)

  # ② EW 는 기준선이라 격자에 넣지 않는다(B1 이 이미 EW 다)
  A <- A[!label %in% c("equal", "ew", "equal_weight")]

  # ③ ★계열 다양성 강제 — 한 계열에서 여러 개 뽑으면 같은 축을 반복 측정한다.
  #    2026-08-30 실측 근거: 내가 고른 5종 중 3종이 score_blend 계열이었고
  #    셋 다 EW 대비 열화하는 같은 결론을 냈다(1.441/1.411/1.396). 정보량 중복이다.
  setorderv(A, c("family", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- A[, .SD[1L], by = family]              # 계열당 1개
  # 낙폭 축을 겨누는 계열을 앞세운다 — B1 이 MDD 55~62%에 갇힌 것이 실측 구속축이다
  prio <- c("tail_aware" = 1, "entropy" = 2, "risk_parity" = 3, "risk_based" = 4,
            "optimizer" = 5, "classical" = 6, "score_blend" = 7)
  picked[, .prio := prio[family] %||% 9]
  picked[is.na(.prio), .prio := 9]
  setorderv(picked, c(".prio", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- head(picked, n)
  if (!nrow(picked)) return(NULL)

  cells <- lapply(seq_len(nrow(picked)), function(i) {
    r <- picked[i]
    list(code = sprintf("B2_%d", 5L + i),
         label = sprintf("%s(%s)", r$label, r$family),
         weighting = list(kind = "catalog", catalog_id = r$catalog_id, label = r$label),
         note = sprintf("카탈로그 선정 — 계열 %s · 출처 %s. 격자가 재구현하지 않고 등록부를 소비한다.",
                        r$family, r$origin %||% "?"),
         root_paper = list(title = sprintf("weight_catalog: %s", r$catalog_id),
                           url = "https://github.com/qvest/weight_catalog"))
  })
  list(cells = cells, n_available = nrow(A), families = sort(unique(A$family)))
}
