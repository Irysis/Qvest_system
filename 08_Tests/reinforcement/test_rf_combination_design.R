#!/usr/bin/env Rscript
#==============================================================================
# test_rf_combination_design.R — 결합 레인이 **설계 → 측정 → 게이트** 로 도는가 (2026-09-04)
#
# 배경(실측): 구판 결합은 두 엔진의 rank-Z 평균을 기저로 삼고 base_grade="NA" 로 25칸을
#   곧장 열었다. 그래서 ①결합 기저를 한 번도 재지 않았고 ②단독 논문 레인의
#   base_min_port_t 가드가 결합에서만 발화 불가였으며(entry 5건 × 25칸 = 125칸 무검증)
#   ③쌍 선정 앵커 a_t/b_t 가 축을 안 가려 폐기된 legacy 축 값(2608.27076 의 1.191)이
#   판정 기준을 정하고 있었다.
#   도훈 지시 2026-09-04: 결합은 **LLM 이 두 논문을 읽고 설계**하고, 그 기저를 충실구현
#   1회로 측정한 뒤 base_min_port_t 를 통과해야 강화 25칸을 연다.
#
# 양방향이다 — 정상 경로가 요청을 옳게 발행하는지 + 축·링크·게이트 위반을 실제로 잡는지.
# 부작용 없음: 격리 임시 root 에만 쓴다(공유 원장·요청 파일 무접촉).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

LAUNCH <- file.path(ROOT, "02_Infrastructure/ops/rf_combination_launch.R")

# ── 격리 root 조립 ───────────────────────────────────────────────────────────
TR <- file.path(tempdir(), sprintf("rf_combo_%d", Sys.getpid()))
unlink(TR, recursive = TRUE, force = TRUE)
dir.create(file.path(TR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TR, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TR, ".cache"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "02_Infrastructure/reinforcement"),
          file.path(TR, "02_Infrastructure"), recursive = TRUE)

