#!/usr/bin/env Rscript
#==============================================================================
# rf_replication_verify.R — 무인 충실구현 **측정 + 검증 게이트** (2026-08-30)
#
# 호출자 = rf_replication_auto.sh (헤드리스 에이전트가 engine.R 을 쓴 직후)
#
# ★이 파일이 판정한다 — 에이전트 진술은 근거가 아니다(AX-008: 산출은 Forge).
#   에이전트가 만든 건 엔진 하나뿐이고, 아래 전부가 기계 재도출이다:
#     ① run_paper_replication 계약 실행 → authoritative_remeasure.json
#     ② 고정 축 재도출 (n_max ≤ 25 · long-only)
#     ③ PIT 정적 검사 + **구조 검사**(정적 검사의 사각을 안다 — CLEAN 을 증명으로 안 쓴다)
#   하나라도 어기면 원장에 열지 않고 세션 대기로 되돌린다. **조용한 통과 없음.**
#
# 통과 시: rf_open_entry 로 새 강화 entry 개설 → 다음 tick 부터 강화 20칸이 무인 재개.
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# ── 큐 소비 미러 (도훈 2026-09-04) ────────────────────────────────────────────
#   큐 카운터(alpha-pending)는 alpha_search_queue_done.json 만 본다. 강화 레인의 소비는
#   강화 원장에만 남아 두 원장이 안 이어져 있었다 — 오늘 5편을 소비했는데 카운터는 75 그대로.
#   ★판정의 정본은 옮기지 않는다. 이건 표시용 미러이고, 실패해도 리서치를 멈추지 않는다.
.qmirror <- function(pk, why, sid = "") tryCatch({
  if (!isTRUE(COUNT_PAPER)) return(invisible(FALSE))   # 결합은 새 논문 소비가 아니다
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_queue_done.R")))
  okm <- rf_mark_queue_done(pk, why, sid, root = ROOT)
  jlog(if (isTRUE(okm)) "queue_done_mirrored" else "queue_done_mirror_skip",
       paper_key = as.character(pk %||% ""), note = why)
}, error = function(e) jlog("queue_done_mirror_failed", err = conditionMessage(e)))
# ★강화 칸 상한은 원장(reinforce_ledger_l1.json::max_attempts)이 정본이다. 메시지에 숫자를
#   박으면 상한을 바꿔도 안 따라온다 — 2026-08-31 도훈 지적: 상한이 25 인데 알림이 "20칸".
.RF_MAXA <- tryCatch(as.integer(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"),
                                         simplifyVector = FALSE)$max_attempts), error = function(e) NA_integer_)
if (!is.finite(.RF_MAXA)) .RF_MAXA <- 20L
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
WDIR  <- Sys.getenv("RP_WDIR"); URL <- Sys.getenv("RP_URL")
TITLE <- Sys.getenv("RP_TITLE"); PKEY <- Sys.getenv("RP_KEY")
# ★결합 판 (2026-09-04) — 결합은 새 논문 소비가 아니라 기존 두 논문의 재조합이므로
#   3편 주기(count_paper)를 건드리지 않는다. 나머지 경로는 단독 논문과 완전히 같다 —
#   같은 계약이 재고 같은 게이트가 막는다. 그게 이 재사용의 요점이다.
IS_COMBO <- identical(Sys.getenv("RP_IS_COMBO", "0"), "1")
COUNT_PAPER <- !identical(Sys.getenv("RP_COUNT_PAPER", "1"), "0")
REQ   <- file.path(ROOT, "06_Registry/replication_request.json")
# ★성과 요약 kv·차트 = 예전 알파 서칭 포맷(도훈 지시 2026-08-30).
#   ★수치를 재계산하지 않는다 — 계약 산출물에서 읽기만 한다(손계산 금지).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_perf_summary.R")))
## ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그를 오염시켰다)
LOG_P <- Sys.getenv("QVEST_RP_JLOG", file.path(ROOT, ".cache/reinforce_auto_log.jsonl"))

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "replication_verify"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rp_vfy] %s\n", event))
}
fail <- function(why, detail = "") {
  jlog("verify_failed", why = why, detail = substr(detail, 1, 200))
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "failed_needs_session"; d$failure <- why; d$failure_detail <- substr(detail, 1, 400)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
    tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off", title = "[1계층] 무인 충실구현 실패 — 세션 착수 필요",
      lock_scope = sprintf("rf_replication_fail_%s", PKEY %||% "unknown"),
      sections = list(
        list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
             items = c("단계: 1계층 충실구현 — 무인 시도", sprintf("대상: %s", substr(TITLE, 1, 60)),
                       "위치: 검증 게이트에서 차단 — 원장 미개설", sprintf("직전 판정: %s", why))),
        list(type = "summary", emoji = "\U0001F4CC",
             body = sprintf("무인 충실구현이 검증을 통과하지 못했습니다 — 사유 %s", why)),
        list(type = "bullet", emoji = "\U0001F6A9", heading = "주의",
             items = c("조용한 통과를 막았습니다 — 원장에 열지 않았습니다",
                       "세션이 착수하면 그 다음부터 강화는 다시 무인으로 돕니다")),
        list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
             items = c("처분: 자본 배정 없음 · 강화 미개시",
                       "대기 파일: 06_Registry/replication_request.json")))) },
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  quit(status = 1)
}

