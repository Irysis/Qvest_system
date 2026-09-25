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
#
# ★검증 판정 한정 (2026-09-24 · 플랜 P0-11 · 감사 D6-09 · 오버레이 22칸 0 pass 실측).
#   구판은 best_calmar 를 **적대검증(G2) 판정 여부와 무관하게** 측정된 B5 칸 전부의 essence Calmar 에서 뽑았다.
#   그런데 오버레이 칸의 Calmar 개선은 노출 축소(변동성 끌림 감소)만으로도 난다 — '개선이 있다' ≠ '타이밍에서 왔다'.
#   미검증 칸의 Calmar 가 전역 최고를 쥐면 그 (action,state) 칸은 영영 포화되지 않고, 그 수치가 지도 파일에 최고로 적혔다
#   (감사 시점: 최고 Calmar 0.609 칸 = verdict 없음).
#   이제 칸마다 적대검증 판정 등급(rfm_verdict_class)을 붙인다:
#     판정(judged)   = pass · fail · below_floor(not_candidate · calmar_not_above_floor = 바닥조차 못 넘었다 — 기전의 음성)
#     따로 센다       = unverified(표식 없음) · deferred(deferred_refresh_lock — 판정이 아니라 '다시 돌려라')
#                      · error(검정 불능·규약 거부) · untested(not_candidate 의 그 밖 사유 — 예: beyond_max_candidates)
#   best_calmar = 판정 칸의 Calmar 최댓값(미검증 수치는 최고로 적지 않는다).
#   포화 = n_verdict ≥ k ∧ pass = 0 — "판정을 k 번 받았는데 한 번도 타이밍 기여가 확인되지 않았다". pass 가 하나라도 있으면
#   계속 판다. 포화는 한계 판정이 아니라 생성 표적의 배분 절단점이다(AX-000 — 새 pass 가 나오면 즉시 풀린다).
#   k = 06_Registry/reinforce_program.json::blocks[B5].mechanism_map.k_saturate (근거는 그 키의 note). 없으면 멈춘다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFM_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★층 정규화(.ov_own_layers)·상주 칸(rfbd_standing_picks)은 정본에서 (2026-09-17). 이미 적재된 환경(러너·notify)이면 건너뛴다.
if (!exists(".ov_own_layers", mode = "function"))
  source(file.path(.RFM_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)
if (!exists("rfbd_standing_picks", mode = "function"))
  invisible(capture.output(source(file.path(.RFM_ROOT(), "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE)))

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

# ── 적대검증 판정 등급 (P0-11 · 머리 주석 ★검증 판정 한정) ─────────────────────────────
#   verdict 어휘의 정본 = rf_overlay_adversary.R 소비자 규약(pass/fail/error/not_candidate/deferred_refresh_lock).
#   미지 문자열은 error 로 둔다 — 판정으로 세지 않는 쪽(소비자 규약상 pass 가 아니면 보류)이 안전하다.
RFM_JUDGED <- c("pass", "fail", "below_floor")
RFM_VCLASSES <- c("pass", "fail", "below_floor", "unverified", "deferred", "error", "untested")
rfm_verdict_class <- function(adv) {
  v <- as.character((adv %||% list())$verdict %||% "")[1]
  if (is.na(v) || !nzchar(v)) return("unverified")
  if (identical(v, "pass")) return("pass")
  if (identical(v, "fail")) return("fail")
  if (identical(v, "not_candidate"))
    return(if (identical(as.character(adv$reason %||% "")[1], "calmar_not_above_floor")) "below_floor" else "untested")
  if (identical(v, "deferred_refresh_lock")) return("deferred")
  "error"
}
#' 포화 술어(순수) — 판정 k 회 이상 ∧ pass 0. 벡터화.
rfm_saturated <- function(n_verdict, n_pass, k) as.integer(n_verdict) >= as.integer(k) & as.integer(n_pass) == 0L
#' k — 격자 B5 블록 설정에서 읽는다(하드코딩 금지 · 근거 = 그 키의 note). 없거나 1 미만 정수가 아니면 멈춘다.
rfm_k_saturate <- function(root = .RFM_ROOT()) {
  p <- file.path(root, "06_Registry/reinforce_program.json")
  if (!file.exists(p)) stop("[rf_mechanism_map] reinforce_program.json 부재 — 포화 k 를 지어내지 않는다: ", p)
  g <- fromJSON(p, simplifyVector = FALSE)
  b5 <- Filter(function(b) identical(as.character(b$id %||% ""), "B5"), g$blocks %||% list())
  k <- if (length(b5)) suppressWarnings(as.integer((b5[[1]]$mechanism_map %||% list())$k_saturate %||% NA)[1]) else NA_integer_
  if (!length(k) || is.na(k) || k < 1L)
    stop("[rf_mechanism_map] reinforce_program.json::blocks[B5].mechanism_map.k_saturate 부재·무효 — 포화 k 를 지어내지 않는다")
  k
}

#' 측정된 B5 셀 → (action, state) 별 집계
#' @param k_saturate NULL = 격자 설정(rfm_k_saturate) · 정수 = 명시(검사·재현용)
#' @return data.table(action, state, n_measured, n_verdict, n_pass, n_fail, n_below_floor, n_unverified, n_deferred,
#'                    n_error, n_untested, best_calmar[판정 칸만], n_arms_catalog, saturated)
rf_mechanism_map <- function(root = .RFM_ROOT(), k_saturate = NULL) {
  k_src <- if (is.null(k_saturate)) "reinforce_program.json::blocks[B5].mechanism_map.k_saturate" else "argument"
  k_saturate <- if (is.null(k_saturate)) rfm_k_saturate(root) else as.integer(k_saturate)
  cat_p <- file.path(root, "06_Registry/overlay_catalog.json")
  arms <- if (file.exists(cat_p)) fromJSON(cat_p, simplifyVector = FALSE)$arms else list()
  ax <- rbindlist(lapply(arms, function(a) {
    z <- rfm_arm_axis(a)
    data.table(arm_id = as.character(a$id %||% ""), kind = as.character(a$kind %||% ""),
               action = z$action, state = z$state)
  }), fill = TRUE)
  # ★상주 arm(program standing_cells · pg2_risk_overlay_v1)은 지도에서 뺀다 — 측정 수·카탈로그 수 둘 다 (2026-09-17).
  #   상주 칸은 탐색 축이 아니라 매 세대 도는 고정 칸이다. 측정에 세면 그 (action,state) 칸이 세대 수만큼 "충분히
  #   쟀다" 로 포화되고, 카탈로그에 세면 생성기가 그 칸에 arm 이 있다고 읽는다 — 둘 다 표적 선택을 왜곡한다.
  standing <- tryCatch(rfbd_standing_picks(root), error = function(e) character(0))
  if (nrow(ax) && length(standing)) ax <- ax[!(arm_id %in% standing)]

  # 측정 결과 — 원장의 B5 시도에서 spec 을 열어 **이 칸의 몫인 층 전부**를 얻고 층마다 essence$calmar 를 붙인다.
  # ★층 단위 (2026-09-17): 구판은 s$overlay$arm_id 하나만 읽어 스택(리스트)이면 NULL → 측정이 통째로 빠졌다.
  #   칸의 몫 = overlay_cell(정본) > overlay − entry carry > 전부(.ov_own_layers). carry 층은 부모가 이미 잰 것이라 안 센다.
  led_p <- file.path(root, "06_Registry/reinforce_ledger_l1.json")
  meas <- data.table(arm_id = character(), calmar = numeric(), vclass = character())
  .id_of <- function(o) {   # arm_id 없는 층은 kind 로 카탈로그 id 를 되찾는다 — 그것도 없으면 kind 자체(축 기본값으로 떨어진다)
    aid <- as.character(o$arm_id %||% "")
    if (nzchar(aid)) return(aid)
    knd <- as.character(o$kind %||% "")
    if (nzchar(knd) && nrow(ax)) { h <- ax[kind == knd]; if (nrow(h)) return(h$arm_id[1]) }
    knd
  }
  if (file.exists(led_p)) {
    led <- tryCatch(fromJSON(led_p, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(led)) {
      rows <- list()
      for (e in led$entries %||% list()) {
        carry_ov <- (e$carry %||% list())$overlay
        for (a in e$attempts %||% list()) {
          es <- a$essence; if (!is.list(es)) next
          cc <- as.character(es$cell_code %||% "")
          if (!startsWith(cc, "B5_")) next
          sp <- as.character(es$spec %||% "")
          if (!nzchar(sp) || !file.exists(sp)) next
          s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
          if (is.null(s)) next
          vc <- rfm_verdict_class(a$adversary)   # 칸 단위 판정 — 스택 칸의 층들은 같은 판정을 공유한다
          for (o in .ov_own_layers(s, carry = carry_ov)) {
            aid <- .id_of(o)
            if (!nzchar(aid) || aid %in% standing) next
            rows[[length(rows) + 1L]] <- data.table(
              arm_id = aid, calmar = suppressWarnings(as.numeric(es$calmar %||% NA)), vclass = vc)
          }
        }
      }
      if (length(rows)) meas <- rbindlist(rows, fill = TRUE)
    }
  }
  m <- merge(meas[nzchar(arm_id)], ax, by = "arm_id", all.x = TRUE)
  m[is.na(action), action := "scalar_exposure"]; m[is.na(state), state := "multivar"]

  grid <- CJ(action = RFM_ACTIONS, state = RFM_STATES)
  .mx <- function(x) { x <- x[is.finite(x)]; if (length(x)) max(x) else NA_real_ }
  agg  <- m[, .(n_measured = .N,
                n_verdict = sum(vclass %in% RFM_JUDGED), n_pass = sum(vclass == "pass"), n_fail = sum(vclass == "fail"),
                n_below_floor = sum(vclass == "below_floor"), n_unverified = sum(vclass == "unverified"),
                n_deferred = sum(vclass == "deferred"), n_error = sum(vclass == "error"), n_untested = sum(vclass == "untested"),
                best_calmar = .mx(calmar[vclass %in% RFM_JUDGED])),     # ★판정 칸만 — 미검증 Calmar 는 최고로 적지 않는다
            by = .(action, state)]
  cnt  <- if (nrow(ax)) ax[, .(n_arms_catalog = .N), by = .(action, state)] else
          data.table(action = character(), state = character(), n_arms_catalog = integer())
  out <- merge(merge(grid, agg, by = c("action", "state"), all.x = TRUE),
               cnt, by = c("action", "state"), all.x = TRUE)
  for (cn in c("n_measured", "n_verdict", "n_pass", "n_fail", "n_below_floor", "n_unverified", "n_deferred", "n_error", "n_untested", "n_arms_catalog"))
    set(out, which(is.na(out[[cn]])), cn, 0L)

  gbest <- suppressWarnings(max(out$best_calmar, na.rm = TRUE))
  if (!is.finite(gbest)) gbest <- NA_real_
  # ★포화 = "판정을 k 번 받았는데 pass 가 0" (P0-11). 구판("측정 k 회 ∧ 전역 최고 아님")은 미검증 Calmar 가 전역 최고를
  #   쥐면 그 칸을 영영 열어 두었다 — 노출 축소만으로 난 Calmar 가 표적 선택을 붙잡았다.
  out[, saturated := rfm_saturated(n_verdict, n_pass, k_saturate)]
  setorderv(out, c("saturated", "n_measured", "action"), c(1L, 1L, 1L))
  attr(out, "global_best_calmar") <- gbest
  attr(out, "k_saturate") <- k_saturate
  attr(out, "k_source") <- k_src
  out[]
}

#' 다음 생성 표적 — 미포화 칸 중 가장 덜 탐색된 것. 전 칸 포화면 NULL.
#' ★NULL 이 정상 종료다. 포화는 결함이 아니라 절단점이다 — 그때는 생성기를 부르지 않는다.
rf_next_target <- function(root = .RFM_ROOT(), k_saturate = NULL) {
  mp <- rf_mechanism_map(root, k_saturate)
  open <- mp[saturated == FALSE]
  if (!nrow(open)) return(NULL)
  setorderv(open, c("n_measured", "n_arms_catalog"), c(1L, 1L))
  list(action = open$action[1], state = open$state[1],
       n_measured = open$n_measured[1], n_arms_catalog = open$n_arms_catalog[1])
}

#' 지도를 파일로. ★생성기는 이 파일을 못 읽는다(arm_gen_read_guard) — best_calmar 가 들어 있기 때문이다.
#'   레인이 프롬프트에 넣는 것은 **성과를 뺀 축약본**이다.
rf_write_mechanism_map <- function(root = .RFM_ROOT(), k_saturate = NULL) {
  mp <- rf_mechanism_map(root, k_saturate)
  p <- file.path(root, "06_Registry/overlay_mechanism_map.json")
  obj <- list(schema = "overlay_mechanism_map_v2",
              generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
              k_saturate = attr(mp, "k_saturate"), k_source = attr(mp, "k_source"),
              saturation_rule = "n_verdict >= k_saturate AND n_pass == 0 (판정 = pass·fail·below_floor)",
              best_calmar_basis = "적대검증 판정 칸(pass·fail·below_floor)의 essence Calmar 만 — unverified·deferred·error·untested 는 제외하고 따로 센다",
              global_best_calmar = attr(mp, "global_best_calmar"),
              note = paste("action = 포트폴리오에 무엇을 하는가 · state = 무엇을 보고 반응하는가.",
                           "생성 표적은 미포화 칸에서만 뽑는다."),
              cells = lapply(seq_len(nrow(mp)), function(i) as.list(mp[i])))
  write(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  invisible(p)
}

#' 프롬프트용 축약본 — **성과 수치를 뺀다**. 생성기는 '무엇이 미측정인가' 만 안다.
#'   ★판정·미검증 **횟수**만 싣는다(pass 수·Calmar 는 싣지 않는다 — 포화 여부가 이미 그 요약이다).
rf_target_brief <- function(root = .RFM_ROOT(), k_saturate = NULL) {
  mp <- rf_mechanism_map(root, k_saturate)
  paste(sprintf("%-16s %-14s 측정 %d(판정 %d · 미검증 %d) · 카탈로그 %d · %s",
                mp$action, mp$state, mp$n_measured, mp$n_verdict, mp$n_unverified + mp$n_deferred, mp$n_arms_catalog,
                ifelse(mp$saturated, "포화", "미포화")), collapse = "\n")
}

cat("[rf_mechanism_map.R] Loaded — rf_mechanism_map() / rf_next_target() / rf_write_mechanism_map() / rf_target_brief()\n")
