#==============================================================================
# test_standalone_track_queue.R — screen_route 소비 배관의 차단 실효 검사 (합성 픽스처)
#
# 2026-08-02 신설. 대상: 02_Infrastructure/portfolio/standalone_track_queue.R
# 근거: STANDALONE_TRACK 라벨이 3주+ 소비자 0으로 방치된 실사고(Chen-Welch
#       STR_AS_20260709_074129_30048, WT-D20260802_005 적발).
#
# ★이 검사기의 존재 이유 — 배관을 놓는 것만으로는 재발이 안 막힌다:
#   소비 배관이 조용히 죽으면(경로 오설정·스키마 드리프트) 미처분 건수가 0 으로 떨어지고,
#   그 0 이 "밀린 후보 없음"으로 읽힌다. 이 저장소가 반복해 밟은 결함
#   (memory project-empty-means-pass-family / feedback-verify-both-directions-always).
#   → 여기서 재는 것은 "몇 건이냐"가 아니라 **일부러 넣은 위반을 실제로 발화시키는가**,
#     그리고 **깨끗한 입력에서 오발화하지 않는가** 둘 다이다.
#
# 실행: Rscript 08_Tests/portfolio/test_standalone_track_queue.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.t_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
# ★앵커는 PROJ 가 아니라 이 파일 자신 — worktree 에서 돌려도 main 의 대상 파일을
#   검사하는 사고를 막는다 (memory reference-cpd-set-in-hooks-unset-in-bash-tool).
.self_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(dirname(f[1]), winslash = "/", mustWork = FALSE) else getwd()
}
SUT_ROOT <- normalizePath(file.path(.self_dir(), "..", ".."), winslash = "/", mustWork = FALSE)
SUT <- file.path(SUT_ROOT, "02_Infrastructure/portfolio/standalone_track_queue.R")
if (!file.exists(SUT)) { SUT_ROOT <- .t_root(); SUT <- file.path(SUT_ROOT, "02_Infrastructure/portfolio/standalone_track_queue.R") }

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" - ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s - %s\n", n, m)) }
cat("=== standalone track queue: 차단 실효 (합성 픽스처) ===\n")
cat(sprintf("  SUT: %s\n", SUT))

source(SUT, encoding = "UTF-8")

#------------------------------------------------------------------------------
# 픽스처 빌더
#------------------------------------------------------------------------------
mk_root <- function(runs = list(), catalog = list(), quarantine = list(),
                    fq_entries = list(), dispositions = NULL, drop_catalog = FALSE) {
  r <- file.path(tempdir(), sprintf("stq_%d_%d", as.integer(Sys.time()), sample(1e6, 1)))
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "stage_artifacts/alpha_search"), recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(r, "02_Infrastructure/hooks/qvest_hook_router.py"))

  for (run in runs) {
    d <- file.path(r, "stage_artifacts/alpha_search", run$dir)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    if (identical(run$kind %||% "manifest", "manifest")) {
      write_json(list(
        strategy_id = run$id, strategy_name = run$name %||% run$id,
        created_at = run$at %||% "2026-07-01T00:00:00+09:00",
        verdict = list(grade = run$grade %||% "B",
                       screening = list(screen_pass = run$pass %||% TRUE,
                                        screen_route = run$route)),
        authoritative = list(essence_grade = run$ess %||% "C")
      ), file.path(d, "strategy_manifest.json"), auto_unbox = TRUE)
    } else {
      # manifest 없이 hurdle_result 만 있는 런 (strategy = 이름, id 아님)
      write_json(list(
        strategy = run$name %||% run$id, grade = run$grade %||% "B",
        timestamp = run$at %||% "2026-07-01 00:00:00",
        screening = list(screen_pass = run$pass %||% TRUE, screen_route = run$route)
      ), file.path(d, "hurdle_result.json"), auto_unbox = TRUE)
    }
  }
  if (!drop_catalog)
    write_json(list(modules = catalog), file.path(r, "06_Registry/module_catalog.json"),
               auto_unbox = TRUE)
  write_json(list(modules = quarantine), file.path(r, "06_Registry/module_quarantine.json"),
             auto_unbox = TRUE)
  ## ★schema 2.0 (2026-08-23 v9 Lean Loop §3.4(f)) — 픽스처도 정본 형태를 따른다.
  ##   `status` 는 enum {open,claimed,done,parked} 이고 원문 서술은 `status_raw` 다.
  ##   픽스처가 구 형태를 쓰면 "구 판을 통과시키는 검사"가 되어, 소비자가 v2 를 못 읽어도
  ##   초록이 난다(= 검사가 마이그레이션 회귀에 눈이 먼다).
  fq_entries <- lapply(fq_entries, function(e) {
    if (is.null(e$status)) e$status <- "open"
    if (is.null(e$status_raw)) e$status_raw <- "frontier_open"
    e
  })
  write_json(list(schema_version = "2.0", entries = fq_entries),
             file.path(r, "06_Registry/alpha_frontier_queue.json"), auto_unbox = TRUE)
  if (!is.null(dispositions))
    write_json(list(dispositions = dispositions),
               file.path(r, "06_Registry/standalone_track_dispositions.json"), auto_unbox = TRUE)
  r
}
cat_mod <- function(reg = "2026-07-01T00:00:00+09:00", fr = TRUE, port_t = 2.6, grade = "B")
  list(origin_mode = "alpha_search", registered_at = reg, fr_eligible = fr,
       grade = grade, metric_type = "backtested",
       meta = list(authoritative_essence = list(portfolio_alpha_t_nw_lag3 = port_t,
                                                oos_retention = 0.2, calmar = 0.35,
                                                net_sharpe = 0.9)))
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