eng <- file.path(WDIR, "engine.R")
if (!file.exists(eng) || file.info(eng)$size < 200) fail("engine_too_small", eng)

# ── ①-0 의존 패키지 자동 설치 (도훈 지시 2026-08-30 "없으면 바로 깔아쓰게") ──
#   에이전트에는 Bash 권한을 주지 않는다(안전). 대신 여기서 엔진을 스캔해 설치한다.
#   2026-08-30 실측: 에이전트가 reticulate 를 쓴 엔진을 냈고 패키지 부재로 계약이 통째로 죽었다.
#   ★CRAN 만 · 개수 상한 6 · 설치 내역 로그 — 무인이라 조용한 설치를 남기지 않는다.
#   ★정규식을 쓰지 않는다: 이 파일을 스크립트로 고치는 왕복에서 역슬래시가 두 번 뭉개져
#     문자열이 깨졌다. 고정문자열 분해가 이 맥락에서는 더 견고하다.
.extract_pkgs <- function(path) {
  ln <- readLines(path, warn = FALSE)
  ln <- vapply(ln, function(x) { k <- regexpr("#", x, fixed = TRUE)
                                 if (k > 0) substr(x, 1, k - 1) else x }, character(1))
  out <- character(0)
  clean <- function(s) gsub("[^A-Za-z0-9._]", "", s)
  for (kw in c("library(", "require(")) {
    for (x in ln) {
      pos <- gregexpr(kw, x, fixed = TRUE)[[1]]
      if (pos[1] < 0) next
      for (q in pos) {
        rest <- substr(x, q + nchar(kw), nchar(x))
        cut  <- regexpr(")", rest, fixed = TRUE)
        if (cut > 0) rest <- substr(rest, 1, cut - 1)
        rest <- strsplit(rest, ",", fixed = TRUE)[[1]][1]
        out <- c(out, clean(rest))
      }
    }
  }
  for (x in ln) {
    pos <- gregexpr("::", x, fixed = TRUE)[[1]]
    if (pos[1] < 0) next
    for (q in pos) {
      head_s <- substr(x, 1, q - 1)
      tok <- tail(strsplit(head_s, "[^A-Za-z0-9._]")[[1]], 1)
      out <- c(out, clean(tok))
    }
  }
  base_pkgs <- c("base","stats","utils","methods","graphics","grDevices","tools",
                 "parallel","compiler","datasets","")
  unique(setdiff(out, base_pkgs))
}
.has <- function(x) nzchar(system.file(package = x))
.deps <- .extract_pkgs(eng)
.missing <- .deps[!vapply(.deps, .has, logical(1))]
if (length(.missing)) {
  if (length(.missing) > 6L) fail("too_many_missing_packages", paste(.missing, collapse = ", "))
  jlog("installing_packages", pkgs = paste(.missing, collapse = ","))
  ok_inst <- tryCatch({
    install.packages(.missing, repos = "https://cloud.r-project.org", quiet = TRUE)
    still <- .missing[!vapply(.missing, .has, logical(1))]
    if (length(still)) { jlog("install_incomplete", still = paste(still, collapse = ",")); FALSE } else TRUE
  }, error = function(e) { jlog("install_error", err = conditionMessage(e)); FALSE })
  if (!isTRUE(ok_inst)) fail("dependency_install_failed", paste(.missing, collapse = ", "))
  jlog("packages_installed", pkgs = paste(.missing, collapse = ","))
}

