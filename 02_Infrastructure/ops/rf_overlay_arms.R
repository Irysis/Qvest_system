#==============================================================================
# rf_overlay_arms.R — B5(리스크 오버레이) 칸을 **등록부에서 선정** (2026-08-30)
#
# 왜: 도훈 "오버레이 방법론을 특정하는건 별로인데". 첫 판은 5종을 격자에 박아 뒀는데
#   그게 곧 방법론 고정이다 — 새 방법이 등록돼도 아무도 안 쓰고, 논문이 바뀌어도 같은
#   다섯 개만 반복 측정한다. weight_catalog 가 이미 같은 병을 진단해 뒀다:
#   "안 붙은 이유는 계약 충돌이 아니라 아무도 한 줄을 안 썼기 때문이다."
#   그래서 격자는 **축(B5)만 선언**하고, 칸의 내용은 매 배치마다 여기서 규칙으로 뽑는다.
#
# 규칙(판단이 아니라 규칙):
#   ① 이미 측정한 팔은 제외 — 같은 것을 두 번 재지 않는다
#   ② 계열당 1개 — 한 계열에서 여러 개 뽑으면 같은 축을 반복 측정한다(B2 실측 교훈)
#   ③ 구속 축 우선 — 지금 막고 있는 것이 낙폭이므로 drawdown/combo 계열을 앞세운다
#   ④ 그래도 자리가 남으면 계열 안에서 비용 낮은 순
#
# 사용: rf_pick_overlay_arms(n = 5, exclude = <이미 측정한 id>) -> list(cells = [...])
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFO_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

rf_overlay_catalog <- function(root = .RFO_ROOT) {
  p <- file.path(root, "06_Registry/overlay_catalog.json")
  if (!file.exists(p)) return(NULL)
  d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d) || !length(d$arms)) return(NULL)
  rbindlist(lapply(d$arms, function(a) data.table(
    id = as.character(a$id), kind = as.character(a$kind), family = as.character(a$family),
    basis = as.character(a$basis %||% ""), status = as.character(a$status %||% "active"),
    est_cost_min = as.numeric(a$est_cost_min %||% 8))), use.names = TRUE)
}

rf_pick_overlay_arms <- function(n = 5L, exclude = character(0), root = .RFO_ROOT) {
  A <- rf_overlay_catalog(root)
  if (is.null(A) || !nrow(A)) return(NULL)
  A <- A[status == "active"]
  A <- A[!(id %in% exclude)]
  if (!nrow(A)) return(NULL)

  setorderv(A, c("family", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- A[, .SD[1L], by = family]                       # ② 계열당 1개
  prio <- c("drawdown" = 1, "combo" = 2, "state_multivar" = 3,
            "ml" = 4, "vol_target" = 5, "trend" = 6)         # ③ 구속 축(MDD) 우선
  picked[, .prio := as.numeric(prio[family])]
  picked[is.na(.prio), .prio := 9]
  setorderv(picked, c(".prio", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- head(picked, n)
  # 계열 수가 n 보다 적으면 남은 자리는 계열 2순위로 채운다(측정 예산을 비우지 않는다)
  if (nrow(picked) < n) {
    rest <- A[!(id %in% picked$id)]
    setorderv(rest, "est_cost_min", 1L, na.last = TRUE)
    picked <- rbindlist(list(picked, head(rest, n - nrow(picked))), use.names = TRUE, fill = TRUE)
  }
  if (!nrow(picked)) return(NULL)

  cells <- lapply(seq_len(nrow(picked)), function(i) {
    r <- picked[i]
    list(code = sprintf("B5_%d", 20L + i),
         label = sprintf("%s(%s)", r$id, r$family),
         overlay = list(kind = r$kind, arm_id = r$id),
         basis = r$basis,
         note = sprintf("등록부 선정 — 계열 %s. 격자가 방법을 갖지 않고 overlay_catalog 를 소비한다.",
                        r$family))
  })
  list(cells = cells, n_available = nrow(A), families = sort(unique(A$family)),
       picked_ids = picked$id)
}

cat("[rf_overlay_arms.R] Loaded — rf_overlay_catalog() / rf_pick_overlay_arms(n, exclude)\n")