RUN_ST <- list(dir = "20260701_120000_111", id = "STR_AS_20260701_120000_111",
               name = "픽스처 standalone", route = "STANDALONE_TRACK", grade = "A")

#------------------------------------------------------------------------------
# ① 위반 주입: 라벨 발급 + 소비 원장 미기록 -> 반드시 검출
#------------------------------------------------------------------------------
r1 <- mk_root(runs = list(RUN_ST),
              catalog = setNames(list(cat_mod()), RUN_ST$id))
s1 <- standalone_track_scan(r1)
if (s1$n_unconsumed >= 1L && RUN_ST$id %in% s1$unconsumed$strategy_id) {
  ok("injection_label_without_disposition", sprintf("미처분 %d건 검출", s1$n_unconsumed))
} else {
  bad("injection_label_without_disposition",
      sprintf("검출 실패 (n_unconsumed=%d) — 배관 무력", s1$n_unconsumed))
}
# FR 풀 등재(fr_eligible=TRUE)가 standalone 처분으로 오인되면 안 된다 — 실사고의 핵심.
if (s1$n_unconsumed >= 1L && isTRUE(s1$unconsumed$fr_eligible[1])) {
  ok("fr_pool_is_not_disposition", "fr_eligible=TRUE 여도 미처분으로 남음")
} else {
  bad("fr_pool_is_not_disposition", "FR 풀 등재가 처분으로 흡수됨 — Chen-Welch 재발 경로")
}

#------------------------------------------------------------------------------
# ② 오발화 확인: 처분이 기록되면 backlog 에서 빠진다
#------------------------------------------------------------------------------
r2 <- mk_root(runs = list(RUN_ST), catalog = setNames(list(cat_mod()), RUN_ST$id),
              dispositions = setNames(list(list(verdict = "graduation_reject",
                                                at = "2026-08-02")), RUN_ST$id))
s2 <- standalone_track_scan(r2)
if (s2$n_standalone == 1L && s2$n_unconsumed == 0L) {
  ok("no_false_fire_when_disposed", "처분 기록분은 미처분에서 제외")
} else {
  bad("no_false_fire_when_disposed",
      sprintf("n_standalone=%d n_unconsumed=%d (기대 1/0)", s2$n_standalone, s2$n_unconsumed))
}

# frontier queue 언급도 처분 증거로 인정
r3 <- mk_root(runs = list(RUN_ST), catalog = setNames(list(cat_mod()), RUN_ST$id),
              fq_entries = list(list(id = "FQ-999", title = "x",
                                     hypothesis = paste("후보", RUN_ST$id, "판정 대기"))))
s3 <- standalone_track_scan(r3)
if (s3$n_unconsumed == 0L) ok("fq_mention_counts_as_disposition") else
  bad("fq_mention_counts_as_disposition", sprintf("n_unconsumed=%d (기대 0)", s3$n_unconsumed))

# 토큰 경계: 접미사가 다른 유사 id 는 매칭되면 안 된다
r4 <- mk_root(runs = list(RUN_ST), catalog = setNames(list(cat_mod()), RUN_ST$id),
              fq_entries = list(list(id = "FQ-998",
                                     hypothesis = paste0(RUN_ST$id, "_EXTRA 를 검토"))))
s4 <- standalone_track_scan(r4)
if (s4$n_unconsumed == 1L) {
  ok("token_boundary_no_substring_match", "유사 id 오매칭 없음")
} else {
  bad("token_boundary_no_substring_match",
      sprintf("n_unconsumed=%d (기대 1) — substring 오매칭으로 처분 위장", s4$n_unconsumed))
}