# ── ① 계약 실행 ───────────────────────────────────────────────────────────────
Sys.setenv(QVEST_NO_LEDGER_OPEN = "1")   # 개설은 아래에서 검증 후 직접 한다
suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
# ★논문 포트폴리오 사양은 **에이전트가 FIDELITY.json 에 남긴 값**을 쓴다.
#   구판은 이 호출에 portfolio_spec 이 아예 없어서 러너 기본값(top_n_long)이 적용됐고,
#   엔진이 롱숏 PORTFOLIO 를 내도 버려졌다(2026-08-31: 무인 3편 전부 롱온리로 측정).
#   에이전트는 필요한 값을 engine.R 주석에 적어 두기까지 했는데 **읽는 자가 없었다**.
#   비용도 마찬가지 — 논문 명시값(예: 2.2bps)이 있으면 그것으로 병기 판을 만든다.
.fid_p <- file.path(dirname(eng), "FIDELITY.json")
.fid_o <- if (file.exists(.fid_p)) tryCatch(fromJSON(.fid_p, simplifyVector = FALSE),
                                            error = function(e) NULL) else NULL
.pspec <- .fid_o$portfolio_spec %||% NULL
## ★보수적 대체값을 넣으면 병기판이 사라진다 (2026-09-04 수리).
##   구판은 논문 무명시(null/부재)를 0.0015 로 덮어썬는데, 그것은 **등급 기준과
##   같은 수**다 — "논문 기준 성과 병기"(헌법)가 동어반복이 돼 서로를 받치는 두 판으로
##   읽힌다. 러너(run_paper_replication.R:180)의 계약이 이미 `NULL = 무명시 -> gross(0)` 이므로
##   덮지 말고 그 기본값에 맡긴다. 0 은 "gross 로 명시" 이므로 그대로 살린다.
.cmsn  <- suppressWarnings(as.numeric(.fid_o$commission_paper %||% NA))
.cmsn_known <- is.finite(.cmsn)
if (!.cmsn_known) .cmsn <- NULL
if (!is.null(.pspec)) jlog("portfolio_spec_from_fidelity",
                           construction = .pspec$construction %||% "?",
                           commission = if (.cmsn_known) .cmsn else "무명시(gross 병기)")
res <- tryCatch(do.call(run_paper_replication, c(list(
  strategy_name = paste0("RP_AUTO_", gsub("[^A-Za-z0-9]", "", substr(PKEY, 1, 20))),
  strategy_idea = paste0("[무인 충실구현] ", substr(TITLE, 1, 120)),
  factor_engine_path = eng, universe = "K200_KQ150",
  source_paper = list(url = URL, title = TITLE, paper_key = PKEY),
  commission_paper = .cmsn, start_date = "2005-01-01", send_telegram = FALSE),
  if (!is.null(.pspec)) list(portfolio_spec = .pspec) else list())),
  error = function(e) structure(list(err = conditionMessage(e)), class = "rp_err"))
if (inherits(res, "rp_err")) fail("replication_error", res$err)

