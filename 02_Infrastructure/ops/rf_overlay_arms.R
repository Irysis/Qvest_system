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
  # ★action/state 는 카탈로그가 정본. 없으면 기전 지도의 계열 매핑으로 파생한다(구 arm 하위호환).
  .ax <- tryCatch({
    suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/rf_mechanism_map.R"),
                            local = TRUE))
    get("rfm_arm_axis")
  }, error = function(e) NULL)
  rbindlist(lapply(d$arms, function(a) {
    z <- if (!is.null(.ax)) .ax(a) else list(action = "scalar_exposure", state = "multivar")
    data.table(
      id = as.character(a$id), kind = as.character(a$kind), family = as.character(a$family),
      action = as.character(a$action %||% z$action), state = as.character(a$state %||% z$state),
      basis = as.character(a$basis %||% ""), status = as.character(a$status %||% "active"),
      est_cost_min = as.numeric(a$est_cost_min %||% 8))
  }), use.names = TRUE)
}

rf_pick_overlay_arms <- function(n = 5L, exclude = character(0), root = .RFO_ROOT) {
  A <- rf_overlay_catalog(root)
  if (is.null(A) || !nrow(A)) return(NULL)
  A <- A[status == "active"]
  A <- A[!(id %in% exclude)]
  if (!nrow(A)) return(NULL)

  # ② ★기전 좌표당 1개 — 다양화해야 할 축은 라벨(family)이 아니라 (action, state) 다.
  #    family 로 묶으면 state 가 다른 두 횡단면 arm 이 서로를 밀어낸다(2026-09-03 실사고).
  A[, .cell := paste(action, state, sep = "/")]
  setorderv(A, c(".cell", "est_cost_min"), c(1L, 1L), na.last = TRUE)
  picked <- A[, .SD[1L], by = .cell]
  # ③ 구속 축(MDD) 우선. ★cross_sectional 을 맨 앞에 둔다 — drawdown 을 밀어낸 것이 아니라
  #   같은 축을 **더 정밀하게** 겨누기 때문이다. 스칼라 축소는 하락과 회복을 같은 비율로 깎아
  #   MDD 를 낮춘 만큼 CAGR 을 더 잃는다(실측). 종목별 차등은 그 대칭을 깨는 유일한 행동 축이다.
  #    행동 축 우선(횡단면 먼저), 그 안에서 상태 축 우선순위.
  aprio <- c("cross_sectional" = 0, "scalar_exposure" = 10)
  sprio <- c("drawdown" = 1, "multivar" = 2, "dispersion" = 3, "holding_level" = 4,
             "ml" = 5, "vol" = 6, "trend" = 7)
  picked[, .prio := as.numeric(aprio[action]) + as.numeric(sprio[state])]
  picked[is.na(.prio), .prio := 99]
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
