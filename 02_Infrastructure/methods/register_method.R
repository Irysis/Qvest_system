#==============================================================================
# register_method.R — 논문 → 어댑터 → **검증된 등재** (2026-08-13 신설, 도훈 지시
#   "논문 라우팅 받고 각 에이전트가 소비해서 규칙에 맞게 분석을 시행하는 배선")
#
#------------------------------------------------------------------------------
# ★왜 필요한가 — 배선의 끊어진 칸은 정확히 여기 하나였다
#------------------------------------------------------------------------------
# 소비측은 이미 완성돼 있다: `method_registry.R` 의 loader 가 레지스트리를 읽어
# `wrap_adapter`/`wrap_sigma_estimator`/`wrap_exposure_adapter` 로 감싸 배터리 arm 을 만들고,
# `paper_research_dispatch.R` 가 그 arm 들을 Σ-A/B 로 실측한다. 세 wrapper 전부 fail-closed 다.
#
# 생산측이 없다. `verdict: "implemented"` 는 **사람이 손으로 친 문자열**이고 아무것도 그걸
# 검증하지 않는다. 그래서:
#   · 라우팅 누적 고유 83편 vs 레지스트리 고유 9편 — 등재가 병목인데 등재 경로가 수기다.
#   · loader 의 방어는 **런타임 skip** 이다(파일 부재·진입점 부재 → 메시지 찍고 넘어감).
#     로그로만 남으므로 "등재됐는데 한 번도 안 실린" 상태가 조용히 유지된다.
#   · 최악은 **로드는 되는데 아무 일도 안 하는** 어댑터다. `wrap_adapter` 는 퇴화 입력을
#     EW 로 내려앉히고 이름만 부른다(:59). 그러면 그 arm 은 "측정됨"으로 집계되지만
#     실제로 잰 것은 EW 다 — 실사고 기록이 그 파일 :73-78 에 있다(minvar 빌트인이 정확히
#     1/25 를 냈다). **측정 실패가 아니라 측정 안 함인데 결과표에는 수치가 찍힌다.**
#
# ⇒ 이 파일은 `verdict="implemented"` 를 **주장이 아니라 통과 기록**으로 바꾼다.
#   등재 시점에 어댑터를 실제로 돌려보고, 통과한 것만 implemented 로 적는다.
#
#------------------------------------------------------------------------------
# 설계 원칙
#------------------------------------------------------------------------------
# ① **원본 wrapper 로 검사한다** — 검사용 사본을 만들지 않는다. 사본 검사는 원본이 죽어도
#    통과한다(이 저장소가 반복 확인한 형태). production `wrap_*` 를 그대로 호출한다.
# ② **비-퇴화 검사가 본체다** — "돌았다"가 아니라 "무언가를 했다"를 요구한다.
#    weight: EW 와 구별될 것 / sigma: 표본공분산과 구별될 것 / exposure: 상수 1 이 아닐 것.
#    이 축이 없으면 EW 로 붕괴한 어댑터가 만점으로 등재된다.
# ③ **실패도 기록한다** — 거부는 `verdict="registration_failed"` + 사유로 남긴다.
#    아무것도 안 쓰면 "시도했는데 안 됐다"와 "아직 시도 안 했다"가 구분되지 않는다.
# ④ **동시쓰기 보호** — 레지스트리는 공유 원장이므로 `shared_registry_io.R` 의 뮤텍스+CAS 를
#    경유한다(FQ-122 갱신 2회 유실의 직접 대응).
# ⑤ **결정성** — 같은 fixture 로 두 번 돌려 다르면 거부. 숨은 RNG 는 A/B 비교를 무의미하게 한다.
#
#------------------------------------------------------------------------------
# 에이전트 핸드오프 (각 에이전트가 큐 논문을 소비하는 규약)
#------------------------------------------------------------------------------
#   mode_queue_<D>.json 항목  →  [optimizer-research / risk-research 에이전트]
#     ①논문 기전 1문단  ②KR long-only 사상(L/S 는 long leg 사상 허용)  ③PIT 근거
#     ④`02_Infrastructure/methods/adapters/<snake_name>.R` 작성 — 진입점은 kind 고정:
#         weight   → method_weights(ctx)      ctx: assets, R(obs×assets, PIT trailing), mu, Sigma
#         sigma    → sigma_estimate(ctx)      ctx: R, assets, lookback_days, decision_date, eval_date
#         exposure → exposure_schedule(ctx)   ctx: periods(decision_date, eval_date), bare_gross
#                    반환 list(exposure=DT(Date,exposure), used_cutoff=Date[], eligible_from=선택)
#     ⑤ register_method(...) 호출 → 통과분만 implemented. 실패하면 사유가 원장에 남는다.
#   등재되면 그 다음 dispatch 런에서 **자동으로** Σ-A/B arm 이 된다(추가 배선 불필요).
#
# ★제약은 어댑터가 지키는 게 아니라 wrapper 가 강제한다: long-only · Σw=1 · w≤0.20 ·
#   exposure∈[0,1] · C5 컷오프 신고. 어댑터는 **선호/추정치**만 낸다.
#==============================================================================

