#!/usr/bin/env Rscript
#==============================================================================
# rf_lcode_mechanism_lib.R — 블록 L-code 에 **기전 서술**을 얹는다 (도훈 지시 2026-09-04)
#
# 왜: 강화 레인의 L-code 는 전부 규칙 조립이다(측정표 -> sprintf). 규칙은 **무엇이
#   일어났는지**는 정확히 적지만 **왜**는 못 적는다. 실측 예 — 2026-09-04 B1 14칸에서
#   규칙이 낸 문장은 "최고 B1_4 t 1.454 · A0/B0/C10/F4" 였고, 정작 읽을 값은
#   "방어 계열 셋(vol_low·crisis_beta·beta_relevel)이 나란히 F 인데 같은 위험 축이라도
#   오버레이의 종목별 arm 은 통했다 — 소비 지점이 다르다" 쪽이었다.
#   lean-loop 는 "기전이 특정되는 실패만 적립" 이라 쓰는데 무인 레인엔 특정할 수단이 없어
#   전부 적립하고 있었다(73건).
#
# 경계 (구조로 강제):
#   ① LLM 은 **서술만** 쓴다. 수치·등급·next_probe 는 규칙이 이미 쓴 것을 건드리지 않는다.
#      병합은 R 이 한다 — 에이전트는 L-code 파일에 접근하지 않는다.
#   ② 이 블록 셀 코드를 최소 1개 인용해야 한다 — 일반론은 기전이 아니다.
#   ③ 등급·수치 주장 금지(정규식 차단). 진술이 계약과 충돌하면 그건 서술이 아니라 위조다.
#   ④ 실패는 조용하지 않다 — 기전 없이도 L-code 는 그대로 남는다(규칙 척추는 불변).
#
# 사용:
#   Rscript rf_lcode_mechanism_lib.R materials <base_id> <block_id> <out.txt>
#   Rscript rf_lcode_mechanism_lib.R merge     <base_id> <block_id> <mech.json>
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
setwd(ROOT)
.LOGP <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
dir.create(dirname(.LOGP), recursive = TRUE, showWarnings = FALSE)
.mx_log <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "lcode_mechanism"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = .LOGP, append = TRUE)
  cat(sprintf("[lcode_mech] %s\n", event))
}
.lc_path <- function(base_id, block_id)
  file.path(ROOT, "stage_artifacts/l_code/reinforcement",
            sprintf("l_code_%s_%s.json", base_id, block_id))