ar <- res$authoritative_remeasure_path %||% file.path(res$out_dir %||% "", "authoritative_remeasure.json")
if (!file.exists(ar)) {
  cand <- list.files(file.path(ROOT, "stage_artifacts/replication"),
                     pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
  if (length(cand)) ar <- cand[which.max(file.mtime(cand))]
}
if (!file.exists(ar)) fail("no_authoritative_remeasure", "계약 미경유 = 미측정")
AR <- fromJSON(ar, simplifyVector = TRUE); es <- AR$essence

# ── ② 고정 축 재도출 ──────────────────────────────────────────────────────────
viol <- character(0)
nm <- suppressWarnings(as.integer(AR$n_max %||% es$n_max %||% NA))
if (is.finite(nm) && nm > 25L) viol <- c(viol, sprintf("n_max %d > 25", nm))
if (isTRUE(AR$has_short %||% es$has_short)) viol <- c(viol, "has_short=TRUE (long-only 위반)")
if (length(viol)) fail("fixed_axis_violation", paste(viol, collapse = "; "))

# ── ③ PIT 구조 검사 (정적 CLEAN 을 증명으로 쓰지 않는다) ─────────────────────
src <- paste(readLines(eng, warn = FALSE), collapse = "\n")
src_nc <- gsub("#[^\n]*", "", src)                       # 주석 제거 후 판정
bad <- character(0)
if (grepl("shift\\s*\\(\\s*[^,]+,\\s*-", src_nc))              bad <- c(bad, "음수 shift(미래 인덱싱)")
if (grepl("lead\\s*\\(", src_nc))                              bad <- c(bad, "lead() 사용")
if (grepl("\\b(cov|cor|mean|sd)\\s*\\([^)]*\\)\\s*$", src_nc) &&
    !grepl("froll|rolling|expanding|by\\s*=", src_nc))          bad <- c(bad, "전 표본 통계 의심")
if (grepl("read_parquet|open_dataset", src_nc) && grepl("factor_db", src_nc))
                                                                bad <- c(bad, "C15 위반(팩터 DB 직접 로드)")
if (grepl("NEGATE_FACTORS|FLIP_SIGN", src_nc))                  bad <- c(bad, "C13 위반(부호 반전)")
if (length(bad)) fail("pit_structural", paste(bad, collapse = "; "))

# ── ③-b 충실도 라벨 (도훈 지시 2026-08-30 — 변형구현 허용, 단 귀속을 구분한다) ──
#   faithful = 논문 그대로 · adapted = 인사이트 이식(기전은 남고 구현이 바뀜).
#   ★라벨이 기록에 안 남으면 구분이 무의미하다 — 원장·요청파일·텔레그램에 전부 흐른다.
.fid <- tryCatch({
  fp <- file.path(WDIR, "FIDELITY.json")
  if (file.exists(fp)) fromJSON(fp, simplifyVector = TRUE) else list(fidelity = "unlabeled")
}, error = function(e) list(fidelity = "unlabeled"))
.fidelity <- as.character(.fid$fidelity %||% "unlabeled")
if (!.fidelity %in% c("faithful", "adapted", "combination", "unlabeled")) .fidelity <- "unlabeled"
# ★결합 판은 라벨이 비어 와도 결합이다 — 요청이 그렇게 말했다(진술보다 요청이 정본).
if (IS_COMBO && identical(.fidelity, "unlabeled")) .fidelity <- "combination"
jlog("fidelity", label = .fidelity, kept = substr(.fid$kept %||% "", 1, 90),
     changed = substr(.fid$changed %||% "", 1, 90))

G <- AR$essence_grade
jlog("verified", grade = G, port_t = es$portfolio_alpha_t_nw_lag3, artifacts = dirname(ar))

# ── ★④ 적대적 충실도 감사 (도훈 지시 2026-09-04) ─────────────────────────────
#   위 3관문은 전부 **산출물**을 본다(계약·고정축·PIT). "논문대로 구현했는가" 만
#   재도출이 없었고, FIDELITY.json 은 에이전트 자신의 진술이었다 — 진술은 증거가 아니다.
#   ★값어치는 A등급 보호보다 **F 판정의 신뢰**에 있다: 아래 base_below_threshold 분기가
#     ledger_consumed 로 논문을 영구 소비하기 때문이다. 구현이 틀려서 F 였다면 그 논문은
#     잘못된 이유로 영영 버려진다. 그래서 감사는 **등급 무관 전건**이고 소비 **앞에** 선다.
#   처분(도훈 선택): misdeclared → 자동 재구현 1회 + 소비 보류. 재구현도 기각되면
#   소비하되 implementation_suspect 꼬리표를 남긴다(무한 재시도도, 조용한 소비도 아니다).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R"), local = TRUE))
.aud_p <- file.path(WDIR, "fidelity_audit.json")
tryCatch(system2("bash", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh")),
                           shQuote(WDIR), shQuote(dirname(ar)), shQuote(URL), shQuote(PKEY %||% "")),
                 wait = TRUE, stdout = TRUE, stderr = TRUE),
         error = function(e) jlog("fidelity_audit_spawn_failed", err = conditionMessage(e)))
.aud <- rf_audit_read(.aud_p)
.rq0 <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
.aud_tries <- as.integer(.rq0$audit_retries %||% 0L)
.disp <- rf_audit_disposition(.aud, retries_done = .aud_tries)
jlog("fidelity_audit_verdict", verdict = .aud$verdict, action = .disp$action,
     undeclared = length(.aud$undeclared_changes %||% list()),
     mismatch = length(.aud$signal_mismatch %||% list()), retries = .aud_tries)