suppressWarnings(suppressMessages({
  library(jsonlite)
}))

.rm_root <- function() {
  for (c in c(Sys.getenv("QM_ROOT"), Sys.getenv("CLAUDE_PROJECT_DIR"), getwd())) {
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(normalizePath(c, "/", TRUE))
  }
  getwd()
}

REGISTER_METHOD_PATH <- "06_Registry/method_registry.json"

# 진입점 이름은 kind 가 정한다 — 어댑터가 임의로 고르지 못하게 한다.
#   (이름을 자유롭게 두면 loader 의 `entrypoint %||% 기본값` 이 조용히 빗나간다.)
.RM_ENTRY <- c(weight = "method_weights", sigma = "sigma_estimate", exposure = "exposure_schedule")

#------------------------------------------------------------------------------
# fixture — 결정적 합성 ctx. 난수는 고정 시드로 **한 번** 만든다.
#   ★실데이터를 쓰지 않는 이유: 등재 검사는 "계약을 지키는가"를 묻지 "성과가 좋은가"를 묻지
#   않는다. 실데이터를 넣으면 검사가 데이터 vintage 에 의존하게 되고, 그러면 같은 어댑터가
#   날마다 다른 판정을 받는다(오늘 세션에서만 vintage 의존 판정 반전을 여러 건 봤다).
#------------------------------------------------------------------------------
rm_fixture <- function(n_assets = 8L, n_obs = 260L, seed = 20260813L) {
  set.seed(seed)
  a <- sprintf("A%05d", seq_len(n_assets))
  R <- matrix(stats::rnorm(n_obs * n_assets, 0, 0.02), nrow = n_obs,
              dimnames = list(NULL, a))
  # 자산별 분산을 다르게 준다 — 전부 동일하면 minvar 류가 정당하게 EW 를 내서
  # 비-퇴화 검사가 **정상 어댑터를 오탐**한다(공허한 게이트의 반대 함정).
  R <- sweep(R, 2, seq(0.6, 1.8, length.out = n_assets), "*")
  mu <- stats::setNames(seq(0.004, -0.001, length.out = n_assets), a)
  S <- stats::cov(R); dimnames(S) <- list(a, a)
  d0 <- as.Date("2026-06-01")
  # ── exposure fixture (2026-08-13 정정) ───────────────────────────────────────
  # ★초판이 두 군데 틀렸고, 그 결과 **정상 어댑터 4건을 FAIL 로 냈다**(레지스트리가 죽었다고
  #   보고할 뻔했다). 검사기의 오탐은 대상의 결함과 겉보기가 같다.
  #   ① 날짜 규약 역전 — decision_date 를 **월말**로 뒀다. wrapper 는 hold_start 를
  #      월초(month(decision_date))로 잡으므로 월말 decision 은 컷오프가 hold_start 뒤에 와서
  #      **모든** 어댑터가 C5 위반으로 거부된다(실측 6개월 위반). production 규약대로
  #      decision_date = **홀딩월 1일** → 컷오프(직전월)가 앞선다.
  #   ② 길이 부족 — 24개월인데 vol-target 류는 burn-in 12개월을 먹는다. 남은 12개월
  #      백색잡음에선 문턱을 못 넘어 발화 0 → 상수 1 → 비-퇴화 검사가 정상 어댑터를 잡는다.
  #      60개월 + **국면이 실제로 바뀌는** 변동성(저변동 ↔ 고변동)을 준다.
  n_m <- 60L
  dd  <- seq(as.Date("2021-01-01"), by = "month", length.out = n_m)
  vol <- c(rep(0.02, 24), rep(0.075, 12), rep(0.025, 24))[seq_len(n_m)]
  # ── ctx 확장 입력 (2026-08-13) — production 과 **같은 provider 레지스트리**를 쓴다.
  #   ★fixture 가 자기만의 목(mock)을 만들면 production 이 provider 를 바꿔도 검사는 옛 모양을
  #     계속 통과한다(사본 검사 = 원본 사망 미검출). 그래서 여기서도 build_ctx_extras 를 부른다.
  #   ★단 등재 검증은 **패널이 있는 운영 조건**을 흉내내야 하므로, 레지스트리가 비었거나
  #     실데이터 로드가 실패하면 합성 패널로 낙하한다(검사 자체가 데이터 vintage 에 묶이면 안 됨).
  .prov <- file.path(.rm_root(), "02_Infrastructure/methods/ctx_providers.R")
  if (!exists("build_ctx_extras") && file.exists(.prov))
    suppressWarnings(try(source(.prov), silent = TRUE))
  # fixture=TRUE — provider 가 선언한 합성값을 쓴다(게이트는 vintage 비의존이어야 함).
  .extras <- if (exists("build_ctx_extras")) build_ctx_extras(d0, a, fixture = TRUE) else list()

  list(
    weight = c(list(assets = a, R = R, mu = mu, Sigma = S,
                    decision_date = d0, eval_date = d0 + 30, lookback_days = n_obs), .extras),
    sigma  = c(list(assets = a, R = R, lookback_days = n_obs,
                    decision_date = d0, eval_date = d0 + 30), .extras),
    exposure = list(
      periods    = data.frame(decision_date = dd, eval_date = dd + 27),
      bare_gross = data.frame(Date = dd + 27, r = stats::rnorm(n_m, 0.004, 1) * vol))
  )
}

