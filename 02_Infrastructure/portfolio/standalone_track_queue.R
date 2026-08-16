#==============================================================================
# standalone_track_queue.R — screen_route 소비 배관 + 라벨↔원장 정합 스크린
#
# 2026-08-02 신설 (WT-D20260802_005 실측 적발). 대상 결함:
#   hurdle_gate.R:1581-1599 가 발급하는 screening-tier 라벨 중 **STANDALONE_TRACK 은
#   소비자 코드가 저장소에 0건**이었다. 실증 피해 = Chen-Welch RD-to-Market
#   (STR_AS_20260709_074129_30048): proxy Grade A + STANDALONE_TRACK 을 받고도
#   standalone 판정 경로가 없어 3주+ 방치, WT-005 재고 회수 라운드가 canonical
#   재실측으로 발굴할 때까지 아무도 몰랐다.
#
# ★유실 기전의 정확한 형태 (초기 진단 정정 — 2026-08-02 실측):
#   후보가 **원장에서 사라진 게 아니다**. Chen-Welch 는 module_catalog.json 에
#   fr_eligible=TRUE 로 정상 등재돼 있다. 문제는 module_catalog 의 유일한 소비자가
#   factor-rotation FR 풀(build_module_performance.R)이라는 것 — 즉
#   "이 후보가 standalone 졸업 심사를 받을 자격이 있나" 를 **묻는 코드가 없다**.
#   라벨이 가리키는 주소(생산자 주석 "기존 등급 경로가 이미 소화")가 실제로는
#   FR 풀에서 끝난다. 라벨 → 판정 사이에 원장이 없었다.
#
# 역할:
#   ① 라벨 보유분 전수 수집 → 06_Registry/standalone_track_queue.json 적재
#   ② standalone 처분(disposition) 증거 대조 → 미처분분이 backlog 로 남는다
#   ③ **양방향 정합 스크린** — 발급→원장 누락 + 원장→발급 역추적 불가 둘 다 검출
#   ④ catalog∩quarantine 중복(사전-재측정 proxy 행 잔존) 검출 — Chen-Welch 가
#      "quarantine 에 유실"처럼 보이던 겉모습의 실체
#
# ★★"빈 결과 = 합격" 금지 (이 저장소 반복 결함, memory project-empty-means-pass-family):
#   스캔 소스가 0건이면 PASS 가 아니라 **UNREPORTED(stop)** 이다. 잘못된 cwd·경로에서
#   돌아 0건을 반환하고 그 0 이 "누락 없음"으로 읽히는 경로를 원천 차단한다.
#
# 소비자: bootstrap.sh §8j 상태라인 + 세션 Q-Lead(FQ-111 경유).
# 검사기: 08_Tests/portfolio/test_standalone_track_queue.R (위반 주입 + 오발화 확인)
#
# Usage: Rscript 02_Infrastructure/portfolio/standalone_track_queue.R [--json] [--no-write]
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# r-portability.md ④: CLAUDE_PROJECT_DIR 우선 + 존재검사 아닌 **marker 검증**으로 루트 확정.
.st_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}

QUEUE_REL <- "06_Registry/standalone_track_queue.json"
DISPO_REL <- "06_Registry/standalone_track_dispositions.json"

# screening tier 도입일 (v8.1.1, 도훈 mandate P2 — hurdle_gate.R:1568).
#   이 날짜 *이전* 등록 모듈은 라벨이 존재하지 않던 시기의 산물이다. 역방향 검사에서
#   이를 "라벨 누락"으로 세면 78건이 상시 점등돼 검사기가 무시당한다(초판 실측 오검출).
ST_SCREENING_SINCE <- "2026-06-10"

# hurdle_gate.R:1581-1599 발급 route 전체. 소비자 실존 여부는 2026-08-02 census 실측.
#   consumer=TRUE 인 값만 "라벨이 코드에 도달한다". 새 route 를 발급하면 여기에 등록해야
#   하고, 등록만 하고 소비자를 안 만들면 아래 스캔이 그 사실을 매번 보고한다.
ST_ROUTE_CONSUMERS <- list(
  NONE              = list(consumer = NA,    ref = "무발급 라우트(신호력 미달) — 소비 대상 아님"),
  OVERLAY_CANDIDATE = list(consumer = TRUE,  ref = "02_Infrastructure/regime/overlay_candidate_queue.R"),
  STANDALONE_TRACK  = list(consumer = TRUE,  ref = "02_Infrastructure/portfolio/standalone_track_queue.R (본 파일, 2026-08-02 신설)"),
  FR_RCMA           = list(consumer = FALSE, ref = "소비자 0 — factor-rotation/RCMA 측 라벨 판독 코드 없음 (regime_module_admission.R 입력에 screen_route 항 부재)"),
  TURNOVER_REVIEW   = list(consumer = FALSE, ref = "소비자 0 — 설계상 기록 전용(hurdle_gate.R:1590 주석). 발급 실적 0건"),
  DPL_FEATURE       = list(consumer = FALSE, ref = "v8.3 발급 중단(measurement-graduation §5). 구 manifest 호환 문자열만 잔존")
)

