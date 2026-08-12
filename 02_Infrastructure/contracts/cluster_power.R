## cluster_power.R — 군집-상관 설계의 착수 전 검정력 계약
##
## 왜 있나 (2026-08-10, FQ-170 P9c/P17a/P19b/P20a — **하루에 같은 실패 4회**):
##   계열-간 상관 라운드를 네 번 돌렸고 네 번 다 미달이었다. 매번 팩터 수(n=40~52)로
##   검정력을 생각했는데, 묶는 것은 **팩터 수가 아니라 계열 수**(n_cluster=15~19)였다.
##   같은 rho 가 전체 n 기준으로는 통과하고 계열 기준으로는 미달한다 —
##   즉 **판정이 군집 선택에 달렸고, 그 선택은 착수 전에 고정돼야 한다.**
##   ★핵심 사실: 팩터 DB 는 331종이지만 **계열은 19종뿐**이다. 팩터를 다 써도 이 한계는 안 풀린다.
##
## 무엇을 하나:
##   required_clusters(rho)     — 목표 rho 를 계열-군집 기준으로 유의하게 검출하는 데 필요한 계열 수
##   cluster_feasibility(...)   — 가용 계열 수로 그 rho 를 볼 수 있는지 GO / NO-GO 판정 + 사유
##   declare_cluster_design(...) — 사전등록용 1줄 선언(어느 기준으로 판정할지 못박음)
##
## 자매 계약: required_effect_size.R (평균/DiD 축). 이 파일은 **상관/군집 축**을 덮는다.
## 위반 = 착수 전 미호출. 오늘 4회의 비용이 그 근거다.

#' spearman 유의 임계 |rho| (t 근사, 양측)
#' @param n 표본 수 (군집 기준이면 **군집 수**를 넣는다 — 관측 수가 아니다)
#' @param alpha 유의수준 (기본 0.05, 양측)
cp_critical_rho <- function(n, alpha = 0.05) {
  n <- as.integer(n)
  if (!length(n) || any(is.na(n)) || any(n < 3L)) return(rep(NA_real_, max(1L, length(n))))
  tc <- stats::qt(1 - alpha/2, df = pmax(n - 2L, 1L))
  sqrt(tc^2 / (tc^2 + pmax(n - 2L, 1L)))
}

#' 목표 rho 를 검출하는 데 필요한 (군집) 표본 수
#' @param target_rho 검출하고자 하는 상관의 크기 (0 < |rho| < 1)
#' @param alpha 유의수준
#' @param max_n 탐색 상한 (도달 못 하면 NA 반환 — 무한 루프 방지)
cp_required_n <- function(target_rho, alpha = 0.05, max_n = 5000L) {
  r <- abs(as.numeric(target_rho))
  if (!is.finite(r) || r <= 0 || r >= 1) return(NA_integer_)
  for (n in 3:max_n) if (cp_critical_rho(n, alpha) <= r) return(as.integer(n))
  NA_integer_
}

#' 군집 설계의 착수 가부 판정
#' @param target_rho 기대/목표 상관
#' @param n_clusters 가용 **군집** 수 (계열 수). 팩터 수가 아니다.
#' @param n_obs 가용 관측 수(팩터 수). 보고용 — 판정에는 쓰지 않는다.
#' @param alpha 유의수준
#' @return list(feasible, verdict, required_clusters, critical_rho_at_clusters, ...)
cp_feasibility <- function(target_rho, n_clusters, n_obs = NA_integer_, alpha = 0.05) {
  r   <- abs(as.numeric(target_rho))
  nc  <- as.integer(n_clusters)
  req <- cp_required_n(r, alpha)
  crit_c <- cp_critical_rho(nc, alpha)
  crit_o <- if (is.na(n_obs)) NA_real_ else cp_critical_rho(as.integer(n_obs), alpha)
  feasible <- is.finite(crit_c) && is.finite(r) && r >= crit_c
  ## 두 기준이 갈리는가 — 오늘 네 번의 실패가 정확히 이 자리였다
  split <- is.finite(crit_o) && is.finite(crit_c) && (r >= crit_o) && (r < crit_c)
  verdict <- if (!is.finite(r) || r <= 0 || r >= 1) "INVALID_TARGET"
             else if (feasible) "GO"
             else if (split) "NO_GO_CLUSTER_BINDS"
             else "NO_GO_UNDERPOWERED"
  msg <- switch(verdict,
    GO = sprintf("착수 가능: rho %.3f >= 군집 임계 %.3f (군집 %d)", r, crit_c, nc),
    NO_GO_CLUSTER_BINDS = sprintf(
      paste0("착수 금지: 관측 기준으로는 통과(rho %.3f >= %.3f)하나 **군집 기준 미달**(%.3f 필요, 군집 %d). ",
             "필요 군집 %s. ★관측 수를 늘려도 안 풀린다 — 묶는 건 군집 수다. ",
             "설계를 군집-내부에서 닫히는 형태(순열·쌍체·시대분할)로 교체할 것."),
      r, crit_o, crit_c, nc, ifelse(is.na(req), ">5000", as.character(req))),
    NO_GO_UNDERPOWERED = sprintf(
      "착수 금지: rho %.3f < 군집 임계 %.3f (군집 %d). 필요 군집 %s.",
      r, crit_c, nc, ifelse(is.na(req), ">5000", as.character(req))),
    "INVALID_TARGET" = sprintf("target_rho 가 (0,1) 밖이다: %s", format(target_rho)))
  list(feasible = feasible, verdict = verdict, message = msg,
       target_rho = r, n_clusters = nc, n_obs = n_obs, alpha = alpha,
       required_clusters = req, critical_rho_at_clusters = crit_c,
       critical_rho_at_obs = crit_o, criteria_split = split)
}