if (identical(.disp$action, "reimplement")) {
  # ★소비 보류 — 원장에 아무것도 열지 않고 요청만 되돌린다. selector 는 원장으로 소비를
  #   판단하므로, 여기서 열지 않으면 같은 논문이 다시 잡힌다(그게 의도다).
  .bk <- file.path(WDIR, sprintf("engine.rejected%d.R", .aud_tries + 1L))
  tryCatch(file.rename(file.path(WDIR, "engine.R"), .bk), error = function(e) NULL)
  d <- .rq0
  d$status <- "pending"
  d$audit_retries <- .aud_tries + 1L
  d$audit_feedback <- .disp$feedback
  d$audit_verdict <- .aud$verdict
  d$audit_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  jlog("fidelity_reimplement_requested", paper_key = PKEY %||% "", grade = G,
       note = "충실도 기각 — 소비 보류. 다음 tick 이 지적사항을 안고 재구현한다")
  tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
    tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
      lock_scope = sprintf("rf_fidelity_%s", PKEY %||% "unknown"),
      title = sprintf("[1계층] 충실도 감사 기각 — 재구현 (측정 등급 %s)", G),
      sections = list(
        list(type = "bullet", emoji = "\U0001F50D", heading = "현재 리서치 상황",
             items = c("단계: 1계층 무인 충실구현 — 적대적 충실도 감사",
                       sprintf("대상: %s", substr(TITLE, 1, 60)),
                       sprintf("판정: %s · 지적 %d건", .aud$verdict,
                               length(.aud$undeclared_changes %||% list()) +
                               length(.aud$signal_mismatch %||% list())),
                       "처분: 소비 보류 + 자동 재구현 1회 — 논문을 잘못된 이유로 버리지 않는다")),
        ## ★summary 는 [20,100]자 헤드라인 계약이고 relaxed 로도 안 풀린다 — 500자 지적을 여기 넣어
        ##   오늘 3/3 유실됐다(13:56·16:16·17:28). 지적은 text 섹션(relaxed 면 길이 면제)으로.
        list(type = "summary", emoji = "\U0001F4CC",
             body = sprintf("충실도 감사 기각 — %s · 지적 %d건 · 자동 재구현 1회",
                            substr(as.character(.aud$verdict %||% "?"), 1, 20),
                            length(.aud$undeclared_changes %||% list()) +
                              length(.aud$signal_mismatch %||% list()))),
        list(type = "text", emoji = "\U0001F4DD", heading = "감사 지적사항",
             body = substr(as.character(.disp$feedback %||% ""), 1, 1500)))) },
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  quit(status = 0)
}
.aud_suspect <- identical(.disp$action, "proceed_suspect")
if (.aud_suspect) jlog("fidelity_suspect_proceed", paper_key = PKEY %||% "",
  note = "재구현도 충실도 기각 — 소비하되 implementation_suspect 로 남긴다")

# ── ★B등급 이상 신호를 팩터 DB 에 무인 등록 (도훈 지시 2026-09-01) ───────────
#   충실구현이 낸 신호가 어디에도 적립되지 않아, B+ 를 받아도 그 논문의 25칸이 끝나면
#   사라졌다 — 다음 논문의 B1 조합 후보가 되지 못했다. 여기가 그 루프를 닫는 자리다.
#   ★게이트·중복판정·되돌리기는 전부 rf_factor_autoregister.R 안에 있고, 실패해도
#     검증을 죽이지 않는다(등급 발행이 이 스크립트의 본업이다).
tryCatch(system2("Rscript",
  c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_factor_autoregister.R")),
    shQuote(dirname(ar)), shQuote(eng %||% ""), shQuote(PKEY %||% "")),
  wait = TRUE, stdout = TRUE, stderr = TRUE),
  error = function(e) jlog("factor_autoregister_failed", err = conditionMessage(e)))

# ── ③-c 기저 품질 문턱 (도훈 지시 2026-08-30 — PORT_t < 0 기준) ─────────────
#   ★왜: 강화 20칸은 기저 신호 **위에** 팩터를 얹는다. 기저 알파가 음수면 그 위에서
#   무엇을 얹어도 20칸이 헛돌 공산이 크다. 어제 JT1993 은 기저 F 였지만 PORT_t 가 0 근처
#   (0.16)였고 거기서 12칸이 C 로 올라왔다. 2026-08-30 Lead-Lag 착안판은 PORT_t -1.559 —
#   "약하다" 가 아니라 "반대로 작동한다" 이고, 그 위에 얹는 건 다른 문제다.
#   ⇒ 음수면 강화를 생략하고 **다음 논문으로 이월**한다. 측정은 이미 남았고 기록도 남는다.
.base_pt <- suppressWarnings(as.numeric(es$portfolio_alpha_t_nw_lag3 %||% NA))
.min_pt  <- suppressWarnings(as.numeric((tryCatch(fromJSON(file.path(ROOT,
              "06_Registry/reinforce_auto_config.json"), simplifyVector = TRUE),
              error = function(e) list())$base_min_port_t) %||% 0))