#------------------------------------------------------------------------------
# ③ 위반 주입: 소비자 없는 route / 미지의 신규 route
#------------------------------------------------------------------------------
# 2026-08-20 정정: 구판은 route="FR_RCMA" 를 "소비자 0" 예시로 썼는데, 그 전제는
#   2026-08-16 도훈의 D2 재정의로 폐기됐다(FR_RCMA = "register_module 유도 라벨" →
#   ST_ROUTE_CONSUMERS 에서 consumer=TRUE). 즉 이 축의 FAIL 은 검사기 사망이 아니라
#   **낡은 기대값**이었다. 축의 목적(등록돼 있으나 소비자가 없는 route 를 잡는가)은
#   유효하므로, 실제로 consumer=FALSE 인 TURNOVER_REVIEW 로 예시를 교체한다.
#   ★예시 route 를 여기 박제한 것이 낡음의 원인이므로, 소비자 맵에서 파생해 고른다 —
#     맵이 또 바뀌어도 이 축은 따라간다(전제가 사라지면 skip 이 아니라 FAIL).
.no_consumer_routes <- names(Filter(function(m) identical(m$consumer, FALSE), ST_ROUTE_CONSUMERS))
if (length(.no_consumer_routes) == 0L) {
  bad("injection_route_without_consumer",
      "ST_ROUTE_CONSUMERS 에 consumer=FALSE 인 route 가 하나도 없다 — 이 축의 전제가 사라졌다(통과로 위장 금지)")
} else {
  .inj_route <- .no_consumer_routes[[1]]
  r5 <- mk_root(runs = list(list(dir = "20260701_130000_222", id = "STR_AS_20260701_130000_222",
                                 route = .inj_route, grade = "C")),
                catalog = list())
  s5 <- standalone_track_scan(r5)
  if (s5$n_route_no_consumer >= 1L) {
    ok("injection_route_without_consumer", sprintf("%s 단독 발급 검출(소비자 맵에서 파생)", .inj_route))
  } else {
    bad("injection_route_without_consumer", sprintf("소비자 0 route(%s) 를 못 봄", .inj_route))
  }
}

r6 <- mk_root(runs = list(list(dir = "20260701_140000_333", id = "STR_AS_20260701_140000_333",
                               route = "BRAND_NEW_ROUTE", grade = "C")),
              catalog = list())
s6 <- standalone_track_scan(r6)
if (s6$n_route_no_consumer >= 1L) {
  ok("injection_unknown_new_route", "route_consumer_map 미등록 신규 값 검출")
} else {
  bad("injection_unknown_new_route",
      "신규 route 가 조용히 통과 — 다음 라벨도 같은 방식으로 유실된다")
}

#------------------------------------------------------------------------------
# ④ 위반 주입: catalog + quarantine 중복 잔존행
#------------------------------------------------------------------------------
r7 <- mk_root(runs = list(RUN_ST), catalog = setNames(list(cat_mod()), RUN_ST$id),
              quarantine = setNames(list(list(origin_mode = "alpha_search", grade = "A",
                                              fr_eligible = FALSE,
                                              registered_at = "2026-07-01T00:00:00+09:00")),
                                    RUN_ST$id))
s7 <- standalone_track_scan(r7)
if (s7$n_shadow >= 1L) {
  ok("injection_shadow_quarantine", "재측정 전 proxy 행 잔존 검출")
} else {
  bad("injection_shadow_quarantine", "중복행 미검출 — quarantine 이 최종상태로 오독됨")
}

#------------------------------------------------------------------------------
# ⑤ 위반 주입: 역방향 — 원장에 있는데 라벨 발급 흔적 없음
#------------------------------------------------------------------------------
# run_dir 은 만들되 manifest/hurdle_result 를 쓰지 않는다 = 라벨 경로를 지났으나 라벨 결손
r8 <- mk_root(runs = list(RUN_ST), catalog = list())
dir.create(file.path(r8, "stage_artifacts/alpha_search/20260715_090000_444"),
           recursive = TRUE, showWarnings = FALSE)
write_json(list(modules = setNames(
  list(cat_mod(), cat_mod(reg = "2026-07-15T09:05:00+09:00")),
  c(RUN_ST$id, "STR_AS_20260715_090000_444"))),
  file.path(r8, "06_Registry/module_catalog.json"), auto_unbox = TRUE)
