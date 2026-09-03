#==============================================================================
# rf_mechanism_map.R — 오버레이 기전 지도 · 포화 감지 (v10.2 2026-09-03 · Phase 2)
#
# ★왜: 카탈로그를 LLM 이 넓히게 하면, 방향을 정해주지 않는 한 **이미 있는 기전의 n+1번째**를
#   만든다. 팩터를 331종으로 늘렸는데 총 조합이 5개였던 실패와 같은 모양이다. 판정 기준은
#   등록부를 소비하느냐가 아니라 **분산**이었다.
#   그래서 생성 표적을 "무엇이 아직 안 측정됐는가" 에서 뽑는다.
#
# 기전 축 2차원:
#   action — 포트폴리오에 **무엇을 하는가**. scalar_exposure(총노출 한 숫자) vs cross_sectional(종목별).
#            ★기존 10 arm 은 계열 라벨이 6종이었지만 action 은 전부 하나였다. 그 사실이
#              라벨만 보면 안 보였고, 그래서 "오버레이는 다 해봤다" 로 오독되기 쉬웠다.
#   state  — 무엇을 보고 반응하는가. vol / drawdown / multivar / ml / trend / dispersion / holding_level
#
# 계약: 부작용은 지도 파일 1개 쓰기뿐. 원장·카탈로그에 쓰지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFM_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

RFM_ACTIONS <- c("scalar_exposure", "cross_sectional")
RFM_STATES  <- c("vol", "drawdown", "multivar", "ml", "trend", "dispersion", "holding_level")

# 계열 → 축. arm 이 action/state 를 명시하면 그쪽이 우선한다(카탈로그가 정본).
.RFM_FAMILY_AXIS <- list(
  drawdown        = list(action = "scalar_exposure", state = "drawdown"),
  vol_target      = list(action = "scalar_exposure", state = "vol"),
  state_multivar  = list(action = "scalar_exposure", state = "multivar"),
  ml              = list(action = "scalar_exposure", state = "ml"),
  trend           = list(action = "scalar_exposure", state = "trend"),
  combo           = list(action = "scalar_exposure", state = "multivar"),
  cross_sectional = list(action = "cross_sectional", state = "drawdown"))

rfm_arm_axis <- function(arm) {
  fam <- as.character(arm$family %||% "")
  d <- .RFM_FAMILY_AXIS[[fam]] %||% list(action = "scalar_exposure", state = "multivar")
  a <- as.character(arm$action %||% d$action)
  s <- as.character(arm$state  %||% d$state)
  list(action = if (a %in% RFM_ACTIONS) a else "scalar_exposure",
       state   = if (s %in% RFM_STATES)  s else "multivar")
}