# ★구제된 기저는 이 문턱을 통과한다 (도훈 지시 2026-09-04).
#   구제의 논지가 "전기간 통계량이 이 전략을 서술하지 못한다" 인데, 바로 그 통계량으로
#   강화를 막으면 앞뒤가 안 맞는다. 실사례 1403.8125: 전기간 PORT_t -0.639 로 여기서
#   park 됐는데, 롤링 36개월 기준 최근 12점 중 83%가 절대문턱을 넘고 현재 CAGR 26.0% ·
#   Calmar 1.32 다. 전기간 MDD 61.1% 는 2012년 2월 사건이고 최근창 MDD 는 19.7% 다.
#   ⇒ 구제된 건은 통과시키되 **경로를 라벨로 남긴다** — 무엇이 왜 들어왔는지 보이게.
#   ★해제가 아니라 예외다: 구제 안 된 음수 알파는 여전히 막힌다(rg_rescue 가 F 에서만,
#     최근 문턱 충족 + 롤링점 하한을 다 만족할 때만 참을 내므로 문이 넓어지지 않는다).
.resc_ok <- isTRUE(AR$recent_regime_rescued)
if (.resc_ok) jlog("base_gate_bypass_rescued", port_t = .base_pt,
                   grade_base = as.character(AR$grade_base %||% ""), grade = G,
                   note = "recent_regime 구제 — 전기간 PORT_t 문턱을 우회한다")
if (is.finite(.base_pt) && .base_pt < .min_pt && !.resc_ok) {
  jlog("base_below_threshold", port_t = .base_pt, threshold = .min_pt,
       note = "기저 알파가 음수 — 강화 생략하고 다음 논문으로 이월(측정·기록은 남는다)")
  # ★원장에 **소비 기록**을 남긴다. 안 남기면 rf_next_paper_pick 이 원장 paper_key 로
  #   소비를 판단하므로 같은 논문을 영원히 다시 집는다 — 8분마다 LLM 에이전트가 재실행된다.
  #   실사고 2026-08-31: 2608.23944 를 19:14~20:34 사이 **5회** 반복 구현했다.
  #   요청 파일(status=done_no_reinforce)만 닫는 것으로는 부족하다. selector 는 그 파일을 안 본다.
  tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
    .bid_sk <- sprintf("RP_%s_skipped_base", format(Sys.time(), "%Y%m%d_%H%M%S"))
    rf_open_entry(1L, .bid_sk, base_grade = G, paper_key = PKEY %||% "", paper_id = "",
                  base_artifacts = dirname(ar), engine_path = eng,
                  count_paper = COUNT_PAPER, root = ROOT)
    rf_park_entry(1L, .bid_sk, sprintf(
      "skipped_base_quality — 기저 PORT_t %.3f < %.2f. 음수 알파 위의 강화는 헛돈다(측정·기록은 보존). 논문 소비 처리.",
      .base_pt, .min_pt), root = ROOT)
    jlog("ledger_consumed", base_id = .bid_sk, paper_key = PKEY %||% "",
         note = "소비 기록 — selector 가 이 논문을 다시 집지 않는다")
    .qmirror(PKEY, sprintf("skipped_base_quality (PORT_t %.3f)", .base_pt), .bid_sk)
  }, error = function(e) jlog("ledger_consume_failed", err = conditionMessage(e),
       note = "★소비 기록 실패 — 같은 논문이 재선택될 수 있다"))
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "done_no_reinforce"; d$grade <- G; d$fidelity <- .fidelity
  d$base_port_t <- .base_pt; d$artifacts <- dirname(ar)
  d$skip_reason <- sprintf("기저 PORT_t %.3f < %.2f — 음수 알파 위의 강화는 헛돈다", .base_pt, .min_pt)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
    tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
      lock_scope = sprintf("rf_replication_%s", PKEY %||% "unknown"),
      title = sprintf("[1계층] 무인 %s 완료 — 등급 %s · 강화 생략",
                      if (identical(.fidelity, "adapted")) "변형구현(착안)" else "충실구현", G),
      sections = list(
        list(type = "bullet", emoji = "🎯", heading = "현재 리서치 상황",
             items = c("단계: 1계층 충실구현 — 무인 완주",
                       substr(sprintf("대상: %s", TITLE), 1, 78),
                       sprintf("위치: 검증 통과 · 기저 다중검정 t값 %.3f", .base_pt),
                       sprintf("직전 판정: 등급 %s · 충실도 %s", G,
                               if (identical(.fidelity, "adapted")) "착안(변형)" else "충실"))),
        list(type = "summary", emoji = "📌",
             body = sprintf("기저 알파가 음수라 강화 %d칸을 생략하고 다음 논문으로 넘어갑니다", .RF_MAXA)),
        list(type = "kv", emoji = "📊", heading = "성과 요약",
             kv = rf_perf_kv(dirname(ar))),
        list(type = "bullet", emoji = "🚩", heading = "주의/약점",
             items = rf_perf_weak(dirname(ar))),
        list(type = "bullet", emoji = "💡", heading = "판단",
             items = c("음수 알파는 약한 게 아니라 반대로 작동한다는 뜻입니다",
                       sprintf("그 위에 팩터를 얹으면 %d칸이 헛돌 공산이 큽니다", .RF_MAXA),
                       "측정 결과는 기록에 남아 다음 라운드가 참조합니다")),
        list(type = "bullet", emoji = "➡️", heading = "다음",
             items = c("처분: 자본 배정 없음 · 강화 미개시",
                       "큐 다음 논문으로 이월합니다"))),
                         charts = rf_perf_charts(dirname(ar)))
    # ★[팩터 분석] — FF3/FF5/Carhart 알파 + Fama-MacBeth. 산출물이 있을 때만 보낸다.
    #   정본 = telegram_notify.R::tg_pass_analysis (구 알파 서칭과 동일 함수 — 재구현 아님).
    if (file.exists(file.path(dirname(ar), "analysis_multifactor.csv")) ||
        file.exists(file.path(dirname(ar), "analysis_fmb_summary.csv")))
      tryCatch(tg_pass_analysis(substr(TITLE, 1, 60), dirname(ar)),
               error = function(e) jlog("factor_tg_failed", err = conditionMessage(e)))
    else jlog("factor_analysis_absent", dir = dirname(ar),
              note = "FF/FMB 산출물 없음 — FACTORS 부재이거나 분석 실패") },
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), wait = TRUE)
  quit(status = 0)
}

