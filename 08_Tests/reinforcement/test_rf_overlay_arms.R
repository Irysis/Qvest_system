#==============================================================================
# test_rf_overlay_arms.R — 오버레이 등록부 소비 검사 (2026-08-30)
#
# 왜: 도훈 "오버레이 방법론을 특정하는건 별로인데". 격자에 방법을 박으면 새 방법이
#   등록돼도 아무도 안 쓰고 같은 다섯 개만 반복 측정한다(weight_catalog 가 이미 진단한 병:
#   "안 붙은 이유는 계약 충돌이 아니라 아무도 한 줄을 안 썼기 때문").
#   그래서 격자는 축만 선언하고 칸은 등록부에서 뽑는다. 이 검사는 그 배선이 살아있는지,
#   그리고 선정 규칙(계열 다양성·제외 회전)이 실제로 작동하는지 양방향으로 본다.
# 부작용 없음.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
# 선정 id → 행동 축 수. 등록부에 없는 id 가 섞이면 NA — unique() 가 NA 를 한 축으로 세어 '2종' 을 부풀리지 않게.
.axes_n <- function(ids, cat) {
  k <- match(ids, cat$id)
  if (!length(k) || anyNA(k)) return(NA_integer_)
  length(unique(cat$action[k]))
}

A <- rf_overlay_catalog(ROOT)
if (is.null(A) || !nrow(A)) {
  ng("등록부 부재", "06_Registry/overlay_catalog.json")
} else {
  ok(sprintf("등록부 %d팔 · %d계열", nrow(A), length(unique(A$family))))
  if (all(nzchar(A$basis))) {
    ok("전 팔이 method(방법) 근거를 갖는다")
  } else ng("근거 없는 팔", paste(A[!nzchar(basis)]$id, collapse = ", "))
}

p <- rf_pick_overlay_arms(5L, root = ROOT)
if (is.null(p) || !length(p$cells)) {
  ng("선정 실패")
} else {
  if (length(unique(p$picked_ids)) == length(p$picked_ids)) {
    ok(sprintf("5팔 선정 · 중복 0 (%s)", paste(p$picked_ids, collapse = ", ")))
  } else ng("선정 중복", paste(p$picked_ids, collapse = ", "))
  # ★다양성 축 = (action, state) 좌표 (2026-09-03). 라벨(family)이 아니다.
  #   실사고: dbeta_tilt_rank 와 csd_idio_tilt 는 state 가 다른데(drawdown vs dispersion)
  #   family 가 같아 '계열당 1개' 규칙에 서로를 밀어냈다 — 라벨 다양성과 행동 다양성은 다르다.
  .pk <- A[match(p$picked_ids, A$id)]
  cel <- paste(.pk$action, .pk$state, sep = "/")
  if (length(unique(cel)) == length(cel)) {
    ok(sprintf("기전 좌표 다양성 강제 (%s)", paste(cel, collapse = ", ")))
  } else ng("좌표 중복 — 같은 (action,state) 를 두 번 잰다", paste(cel, collapse = ", "))
  # 행동 축이 실제로 갈리는가 — 전부 스칼라면 '오버레이를 여러 방향으로 쟀다' 가 거짓이 된다
  if (isTRUE(.axes_n(p$picked_ids, A) >= 2L)) {
    ok(sprintf("행동 축 2종 이상 선정 (%s)", paste(unique(.pk$action), collapse = "+")))
  } else ng("행동 축이 하나뿐 — 라벨만 다르고 하는 일이 같다", paste(unique(.pk$action), collapse = "+"))
  # 구속 축(낙폭)이 선정에서 밀려나지 않는가
  if ("drawdown" %in% .pk$state) {
    ok(sprintf("구속 축(drawdown 상태)이 선정에 남는다 (%s)", paste(unique(.pk$state), collapse = "+")))
  } else ng("구속 축이 선정에서 빠졌다", paste(unique(.pk$state), collapse = "+"))
}

