#==============================================================================
# new_adapter.R — 어댑터 **골격 생성기** (2026-08-13 신설)
#
# 왜: 2026-08-13 실측으로 비-alpha 레인의 병목이 확정됐다 — 큐 논문 12편 표본에서
#   **도달 가능 10/12(83%)**, 진짜 대상 아님 17%. 즉 "논문이 안 맞는다"가 아니라
#   **등재 노동량**이 병목이다. 처분이 다르다: 전자면 큐를 버리고, 후자면 **등재를 줄인다.**
#
# 오늘 어댑터 3종을 손으로 쓰면서 반복한 작업을 분해하면:
#   ①원문 해석(paper_pdf) — 이미 자동
#   ②기전 추출·KR 사상 판단 — **환원 불가**(이게 리서치다)
#   ③어댑터 파일 작성(진입점 이름·NULL 처리·헤더 규약) — **기계적**
#   ④register_method 호출(메타데이터 필드) — **기계적**
# ③④가 이 파일이 맡는 부분이고, 하필 **내가 오늘 두 번 틀린 곳**이기도 하다:
#   · 진입점 이름을 kind 와 어긋나게 쓰면 loader 가 영원히 안 싣는다(route≠adapter_kind 혼동).
#   · 특성/매크로를 쓰는 어댑터가 NULL 처리를 빠뜨리면 패널이 빈 달에 죽는다.
#   골격이 그 둘을 기본으로 깔아두면 같은 실수를 반복할 자리가 없어진다.
#
# ★골격은 **기전을 채우지 않는다.** 헤더의 기전·KR 사상·PIT 칸은 `TODO(원문)` 로 남고,
#   그대로 두면 register_method 가 거부한다(mechanism/kr_mapping 필수). 즉 이 생성기는
#   노동을 줄이지 **날조를 돕지 않는다** — 사람이 원문을 읽어야만 통과한다.
#
# 사용:
#   source("02_Infrastructure/methods/new_adapter.R")
#   new_adapter("SchurDamping", kind = "weight", paper_id = "arxiv:2606.14798")
#==============================================================================