#------------------------------------------------------------------------------
# 어댑터 1건 검증. list(ok, reason, checks)
#------------------------------------------------------------------------------
verify_adapter <- function(adapter_path, kind, method_id = "CANDIDATE", root = .rm_root(),
                           allow_fixture_degenerate = NULL) {
  chk <- list(); fail <- function(r) list(ok = FALSE, reason = r, checks = chk)
  if (!(kind %in% names(.RM_ENTRY))) return(fail(sprintf("adapter_kind 미지원: %s", kind)))
  ap <- if (file.exists(adapter_path)) adapter_path else file.path(root, adapter_path)
  if (!file.exists(ap)) return(fail(sprintf("어댑터 파일 부재: %s", adapter_path)))
  chk$file_exists <- TRUE

  env <- new.env(parent = globalenv())
  src <- tryCatch({ sys.source(ap, envir = env); TRUE },
                  error = function(e) conditionMessage(e))
  if (!isTRUE(src)) return(fail(sprintf("source 실패: %s", src)))
  chk$sources <- TRUE

  fname <- .RM_ENTRY[[kind]]
  if (!exists(fname, envir = env, inherits = FALSE))
    return(fail(sprintf("진입점 `%s` 부재 (kind=%s 는 이 이름 고정)", fname, kind)))
  chk$entrypoint <- fname
  fn <- get(fname, envir = env)
  if (!is.function(fn)) return(fail(sprintf("`%s` 가 함수가 아님", fname)))

  fx <- rm_fixture()
  # ★production wrapper 를 그대로 쓴다 — 검사용 사본 금지(사본은 원본 사망을 못 잡는다).
  mrp <- file.path(root, "02_Infrastructure/methods/method_registry.R")
  if (!file.exists(mrp)) return(fail("method_registry.R 부재 — wrapper 로 검사할 수 없음"))
  wenv <- new.env(parent = globalenv())
  # ★wrapper 의 **의존까지** 갖춰야 검사가 성립한다. `wrap_adapter` 는 `normalize_long_only`
  #   (02_Infrastructure/portfolio/strategy_tilt_weights.R)를 부르는데, production 은 호출자가
  #   미리 로드해둔 상태로 돈다. 이걸 빠뜨리면 **모든 weight 어댑터가 "실행 예외"로 거부**된다.
  #   실제로 초판이 그랬고, 위반 주입 8/8 거부만 보면 성공처럼 보였다 — 양성 대조(실동작
  #   어댑터가 통과하는가)가 그걸 잡았다. 의존 결손을 조용히 넘기지 않고 이름 붙여 실패시킨다.
  dep <- file.path(root, "02_Infrastructure/portfolio/strategy_tilt_weights.R")
  if (file.exists(dep)) suppressWarnings(try(sys.source(dep, envir = wenv), silent = TRUE))
  # ★wrap_exposure_adapter 는 data.table 을 쓴다(`as.data.table`, `e[, .(Date, exposure)]`).
  #   production 은 호출자가 이미 로드한 상태로 돈다 — 검증기에서 빠뜨리면 **어댑터가 정상인데
  #   "실행 예외"로 거부**된다(실측: TFCostOptSpan 이 자기 로그까지 찍고 나서 wrapper 에서 죽었다).
  #   normalize_long_only 때와 같은 계열 — wrapper 의존은 한 곳에 모아 갖춘다.
  suppressWarnings(suppressMessages(try(library(data.table), silent = TRUE)))
  ok <- tryCatch({ sys.source(mrp, envir = wenv); TRUE }, error = function(e) conditionMessage(e))
  if (!isTRUE(ok)) return(fail(sprintf("method_registry.R source 실패: %s", ok)))
  if (kind == "weight" && !exists("normalize_long_only", envir = wenv, inherits = TRUE))
    return(fail("하네스 의존 결손 — normalize_long_only 미로드(strategy_tilt_weights.R). 어댑터 문제가 아니다."))

  run <- function(ctx, wrapped) tryCatch(wrapped(ctx), error = function(e) structure(NA, err = conditionMessage(e)))

  if (kind == "weight") {
    w <- get("wrap_adapter", envir = wenv)(fn, method_id)
    o1 <- run(fx$weight, w); o2 <- run(fx$weight, w)
    if (length(o1) == 1L && is.na(o1)) return(fail(sprintf("실행 예외: %s", attr(o1, "err"))))
    if (!isTRUE(all.equal(o1, o2))) return(fail("비결정적 — 같은 fixture 에서 두 실행이 다르다(숨은 RNG?)"))
    chk$deterministic <- TRUE
    ew <- rep(1 / length(fx$weight$assets), length(fx$weight$assets))
    # ★비-퇴화: EW 와 구별되지 않으면 '돌았지만 아무것도 안 한' 상태다(wrap_adapter :73-78 실사고).
    if (max(abs(as.numeric(o1) - ew)) < 1e-6)
      return(fail("퇴화 — 출력이 EW 와 동일. 어댑터가 실질적으로 아무 것도 하지 않는다"))
    chk$non_degenerate <- sprintf("max|w-EW|=%.4g", max(abs(as.numeric(o1) - ew)))
    chk$constraints <- sprintf("sum=%.6f max=%.4f", sum(o1), max(o1))

  } else if (kind == "sigma") {
    w <- get("wrap_sigma_estimator", envir = wenv)(fn, method_id)
    o1 <- run(fx$sigma, w); o2 <- run(fx$sigma, w)
    if (length(o1) == 1L && is.na(o1)) return(fail(sprintf("실행 예외: %s", attr(o1, "err"))))
    if (!isTRUE(all.equal(o1, o2))) return(fail("비결정적 — 두 실행이 다르다"))
    chk$deterministic <- TRUE
    samp <- stats::cov(fx$sigma$R)
    rel <- max(abs(o1 - samp)) / max(abs(samp))
    # 표본공분산과 구별 안 되면 wrapper 가 폴백했거나 추정기가 표본공분산 그 자체다.
    if (!is.finite(rel) || rel < 1e-8)
      return(fail("퇴화 — 표본공분산과 구별되지 않음(폴백했거나 추정기가 사실상 표본공분산)"))
    chk$non_degenerate <- sprintf("rel_dev=%.4g", rel)

  } else {  # exposure
    w <- get("wrap_exposure_adapter", envir = wenv)(fn, method_id)
    o1 <- run(fx$exposure, w); o2 <- run(fx$exposure, w)
    if (is.null(o1)) return(fail("wrapper 가 로드 거부 — 계약 위반(exposure/used_cutoff 결손 · [0,1] 이탈 · C5 컷오프 위반 중 하나). 콘솔 사유 확인"))
    if (length(o1) == 1L && !is.list(o1) && is.na(o1)) return(fail(sprintf("실행 예외: %s", attr(o1, "err"))))
    if (!isTRUE(all.equal(o1, o2))) return(fail("비결정적 — 두 실행이 다르다"))
    chk$deterministic <- TRUE
    # ★wrapper 반환은 list 가 아니라 **data.table(Date, exposure)** 다(method_registry.R 끝줄
    #   `e[, .(Date, exposure)]`). `o1$exposure` 로 읽으면 초판처럼 NULL → 상수1 오판이 난다.
    .edf <- as.data.frame(o1)
    if (!("exposure" %in% names(.edf))) return(fail("wrapper 반환에 exposure 열 없음 — 계약 변경 의심"))
    ex <- as.numeric(.edf$exposure)
    if (all(abs(ex - 1) < 1e-9)) {
      # ★제3 결과 — 합성 fixture 로 **원리적으로** 판정 불가한 부류가 있다 (2026-08-13).
      #   확장창 분위 문턱(rate-matched) 어댑터는 문턱을 자기 과거 신호 분포에서 뽑는다.
      #   그 분포는 실신호의 정상성/군집성에 의존하므로(method_registry.R:258-261 에 기전 기록:
      #   초기 고변동이 분포 상단을 점유해 발화율이 붕괴) 합성 계열에선 발화가 0 이 될 수 있다.
      #   ⇒ 여기서 FAIL 을 내면 **정상 어댑터를 막고**, 통과시키려 fixture 를 손보면
      #     답을 보고 검사를 고치는 것이다. 둘 다 하지 않고 "검증 안 됨"으로 분리한다.
      #   등재자는 `allow_fixture_degenerate=<사유>` 로 명시 선언해야 하며, 그 사유가 원장에 남는다.
      if (nzchar(allow_fixture_degenerate %||% ""))
        return(list(ok = TRUE, unverified = TRUE,
                    reason = sprintf("fixture 비발화 — 선언 사유: %s", allow_fixture_degenerate),
                    checks = c(chk, list(non_degenerate = "UNVERIFIED_ON_FIXTURE"))))
      return(fail(paste0("퇴화 — 노출이 상수 1(오버레이가 아무것도 하지 않음). ",
                         "확장창 분위 문턱처럼 실신호 분포에 의존해 합성 fixture 에서 발화가 0 이 되는 ",
                         "부류라면 allow_fixture_degenerate=<사유> 로 선언할 것(원장에 기록됨).")))
    }
    chk$non_degenerate <- sprintf("발화 %d/%d · 평균 %.3f", sum(ex < 1 - 1e-9), length(ex), mean(ex))
  }
  list(ok = TRUE, reason = NA_character_, checks = chk)
}