# ★행동 축 다양성 — 합성 등록부로 양방향 (2026-09-17)
#   위 검사는 운영 등록부를 빌린다. 그 빨강(09-07~)은 선정 규칙이 바뀌어서가 아니라 생성 레인이 횡단면 열에
#   5칸째(multivar_channel_tilt)를 넣어서 났다 — 등록부가 다시 바뀌면 같은 규칙이 조용히 초록으로 돌아올 수 있다.
#   그래서 규칙 자체를 합성 등록부 둘로 잰다(축 파생 경로를 우회하지 않도록 기전 지도는 운영 사본을 깐다):
#   ①양성 — 한 행동 축이 칸 수 n 이상을 채우고 더 싸기까지 한 등록부에서도 선정이 두 축을 다 잰다
#   ②음성 대조 — 전 팔이 한 축인 등록부에서 같은 판정기가 실제로 '한 축' 을 낸다(판정기가 죽지 않았다)
.fx_root <- function(tag, arms) {
  r <- file.path(tempdir(), sprintf("rfo_axis_%s_%d", tag, Sys.getpid()))
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure/reinforcement"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/rf_mechanism_map.R"),
            file.path(r, "02_Infrastructure/reinforcement"), overwrite = TRUE)
  write(jsonlite::toJSON(list(schema = "overlay_catalog_v1", arms = arms), auto_unbox = TRUE, pretty = TRUE),
        file.path(r, "06_Registry/overlay_catalog.json"))
  r
}
.fx_arm <- function(action, state, cost)
  list(id = sprintf("fx_%s_%s", action, state), kind = sprintf("fx_%s_%s", action, state), family = "fixture",
       basis = "합성 픽스처", status = "active", est_cost_min = cost, action = action, state = state)
.xs_states <- c("drawdown", "multivar", "dispersion", "holding_level", "ml", "vol")
fx1 <- .fx_root("mixed", c(lapply(.xs_states, function(s) .fx_arm("cross_sectional", s, 5)),
                           list(.fx_arm("scalar_exposure", "drawdown", 9), .fx_arm("scalar_exposure", "trend", 9))))
fx2 <- .fx_root("onecol", lapply(.xs_states, function(s) .fx_arm("cross_sectional", s, 5)))
A1 <- rf_overlay_catalog(fx1); q1 <- rf_pick_overlay_arms(5L, root = fx1)
if (!is.null(q1) && length(q1$picked_ids) == 5L && isTRUE(.axes_n(q1$picked_ids, A1) >= 2L)) {
  ok(sprintf("횡단면 6칸(더 쌈) + 스칼라 2칸 등록부에서도 두 축을 잰다 (%s)",
             paste(A1$action[match(q1$picked_ids, A1$id)], collapse = ",")))
} else ng("한 행동 축이 칸 수를 다 채우면 다른 축이 밀려난다",
          if (is.null(q1)) "선정 NULL" else paste(A1$action[match(q1$picked_ids, A1$id)], collapse = ","))
A2 <- rf_overlay_catalog(fx2); q2 <- rf_pick_overlay_arms(5L, root = fx2)
if (!is.null(q2) && length(q2$picked_ids) == 5L && identical(.axes_n(q2$picked_ids, A2), 1L)) {
  ok("음성 대조 — 전 팔이 한 축인 등록부면 판정기가 한 축을 낸다 · 자리는 비우지 않는다")
} else ng("음성 대조 불발 — 한 축 등록부인데 판정기가 한 축을 못 낸다(죽은 검사)",
          if (is.null(q2)) "선정 NULL" else sprintf("n=%d · axes=%s", length(q2$picked_ids),
                                                     as.character(.axes_n(q2$picked_ids, A2))))
unlink(c(fx1, fx2), recursive = TRUE, force = TRUE)

# 제외 회전 — 이미 측정한 팔은 다시 뽑지 않는다(같은 것을 두 번 재지 않는다)
ex <- p$picked_ids[1:2]
p2 <- rf_pick_overlay_arms(5L, exclude = ex, root = ROOT)
if (!is.null(p2) && !any(ex %in% p2$picked_ids)) {
  ok(sprintf("제외 회전 — %s 빠지고 %s 로 대체", paste(ex, collapse = "/"),
             paste(setdiff(p2$picked_ids, p$picked_ids), collapse = "/")))
} else ng("제외 미작동", "이미 측정한 팔을 또 뽑는다")

# 격자가 등록부를 소비한다고 선언하는가 + 러너가 배치 시점에 다시 뽑는가
g <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
b5 <- Filter(function(b) identical(b$id, "B5"), g$blocks)
if (length(b5) && identical(b5[[1]]$source, "overlay_catalog")) {
  ok("격자 B5 가 등록부 소비를 선언")
} else ng("B5 source 선언 부재", "격자에 박힌 값이 정본으로 오인된다")
rr <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE)
if (any(grepl("rf_pick_overlay_arms", rr, fixed = TRUE))) {
  ok("러너가 배치 시점에 등록부에서 다시 뽑는다")
} else ng("런타임 선정 미배선", "격자 스냅샷이 사실상 고정 목록이 된다")

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_overlay_arms","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