#' 논문 1편 분량의 가짜 entry — 엔진 파일과 권위 산출물을 실제로 만든다
mk_paper <- function(key, t, axis, url) {
  eng <- file.path(TR, sprintf("engine_%s.R", gsub("[^A-Za-z0-9]", "_", key)))
  writeLines("FACTORS <- NULL", eng)
  art <- file.path(TR, sprintf("art_%s", gsub("[^A-Za-z0-9]", "_", key)))
  dir.create(art, showWarnings = FALSE, recursive = TRUE)
  write(toJSON(list(essence = list(portfolio_alpha_t_nw_lag3 = t),
                    replication = list(source_paper = list(url = url, title = paste("T", key)))),
               auto_unbox = TRUE, null = "null"),
        file.path(art, "authoritative_remeasure.json"))
  list(base_id = paste0("E_", key), base_grade = "C", paper_key = key, status = "exhausted",
       measurement_axis = axis, axis_valid = !identical(axis, "legacy_axis"),
       target_grade = "A", attempts_used = 0L, attempts = list(),
       base_artifacts = art, engine_path = eng)
}
write_ledger <- function(entries) {
  write(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
                    note = "test", current_axis = "n_max_25", entries = entries,
                    combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()),
                    last_updated = ""), auto_unbox = TRUE, null = "null", na = "null"),
        file.path(TR, "06_Registry/reinforce_ledger_l1.json"))
}
write_cfg <- function(on) {
  write(toJSON(list(schema = "t", enabled = TRUE, base_min_port_t = 0,
                    combination = list(enabled = on, note = "test")),
               auto_unbox = TRUE, null = "null"),
        file.path(TR, "06_Registry/reinforce_auto_config.json"))
}
REQ <- file.path(TR, "06_Registry/replication_request.json")
run <- function() {
  unlink(REQ, force = TRUE)
  # ★Windows 에서 system2(env=) 는 무시된다(실측 2026-08-30) — 그대로 두면 자식이 **진짜
  #   root** 로 돌아 공유 요청 파일을 건드릴 뻔한다. 부모 환경에 심고 원복한다.
  # QM_ROOT 로는 격리가 안 된다 — ~/.Renviron 이 R 시작 시 셸 값을 덮어써서, 자식 Rscript 는
  # 진짜 root 를 본다(실측 2026-09-04: 격리 사본을 쓴다고 믿은 검사가 공유 파일을 볼 뻔했다).
  # 런처가 QVEST_RF_ROOT 를 먼저 보므로 그쪽으로 가둔다. Windows 에서 system2(env=) 는
  # 무시되므로 부모 환경에 심고 원복한다.
  .old <- Sys.getenv("QVEST_RF_ROOT", unset = NA)
  Sys.setenv(QVEST_RF_ROOT = TR)
  on.exit({ if (is.na(.old)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = .old) }, add = TRUE)
  out <- suppressWarnings(system2("Rscript", shQuote(LAUNCH), stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}
req <- function() if (file.exists(REQ)) fromJSON(REQ, simplifyVector = FALSE) else NULL

cat("=== A. 정상 경로 — 현행 축 논문 2편이면 설계 요청이 나간다 ===\n")
write_cfg(TRUE)
write_ledger(list(mk_paper("PA", 1.5, "n_max_25", "https://arxiv.org/abs/1111.1111"),
                  mk_paper("PB", 1.2, "n_max_25", "https://arxiv.org/abs/2222.2222")))
o <- run(); r <- req()
if (grepl("combination_design_requested", o, fixed = TRUE)) ok("A1 설계 요청 이벤트 발행") else ng("A1 설계 요청 이벤트", substr(o, 1, 160))
if (!is.null(r)) {
  if (identical(r$status, "pending")) ok("A2 status=pending — 러너가 집어간다") else ng("A2 status", r$status %||% "")
  if (identical(as.character(r$paper$paper_key), "combo:PA+PB")) ok("A3 paper_key = combo:a+b") else ng("A3 paper_key", as.character(r$paper$paper_key %||% ""))
  cb <- r$combo %||% list()
  need <- c("setkey", "k_items", "n_papers", "papers", "item_engines",
            "best_parent_t", "tries_before", "axis", "dilution_test", "count_paper")
  miss <- need[!need %in% names(cb)]
  if (!length(miss)) ok("A4 combo 키 10종 전부 — 설계자가 재료 논문 전부를 읽을 수 있다") else ng("A4 combo 키", paste(miss, collapse = ","))
  if (isFALSE(cb$count_paper)) ok("A5 count_paper=FALSE — 결합은 새 논문 소비가 아니다") else ng("A5 count_paper", as.character(cb$count_paper %||% ""))
  if (nzchar(as.character(cb$dilution_test %||% ""))) ok("A6 희석 판정 기준이 요청에 박힌다(사후 변경 차단)") else ng("A6 희석 판정 기준 부재")
} else ng("A2~A6 요청 파일 자체가 없다")
# ★음성 대조 — 구판이 하던 일(entry 개설)은 이제 여기서 일어나지 않아야 한다
led_after <- fromJSON(file.path(TR, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
if (length(led_after$entries) == 2L) ok("A7 원장에 entry 를 열지 않는다 — 측정 전 개설 금지") else
  ng("A7 원장 무개설", sprintf("entries=%d", length(led_after$entries)))

cat("\n=== A2. N편 결합 — 2편 고정이 아니다 (도훈 2026-09-04 '갯수 제한 두지마') ===\n")
write_ledger(list(mk_paper("PA", 1.5, "n_max_25", "https://arxiv.org/abs/1111.1111"),
                  mk_paper("PB", 1.2, "n_max_25", "https://arxiv.org/abs/2222.2222"),
                  mk_paper("PC", 1.1, "n_max_25", "https://arxiv.org/abs/3333.3333")))
o <- run(); r <- req()
if (!is.null(r)) {
  cb <- r$combo %||% list()
  if (as.integer(cb$n_papers %||% 0L) >= 3L) ok(sprintf("N1 3편 결합이 나온다(n_papers=%s)", cb$n_papers)) else
    ng("N1 3편 결합", sprintf("n_papers=%s — 2편에 갇혀 있다", cb$n_papers %||% "?"))
  if (length(cb$papers %||% list()) == as.integer(cb$n_papers %||% 0L))
    ok("N2 재료 논문 목록이 개수와 일치 — 설계자가 전부 읽는다") else ng("N2 논문 목록 길이 불일치")
  if (identical(as.character(cb$setkey), "PA+PB+PC")) ok("N3 setkey 는 정렬된 구성 논문 집합") else
    ng("N3 setkey", as.character(cb$setkey %||% ""))
} else ng("N1~N3 요청 파일 없음")
if (grepl("max_k=3", o, fixed = TRUE)) ok("N4 열거가 크기 3까지 간다") else ng("N4 열거 크기", substr(o, 1, 200))

cat("\n=== B. 위반 주입 — 폐기 축 값은 앵커가 아니다 ===\n")
write_ledger(list(mk_paper("PA", 1.5, "n_max_25", "https://arxiv.org/abs/1111.1111"),
                  mk_paper("PL", 9.9, "legacy_axis", "https://arxiv.org/abs/3333.3333")))
o <- run()
if (grepl("halt_too_few_papers", o, fixed = TRUE)) ok("B1 legacy 축 논문은 풀에 못 들어간다(t 9.9 여도)") else
  ng("B1 축 필터", substr(o, 1, 200))
if (is.null(req())) ok("B2 요청이 나가지 않는다") else ng("B2 요청 발행됨 — 폐기 축으로 쌍을 지었다")

cat("\n=== C. 위반 주입 — 원문 링크 없는 논문은 쌍을 못 이룬다 ===\n")
write_ledger(list(mk_paper("PA", 1.5, "n_max_25", "https://arxiv.org/abs/1111.1111"),
                  mk_paper("PN", 1.2, "n_max_25", "")))
o <- run()
if (grepl("halt_no_new_pair", o, fixed = TRUE) || grepl("halt_too_few_papers", o, fixed = TRUE))
  ok("C1 링크 없으면 재료 제외 — 설계자가 읽을 수 없다") else
  ng("C1 링크 필수", substr(o, 1, 200))

cat("\n=== D. 게이트 — combination.enabled=false 면 즉시 물러난다 ===\n")
write_cfg(FALSE)
write_ledger(list(mk_paper("PA", 1.5, "n_max_25", "https://arxiv.org/abs/1111.1111"),
                  mk_paper("PB", 1.2, "n_max_25", "https://arxiv.org/abs/2222.2222")))
o <- run()
if (grepl("halt_combination_disabled", o, fixed = TRUE)) ok("D1 게이트 발화") else ng("D1 게이트", substr(o, 1, 160))
if (is.null(req())) ok("D2 정지 중에는 요청도 안 쓴다") else ng("D2 정지 중 요청 발행됨")

cat("\n=== E. 배선 — 세 파일이 결합 판을 실제로 다루는가 ===\n")
# ★주석은 걷어내고 본다 — 이 수리의 사연을 적은 주석이 검사를 발화시키면 안 된다.
code_of <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
au <- code_of("02_Infrastructure/ops/rf_replication_auto.sh")
vf <- code_of("02_Infrastructure/ops/rf_replication_verify.R")
nx <- code_of("02_Infrastructure/ops/reinforce_auto_next_paper.R")
if (grepl("IS_COMBO", au, fixed = TRUE)) ok("E1 러너가 결합으로 분기") else ng("E1 러너 분기")
if (grepl("RP_IS_COMBO", au, fixed = TRUE) && grepl("RP_IS_COMBO", vf, fixed = TRUE))
  ok("E2 결합 표식이 검증기까지 전달") else ng("E2 표식 전달")
if (grepl("COUNT_PAPER", vf, fixed = TRUE)) ok("E3 검증기가 count_paper 를 존중") else ng("E3 count_paper")
if (grepl('"combination"', vf, fixed = TRUE)) ok("E4 fidelity=combination 허용") else ng("E4 fidelity 허용값")
if (grepl("dilution_verdict", vf, fixed = TRUE)) ok("E5 희석 판정을 원장에 남긴다") else ng("E5 희석 판정 기록")
if (grepl("combination_design_requested", nx, fixed = TRUE))
  ok("E6 호출자가 설계 요청을 처리됨으로 본다(다음 논문이 덮지 않는다)") else ng("E6 호출자 인식")
# 설계 원칙이 프롬프트에 실제로 있는가 — 평균 금지가 이 레인의 존재 이유다
pr <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), warn = FALSE), collapse = "\n")
# ★설계 방식은 열려 있어야 한다(도훈 2026-09-04 "LLM이 읽고 판단할테니 제약 안둬도 될 것 같아").
#   구판 프롬프트는 맞물림 4종 메뉴에서 고르게 하고 못 찾으면 ABORT 시켰다 — 그건 리서치를
#   규칙으로 환원한 것이고, 규칙으로 환원될 것이면 LLM 을 부를 이유가 없다.
if (grepl("방식은 네가 정한다", pr, fixed = TRUE)) ok("E7 설계 방식을 에이전트에게 연다") else
  ng("E7 설계 개방 문구 부재")
if (grepl("평균하지 마라", pr, fixed = TRUE)) ng("E8 아직 형태를 금지하고 있다(설계 제약 잔존)") else
  ok("E8 형태 금지 문구 제거 — 실측 기록만 준다")
if (grepl("전부 재료 단독 성적을 못 넘었다", pr, fixed = TRUE))
  ok("E9 실측 기록(5회 희석)은 그대로 전달 — 자료는 감추지 않는다") else ng("E9 실측 기록 부재")

unlink(TR, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_combination_design","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
