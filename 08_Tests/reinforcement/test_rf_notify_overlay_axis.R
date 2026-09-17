#==============================================================================
# test_rf_notify_overlay_axis.R — 텔레그램 "무엇을 강화했나" 오버레이 축 (v10.2 2026-09-03)
#
# ★실사고: B5 순위 1~4위 문장이 **전부 동일**했다. 셀 설명이 `팩터|비중|유니버스` 3축이라
#   오버레이만 다른 칸을 가를 값이 문장에 없었다 — 하필 그 블록의 처치가 오버레이다.
#   도훈 지적("1위부터 4위까지 텍스트가 모두 같다")으로 드러났고 재현·수리했다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages({ library(jsonlite); library(data.table)
                   source("02_Infrastructure/ops/rf_auto_notify.R") })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

# ── ① 오버레이 없으면 NA — 3축 문장이 그대로 유지된다(하위호환) ─────────────
if (is.na(.rf_ov(NULL)) && is.na(.rf_ov(list(kind = "none"))))
  ok("① 오버레이 없음 → NA (B1~B3 문장은 3축 그대로)") else
  ng("① 오버레이 없는데 축이 붙는다")

# ── ② 서로 다른 arm 은 서로 다른 라벨 — 이게 실사고의 핵심 축 ───────────────
lb <- vapply(list(list(kind="dbeta_tilt", arm_id="dbeta_tilt_rank"),
                  list(kind="dd_brake",  arm_id="dd_brake_q"),
                  list(kind="turbulence",arm_id="turbulence"),
                  list(kind="ml_tail_gate",arm_id="ml_tail_gate")),
            function(o) .rf_ov(o), character(1))
if (length(unique(lb)) == length(lb))
  ok(sprintf("② arm 4종이 서로 다른 라벨 (%s)", paste(substr(lb, 1, 18), collapse = " / "))) else
  ng("② 라벨이 겹친다 — 순위 줄이 같은 문장이 된다", paste(unique(lb), collapse = " | "))

# ── ③ 행동 축이 보이는가 — 총노출 vs 종목별이 구별의 본체다 ─────────────────
if (any(grepl("종목별", lb, fixed = TRUE)) && any(grepl("총노출", lb, fixed = TRUE)))
  ok("③ 행동 축(총노출·종목별)이 문장에 드러난다") else
  ng("③ 행동 축이 안 보인다 — 라벨만 다르고 하는 일이 같아 보인다", paste(lb, collapse = " | "))

# ── ④ 한글 축 라벨 — 영문 약어를 늘리지 않는다(§3.1 bullet 당 2건 미만) ─────
.eng <- function(s) length(regmatches(s, gregexpr("[A-Za-z_]{3,}", s, perl = TRUE))[[1]])
if (all(vapply(lb, .eng, integer(1)) <= 2L))
  ok("④ 항목당 영문 토큰 2건 이하") else
  ng("④ 영문 토큰 과다", paste(lb[vapply(lb, .eng, integer(1)) > 2L], collapse = " | "))

# ── ⑤ 구 arm 도 축이 파생되는가 — 카탈로그에 action/state 가 없는 항목 ──────
#    두 곳에서 축 라벨을 따로 만들면 갈린다. 기전 지도 매핑을 재사용해야 한다.
if (grepl("/", .rf_ov(list(kind = "dd_brake", arm_id = "dd_brake_q")), fixed = TRUE))
  ok("⑤ action/state 없는 구 arm 도 계열 매핑으로 축 파생") else
  ng("⑤ 구 arm 에 축이 안 붙는다 — 메시지가 신·구 arm 에서 다른 모양이 된다")

# ── ⑥ 실측 재현 — 살아 있는 entry 의 B5 설명이 서로 달라야 한다 ─────────────
.led <- tryCatch(fromJSON("06_Registry/reinforce_ledger_l1.json", simplifyVector = FALSE),
                 error = function(e) NULL)
.bid <- NULL
if (!is.null(.led)) for (e in .led$entries) {
  n5 <- sum(vapply(e$attempts %||% list(), function(a)
    startsWith(as.character((a$essence %||% list())$cell_code %||% ""), "B5_"), logical(1)))
  if (n5 >= 2L) { .bid <- e$base_id; break }
}
if (is.null(.bid)) {
  ok("⑥ B5 측정 2건 이상인 entry 없음 — 실측 재현 생략(픽스처 아님)")
} else {
  d <- rf_cell_desc(.bid)
  b5 <- d[grepl("^B5_", names(d))]
  if (length(b5) >= 2L && length(unique(unlist(b5))) == length(b5))
    ok(sprintf("⑥ 실측 %s — B5 %d칸 설명이 전부 다르다", .bid, length(b5))) else
    ng(sprintf("⑥ B5 설명 중복 (%d칸 중 고유 %d)", length(b5), length(unique(unlist(b5)))),
       substr(unlist(b5)[1], 1, 70))
}