# ── ④ 원장 개설 → 강화 무인 재개 ─────────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
BID <- paste0(AR$strategy_id %||% paste0("RP_AUTO_", format(Sys.time(), "%Y%m%d_%H%M%S")), "_rulefast")
# ★귀속을 base_id 에 새긴다 — adapted 를 충실구현으로 오독하는 경로를 원천 차단
BID <- if (identical(.fidelity, "adapted")) paste0(sub("_rulefast$", "", BID), "_adapted_rulefast") else BID
BID <- if (identical(.fidelity, "combination")) paste0(sub("_rulefast$", "", BID), "_combo_rulefast") else BID
tryCatch(rf_open_entry(1L, BID, base_grade = G, paper_key = PKEY,
                       base_artifacts = dirname(ar), engine_path = eng,
                       count_paper = COUNT_PAPER, root = ROOT),
         error = function(e) fail("ledger_open_failed", conditionMessage(e)))
.qmirror(PKEY, sprintf("강화 entry 개설 (기저 %s)", G), BID)

# ★결합이면 원장 entry 에 앵커와 **희석 판정**을 남긴다 (2026-09-04).
#   구판은 이 판정을 "첫 셀(B1_1)이 부모를 넘는가" 로 대리했는데, B1_1 은 순수 기저가
#   아니라 기저+팩터1종(w0=0.5)이라 재려는 것과 재는 도구가 달랐다. 이제 기저를 직접 잰다.
#   ★차단하지 않고 기록만 한다 — 격자는 기저 **위에** 쌓으므로 부모보다 낮은 기저에서도
#   강화가 뒤집을 수 있다(도훈 선택, 2026-09-04). 차단은 base_min_port_t 하나뿐이다.
if (IS_COMBO) tryCatch({
  .rq <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  .cb <- .rq$combo %||% list()
  .pt <- suppressWarnings(as.numeric(es$portfolio_alpha_t_nw_lag3 %||% NA))
  # ★N편 재편(2026-09-04)으로 앵커 키가 a_t/b_t -> best_parent_t/parent_t 로 바뀌었다.
  #   구 키를 읽어 max(NA, na.rm=TRUE) = -Inf 가 나왔고 판정이 unmeasured 로 죽었다(11:39 실측).
  #   구 키 폴백을 남긴다 — 이전 요청 형식으로 열린 건이 아직 흐를 수 있다.
  .parents <- suppressWarnings(as.numeric(unlist(.cb$parent_t %||% list())))
  .best_parent <- suppressWarnings(as.numeric(.cb$best_parent_t %||% NA))
  if (!is.finite(.best_parent) && length(.parents) && any(is.finite(.parents)))
    .best_parent <- max(.parents[is.finite(.parents)])
  if (!is.finite(.best_parent)) {
    .legacy <- suppressWarnings(as.numeric(c(.cb$a_t %||% NA, .cb$b_t %||% NA)))
    if (any(is.finite(.legacy))) .best_parent <- max(.legacy[is.finite(.legacy)])
  }
  .verdict <- if (!is.finite(.pt) || !is.finite(.best_parent)) "unmeasured"
              else if (.pt > .best_parent) "additive" else "dilution"
  .o <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  .k <- which(vapply(.o$entries, function(z) identical(z$base_id, BID), logical(1)))[1]
  if (!is.na(.k)) {
    .o$entries[[.k]]$combo <- c(.cb, list(
      base_port_t = if (is.finite(.pt)) round(.pt, 4) else NULL,
      best_parent_t = if (is.finite(.best_parent)) round(.best_parent, 4) else NULL,
      dilution_verdict = .verdict,
      note = "LLM 결합 설계 → 충실구현 1회로 기저 측정 → base_min_port_t 통과분만 25칸(2026-09-04 도훈). 희석 판정은 기록 전용 — 차단하지 않는다."))
    .txt <- toJSON(.o, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
    stopifnot(length(fromJSON(.txt, simplifyVector = FALSE)$entries) == length(.o$entries))
    writeLines(.txt, file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), useBytes = TRUE)
    jlog("combo_verdict", base_id = BID, base_port_t = .pt,
         best_parent_t = .best_parent, verdict = .verdict)
  }
}, error = function(e) jlog("combo_meta_failed", err = conditionMessage(e)))