# ── materials — 이 블록의 표 + **이 entry 에 쌓인 앞선 교훈** ────────────────
#   도훈 지시: "이번 배치에서 쌓인 교훈들 참고해서 L-code 내용 작성".
#   앞 블록의 lesson_text·next_probes 를 같이 준다 — 기전은 블록 하나가 아니라
#   블록 사이에서 드러나는 일이 많다(오늘 B1 방어계열 F 와 B5 종목별 성공이 그랬다).
lcm_materials <- function(base_id, block_id, out_p) {
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"), local = TRUE))
  S <- rf_notify_table(base_id)
  if (is.null(S) || !nrow(S$tab)) stop("[lcode_mech] 측정표 없음: ", base_id)
  tab <- S$tab
  blk <- tab[grepl(paste0("^", block_id, "_"), code)]
  if (!nrow(blk)) stop("[lcode_mech] 블록 칸 없음: ", block_id)
  E <- S$entry
  dsc <- tryCatch(rf_cell_desc(base_id), error = function(e) list())
  # ★키 공간을 **표와 같은 식**으로 잡는다 (2026-09-05). 구판은 등록 코드
  #   (a$cell_code %||% a$essence$cell_code)로 키를 잡았는데 표(rf_notify_table)의 행 코드는
  #   측정 코드(es$cell_code %||% n%02d)라 두 식이 갈렸다 — 실측 53/499 시도가 불일치였고,
  #   그 중 8건은 실제로 표에 뜨는 칸이었다. 표의 행 코드가 아래 식에서 나오므로 같은 식으로
  #   키를 잡으면 "표에 있는데 여기 없는 코드" 라는 부류 자체가 사라진다(생산자 통합이 아니라
  #   **소비 지점 정렬** — rf_notify_table 의 코드 열을 바꾸면 블록 귀속·승자 판정·LOO 가 같이
  #   움직인다. 그건 계기가 아니라 측정을 옮기는 일이다).
  #   ★main 착지 2026-09-23 — 이 수리는 09-05 worktree(sharp-chebyshev)에만 있었고, 같은 날
  #     커밋 6d0c2fc65 는 메시지로 이 수리를 주장했지만 diff 엔 다음 블록 리졸버만 실렸다.
  .att <- E$attempts %||% list()
  ide <- setNames(vapply(.att, function(a) as.character(a$idea %||% "")[1], character(1)),
                  vapply(.att, function(a)
                    as.character(a$essence$cell_code %||% sprintf("n%02d", a$n))[1], character(1)))
  # ★[[ 로 읽지 않는다 — 이름 있는 **원자 벡터**의 [[ 는 없는 이름에 NULL 이 아니라
  #   `subscript out of bounds` 를 던진다(list 는 NULL 을 돌려준다). %||% 는 NULL 만 받으므로
  #   그 예외를 못 받고 materials 생성이 통째로 죽는다. 그리고 죽으면 rf_lcode_mechanism.sh 가
  #   `materials_failed` 한 라벨로만 적고 exit 0 이라 — 크래시가 "재료 없음" 으로 위장된다.
  #   list·원자벡터 어느 쪽이든 **없는 이름 = 없음(NULL)** 으로 떨어뜨린다.
  #   검사 = 08_Tests/reinforcement/test_rf_materials_cell_lookup.R (양방향 · 위반 주입 포함).
  .look1 <- function(m, cd) {
    if (is.null(m) || !length(m) || !(cd %in% names(m))) return(NULL)
    v <- m[[cd]]
    if (is.null(v) || !length(v) || is.na(v[1])) NULL else as.character(v)[1]
  }
  L <- c(sprintf("## 블록 %s — 측정 %d칸 (수치는 계약 산출물)", block_id, nrow(blk)),
         "code | grade | PORT_t | CAGR | Calmar | MDD | 처치")
  for (i in seq_len(nrow(blk))) {
    cd <- blk$code[i]
    tr <- as.character(.look1(dsc, cd) %||% .look1(ide, cd) %||% "")
    L <- c(L, sprintf("%s | %s | %.3f | %.3f | %.3f | %.3f | %s",
                      cd, blk$grade[i], blk$port_t[i], blk$cagr[i], blk$calmar[i], blk$mdd[i],
                      substr(gsub("\\s+", " ", tr), 1, 110)))
  }
  L <- c(L, "",
         sprintf("## 기저 — %s · 등급 %s", as.character(E$paper_key %||% base_id),
                 as.character(E$base_grade %||% "?")))
  # 이 entry 에 이미 쌓인 블록 L-code (누적 교훈)
  pri <- list()
  for (f in list.files(file.path(ROOT, "stage_artifacts/l_code/reinforcement"),
                       pattern = sprintf("^l_code_%s_B[0-9]+\\.json$", base_id), full.names = TRUE)) {
    b <- sub("^.*_(B[0-9]+)\\.json$", "\\1", basename(f))
    if (identical(b, block_id)) next
    d <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    if (!is.null(d)) pri[[b]] <- d
  }
  if (length(pri)) {
    L <- c(L, "", sprintf("## 이 전략에 이미 쌓인 교훈 (%d블록) — 기전은 블록 사이에서 드러난다", length(pri)))
    for (b in names(pri)) {
      L <- c(L, sprintf("### %s", b),
             sprintf("- 규칙 요약: %s", as.character(pri[[b]]$lesson_text %||% "")))
      if (nzchar(as.character(pri[[b]]$mechanism %||% "")))
        L <- c(L, sprintf("- 기전(앞서 적힌 것): %s", as.character(pri[[b]]$mechanism)))
      np <- pri[[b]]$next_probes %||% character(0)
      if (length(np)) L <- c(L, sprintf("- 다음 탐침(규칙): %s", paste(as.character(np), collapse = " / ")))
      # ★앞 블록이 내놓은 **처방**과 그 결과를 같이 준다 — 처방이 먹혔는지 안 먹혔는지가
      #   다음 처방의 가장 좋은 재료다(생산자만 있고 소비자가 없는 계기를 만들지 않는다).
      .pa <- pri[[b]]$next_block_actions
      if (!is.null(.pa) && length(.pa)) {
        .txt <- if (is.data.frame(.pa)) as.character(.pa$action) else
                vapply(.pa, function(x) as.character(x$action %||% "")[1], character(1))
        L <- c(L, sprintf("- 앞서 내놓은 처방: %s", paste(.txt, collapse = " / ")),
               "  (이 블록 결과가 그 처방을 지지하는가 · 반증하는가를 반드시 언급하라)")
      }
      .av <- pri[[b]]$avoid
      if (!is.null(.av) && length(.av)) L <- c(L, sprintf("- 앞서 '쓰지 말 것': %s",
                                                          paste(as.character(unlist(.av)), collapse = " / ")))
    }
  } else L <- c(L, "", "## 이 전략에 쌓인 앞선 블록 교훈: 없음(첫 블록)")

  # ── ★다음 블록 설계 재료 (도훈 지시 ④ · 2026-09-04) ─────────────────────
  #   처방을 쓰는 자와 설계를 하는 자가 갈리면 어긋나도 아무도 모른다 —
  #   그래서 **같은 산출물**로 만든다. 여기에 다음 블록이 고를 수 있는 것을 준다.
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
  # ★다음 블록은 **리졸버 한 곳**에서만 읽는다 (2026-09-05). 구판은 entry$block_order 가
  #   비었을 때 정적 목록 c("B1","B2","B3","B5","B4") 로 떨어졌는데, 그 부재 창이 정확히
  #   이 코드가 도는 창이다 — 러너는 `used >= 5 && !pending` 인 **다음 배치 직전**에야
  #   순서를 쓰고(reinforce_auto_parallel.R), 블록 경계 재료 생성기는 그보다 먼저 돈다.
  #   실측(RP_20260904_163647_18444_rescued_rulefast_promo2 · B1 완료 시점): block_order 가
  #   비어 정적 목록의 [2] = B2 를 집었고 rfbd_catalog("B2") 를 설계자에게 넘겼다. 그런데
  #   러너가 실제로 간 곳은 B5 다(재도출 순서 B1>B5>B2>B3>B4 · 사유 "CAGR 0.207 >= 0.16
  #   충족 · Calmar 0.364 < 0.64 미달 → 위험 축(B5)을 2번째로"). 설계자는 **가지 않을 블록**의
  #   칸을 짜고 그 설계는 집행되지 않는다 — 조용한 실패다(둘 다 그럴듯한 블록 이름이라 읽어서는
  #   안 잡힌다). rf_next_block 이 원장 → 재도출 → 선언 순서를 한 곳에서 판정한다.
  #   ★블록 id 는 격자(06_Registry/reinforce_program.json)에서 온다 — 여기서 짓지 않는다.
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R"), local = TRUE))
  .prog <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"),
                             simplifyVector = FALSE), error = function(e) NULL)
  .nb0 <- rf_next_block(E, block_id, .prog, root = ROOT)
  .nxt <- as.character(.nb0$id %||% NA_character_)[1]
  # 계기에는 나이를 같이 적는다 — 순서가 원장에 박힌 것인지 규칙이 방금 재도출한 잠정인지가
  #   설계를 읽을 때(그리고 어긋났을 때) 첫 단서다.
  .ordline <- sprintf("(블록 순서 %s · 출처 %s)", paste(.nb0$order, collapse = ">"),
                      switch(as.character(.nb0$src %||% ""),
                             ledger  = "원장 등록",
                             decide  = "규칙 재도출 — 원장 미등록(잠정)",
                             program = "격자 선언 순서",
                             as.character(.nb0$src %||% "?")))
  if (!is.na(.nxt) && .nxt %in% RFBD_BLOCKS) {
    .cat <- rfbd_catalog(.nxt, ROOT)
    ## ★상주 arm 은 목록에서 뺀다 (2026-09-17 · WP-R) — 상주 칸(B5_31)이 매 세대 잰다 · 설계에 넣으면 rfbd_verify 가 기각한다
    if (identical(.nxt, "B5")) { .std <- tryCatch(rfbd_standing_picks(ROOT), error = function(e) character(0))
      .cat <- Filter(function(x) !(as.character(x$id) %in% .std), .cat) }
    L <- c(L, "", sprintf("## 다음 블록 = %s — 여기서 무엇을 시험할지 **네가 정한다**", .nxt),
           .ordline,
           sprintf("고를 수 있는 항목 %d종 (여기 있는 id 만 쓸 수 있다):", length(.cat)))
    for (x in .cat) L <- c(L, sprintf("- %s | %s | %s", x$id, x$label, x$family %||% ""))
    # 앞서 그 블록에 설계가 있었다면 집행 여부도 준다(고리를 닫는 자리)
    .as <- tryCatch(rfbd_action_status(ROOT, base_id, block_id, E$attempts), error = function(e) NULL)
    if (!is.null(.as) && !identical(.as$status, "no_design"))
      L <- c(L, "", sprintf("## 이 블록에 걸었던 설계의 집행 결과: %s — %s", .as$status, .as$detail),
             "  (집행됐는데도 안 먹혔다면 처방이 틀린 것이고, 안 집행됐다면 이유를 봐야 한다)")
  } else if (!is.na(.nxt)) {
    L <- c(L, "", sprintf("## 다음 블록 = %s — 이 블록은 **설계 대상이 아니다**(계약)", .nxt),
           .ordline,
           "  B4 결합은 LOO 가 계약이다. 부분집합을 흔들면 귀속이 깨진다 — 설계를 내지 마라.")
  } else L <- c(L, "", "## 다음 블록: 없음(마지막 블록) — 설계를 내지 마라.", .ordline)
  writeLines(L, out_p, useBytes = TRUE)
  .mx_log("materials_written", base_id = base_id, block = block_id,
          cells = nrow(blk), prior_blocks = length(pri))
  invisible(out_p)
}