#------------------------------------------------------------------------------
# 등재. 통과 → implemented / 실패 → registration_failed(사유 보존).
#------------------------------------------------------------------------------
register_method <- function(method_id, paper_id, paper_title, route, adapter_kind,
                            adapter, mechanism, kr_mapping,
                            screen_axes = NULL, selection_type = "chain",
                            free_params = NULL, routed_on = NULL,
                            allow_fixture_degenerate = NULL,
                            root = .rm_root(), dry_run = FALSE) {
  stopifnot(nzchar(method_id), nzchar(paper_id), nzchar(adapter_kind), nzchar(adapter))
  if (!nzchar(mechanism %||% "") || !nzchar(kr_mapping %||% ""))
    stop("[register_method] mechanism · kr_mapping 필수 — 기전 없이 등재하면 나중에 무엇을 쟀는지 복원 불가.")

  v <- verify_adapter(adapter, adapter_kind, method_id, root = root,
                      allow_fixture_degenerate = allow_fixture_degenerate)
  cat(sprintf("[register_method] %s (%s) 검증: %s%s\n", method_id, adapter_kind,
              if (v$ok) "PASS" else "FAIL", if (v$ok) "" else paste0(" — ", v$reason)))
  for (k in names(v$checks)) cat(sprintf("    %-16s %s\n", k, as.character(v$checks[[k]])))

  entry <- list(
    method_id = method_id, route = route, adapter_kind = adapter_kind,
    paper_id = paper_id, paper_title = paper_title,
    routed_on = routed_on %||% NA_character_,
    mechanism = mechanism, kr_mapping = kr_mapping,
    adapter = adapter, entrypoint = unname(.RM_ENTRY[[adapter_kind]]),
    verdict = if (v$ok) "implemented" else "registration_failed",
    registration = list(
      # ★"검증됨"이 무엇을 통과했다는 뜻인지 명시한다 — 라벨만 남기면 나중에 그 범위를 못 묻는다.
      verified_by = "register_method.R (production wrapper 경유 · 합성 fixture)",
      checks = v$checks,
      failure_reason = if (v$ok) NULL else v$reason,
      unverified_on_fixture = isTRUE(v$unverified),
      unverified_reason = if (isTRUE(v$unverified)) v$reason else NULL,
      fixture = "rm_fixture(n_assets=8, n_obs=260, seed=20260813)",
      scope_note = "계약 준수 검증이지 성과 검증이 아니다. 성과는 dispatch Σ-A/B 가 잰다."
    ),
    screen_axes = screen_axes, selection_type = selection_type, free_params = free_params,
    measured = FALSE, similar_to = list()
  )
  if (dry_run) { cat("[register_method] dry_run — 원장 미기록\n"); return(invisible(list(ok = v$ok, entry = entry))) }

  # ── 공유 원장 쓰기: 뮤텍스 + CAS + churn 예산 (shared_registry_io)
  sio <- file.path(root, "02_Infrastructure/ops/shared_registry_io.R")
  if (!file.exists(sio)) stop("[register_method] shared_registry_io.R 부재 — 동시쓰기 가드 없이 원장에 쓰지 않는다.")
  senv <- new.env(parent = globalenv()); sys.source(sio, envir = senv)
  path <- file.path(root, REGISTER_METHOD_PATH)

  res <- get("sr_with_lock", envir = senv)(path, {
    base <- get("sr_read", envir = senv)(path)
    reg  <- jsonlite::fromJSON(base$text, simplifyVector = FALSE)
    ms   <- reg$methods %||% list()
    ids  <- vapply(ms, function(m) as.character(m$method_id %||% ""), character(1))
    if (method_id %in% ids) {
      ms[[which(ids == method_id)[1]]] <- entry
      act <- "갱신"
    } else { ms[[length(ms) + 1L]] <- entry; act <- "신규" }
    reg$methods <- ms
    txt <- jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
    get("sr_guard_write", envir = senv)(path, as.character(txt), base,
                                        budget_lines = 200L, what = "method_registry.json")
    act
  })
  cat(sprintf("[register_method] 원장 %s — verdict=%s\n", res, entry$verdict))
  invisible(list(ok = v$ok, action = res, entry = entry))
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
