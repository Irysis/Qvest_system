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

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_mechanism_map","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