# ── merge — 검증 후 R 이 병합한다 (에이전트는 L-code 에 접근하지 않는다) ────
LCM_BANNED <- "(Grade\\s*[ABCF]\\b|등급\\s*[ABCF]\\b|합격|졸업|BOOK\\s*등재)"
lcm_merge <- function(base_id, block_id, mech_p) {
  bad <- function(why) { .mx_log("mechanism_rejected", base_id = base_id, block = block_id, why = why)
                         unlink(mech_p, force = TRUE)
                         ## ★시도 횟수를 남긴다 (2026-09-04) — 백필(rf_mech_backfill)이 같은 블록을 무한히 안 돌게
                         tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), local = TRUE))
                                    rf_mech_note_try(base_id, block_id, ROOT) }, error = function(e) NULL)
                         return(FALSE) }
  if (!file.exists(mech_p) || file.size(mech_p) == 0L) return(bad("기전 파일 부재"))
  M <- tryCatch(fromJSON(mech_p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(M)) return(bad("JSON 파싱 실패"))
  mech <- as.character(M$mechanism %||% "")[1]
  if (is.na(mech) || !nzchar(trimws(mech))) return(bad("mechanism 비어 있음"))
  # ★글자수 제한 없음 (도훈 지시 2026-09-04). 길이는 품질의 대용물이었고 대용물은 늘 틀린다 —
  #   위는 긴 기전을 "보고서" 라며 잘랐고, 아래는 짧지만 정확한 한 줄을 "감상" 으로 몰았다.
  #   품질 게이트는 **구조**가 진다: 이 블록 셀 코드 인용 · 등급 주장 금지 · 처방 존재.
  #   그 셋은 길이와 무관하게 "기전인가" 를 가른다.
  # ★이 블록 셀을 최소 1개 인용해야 한다 — 일반론은 기전이 아니다
  lp <- .lc_path(base_id, block_id)
  if (!file.exists(lp)) return(bad("L-code 파일 부재 — 규칙 척추가 먼저다"))
  if (!grepl(sprintf("%s_[0-9]+", block_id), mech)) return(bad("이 블록 셀 코드 인용 0건 — 일반론"))
  # ★등급·합격 주장 금지 — 판정은 계약이 한다(AX-008)
  if (grepl(LCM_BANNED, mech)) return(bad("등급·합격 주장 포함 — 판정은 계약 소관"))
  # ★처방 없는 기전은 반려한다 — 진단만 쌓이는 것이 지금까지의 문제였다(도훈 2026-09-04).
  #   단 "이 블록만으로는 못 가른다" 도 처방이다: 무엇이 있어야 갈리는지를 적으면 된다.
  .acts0 <- M$next_block_actions %||% list()
  if (!length(.acts0)) return(bad("next_block_actions 0건 — 진단만 있고 처방이 없다"))
  .empty <- Filter(function(x) !nzchar(trimws(as.character(x$action %||% "")[1])), .acts0)
  if (length(.empty) == length(.acts0)) return(bad("처방 action 이 전부 비어 있다"))
  D <- tryCatch(fromJSON(lp, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(D)) return(bad("L-code 파싱 실패"))
  D$mechanism        <- mech
  D$mechanism_by     <- "llm:block_end"
  D$mechanism_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  D$prior_lessons_used <- as.character(unlist(M$prior_lessons_used %||% list()))
  # ★처방 (도훈 지시 2026-09-04) — 진단만으로는 다음 칸이 안 바뀐다.
  #   규칙이 쓴 next_probes 는 격자 순서에서 나오는 일반문("다음 축 B2 로")이라 방향이 없다.
  #   여기는 기전에서 따라 나오는 **집행 가능한 처치**다. 둘을 덮어쓰지 않고 나란히 둔다 —
  #   규칙 척추는 불변이고, 이건 그 위에 얹는 층이다.
  .acts <- M$next_block_actions %||% list()
  if (length(.acts)) {
    D$next_block_actions <- lapply(.acts, function(x) list(
      action = as.character(x$action %||% "")[1],
      why    = as.character(x$why    %||% "")[1],
      expect = as.character(x$expect %||% "")[1]))
    D$next_block_actions_by <- "llm:block_end"
  }
  .av <- as.character(unlist(M$avoid %||% list()))
  if (length(.av)) D$avoid <- .av
  # ★다음 블록 설계 — 검증을 통과해야 저장한다. 실패해도 기전·처방은 남고 그 블록만 규칙 폴백.
  .nd <- M$next_block_design
  if (!is.null(.nd) && length(.nd$cells %||% list())) {
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
    .nb <- as.character(.nd$block %||% "")[1]
    ## ★H6 재개 방지 (2026-09-17 · WP-R): 이 entry 에 B5 시도가 **하나라도** 있으면 기전 경로의 B5 설계는 거부한다 —
    ##   측정을 보고 B5 를 다시 짜는 것은 사후 선택이다. 재설계는 별도 레인(rf_b5_design.sh · source="b5_design_lane")만
    ##   열 수 있고 그 레인은 이 함수를 거치지 않는다(측정된 칸을 앞에 두고 새 칸을 덧붙인다). 기전·처방·avoid 는 그대로 남는다.
    .b5_measured <- identical(.nb, "B5") && isTRUE(tryCatch({
      .led5 <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
      .e5 <- Filter(function(x) identical(x$base_id, base_id), .led5$entries %||% list())
      length(.e5) > 0L && any(vapply(.e5[[1]]$attempts %||% list(), function(a) {
        cc <- as.character(a$cell_code %||% "")[1]
        if (is.na(cc) || !nzchar(cc)) cc <- as.character(a$essence$cell_code %||% "")[1]
        isTRUE(startsWith(cc, "B5_")) }, logical(1))) },
      error = function(e) FALSE))
    if (isTRUE(.b5_measured))
      .mx_log("b5_design_refused_post_measure", base_id = base_id, block = .nb,
              note = "B5 시도가 이미 있다 — 기전 경로의 B5 재설계 거부(재설계 = rf_b5_design 레인 전용 · 사후 선택 차단)")
    .vv <- if (isTRUE(.b5_measured)) "b5_design_refused_post_measure"
           else if (!(.nb %in% RFBD_BLOCKS)) sprintf("설계 대상 블록이 아니다: %s", .nb)
           else rfbd_verify(.nd, .nb, ROOT)
    if (isTRUE(.vv)) {
      dir.create(dirname(rfbd_path(ROOT, base_id, .nb)), recursive = TRUE, showWarnings = FALSE)
      write(toJSON(.nd, auto_unbox = TRUE, pretty = TRUE, null = "null"),
            rfbd_path(ROOT, base_id, .nb))
      D$next_block_design_for <- .nb
      D$next_block_design_n   <- length(.nd$cells)
      .mx_log("block_design_saved", base_id = base_id, block = .nb, cells = length(.nd$cells))
    } else .mx_log("block_design_rejected", base_id = base_id, block = .nb, why = as.character(.vv))
  }
  # ★이 블록에 걸었던 설계의 집행 판정 — 고리를 닫는다(먹혔다고 믿는 상태 차단)
  .as2 <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
                     .E2 <- NULL
                     .led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"),
                                               simplifyVector = FALSE), error = function(e) NULL)
                     if (!is.null(.led)) { .f <- Filter(function(x) identical(x$base_id, base_id), .led$entries)
                                           if (length(.f)) .E2 <- .f[[1]] }
                     if (is.null(.E2)) NULL else rfbd_action_status(ROOT, base_id, block_id, .E2$attempts) },
                   error = function(e) NULL)
  if (!is.null(.as2)) { D$prior_action_status <- .as2$status; D$prior_action_detail <- .as2$detail }
  D$mechanism_confidence <- as.character(M$confidence %||% "")
  write(toJSON(D, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), lp)
  .mx_log("mechanism_merged", base_id = base_id, block = block_id, chars = nchar(mech),
          prior = length(D$prior_lessons_used))
  TRUE
}

if (!interactive()) {
  a <- commandArgs(TRUE)
  if (length(a) >= 4L && identical(a[1], "materials")) lcm_materials(a[2], a[3], a[4])
  else if (length(a) >= 4L && identical(a[1], "merge"))
    quit(status = if (isTRUE(lcm_merge(a[2], a[3], a[4]))) 0L else 1L)
}
