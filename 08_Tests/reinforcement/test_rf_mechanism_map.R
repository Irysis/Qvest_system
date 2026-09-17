#==============================================================================
# test_rf_mechanism_map.R — 기전 지도·포화 감지 계약 (v10.2 2026-09-03)
# 대상: 02_Infrastructure/reinforcement/rf_mechanism_map.R
# ★가장 중요한 축은 ⑦ 축약본 누출이다 — 생성기에 넘어가는 문자열에 성과가 새면
#   "생성기는 성과를 보지 않는다" 가 훅과 무관하게 무너진다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source("02_Infrastructure/reinforcement/rf_mechanism_map.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

mp <- rf_mechanism_map()

# ① 격자 전수 — 축이 늘면 지도도 늘어야 한다
if (nrow(mp) == length(RFM_ACTIONS) * length(RFM_STATES))
  ok(sprintf("① 기전 격자 %d칸 = action %d × state %d",
             nrow(mp), length(RFM_ACTIONS), length(RFM_STATES))) else
  ng("① 격자 칸 수 불일치", as.character(nrow(mp)))

# ② ★실측 사실 — 기존 카탈로그의 오버레이는 action 이 전부 스칼라다.
#    계열 라벨 6종이 다양해 보여서 "오버레이는 다 해봤다" 로 오독되던 자리.
cats <- jsonlite::fromJSON("06_Registry/overlay_catalog.json", simplifyVector = FALSE)$arms
axs <- vapply(cats, function(a) rfm_arm_axis(a)$action, character(1))
n_sc <- sum(axs == "scalar_exposure"); n_xs <- sum(axs == "cross_sectional")
if (n_sc >= 10L) ok(sprintf("② 스칼라 action arm %d개 — 라벨 다양성과 행동 다양성은 다르다", n_sc)) else
  ng("② 스칼라 arm 수 이상", as.character(n_sc))
if (n_xs >= 1L) ok(sprintf("② cross_sectional arm %d개 등재", n_xs)) else
  ng("② 횡단면 arm 이 없다 — 행동 축이 여전히 하나다")

# ③ 전역 최고를 쥔 칸은 포화가 아니다 (합성 대조 — 규칙 자체를 잰다)
syn <- data.table(action = c("a", "a", "b"), state = c("s1", "s2", "s3"),
                  n_measured = c(10L, 10L, 1L), best_calmar = c(0.44, 0.30, NA_real_))
gb <- max(syn$best_calmar, na.rm = TRUE)
syn[, sat := n_measured >= 3L & (is.na(best_calmar) | best_calmar < gb)]
if (identical(syn$sat, c(FALSE, TRUE, FALSE)))
  ok("③ 포화 규칙 — 전역 최고 보유 칸은 계속 판다 · 표본 부족 칸은 포화 아님") else
  ng("③ 포화 규칙 오작동", paste(syn$sat, collapse = ","))

# ④ 실제 지도에서 포화 칸이 잡히는가(측정이 쌓인 칸이 하나라도 있어야 의미가 있다)
if (sum(mp$n_measured) > 0L) {
  if (any(mp$saturated)) ok(sprintf("④ 포화 칸 %d개 검출 (총 측정 %d)",
                                    sum(mp$saturated), sum(mp$n_measured))) else
    ok(sprintf("④ 포화 칸 0 — 아직 아무 칸도 %d회에 도달하지 않았다", 3L))
} else ng("④ 측정이 0건 — 지도가 원장을 못 읽는다")

# ⑤ 다음 표적은 미포화 칸이어야 한다
tg <- rf_next_target()
if (!is.null(tg)) {
  hit <- mp[action == tg$action & state == tg$state]
  if (nrow(hit) == 1L && !hit$saturated)
    ok(sprintf("⑤ 표적 = 미포화 칸 (%s / %s · 측정 %d)", tg$action, tg$state, tg$n_measured)) else
    ng("⑤ 포화된 칸을 표적으로 골랐다", paste(tg$action, tg$state))
} else ok("⑤ 전 칸 포화 — 생성기를 부르지 않는다(정상 종료)")

# ⑥ 표적은 가장 덜 탐색된 칸이어야 한다
if (!is.null(tg)) {
  mn <- min(mp[saturated == FALSE]$n_measured)
  if (tg$n_measured == mn) ok("⑥ 가장 덜 탐색된 칸 선택") else
    ng("⑥ 덜 탐색된 칸을 두고 다른 칸을 골랐다", sprintf("%d vs 최소 %d", tg$n_measured, mn))
}

# ⑦ ★축약본 누출 — 생성기에 넘어가는 문자열에 성과 수치가 있으면 안 된다
brief <- rf_target_brief()
leak <- c("calmar", "port_t", "sharpe", "grade", "cagr", "mdd")
hitl <- leak[vapply(leak, function(k) grepl(k, tolower(brief), fixed = TRUE), logical(1))]
if (!length(hitl)) ok("⑦ 축약본에 성과 수치 0 — 생성기는 '무엇이 미측정인가' 만 본다") else
  ng("⑦ 축약본이 성과를 누출한다", paste(hitl, collapse = ","))
# 양성 대조 — 스캐너가 실제로 잡는가
if (any(vapply(leak, function(k) grepl(k, "best_calmar 0.44", fixed = TRUE), logical(1))))
  ok("⑦ 누출 스캐너 양성 대조 발화") else ng("⑦ 누출 스캐너가 죽어 있다")