# ── ⑦ 스택 서술 (2026-09-17 WP-Z) — 층을 " × " 로 잇고 어느 층도 잃지 않는다 ─────
LA <- list(kind = "ts_mom_gate", arm_id = "ts_mom_sign"); LB <- list(kind = "dbeta_tilt", arm_id = "dbeta_tilt_rank")
LC <- list(kind = "gen_20260903_133452", arm_id = "csd_idio_tilt")
st <- .rf_ov(list(LA, LB, LC))
if (!is.na(st) && length(strsplit(st, " × ", fixed = TRUE)[[1]]) == 3L && all(vapply(c("ts_mom_sign", "dbeta_tilt_rank", "csd_idio_tilt"), function(k) grepl(k, st, fixed = TRUE), logical(1))) &&
    startsWith(st, "오버레이 ") && length(gregexpr("오버레이", st)[[1]]) == 1L)
  ok(sprintf("⑦ 3층 스택 → \"a × b × c\" · 접두 한 번 (%s)", substr(st, 1, 60))) else ng("⑦ 스택 서술", as.character(st))
if (identical(.rf_ov(list(list(LA), list(LB, LC))), st)) ok("⑦ 중첩 리스트도 같은 서술(정본 .ov_layers 평탄화)") else ng("⑦ 중첩 서술", as.character(.rf_ov(list(list(LA), list(LB, LC)))))
if (identical(.rf_ov(list(LA)), .rf_ov(LA))) ok("⑦ 1원소 리스트 = 단수 객체 서술") else ng("⑦ 1원소 리스트")

# ── ⑧ 자기 층만 남기기 — 순위 줄의 구분자는 마지막 층이다 ───────────────────
own <- .rf_ov_own(st, .rf_ov(LA))
if (identical(own, .rf_ov(list(LB, LC)))) ok("⑧ 승계(LA)를 빼면 LB × LC 만 남는다") else ng("⑧ 자기 층", as.character(own))
if (is.na(.rf_ov_own(.rf_ov(LA), .rf_ov(LA)))) ok("⑧ 승계와 같으면 NA(순위 줄에 오버레이 안 붙는다 — 구판과 같다)") else ng("⑧ 동일 스택이 NA 가 아니다")
if (identical(.rf_ov_own(st, ""), st) && identical(.rf_ov_own(st, NA_character_), st)) ok("⑧ 기준이 없으면 전부(접두 포함)") else ng("⑧ 빈 기준", as.character(.rf_ov_own(st, "")))
if (identical(.rf_ov_own(.rf_ov(list(LA, LB)), .rf_ov(list(LA, LC))), .rf_ov(LB))) ok("⑧ 집합 차 — 순서·기준 스택의 다른 층에 무관") else ng("⑧ 집합 차")

# ── ⑨ 격자 밖 코드 — 설계 칸(B5_16..)·상주 칸(B5_31)이 서술에 있다 ───────────
suppressMessages(source("02_Infrastructure/reinforcement/rf_block_design.R"))
TB9 <- sprintf("TEST_NOTIFY_OV_%d", Sys.getpid())
c5 <- rfbd_catalog("B5", ROOT); a5 <- vapply(c5, function(x) x$id, character(1)); k5 <- vapply(c5, function(x) x$kind, character(1))
if (length(a5) >= 3L) {
  dp9 <- rfbd_path(ROOT, TB9, "B5"); dir.create(dirname(dp9), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(block = "B5", cells = list(list(picks = list(a5[1], a5[2]), label = "st", why = "w"),
                                               list(pick = a5[3], label = "one", why = "w"))), auto_unbox = TRUE, null = "null"), dp9)
  d9 <- tryCatch(rf_cell_desc(TB9), error = function(e) list())
  unlink(c(dp9, paste0(dp9, ".bak")), force = TRUE)
  if (all(c("B5_16", "B5_17") %in% names(d9)) && grepl(" × ", d9[["B5_16"]], fixed = TRUE) &&
      grepl(a5[1], d9[["B5_16"]], fixed = TRUE) && grepl(a5[2], d9[["B5_16"]], fixed = TRUE) && grepl(a5[3], d9[["B5_17"]], fixed = TRUE))
    ok("⑨ 설계 칸 B5_16(스택 a × b)·B5_17 이 서술에 있다 — '격자 밖' 아님") else
    ng("⑨ 설계 칸 서술", paste(names(d9)[grepl("^B5_", names(d9))], collapse = ","))
  sc <- rfbd_standing_cells(ROOT)
  if (length(sc)) { cd <- sc[[1]]$code; pk <- sc[[1]]$overlay_pick
    if (!is.null(d9[[cd]]) && grepl(pk, d9[[cd]], fixed = TRUE)) ok(sprintf("⑨ 상주 칸 %s 서술에 %s", cd, pk)) else ng(sprintf("⑨ 상주 칸 %s 서술 없음", cd), as.character(d9[[cd]] %||% "NULL"))
  } else ng("⑨ 격자 standing_cells 부재")
} else cat("  SKIP ⑨ B5 active arm 3종 미만\n")

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_notify_overlay_axis","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