s8 <- standalone_track_scan(r8)
if (s8$n_orphan_ledger >= 1L && "STR_AS_20260715_090000_444" %in% s8$orphan_ledger) {
  ok("injection_reverse_ledger_orphan", "라벨 없는 원장행 검출 (역방향 발화)")
} else {
  bad("injection_reverse_ledger_orphan",
      sprintf("n_orphan=%d — 역방향 검사 사망(단방향만 봄)", s8$n_orphan_ledger))
}
# 오발화 확인: screening tier 도입 이전 등록분은 세지 않는다 (초판이 78건 오검출한 축)
r9 <- mk_root(runs = list(RUN_ST), catalog = list())
dir.create(file.path(r9, "stage_artifacts/alpha_search/20260601_090000_555"),
           recursive = TRUE, showWarnings = FALSE)
write_json(list(modules = setNames(
  list(cat_mod(), cat_mod(reg = "2026-06-01T09:05:00+09:00")),
  c(RUN_ST$id, "STR_AS_20260601_090000_555"))),
  file.path(r9, "06_Registry/module_catalog.json"), auto_unbox = TRUE)
s9 <- standalone_track_scan(r9)
if (s9$n_orphan_ledger == 0L) {
  ok("no_false_fire_pre_screening_era", "라벨 도입 이전 등록분 미계상")
} else {
  bad("no_false_fire_pre_screening_era",
      sprintf("n_orphan=%d — 상시 점등으로 검사기가 무시당함", s9$n_orphan_ledger))
}

#------------------------------------------------------------------------------
# ⑥ ★"빈 결과 = 합격" 금지 — 0 은 PASS 가 아니라 UNREPORTED(stop)
#------------------------------------------------------------------------------
r10 <- mk_root(runs = list(), catalog = list())     # 소스 디렉터리는 있으나 라벨 0건
e10 <- tryCatch({ standalone_track_scan(r10); NULL }, error = function(e) e)
if (!is.null(e10) && grepl("0건|UNREPORTED", conditionMessage(e10))) {
  ok("zero_labels_is_not_pass", "라벨 0건 -> stop (합격 아님)")
} else {
  bad("zero_labels_is_not_pass",
      "라벨 0건이 조용히 통과 — 스캐너 사망이 '누락 없음'으로 위장된다")
}

r11 <- mk_root(runs = list(RUN_ST), drop_catalog = TRUE)
e11 <- tryCatch({ standalone_track_scan(r11); NULL }, error = function(e) e)
if (!is.null(e11) && grepl("부재", conditionMessage(e11))) {
  ok("missing_ledger_is_not_pass", "소비 원장 부재 -> stop")
} else {
  bad("missing_ledger_is_not_pass", "원장 부재가 통과 — 미측정이 정상으로 위장")
}

# 상태라인도 같은 규율: 깨진 루트에서 초록 줄을 뱉으면 안 된다
sl_broken <- standalone_track_status_line(file.path(tempdir(), "stq_nonexistent_root"))
if (grepl("UNREPORTED", sl_broken)) {
  ok("status_line_reports_unreported", "깨진 루트 -> UNREPORTED 표기")
} else {
  bad("status_line_reports_unreported", sprintf("초록 위장: %s", substr(sl_broken, 1, 90)))
}

#------------------------------------------------------------------------------
# ⑦ 오발화 확인: 깨끗한 입력(NONE 라벨만)에서 조용하다
#------------------------------------------------------------------------------
r12 <- mk_root(runs = list(list(dir = "20260701_150000_666", id = "STR_AS_20260701_150000_666",
                                route = "NONE", pass = FALSE, grade = "F")),
               catalog = list())
s12 <- standalone_track_scan(r12)
if (s12$n_unconsumed == 0L && s12$n_route_no_consumer == 0L && s12$n_shadow == 0L) {
  ok("no_false_fire_clean_input", "NONE 라벨만 있을 때 무발화")
} else {
  bad("no_false_fire_clean_input",
      sprintf("unconsumed=%d route=%d shadow=%d (기대 0/0/0)",
              s12$n_unconsumed, s12$n_route_no_consumer, s12$n_shadow))
}

#------------------------------------------------------------------------------
# ⑧ manifest 없는 런의 id 해석 — 이름이 아니라 run_dir 파생 id 로 원장과 붙는가
#------------------------------------------------------------------------------
r13 <- mk_root(runs = list(list(dir = "20260702_100000_777", kind = "hurdle_result",
                                name = "52-Week High Anchor Momentum",
                                route = "STANDALONE_TRACK", grade = "B")),
               catalog = setNames(list(cat_mod(port_t = 2.215)), "STR_AS_20260702_100000_777"))