# ⑧ 지도 파일 쓰기 — 부작용은 이 파일 하나뿐
p <- rf_write_mechanism_map()
if (file.exists(p) && length(jsonlite::fromJSON(p, simplifyVector = FALSE)$cells) == nrow(mp))
  ok("⑧ 지도 파일 기록") else ng("⑧ 지도 파일 기록 실패", as.character(p))

# ⑨ ★스택 칸은 층마다 센다 · 상주 arm 은 안 센다 (2026-09-17 WP-Z) — 격리 root 합성 픽스처
TMP <- file.path(tempdir(), sprintf("rfm_stack_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TMP, "specs"), showWarnings = FALSE)
J <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")
write(J(list(schema = "overlay_catalog_v1", arms = list(
  list(id = "X", kind = "kx", family = "cross_sectional", status = "active", action = "cross_sectional", state = "drawdown"),
  list(id = "Y", kind = "ky", family = "cross_sectional", status = "active", action = "cross_sectional", state = "trend"),
  list(id = "Z", kind = "kz", family = "vol_target",      status = "active", action = "scalar_exposure", state = "vol"),
  list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", family = "book_spec", status = "active", action = "scalar_exposure", state = "multivar")))),
  file.path(TMP, "06_Registry/overlay_catalog.json"))
write(J(list(schema = "reinforce_program_v1", blocks = list(),
             standing_cells = list(list(code = "B5_31", block = "B5", label = "상주", overlay_pick = "pg2_risk_overlay_v1")))),
      file.path(TMP, "06_Registry/reinforce_program.json"))
LZ <- list(kind = "kz", arm_id = "Z"); LX <- list(kind = "kx", arm_id = "X"); LY <- list(kind = "ky", arm_id = "Y")
LS <- list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1")
sp1 <- file.path(TMP, "specs/s1.json"); write(J(list(overlay = list(LZ, LX, LY), overlay_cell = list(LX, LY))), sp1)   # carry Z + 자기 층 X×Y
sp2 <- file.path(TMP, "specs/s2.json"); write(J(list(overlay = list(LZ, LS))), sp2)                                   # 상주 칸: carry Z + 상주
sp3 <- file.path(TMP, "specs/s3.json"); write(J(list(overlay = list(LZ, LX))), sp3)                                   # overlay_cell 없음 → overlay − carry = X
write(J(list(entries = list(list(base_id = "T", carry = list(overlay = LZ), attempts = list(
  list(n = 1, essence = list(cell_code = "B5_16", calmar = 0.5, spec = sp1)),
  list(n = 2, essence = list(cell_code = "B5_31", calmar = 0.9, spec = sp2)),
  list(n = 3, essence = list(cell_code = "B5_17", calmar = 0.3, spec = sp3))))))),
  file.path(TMP, "06_Registry/reinforce_ledger_l1.json"))
mt <- rf_mechanism_map(TMP)
g <- function(a, s, col) mt[action == a & state == s][[col]]
if (identical(g("cross_sectional", "drawdown", "n_measured"), 2L) && identical(g("cross_sectional", "trend", "n_measured"), 1L))
  ok("⑨ 스택 칸 [X×Y] 는 X·Y 칸에 각각 1 — 층마다 센다 (X 는 s3 까지 2)") else
  ng("⑨ 층 단위 집계", sprintf("drawdown=%s trend=%s", g("cross_sectional", "drawdown", "n_measured"), g("cross_sectional", "trend", "n_measured")))
if (identical(g("scalar_exposure", "vol", "n_measured"), 0L)) ok("⑨ carry 층 Z 는 자기 층이 아니라 안 센다") else ng("⑨ carry 층이 세졌다", as.character(g("scalar_exposure", "vol", "n_measured")))
if (identical(g("scalar_exposure", "multivar", "n_measured"), 0L) && identical(g("scalar_exposure", "multivar", "n_arms_catalog"), 0L))
  ok("⑨ 상주 arm(pg2_risk_overlay_v1)은 측정·카탈로그 수에서 제외") else
  ng("⑨ 상주 제외", sprintf("meas=%s cat=%s", g("scalar_exposure", "multivar", "n_measured"), g("scalar_exposure", "multivar", "n_arms_catalog")))
if (identical(g("scalar_exposure", "vol", "n_arms_catalog"), 1L)) ok("⑨ 상주가 아닌 카탈로그 arm 은 그대로 센다") else ng("⑨ 카탈로그 수")
if (isTRUE(abs(g("cross_sectional", "drawdown", "best_calmar") - 0.5) < 1e-9)) ok("⑨ best_calmar 는 그 층이 실린 칸의 essence 값") else ng("⑨ best_calmar")
# 돌연변이 통제 — 구판(s$overlay$arm_id 하나)은 스택(리스트)에서 NULL 을 내 X·Y 를 0 으로 셌다
old_aid <- as.character(jsonlite::fromJSON(sp1, simplifyVector = FALSE)$overlay$arm_id %||% "")
if (!nzchar(old_aid)) ok("⑨ 돌연변이 통제 — 구판 s$overlay$arm_id 는 스택에서 빈 문자열 → 측정 소실(픽스처가 결함을 가른다)") else ng("⑨ 픽스처 판별력 없음")
brief_t <- rf_target_brief(TMP)
if (!any(vapply(leak, function(k) grepl(k, tolower(brief_t), fixed = TRUE), logical(1)))) ok("⑨ 격리 root 축약본도 성과 누출 0") else ng("⑨ 축약본 누출")
unlink(TMP, recursive = TRUE, force = TRUE)

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_mechanism_map","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