# 저장소-상대경로. ★root 를 정규식으로 쓰면 안 된다 — Windows 경로의 백슬래시가
#   역참조로 해석돼 sub() 가 통째로 죽는다(검사기가 실측 검출). 문자열 접두 제거로 처리.
.st_rel <- function(p, root) {
  p2 <- gsub("\\\\", "/", p); r2 <- sub("/+$", "", gsub("\\\\", "/", root))
  if (nzchar(r2) && startsWith(p2, paste0(r2, "/"))) substring(p2, nchar(r2) + 2L) else p2
}

.st_num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x[1]))
.st_chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[1])
.st_dig <- function(d, ...) { cur <- d; for (k in c(...)) { if (!is.list(cur)) return(NULL); cur <- cur[[k]] }; cur }
.st_json <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL

# strategy_id 는 토큰 경계로 찾는다 — substring 매칭은 같은 STR 번호 다른 전략을 오결합한다
# (memory project-strategy-id-substring-ambiguity, 07-25 실사고).
.st_mentions <- function(blob, id) {
  if (!nzchar(id %||% "")) return(FALSE)
  grepl(paste0("(^|[^A-Za-z0-9_])", id, "([^A-Za-z0-9_]|$)"), blob, perl = TRUE)
}

#------------------------------------------------------------------------------
# 라벨 발급분 전수 수집 — manifest(정본) + hurdle_result(manifest 결손분 보강)
#------------------------------------------------------------------------------
.st_collect_labels <- function(root) {
  out <- list()
  seen_dir <- character(0)

  mf <- Sys.glob(file.path(root, "stage_artifacts/alpha_search/*/strategy_manifest.json"))
  for (f in mf) {
    m <- .st_json(f); if (is.null(m)) next
    d <- basename(dirname(f)); seen_dir <- c(seen_dir, d)
    scr <- .st_dig(m, "verdict", "screening") %||% list()
    out[[length(out) + 1L]] <- list(
      run_dir = d, src = "manifest", src_path = .st_rel(f, root),
      strategy_id = .st_chr(m$strategy_id) %||% d,
      strategy_name = .st_chr(m$strategy_name),
      route = .st_chr(scr$screen_route),
      screen_pass = isTRUE(scr$screen_pass),
      proxy_grade = .st_chr(.st_dig(m, "verdict", "grade")) %||% .st_chr(m$grade),
      essence_grade = .st_chr(.st_dig(m, "authoritative", "essence_grade")),
      labeled_at = .st_chr(m$created_at)
    )
  }
  # manifest 없는 런: 라벨이 hurdle_result 에만 남는다. 여기서 안 보면 사각이 된다.
  hr <- Sys.glob(file.path(root, "stage_artifacts/alpha_search/*/hurdle_result.json"))
  for (f in hr) {
    d <- basename(dirname(f)); if (d %in% seen_dir) next
    h <- .st_json(f); if (is.null(h)) next
    scr <- h$screening %||% .st_dig(h, "verdict", "screening") %||% list()
    # 2026-06-10 screening tier 도입 이전 런은 screening 자체가 없다(결함 아님 — 미발급).
    if (is.null(scr$screen_route)) next
    # ★hurdle_result 의 `strategy` 는 전략 *이름*이지 id 가 아니다("52-Week High Anchor
    #   Momentum"). 그대로 id 로 쓰면 원장 대조가 전건 실패해 미처분이 부풀려진다.
    #   run_dir 파생 id 를 우선 시도하고, 원장에 없을 때만 이름으로 떨어진다.
    sid_guess <- paste0("STR_AS_", d)
    out[[length(out) + 1L]] <- list(
      run_dir = d, src = "hurdle_result", src_path = .st_rel(f, root),
      strategy_id = sid_guess, id_basis = "run_dir_derived",
      strategy_name = .st_chr(h$strategy),
      route = .st_chr(scr$screen_route),
      screen_pass = isTRUE(scr$screen_pass),
      proxy_grade = .st_chr(h$grade),
      essence_grade = NA_character_,
      labeled_at = .st_chr(h$timestamp)
    )
  }
  out
}