#' 측정된 B5 셀 → (action, state) 별 집계
#' @return data.table(action, state, n_arms_catalog, n_measured, best_calmar, saturated)
rf_mechanism_map <- function(root = .RFM_ROOT(), k_saturate = 3L) {
  cat_p <- file.path(root, "06_Registry/overlay_catalog.json")
  arms <- if (file.exists(cat_p)) fromJSON(cat_p, simplifyVector = FALSE)$arms else list()
  ax <- rbindlist(lapply(arms, function(a) {
    z <- rfm_arm_axis(a)
    data.table(arm_id = as.character(a$id %||% ""), kind = as.character(a$kind %||% ""),
               action = z$action, state = z$state)
  }), fill = TRUE)

  # 측정 결과 — 원장의 B5 시도에서 spec 을 열어 arm_id 를 얻고 essence$calmar 를 붙인다.
  led_p <- file.path(root, "06_Registry/reinforce_ledger_l1.json")
  meas <- data.table(arm_id = character(), calmar = numeric())
  if (file.exists(led_p)) {
    led <- tryCatch(fromJSON(led_p, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(led)) {
      rows <- list()
      for (e in led$entries %||% list()) for (a in e$attempts %||% list()) {
        es <- a$essence; if (!is.list(es)) next
        cc <- as.character(es$cell_code %||% "")
        if (!startsWith(cc, "B5_")) next
        sp <- as.character(es$spec %||% "")
        aid <- if (nzchar(sp) && file.exists(sp)) {
          s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
          if (is.null(s)) "" else as.character(s$overlay$arm_id %||% "")
        } else ""
        rows[[length(rows) + 1L]] <- data.table(
          arm_id = aid, calmar = suppressWarnings(as.numeric(es$calmar %||% NA)))
      }
      if (length(rows)) meas <- rbindlist(rows, fill = TRUE)
    }
  }
  m <- merge(meas[nzchar(arm_id)], ax, by = "arm_id", all.x = TRUE)
  m[is.na(action), action := "scalar_exposure"]; m[is.na(state), state := "multivar"]

  grid <- CJ(action = RFM_ACTIONS, state = RFM_STATES)
  agg  <- m[, .(n_measured = .N, best_calmar = suppressWarnings(max(calmar, na.rm = TRUE))),
            by = .(action, state)]
  agg[!is.finite(best_calmar), best_calmar := NA_real_]
  cnt  <- if (nrow(ax)) ax[, .(n_arms_catalog = .N), by = .(action, state)] else
          data.table(action = character(), state = character(), n_arms_catalog = integer())
  out <- merge(merge(grid, agg, by = c("action", "state"), all.x = TRUE),
               cnt, by = c("action", "state"), all.x = TRUE)
  out[is.na(n_measured), n_measured := 0L][is.na(n_arms_catalog), n_arms_catalog := 0L]

  gbest <- suppressWarnings(max(out$best_calmar, na.rm = TRUE))
  if (!is.finite(gbest)) gbest <- NA_real_
  # ★포화 = "충분히 재봤는데 전역 최고를 못 냈다". 전역 최고를 쥔 칸은 계속 판다.
  out[, saturated := n_measured >= k_saturate &
        (is.na(best_calmar) | (is.finite(gbest) & best_calmar < gbest))]
  setorderv(out, c("saturated", "n_measured", "action"), c(1L, 1L, 1L))
  attr(out, "global_best_calmar") <- gbest
  out[]
}

#' 다음 생성 표적 — 미포화 칸 중 가장 덜 탐색된 것. 전 칸 포화면 NULL.
#' ★NULL 이 정상 종료다. 포화는 결함이 아니라 절단점이다 — 그때는 생성기를 부르지 않는다.
rf_next_target <- function(root = .RFM_ROOT(), k_saturate = 3L) {
  mp <- rf_mechanism_map(root, k_saturate)
  open <- mp[saturated == FALSE]
  if (!nrow(open)) return(NULL)
  setorderv(open, c("n_measured", "n_arms_catalog"), c(1L, 1L))
  list(action = open$action[1], state = open$state[1],
       n_measured = open$n_measured[1], n_arms_catalog = open$n_arms_catalog[1])
}

#' 지도를 파일로. ★생성기는 이 파일을 못 읽는다(arm_gen_read_guard) — best_calmar 가 들어 있기 때문이다.
#'   레인이 프롬프트에 넣는 것은 **성과를 뺀 축약본**이다.
rf_write_mechanism_map <- function(root = .RFM_ROOT(), k_saturate = 3L) {
  mp <- rf_mechanism_map(root, k_saturate)
  p <- file.path(root, "06_Registry/overlay_mechanism_map.json")
  obj <- list(schema = "overlay_mechanism_map_v1",
              generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
              k_saturate = k_saturate,
              global_best_calmar = attr(mp, "global_best_calmar"),
              note = paste("action = 포트폴리오에 무엇을 하는가 · state = 무엇을 보고 반응하는가.",
                           "생성 표적은 미포화 칸에서만 뽑는다."),
              cells = lapply(seq_len(nrow(mp)), function(i) as.list(mp[i])))
  write(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  invisible(p)
}

#' 프롬프트용 축약본 — **성과 수치를 뺀다**. 생성기는 '무엇이 미측정인가' 만 안다.
rf_target_brief <- function(root = .RFM_ROOT(), k_saturate = 3L) {
  mp <- rf_mechanism_map(root, k_saturate)
  paste(sprintf("%-16s %-14s 측정 %d · 카탈로그 %d · %s",
                mp$action, mp$state, mp$n_measured, mp$n_arms_catalog,
                ifelse(mp$saturated, "포화", "미포화")), collapse = "\n")
}

cat("[rf_mechanism_map.R] Loaded — rf_mechanism_map() / rf_next_target() / rf_write_mechanism_map() / rf_target_brief()\n")