#' 사전등록용 선언 — **어느 기준으로 판정할지**를 착수 전에 못박는다
#' @param basis "cluster"(권장) 또는 "obs". obs 를 고를 때는 사유를 남긴다.
cp_declare <- function(target_rho, n_clusters, n_obs = NA_integer_,
                       basis = c("cluster", "obs"), reason = NULL, alpha = 0.05) {
  basis <- match.arg(basis)
  f <- cp_feasibility(target_rho, n_clusters, n_obs, alpha)
  if (identical(basis, "obs") && is.null(reason))
    stop("basis='obs' 는 사유(reason)를 요구한다 — 군집 기준이 기본값이고 이탈은 명시적이어야 한다.")
  f$declared_basis <- basis
  f$declared_reason <- reason
  f$threshold_used <- if (identical(basis, "cluster")) f$critical_rho_at_clusters else f$critical_rho_at_obs
  cat(sprintf("[cluster_power] 사전등록: basis=%s · 임계 |rho| %.3f · 대상 %.3f · %s\n",
              basis, f$threshold_used, f$target_rho, f$verdict))
  if (!is.null(reason)) cat(sprintf("  사유: %s\n", reason))
  cat(sprintf("  %s\n", f$message))
  invisible(f)
}

## 이 저장소의 현행 상수 — **출처는 레지스트리의 선언 필드이지 이름 휴리스틱이 아니다**
##
## ★2026-08-10 정정(초판 19 → 15): 초판은 팩터 이름의 접두를 문자열로 잘라 19 를 셌다.
##   그런데 `factor_registry.json` 에 **선언 필드**(`category` / `labels$economic_family`)가
##   이미 있고 커넥터의 `group_factors_by_family()` 가 그걸 읽는다 — **정답 배관이 있는데 안 썼다.**
##   선언 고유값은 **15종**: defense 59 · quality 47 · liquidity 44 · momentum 32 · regime 28 ·
##   accrual 25 · value 24 · consensus 23 · growth 21 · risk 19 · crowding 16 · investor_flow 15 ·
##   technical 12 · leverage 6 · size 2.
##   ⇒ 임계가 0.456(n=19) → **0.514(n=15)** 로 오르고, FQ-170 P19b 의 rho 0.500 판정이
##     GO → **NO_GO_CLUSTER_BINDS** 로 뒤집혔다. '19 vs 20 하나 차이' 서술도 폐기(실제 15 vs 20).
##   ★교훈: **계열 같은 분류량은 이름에서 유추하지 말고 선언 필드에서 읽어라.**
##     휴리스틱은 오탐(C/CR·IN/INV·M/MA 처럼 접두만 겹치는 별개 계열)과 누락을 동시에 낸다.
CP_FACTOR_DB_CLUSTERS <- 15L

#' 레지스트리에서 선언 계열 수를 직접 읽는다 (상수 드리프트 감시용)
#' @return integer 고유 계열 수, 못 읽으면 NA (0 을 반환해 '없음'으로 위장하지 않는다)
cp_declared_cluster_count <- function(registry_path = NULL) {
  if (is.null(registry_path)) {
    root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
    cand <- c(file.path(root, "02_Infrastructure/factor_db/factor_registry.json"),
              "02_Infrastructure/factor_db/factor_registry.json")
    registry_path <- cand[file.exists(cand)][1]
  }
  if (is.na(registry_path[1]) || !length(registry_path) || !file.exists(registry_path[1]))
    return(NA_integer_)
  reg <- tryCatch(jsonlite::fromJSON(registry_path[1], simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(reg) || !length(reg)) return(NA_integer_)
  cats <- vapply(reg, function(x) {
    v <- x[["category"]]
    if (is.null(v)) v <- tryCatch(x[["labels"]][["economic_family"]], error = function(e) NULL)
    if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1]
  }, character(1))
  cats <- cats[!is.na(cats) & nzchar(cats)]
  if (!length(cats)) return(NA_integer_)
  length(unique(cats))
}

#' 팩터 DB 계열 수를 기본값으로 쓰는 편의 래퍼
cp_feasibility_factor_db <- function(target_rho, n_obs = NA_integer_, alpha = 0.05)
  cp_feasibility(target_rho, CP_FACTOR_DB_CLUSTERS, n_obs, alpha)

if (identical(environment(), globalenv()) && !interactive()) {
  cat("[cluster_power.R] Loaded — cp_feasibility() / cp_required_n() / cp_declare()\n")
  cat(sprintf("  팩터 DB 계열 수 = %d · rho 0.45 검출 필요 군집 = %s\n",
              CP_FACTOR_DB_CLUSTERS, cp_required_n(0.45)))
}