s13 <- standalone_track_scan(r13)
row13 <- s13$standalone[strategy_id == "STR_AS_20260702_100000_777"]
if (nrow(row13) == 1L && isTRUE(row13$in_catalog[1]) && !is.na(row13$port_t_nw3[1])) {
  ok("orphan_manifest_id_resolution", "run_dir 파생 id 로 원장 실측치 결합")
} else {
  bad("orphan_manifest_id_resolution",
      "전략 '이름'을 id 로 써서 원장 대조 실패 — 미처분이 부풀려진다")
}

#------------------------------------------------------------------------------
# ⑨ 큐 산출물 계약 — 소비자가 읽을 필드가 실제로 있는가
#------------------------------------------------------------------------------
b <- build_standalone_track_queue(r1, write = FALSE)
q <- b$queue
need <- c("schema_version", "producer_ref", "consumer_ref", "route_consumer_map",
          "counts", "unconsumed")
missing <- need[!need %in% names(q)]
if (!length(missing) && q$counts$unconsumed >= 1L && length(q$unconsumed) >= 1L) {
  ok("queue_contract_fields", "필수 필드 + 미처분 항목 적재")
} else {
  bad("queue_contract_fields", sprintf("결손 필드: %s", paste(missing, collapse = ",")))
}
# route_consumer_map 이 생산자와 어긋나면 census 가 낡는다 — 생산자 파일 실독 대조
hg <- file.path(SUT_ROOT, "02_Infrastructure/hurdle_gate.R")
if (file.exists(hg)) {
  L <- readLines(hg, warn = FALSE, encoding = "UTF-8")
  # 발급 블록만 잘라낸다: `screen_route <- ` 부터 그 다음 `verdict <- list(` 직전까지.
  #   행번호 하드코딩은 생산자가 몇 줄만 움직여도 조용히 빗나간다.
  i0 <- grep("^\\s*screen_route\\s*<-", L)[1]
  i1 <- grep("^\\s*verdict\\s*<-\\s*list\\(", L)
  i1 <- i1[i1 > i0][1]
  blk <- L[i0:(i1 - 1L)]
  # ★등급 목록은 route 가 아니다 — `grade %in% c("A","A_NOVEL",...)` 줄을 제외하지 않으면
  #   A_NOVEL/A_DEF/B_DEF 가 "미등록 route" 로 오검출된다(초판 실측).
  blk <- blk[!grepl("grade\\s*%in%", blk)]
  blk <- sub("#.*$", "", blk)   # 주석 안의 예시 라벨도 발급이 아니다
  blk_routes <- gsub('"', "", unique(unlist(
    # perl=TRUE 필수 (r-portability 금칙 ⑥) — 소스 줄에 이모지·한자 등 non-BMP 가
    #   섞이면 TRE 색인이 UTF-16 기준이라 추출 창이 밀려 **그럴듯한 쓰레기**가 나온다.
    #   여기선 route 라벨을 뽑아 소비자 등록 여부를 판정하므로, 밀린 문자열은
    #   "미등록 route" 오검출 또는 진짜 누락의 은폐로 곧장 이어진다.
    regmatches(blk, gregexpr('"[A-Z][A-Z_]{3,}"', blk, perl = TRUE)))))
  unknown <- setdiff(blk_routes, names(ST_ROUTE_CONSUMERS))
  if (length(blk_routes) >= 3L && !length(unknown)) {
    ok("route_map_covers_producer",
       sprintf("생산자 발급 route %d종 전부 등록: %s",
               length(blk_routes), paste(sort(blk_routes), collapse = ",")))
  } else if (length(blk_routes) < 3L) {
    # 추출 0~2건 = 블록 절단 실패. 이 0 을 '이상 없음'으로 읽으면 대조가 죽는다.
    bad("route_map_covers_producer",
        sprintf("발급 블록 추출 실패(route %d종) — 대조 무력(UNREPORTED)", length(blk_routes)))
  } else {
    bad("route_map_covers_producer",
        sprintf("미등록 route: %s — 새 라벨이 소비자 없이 발급된다", paste(unknown, collapse = ",")))
  }
} else {
  bad("route_map_covers_producer", "hurdle_gate.R 미발견 — 대조 불가(미측정)")
}

cat(sprintf("\n=== standalone_track_queue: PASS %d / FAIL %d (총 %d) ===\n",
            PASS, FAIL, PASS + FAIL))
# run_all_hooks.sh 배터리 규약 — 마지막 줄 JSON 요약. 없으면 러너가 파싱 실패로
#   suite 를 통째로 FAIL 계상한다(등재는 됐는데 집계가 안 되는 침묵 결손 자리).
cat(sprintf('{"test":"standalone_track_queue","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