d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
d$status <- "done"; d$base_id <- BID; d$grade <- G; d$artifacts <- dirname(ar)
d$fidelity <- .fidelity; d$fidelity_detail <- .fid
d$fidelity_audit <- .aud; d$implementation_suspect <- isTRUE(.aud_suspect)
d$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)

tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
    lock_scope = sprintf("rf_replication_%s", PKEY %||% "unknown"),
    title = sprintf("[1계층] 무인 %s 완료 — 등급 %s · 강화 개시",
                    if (identical(.fidelity, "adapted")) "변형구현(착안)" else "충실구현", G),
    sections = list(
      list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
           items = c("단계: 1계층 충실구현 — 무인 완주",
                     sprintf("대상: %s", substr(TITLE, 1, 58)),
                     sprintf("위치: 검증 4관문 통과 · 강화 원장 개설 %s", substr(BID, 1, 30)),
                     sprintf("직전 판정: 기저 등급 %s · 충실도 %s", G,
                             if (identical(.fidelity, "adapted")) "착안(변형)" else "충실"))),
      list(type = "summary", emoji = "\U0001F4CC",
           body = sprintf("충실구현 기저 등급 %s — 강화 %d칸이 다음 주기부터 무인으로 돕니다", G, .RF_MAXA)),
      list(type = "kv", emoji = "📊", heading = "성과 요약",
           kv = rf_perf_kv(dirname(ar))),
      list(type = "bullet", emoji = "\U0001F6A9", heading = "주의",
           items = c(if (identical(.fidelity, "adapted"))
                       substr(sprintf("착안 구현 — 남긴 기전: %s", .fid$kept %||% "?"), 1, 78)
                     else "논문 그대로 구현 — 유니버스만 치환",
                     "등급은 계약 산출값만 인용 — 에이전트 진술은 근거가 아닙니다",
                     "고정 축·PIT 는 기계가 산출물에서 재도출해 확인했습니다")),
      list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
           items = c("처분: 자본 배정 없음 — 강화 프로세스로 진입",
                     sprintf("강화 %d칸은 블록당 5개씩 병렬로 무인 실행됩니다", .RF_MAXA)))),
                       charts = rf_perf_charts(dirname(ar)))
    # ★[팩터 분석] — FF3/FF5/Carhart 알파 + Fama-MacBeth. 산출물이 있을 때만 보낸다.
    #   정본 = telegram_notify.R::tg_pass_analysis (구 알파 서칭과 동일 함수 — 재구현 아님).
    if (file.exists(file.path(dirname(ar), "analysis_multifactor.csv")) ||
        file.exists(file.path(dirname(ar), "analysis_fmb_summary.csv")))
      tryCatch(tg_pass_analysis(substr(TITLE, 1, 60), dirname(ar)),
               error = function(e) jlog("factor_tg_failed", err = conditionMessage(e)))
    else jlog("factor_analysis_absent", dir = dirname(ar),
              note = "FF/FMB 산출물 없음 — FACTORS 부재이거나 분석 실패") },
  error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
quit(status = 0)