#------------------------------------------------------------------------------
# 정합 스캔 — 인자화(root)로 픽스처 호출 가능. 위반 주입 검사기가 이 함수를 때린다.
#------------------------------------------------------------------------------
#' @param root 프로젝트 루트
#' @return list(rows, n_labeled, n_unconsumed, n_route_no_consumer, n_shadow, inputs, status)
standalone_track_scan <- function(root = .st_root()) {
  as_dir <- file.path(root, "stage_artifacts/alpha_search")
  cat_p  <- file.path(root, "06_Registry/module_catalog.json")
  qua_p  <- file.path(root, "06_Registry/module_quarantine.json")
  fq_p   <- file.path(root, "06_Registry/alpha_frontier_queue.json")

  # ★입력 부재 = 미측정. PASS 로 흘리지 않는다.
  if (!dir.exists(as_dir))
    stop("[standalone_track] 스캔 소스 부재(미측정, PASS 아님): ", as_dir)
  miss <- c(cat_p, fq_p)[!file.exists(c(cat_p, fq_p))]
  if (length(miss))
    stop("[standalone_track] 소비 원장 부재(미측정, PASS 아님): ",
         paste(basename(miss), collapse = ", "))

  labels <- .st_collect_labels(root)
  # ★0건 = 합격 아님. 라벨 발급 이력이 실재하는 시스템에서 0 은 스캐너 사망 신호다.
  if (!length(labels))
    stop("[standalone_track] 라벨 발급분 0건 — 스캔 경로/스키마 사망 의심(UNREPORTED, PASS 아님). 소스: ", as_dir)

  CAT <- .st_json(cat_p); QUA <- .st_json(qua_p)
  cat_mods <- CAT$modules %||% list(); qua_mods <- QUA$modules %||% list()
  fq_blob  <- paste(readLines(fq_p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  dispo    <- .st_json(file.path(root, DISPO_REL))
  dispo_map <- dispo$dispositions %||% list()

  rows <- list()
  for (L in labels) {
    rt <- L$route %||% ""
    parts <- unlist(strsplit(rt, "|", fixed = TRUE))
    parts <- parts[nzchar(parts)]
    # 소비자 미등록 route (미지 route 포함 — 새 값을 발급하면 여기서 즉시 보인다)
    no_consumer <- parts[vapply(parts, function(p) {
      m <- ST_ROUTE_CONSUMERS[[p]]
      is.null(m) || identical(m$consumer, FALSE)
    }, logical(1))]

    sid <- L$strategy_id %||% L$run_dir
    cm  <- cat_mods[[sid]]; qm <- qua_mods[[sid]]
    ess <- .st_dig(cm, "meta", "authoritative_essence")

    # standalone 처분 증거: 명시 처분 원장 ∨ frontier queue 언급 ∨ live_track 등재
    live_dir <- file.path(root, "06_Registry/live_track", sid)
    dispo_hit <- !is.null(dispo_map[[sid]])
    fq_hit    <- .st_mentions(fq_blob, sid)
    live_hit  <- dir.exists(live_dir)
    disposition <- if (dispo_hit) .st_chr(dispo_map[[sid]]$verdict) %||% "recorded"
                   else if (live_hit) "live_track"
                   else if (fq_hit) "frontier_queued"
                   else "none"

    rows[[length(rows) + 1L]] <- data.table(
      strategy_id  = sid,
      run_dir      = L$run_dir,
      src          = L$src,
      route        = rt,
      screen_pass  = isTRUE(L$screen_pass),
      proxy_grade  = L$proxy_grade %||% NA_character_,
      essence_grade = L$essence_grade %||% .st_chr(cm$grade),
      port_t_nw3   = .st_num(ess$portfolio_alpha_t_nw_lag3),
      oos_retention = .st_num(ess$oos_retention),
      calmar       = .st_num(ess$calmar),
      net_sharpe   = .st_num(ess$net_sharpe),
      in_catalog   = !is.null(cm),
      fr_eligible  = isTRUE(cm$fr_eligible),
      metric_type  = .st_chr(cm$metric_type),
      shadow_quarantine = (!is.null(cm) && !is.null(qm)),
      disposition  = disposition,
      routes_without_consumer = paste(no_consumer, collapse = "|"),
      strategy_name = substr(L$strategy_name %||% "", 1, 90),
      labeled_at   = L$labeled_at %||% NA_character_,
      src_path     = L$src_path
    )
  }
  R <- rbindlist(rows, fill = TRUE)

  # 추적 대상 = 신호력 통과분 중 NONE 이 아닌 라벨 (NONE 은 발급-무의미 라우트)
  tracked <- R[screen_pass == TRUE & !is.na(route) & route != "" & route != "NONE"]
  standalone <- tracked[grepl("STANDALONE_TRACK", route, fixed = TRUE)]
  unconsumed <- standalone[disposition == "none"]

  # 역방향: 원장(module_catalog) 에 있는데 라벨 발급 흔적을 못 찾는 alpha_search 모듈.
  #   ★단방향 검사는 "라벨은 있는데 원장에 없다" 만 본다 — 그 반대(원장 행이 어느
  #   라벨에서 왔는지 역추적 불가)를 놓치면 원장이 유령 행으로 오염돼도 초록이 뜬다.
  #   ★★단 대상은 **라벨 경로를 실제로 지나는 모듈**로 한정한다:
  #     ① screening tier 도입 이후 등록분 (그 전엔 라벨이 없었다)
  #     ② stage_artifacts/alpha_search 아래 run_dir 이 실재하는 것
  #        (논문복제 러너 run_pead_paper.R 등은 register_module 을 직접 부르고
  #         alpha_search run_dir 을 만들지 않는다 — 라벨 대상이 아니다)
  #   이 한정 없이는 78건이 상시 점등된다(초판 실측) = 검사기가 무시당하는 경로.
  labeled_ids <- unique(R$strategy_id)
  as_cat_ids <- names(cat_mods)[vapply(cat_mods, function(m)
    identical(.st_chr(m$origin_mode), "alpha_search"), logical(1))]
  in_label_path <- vapply(as_cat_ids, function(sid) {
    reg <- substr(.st_chr(cat_mods[[sid]]$registered_at) %||% "", 1, 10)
    if (!nzchar(reg) || reg < ST_SCREENING_SINCE) return(FALSE)
    rd <- sub("^STR_AS_", "", sid)
    if (identical(rd, sid)) return(FALSE)        # STR_AS_ 접두 아님 = 라벨 경로 밖
    dir.exists(file.path(root, "stage_artifacts/alpha_search", rd))
  }, logical(1))
  orphan_ledger <- setdiff(as_cat_ids[in_label_path], labeled_ids)

  list(
    rows = R,
    tracked = tracked,
    standalone = standalone,
    unconsumed = unconsumed,
    n_labeled = nrow(R),
    n_tracked = nrow(tracked),
    n_standalone = nrow(standalone),
    n_unconsumed = nrow(unconsumed),
    n_route_no_consumer = nrow(tracked[routes_without_consumer != ""]),
    n_shadow = nrow(R[shadow_quarantine == TRUE]),
    orphan_ledger = orphan_ledger,
    n_orphan_ledger = length(orphan_ledger),
    inputs = list(labels = nrow(R), catalog = length(cat_mods),
                  quarantine = length(qua_mods), alpha_search_catalog = length(as_cat_ids)),
    status = "MEASURED"
  )
}

#------------------------------------------------------------------------------
# 큐 적재 — 재실행 idempotent (전량 재생성)
#------------------------------------------------------------------------------
build_standalone_track_queue <- function(root = .st_root(), write = TRUE) {
  s <- standalone_track_scan(root)
  # graduation 근접도 순 정렬: PORT_t 실측 보유분 우선, 그 안에서 t 내림차순.
  U <- copy(s$unconsumed)
  if (nrow(U)) setorder(U, -port_t_nw3, na.last = TRUE)

  mk <- function(dt) lapply(seq_len(nrow(dt)), function(i) as.list(dt[i]))

  q <- list(
    schema_version = "standalone_track_queue_v1",
    generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    producer_ref   = "02_Infrastructure/hurdle_gate.R:1581-1599 verdict$screening$screen_route (measurement-graduation §3 screening tier)",
    consumer_ref   = "Q-Lead standalone 판정 (graduation HARD 3종: PORT_t>=2.95 / oos_retention>=0.7 / calmar>=0.64) — 처분 기록은 06_Registry/standalone_track_dispositions.json",
    note = paste0(
      "screening tier 라벨 — 자본/졸업 게이트 아님(HARD 불변). disposition='none' = ",
      "standalone 판정을 아무도 안 한 backlog. FR 풀 등재(fr_eligible)는 standalone 처분이 ",
      "아니다 — module_catalog 의 소비자는 factor-rotation 뿐이다."),
    route_consumer_map = ST_ROUTE_CONSUMERS,
    counts = list(
      labeled = s$n_labeled, tracked = s$n_tracked, standalone = s$n_standalone,
      unconsumed = s$n_unconsumed, routes_without_consumer = s$n_route_no_consumer,
      shadow_quarantine = s$n_shadow, orphan_ledger = s$n_orphan_ledger
    ),
    unconsumed = mk(U),
    routes_without_consumer = mk(s$tracked[routes_without_consumer != ""][
      , .(strategy_id, route, routes_without_consumer, proxy_grade, labeled_at)]),
    shadow_quarantine = mk(s$rows[shadow_quarantine == TRUE][
      , .(strategy_id, proxy_grade, essence_grade, route, labeled_at)]),
    orphan_ledger = s$orphan_ledger
  )
  if (isTRUE(write)) {
    qp <- file.path(root, QUEUE_REL)
    write_json(q, qp, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
    cat(sprintf("[standalone_track] wrote %s — unconsumed=%d / standalone=%d / labeled=%d\n",
                QUEUE_REL, s$n_unconsumed, s$n_standalone, s$n_labeled))
  }
  invisible(list(queue = q, scan = s))
}

#------------------------------------------------------------------------------
# 처분 기록 배관 (2026-08-16 P0#4 — L1 자동 스폰 설계, 도훈 승인)
#   왜: 큐 신설(08-02) 후 backlog 50건에 dispositions.json 이 빈 맵({}) — 처분을
#   *기록하는* 함수가 저장소에 없어 스캔의 disposition='none' 이 영구 상태였다.
#   처분은 판정이 아니라 라우팅 기록 — graduation HARD/governor 는 불변.
#------------------------------------------------------------------------------
ST_DISPO_VERDICTS <- c("standalone_reject", "overlay_routed", "fr_routed", "ramp_routed",
                       "frontier_queued", "revival_wait", "graduation_candidate", "duplicate")

st_record_disposition <- function(strategy_id, verdict, note = "", by = "Q-Lead",
                                  root = .st_root()) {
  if (!nzchar(strategy_id %||% "")) stop("[standalone_track] strategy_id 필수")
  if (!nzchar(verdict %||% ""))
    stop("[standalone_track] verdict 필수 — 표준: ", paste(ST_DISPO_VERDICTS, collapse = ", "))
  if (!(verdict %in% ST_DISPO_VERDICTS))
    message("[standalone_track] 비표준 verdict '", verdict, "' — 표준: ",
            paste(ST_DISPO_VERDICTS, collapse = ", "), " (기록은 진행)")
  dp <- file.path(root, DISPO_REL)
  d <- .st_json(dp)
  if (is.null(d)) d <- list(schema_version = "standalone_dispositions_v1",
                            `_doc` = paste("standalone_track_queue 처분 원장 —",
                                           "st_record_disposition() 로만 기록.",
                                           "verdict 는 라우팅 기록이지 자본 판정 아님."),
                            dispositions = list())
  if (is.null(d$dispositions)) d$dispositions <- list()
  prior <- d$dispositions[[strategy_id]]
  rec <- list(verdict = verdict, note = note, by = by,
              recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (!is.null(prior)) rec$supersedes <- prior$recorded_at %||% NA_character_
  d$dispositions[[strategy_id]] <- rec
  # 원자적 temp-rename (OneDrive/Win 확립 관행 — hypothesis_index F-1 선례)
  tmp <- paste0(dp, ".tmp", Sys.getpid())
  write_json(d, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  if (file.exists(dp)) suppressWarnings(file.remove(dp))
  if (!isTRUE(suppressWarnings(file.rename(tmp, dp)))) {
    ok <- suppressWarnings(file.copy(tmp, dp, overwrite = TRUE))
    suppressWarnings(file.remove(tmp))
    if (!isTRUE(ok)) stop("[standalone_track] dispositions 원자 기록 실패: ", dp)
  }
  # 기록 후 재읽기 확인 (frontier 큐 consume_rule 관행 승계 — 조용한 유실 차단)
  chk <- .st_json(dp)
  if (is.null(chk$dispositions[[strategy_id]]))
    stop("[standalone_track] 기록 후 재읽기 실패 — 처분이 저장되지 않음: ", strategy_id)
  cat(sprintf("[standalone_track] 처분 기록: %s -> %s (by %s)%s\n", strategy_id, verdict, by,
              if (!is.null(prior)) " [기존 기록 supersede]" else ""))
  invisible(rec)
}

#------------------------------------------------------------------------------
# 상태 1줄 (bootstrap §8j 소비)
#------------------------------------------------------------------------------
standalone_track_status_line <- function(root = .st_root()) {
  s <- tryCatch(standalone_track_scan(root), error = function(e) e)
  if (inherits(s, "error"))
    return(sprintf("StandaloneTrk: UNREPORTED — %s", conditionMessage(s)))
  top <- ""
  if (s$n_unconsumed > 0L) {
    U <- copy(s$unconsumed); setorder(U, -port_t_nw3, na.last = TRUE)
    top <- sprintf(" · 최상위 %s(PORT_t %s)", U$strategy_id[1],
                   ifelse(is.na(U$port_t_nw3[1]), "미실측", sprintf("%.3f", U$port_t_nw3[1])))
  }
  sprintf(paste0("StandaloneTrk: 미처분 %d / STANDALONE_TRACK 발급 %d%s",
                 " · 소비자없는 route %d · quarantine 잔존행 %d"),
          s$n_unconsumed, s$n_standalone, top, s$n_route_no_consumer, s$n_shadow)
}

# main-guard: source() 시 CLI 가 덩달아 실행되지 않도록 --file 인자로 자기 확인
# (frontier_registry_coherence.R 선례 — identical(environment(), globalenv()) 은 source 에서도 참).
.st_invoked_directly <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  # ★suffix 매칭 금지 — "test_standalone_track_queue.R" 도 그 정규식에 걸려서
  #   검사기가 SUT 를 source 하는 순간 CLI 가 덩달아 실행됐다(검사기가 실측 검출).
  length(f) > 0L && identical(basename(f[1]), "standalone_track_queue.R")
}

if (.st_invoked_directly()) {
  args <- commandArgs(trailingOnly = TRUE)
  root <- .st_root()
  # --dispose: 처분 기록 (P0#4). 예: --dispose=STR_AS_x --verdict=overlay_routed [--note=..]
  dv <- grep("^--dispose=", args, value = TRUE)
  if (length(dv)) {
    gv <- function(key) {
      h <- grep(paste0("^--", key, "="), args, value = TRUE)
      if (length(h)) sub(paste0("^--", key, "="), "", h[1]) else ""
    }
    st_record_disposition(sub("^--dispose=", "", dv[1]), gv("verdict"), gv("note"),
                          by = if (nzchar(gv("by"))) gv("by") else "Q-Lead", root = root)
    quit(save = "no", status = 0L)
  }
  # --status-line: 부팅 표면 전용(읽기만). 매 부팅 write 는 generated_at 만 바꿔
  #   git 잡음(auto-commit 밸브)을 만든다 — 상태 노출과 원장 갱신을 분리한다.
  if ("--status-line" %in% args) {
    cat(standalone_track_status_line(root), "\n", sep = "")
    quit(save = "no", status = 0L)
  }
  res  <- build_standalone_track_queue(root, write = !("--no-write" %in% args))
  s <- res$scan
  if ("--json" %in% args) {
    cat(toJSON(list(counts = res$queue$counts, inputs = s$inputs, status = s$status,
                    unconsumed = res$queue$unconsumed),
               auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")
  } else {
    cat("=== standalone track queue (screening tier 라벨 소비 배관) ===\n")
    cat(sprintf("  라벨 발급 %d건 / 추적대상(NONE 제외) %d / STANDALONE_TRACK %d\n",
                s$n_labeled, s$n_tracked, s$n_standalone))
    cat(sprintf("  ★미처분(standalone 판정 0회): %d건\n", s$n_unconsumed))
    cat(sprintf("  소비자 없는 route 보유: %d건 / catalog+quarantine 중복행: %d건 / 역추적 불가 원장행: %d건\n",
                s$n_route_no_consumer, s$n_shadow, s$n_orphan_ledger))
    if (s$n_unconsumed) {
      U <- copy(s$unconsumed); setorder(U, -port_t_nw3, na.last = TRUE)
      print(utils::head(U[, .(strategy_id, proxy_grade, essence_grade, port_t_nw3,
                              oos_retention, calmar, disposition)], 12), row.names = FALSE)
    }
    cat("\n  ", standalone_track_status_line(root), "\n", sep = "")
  }
}