.na_root <- function() {
  for (c in c(Sys.getenv("QM_ROOT"), Sys.getenv("CLAUDE_PROJECT_DIR"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
}

.NA_ENTRY <- c(weight = "method_weights", sigma = "sigma_estimate", exposure = "exposure_schedule")
.NA_CTX <- c(
  weight   = "assets, R(obs x assets, PIT trailing), mu, Sigma, ub, lookback_days, decision_date, eval_date",
  sigma    = "R, assets, lookback_days, decision_date, eval_date   (Sigma 는 주지 않는다 - 그걸 만드는 게 일)",
  exposure = "periods(decision_date, eval_date), bare_gross(Date, r)")
.NA_RET <- c(
  weight   = "named 선호 벡터 (스케일 자유 - wrapper 가 합-정규화 후 상한 적용)",
  sigma    = "matrix (assets x assets, 대칭·PD)",
  exposure = "list(exposure = data.frame(Date, exposure in [0,1]), used_cutoff = Date[], eligible_from = 선택)")

new_adapter <- function(method_id, kind, paper_id, paper_title = "TODO(원문)",
                        route = NULL, file = NULL, root = .na_root(), overwrite = FALSE) {
  if (!(kind %in% names(.NA_ENTRY)))
    stop("[new_adapter] kind 는 weight / sigma / exposure 중 하나 — 받은 값: ", kind)
  snake <- tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", method_id))
  f <- file %||% file.path(root, "02_Infrastructure/methods/adapters", paste0(snake, ".R"))
  if (file.exists(f) && !overwrite) stop("[new_adapter] 이미 존재: ", f, " (overwrite=TRUE 로 덮어쓰기)")

  ep <- .NA_ENTRY[[kind]]
  null_guard <- if (kind == "exposure")
"  # ctx 확장 입력이 필요하면: ch <- if (is.function(ctx$macro)) ctx$macro() else NULL
  #   ★NULL 처리 필수 — 패널이 빈 구간이 실재한다(성공 경로만 쓰면 그 달에 죽는다)."
  else
"  ch <- if (is.function(ctx$characteristics)) ctx$characteristics() else NULL
  # ★NULL 처리 필수 — 패널 부재/로드 실패 시 NULL 이 온다. 신호가 전부 그 입력에서 오면
  #   **중립 반환**이 옳다(제외가 아니라 중립 — 제외하면 선별이 바뀌어 A/B 통제가 깨진다)."

  body <- if (kind == "exposure")
"  pr <- as.data.frame(ctx$periods); bg <- as.data.frame(ctx$bare_gross)
  n <- nrow(pr)
  hold_start <- as.Date(format(as.Date(pr$decision_date), \"%Y-%m-01\"))
  bg$Date <- as.Date(bg$Date); bg <- bg[order(bg$Date), , drop = FALSE]
  expo <- rep(1, n); cut <- as.Date(rep(NA, n))
  for (i in seq_len(n)) {
    ok <- bg$Date < hold_start[i]                  # ★C5: 홀딩월 시작 **전** 관측만
    cut[i] <- if (any(ok)) max(bg$Date[ok]) else (hold_start[i] - 1L)
    # TODO(원문): 논문 규칙으로 expo[i] 산출. [0,1] 밖이면 wrapper 가 제외한다.
  }
  list(exposure = data.frame(Date = as.Date(pr$eval_date), exposure = expo),
       used_cutoff = cut)   # ★used_cutoff 미신고 = 로드 거부(계약)"
  else if (kind == "sigma")
"  a <- ctx$assets; R <- ctx$R[, a, drop = FALSE]
  C <- suppressWarnings(stats::cor(R, use = \"pairwise.complete.obs\"))
  C[!is.finite(C)] <- 0; diag(C) <- 1
  # TODO(원문): 논문 추정기로 조건부 sd 또는 Σ 산출.
  #   ★비-퇴화 필수 — 표본공분산과 구별되지 않으면 등재가 거부된다(폴백/항등 추정기 검출).
  s <- suppressWarnings(apply(R, 2, stats::sd, na.rm = TRUE))
  S <- diag(s, length(a)) %*% C %*% diag(s, length(a))
  dimnames(S) <- list(a, a)
  S"
  else
"  a <- ctx$assets
  # TODO(원문): 논문 규칙으로 선호 벡터 산출.
  #   ★비-퇴화 필수 — EW 와 구별되지 않으면 등재가 거부된다('돌았는데 아무것도 안 함' 검출).
  w <- rep(1, length(a)); names(w) <- a
  w"

  txt <- sprintf(
'# %s.R — %s (%s)
#   원문: paper_pdf("%s") 로 해석. ★원문 없이 memo 만 보고 쓰면 날조다.
#
#------------------------------------------------------------------------------
# 논문 기전 (충실한 재구성 — 날조 아님)
#------------------------------------------------------------------------------
# TODO(원문): 기전 1문단 + 핵심 식(원문 식 번호 병기).
#
#------------------------------------------------------------------------------
# KR long-only 사상
#------------------------------------------------------------------------------
# TODO(원문): L/S 논문이면 long leg 사상 명시. 제약(long-only·Σw=1·w<=0.20·exposure[0,1])은
#   **wrapper 가 강제**한다 — 어댑터는 선호/추정치만 낸다.
#
# ★논문이 준 것과 이 구현이 정한 것을 반드시 구분해 적을 것.
#   자유 파라미터가 있으면: 사전고정인가(chain) / 백테로 골랐나(sweep → DSR).
#   판별 질문 = "이 값을 바꿔가며 **백테를 돌려봤는가**".
#
# PIT: ctx 는 하네스가 PIT 안전하게 만든다. ctx 밖 데이터를 읽지 말 것.
#   ctx(%s) = %s

%s <- function(ctx) {
%s

%s
}
', snake, paper_title, paper_id, paper_id, kind, .NA_CTX[[kind]], ep, null_guard, body)

  dir.create(dirname(f), showWarnings = FALSE, recursive = TRUE)
  writeLines(txt, f)

  stub <- sprintf(
'source("02_Infrastructure/methods/register_method.R")
register_method(
  method_id    = "%s",
  paper_id     = "%s",
  paper_title  = "%s",
  route        = "%s",          # 논문이 어느 모드 연료인가 (adapter_kind 와 **다른 축**)
  adapter_kind = "%s",          # 무엇을 교체하는가
  adapter      = "02_Infrastructure/methods/adapters/%s.R",
  mechanism    = "TODO(원문) — 없으면 register_method 가 거부한다",
  kr_mapping   = "TODO(원문) — 없으면 register_method 가 거부한다",
  selection_type = "chain",      # 백테로 골랐으면 "sweep" (DSR 게이트)
  free_params  = list()          # 사전고정 값과 그 근거를 적을 것
)', method_id, paper_id, paper_title, route %||% kind, kind, snake)

  cat(sprintf("[new_adapter] 생성: %s\n", f))
  cat(sprintf("  진입점 %s(ctx) · 반환 %s\n", ep, .NA_RET[[kind]]))
  cat("  ★TODO(원문) 칸을 채우기 전에는 register_method 가 거부한다(mechanism/kr_mapping 필수).\n")
  cat("\n── 등재 stub ──\n", stub, "\n", sep = "")
  invisible(list(file = f, entrypoint = ep, register_stub = stub))
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
