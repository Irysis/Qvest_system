#==============================================================================
# test_rf_mechanism_map.R — 기전 지도·포화 감지 계약 (v10.2 2026-09-03 · P0-11 판정 한정 2026-09-24)
# 대상: 02_Infrastructure/reinforcement/rf_mechanism_map.R
# ★가장 중요한 축은 ⑦ 축약본 누출이다 — 생성기에 넘어가는 문자열에 성과가 새면
#   "생성기는 성과를 보지 않는다" 가 훅과 무관하게 무너진다.
# ★P0-11(2026-09-24): best_calmar 는 적대검증 판정 칸(pass·fail·below_floor)만 · unverified·deferred 는 따로 센다 ·
#   포화 = n_verdict ≥ k ∧ pass = 0 (k = reinforce_program.json::blocks[B5].mechanism_map.k_saturate). ③·⑨·⑩·⑪ 이 잰다.
#   ⑧ 지도 파일 쓰기는 격리 root 에서 한다(운영 06_Registry 무접촉 — 구판은 배터리마다 운영 지도 파일을 덮어썼다).
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

# ③ 포화 규칙 (P0-11) — **정본 함수** rfm_saturated 를 직접 잰다(인라인 재구현 금지)
#   판정 k 이상 ∧ pass 0 → 포화 · pass 가 하나라도 있으면 계속 판다 · 판정 부족(미검증 다수여도)은 포화 아님
syn <- data.table(n_verdict = c(3L, 5L, 2L, 0L, 3L), n_pass = c(0L, 1L, 0L, 0L, 0L), n_measured = c(3L, 5L, 9L, 9L, 4L))
sat <- rfm_saturated(syn$n_verdict, syn$n_pass, 3L)
if (identical(sat, c(TRUE, FALSE, FALSE, FALSE, TRUE)))
  ok("③ 포화 = 판정 ≥k ∧ pass 0 · pass 1 → 계속 · 판정 2(측정 9) → 미포화 · 미검증만 9 → 미포화") else
  ng("③ 포화 규칙 오작동", paste(sat, collapse = ","))
# 돌연변이 통제 — 구판 규칙(측정 ≥k ∧ 전역 최고 아님)은 '판정 0 · 미검증 9' 칸을 포화로 본다(측정 수로 센다) = 규칙이 갈린다
old_sat <- syn$n_measured >= 3L
if (!identical(old_sat, sat)) ok("③ 돌연변이 통제 — 구판(측정 수) 규칙과 판정이 갈린다(픽스처 판별력)") else ng("③ 픽스처가 구판과 신판을 못 가른다")
# 판정 등급 — verdict 어휘 → 등급
vc <- vapply(list(NULL, list(verdict = "pass"), list(verdict = "fail"),
                  list(verdict = "not_candidate", reason = "calmar_not_above_floor"),
                  list(verdict = "not_candidate", reason = "beyond_max_candidates"),
                  list(verdict = "deferred_refresh_lock"), list(verdict = "error", reason = "regime_mismatch: x"),
                  list(verdict = "zzz_unknown")), rfm_verdict_class, character(1))
if (identical(vc, c("unverified", "pass", "fail", "below_floor", "untested", "deferred", "error", "error")))
  ok("③ 판정 등급 — 표식 없음=unverified · 바닥 미달=below_floor(판정) · 후보 밖=untested · 연기=deferred · 미지=error(판정 아님)") else
  ng("③ 판정 등급", paste(vc, collapse = ","))
if (identical(RFM_JUDGED, c("pass", "fail", "below_floor"))) ok("③ 판정 집합 = pass·fail·below_floor") else ng("③ 판정 집합", paste(RFM_JUDGED, collapse = ","))

# ④ 실제 지도에서 포화 칸이 잡히는가(측정이 쌓인 칸이 하나라도 있어야 의미가 있다)
K <- attr(mp, "k_saturate")
if (sum(mp$n_measured) > 0L) {
  if (any(mp$saturated)) ok(sprintf("④ 포화 칸 %d개 검출 (총 측정 %d · 판정 %d · 미검증 %d · k=%s)",
                                    sum(mp$saturated), sum(mp$n_measured), sum(mp$n_verdict), sum(mp$n_unverified), K)) else
    ok(sprintf("④ 포화 칸 0 — 아직 아무 칸도 판정 %s회에 도달하지 않았거나 pass 가 있다", K))
} else ng("④ 측정이 0건 — 지도가 원장을 못 읽는다")
# 운영 지도 불변식 — best_calmar 가 있는 칸은 판정이 1 이상이어야 한다(미검증 Calmar 가 최고로 적히지 않는다)
if (!nrow(mp[is.finite(best_calmar) & n_verdict == 0L]) &&
    all(mp$n_measured == mp$n_verdict + mp$n_unverified + mp$n_deferred + mp$n_error + mp$n_untested))
  ok("④ 운영 지도 — best_calmar 칸은 전부 판정 ≥1 · 측정 = 판정+미검증+연기+오류+후보밖") else
  ng("④ 운영 지도 불변식 위반")
if (identical(attr(mp, "k_source"), "reinforce_program.json::blocks[B5].mechanism_map.k_saturate") && is.integer(K) && K >= 1L)
  ok(sprintf("④ k = 격자 설정에서(%d)", K)) else ng("④ k 출처", paste(attr(mp, "k_source"), K))

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
write(J(list(schema = "reinforce_program_v1",
             blocks = list(list(id = "B5", axis = "risk_overlay", mechanism_map = list(k_saturate = 2L, note = "fixture"))),
             standing_cells = list(list(code = "B5_31", block = "B5", label = "상주", overlay_pick = "pg2_risk_overlay_v1")))),
      file.path(TMP, "06_Registry/reinforce_program.json"))
LZ <- list(kind = "kz", arm_id = "Z"); LX <- list(kind = "kx", arm_id = "X"); LY <- list(kind = "ky", arm_id = "Y")
LS <- list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1")
sp1 <- file.path(TMP, "specs/s1.json"); write(J(list(overlay = list(LZ, LX, LY), overlay_cell = list(LX, LY))), sp1)   # carry Z + 자기 층 X×Y
sp2 <- file.path(TMP, "specs/s2.json"); write(J(list(overlay = list(LZ, LS))), sp2)                                   # 상주 칸: carry Z + 상주
sp3 <- file.path(TMP, "specs/s3.json"); write(J(list(overlay = list(LZ, LX))), sp3)                                   # overlay_cell 없음 → overlay − carry = X
sp5 <- file.path(TMP, "specs/s5.json"); write(J(list(overlay = list(LZ, LY))), sp5)                                   # 자기 층 Y
ADV <- function(v, reason = NULL) { a <- list(verdict = v); if (!is.null(reason)) a$reason <- reason; a }
LEDGER <- function(extra = list()) write(J(list(entries = list(list(base_id = "T", carry = list(overlay = LZ), attempts = c(list(
  list(n = 1, essence = list(cell_code = "B5_16", calmar = 0.5, spec = sp1), adversary = ADV("fail")),                   # 판정(fail) — X·Y
  list(n = 2, essence = list(cell_code = "B5_31", calmar = 0.9, spec = sp2)),                                              # 상주 — 안 센다
  list(n = 3, essence = list(cell_code = "B5_17", calmar = 0.3, spec = sp3)),                                              # 미검증 — X
  list(n = 4, essence = list(cell_code = "B5_18", calmar = 0.95, spec = sp3), adversary = ADV("deferred_refresh_lock")),  # 연기 — X (★최고 Calmar 지만 미판정)
  list(n = 5, essence = list(cell_code = "B5_19", calmar = 0.2, spec = sp5), adversary = ADV("not_candidate", "calmar_not_above_floor"))), # 바닥 미달 — Y
  extra))))), file.path(TMP, "06_Registry/reinforce_ledger_l1.json"))
LEDGER()
mt <- rf_mechanism_map(TMP)
g <- function(a, s, col, m = mt) m[action == a & state == s][[col]]
if (identical(g("cross_sectional", "drawdown", "n_measured"), 3L) && identical(g("cross_sectional", "trend", "n_measured"), 2L))
  ok("⑨ 스택 칸 [X×Y] 는 X·Y 칸에 각각 1 — 층마다 센다 (X = s1·s3·s3 3 · Y = s1·s5 2)") else
  ng("⑨ 층 단위 집계", sprintf("drawdown=%s trend=%s", g("cross_sectional", "drawdown", "n_measured"), g("cross_sectional", "trend", "n_measured")))
if (identical(g("scalar_exposure", "vol", "n_measured"), 0L)) ok("⑨ carry 층 Z 는 자기 층이 아니라 안 센다") else ng("⑨ carry 층이 세졌다", as.character(g("scalar_exposure", "vol", "n_measured")))
if (identical(g("scalar_exposure", "multivar", "n_measured"), 0L) && identical(g("scalar_exposure", "multivar", "n_arms_catalog"), 0L))
  ok("⑨ 상주 arm(pg2_risk_overlay_v1)은 측정·카탈로그 수에서 제외") else
  ng("⑨ 상주 제외", sprintf("meas=%s cat=%s", g("scalar_exposure", "multivar", "n_measured"), g("scalar_exposure", "multivar", "n_arms_catalog")))
if (identical(g("scalar_exposure", "vol", "n_arms_catalog"), 1L)) ok("⑨ 상주가 아닌 카탈로그 arm 은 그대로 센다") else ng("⑨ 카탈로그 수")
# ★P0-11 — best_calmar 는 판정 칸만: X 의 최고 측정 Calmar 0.95 는 연기(deferred)·0.3 은 미검증 → best = 판정(fail) 칸 0.5
if (isTRUE(abs(g("cross_sectional", "drawdown", "best_calmar") - 0.5) < 1e-9)) ok("⑨ best_calmar = 판정 칸(fail 0.5) — 연기 0.95·미검증 0.3 은 최고로 적지 않는다") else
  ng("⑨ best_calmar 판정 한정", as.character(g("cross_sectional", "drawdown", "best_calmar")))
if (identical(c(g("cross_sectional", "drawdown", "n_verdict"), g("cross_sectional", "drawdown", "n_unverified"), g("cross_sectional", "drawdown", "n_deferred")), c(1L, 1L, 1L)))
  ok("⑨ X 칸: 판정 1 · 미검증 1 · 연기 1 — 따로 센다") else
  ng("⑨ X 칸 판정 계수", paste(g("cross_sectional", "drawdown", "n_verdict"), g("cross_sectional", "drawdown", "n_unverified"), g("cross_sectional", "drawdown", "n_deferred")))
if (identical(g("cross_sectional", "trend", "n_verdict"), 2L) && identical(g("cross_sectional", "trend", "n_below_floor"), 1L) && isTRUE(abs(g("cross_sectional", "trend", "best_calmar") - 0.5) < 1e-9))
  ok("⑨ Y 칸: 판정 2(fail·바닥 미달) · best 0.5") else ng("⑨ Y 칸", paste(g("cross_sectional", "trend", "n_verdict"), g("cross_sectional", "trend", "n_below_floor")))
# 돌연변이 통제 — 구판 best(측정 칸 전부의 max)는 X 에 0.95(미판정)를 적는다 = 픽스처가 판정 한정을 가른다
old_best <- max(c(0.5, 0.3, 0.95))
if (abs(old_best - g("cross_sectional", "drawdown", "best_calmar")) > 0.1) ok("⑨ 돌연변이 통제 — 구판 best(0.95 · 미판정 포함)와 신판(0.5)이 갈린다") else ng("⑨ 판별력 없음")
# 포화(k=2 · 격리 설정): Y 판정 2 ∧ pass 0 → 포화 · X 판정 1 → 미포화(측정은 3 이지만 판정이 부족)
if (isTRUE(g("cross_sectional", "trend", "saturated")) && !isTRUE(g("cross_sectional", "drawdown", "saturated")) && identical(attr(mt, "k_saturate"), 2L))
  ok("⑨ 포화 — Y(판정 2 · pass 0) 포화 · X(측정 3 · 판정 1) 미포화 · k=2 는 격리 설정에서") else
  ng("⑨ 포화", paste(g("cross_sectional", "trend", "saturated"), g("cross_sectional", "drawdown", "saturated"), attr(mt, "k_saturate")))
# 돌연변이 통제 — 구판 포화(측정 ≥k ∧ 전역 최고 아님)로 같은 지도를 읽으면 X(측정 3 · 구판 best 0.95 = 전역 최고)는 미포화,
#   Y(측정 2 · 구판 best 0.5 < 0.95)는 포화 — 이 픽스처에선 우연히 같다. 그래서 X 를 판정 기준으로 가르는 칸을 따로 본다:
#   k=1 이면 신판은 X(판정 1 · pass 0)를 포화로 닫고, 구판은 X 가 미판정 0.95 로 전역 최고를 쥐어 영영 못 닫는다.
m_k1 <- rf_mechanism_map(TMP, k_saturate = 1L)
old_x_sat <- 3L >= 1L & !(0.95 >= 0.95)
if (isTRUE(g("cross_sectional", "drawdown", "saturated", m_k1)) && !old_x_sat)
  ok("⑨ 돌연변이 통제 — k=1: 신판은 X 를 포화로 닫고, 구판은 미판정 0.95(전역 최고)에 붙잡혀 못 닫는다") else ng("⑨ 포화 판별력")
old_aid <- as.character(jsonlite::fromJSON(sp1, simplifyVector = FALSE)$overlay$arm_id %||% "")
if (!nzchar(old_aid)) ok("⑨ 돌연변이 통제 — 구판 s$overlay$arm_id 는 스택에서 빈 문자열 → 측정 소실(픽스처가 결함을 가른다)") else ng("⑨ 픽스처 판별력 없음")
brief_t <- rf_target_brief(TMP)
if (!any(vapply(leak, function(k) grepl(k, tolower(brief_t), fixed = TRUE), logical(1))) && grepl("판정 2", brief_t, fixed = TRUE) && !grepl("pass", brief_t, fixed = TRUE))
  ok("⑨ 격리 root 축약본 — 성과 누출 0 · 판정/미검증 횟수만(pass 수 없음)") else ng("⑨ 축약본", brief_t)

# ⑩ k 는 설정에서 — 키가 없으면 멈춘다(지어내지 않는다) · 명시 인자는 설정보다 앞선다
write(J(list(schema = "reinforce_program_v1", blocks = list(list(id = "B5", axis = "risk_overlay")))), file.path(TMP, "06_Registry/reinforce_program.json"))
e10 <- tryCatch({ rf_mechanism_map(TMP); "no" }, error = function(e) conditionMessage(e))
if (grepl("k_saturate", e10, fixed = TRUE)) ok("⑩ 설정 키 부재 → 멈춤(포화 k 를 지어내지 않는다)") else ng("⑩ 키 부재 통과", e10)
m1 <- rf_mechanism_map(TMP, k_saturate = 1L)
if (isTRUE(g("cross_sectional", "drawdown", "saturated", m1)) && identical(attr(m1, "k_source"), "argument")) ok("⑩ 명시 k=1 → X(판정 1 · pass 0) 포화 · 출처 argument") else ng("⑩ 명시 k")

# ⑪ pass 는 포화를 즉시 푼다(AX-000 — 포화는 한계 판정이 아니다)
LEDGER(list(list(n = 6, essence = list(cell_code = "B5_20", calmar = 0.25, spec = sp5), adversary = ADV("pass"))))
m2 <- rf_mechanism_map(TMP, k_saturate = 2L)
if (!isTRUE(g("cross_sectional", "trend", "saturated", m2)) && identical(g("cross_sectional", "trend", "n_pass", m2), 1L) && identical(g("cross_sectional", "trend", "n_verdict", m2), 3L))
  ok("⑪ Y 에 pass 1 추가 → 판정 3 · pass 1 → 미포화(계속 판다)") else ng("⑪ pass 해제", paste(g("cross_sectional", "trend", "saturated", m2)))

# ⑧ 지도 파일 쓰기 — 격리 root(부작용은 그 root 의 지도 파일 하나뿐 · 운영 06_Registry 무접촉)
write(J(list(schema = "reinforce_program_v1", blocks = list(list(id = "B5", axis = "risk_overlay", mechanism_map = list(k_saturate = 2L))))),
      file.path(TMP, "06_Registry/reinforce_program.json"))
p8 <- rf_write_mechanism_map(TMP)
j8 <- jsonlite::fromJSON(p8, simplifyVector = FALSE)
.np <- function(x) tolower(gsub("\\\\", "/", x))
if (startsWith(.np(p8), .np(TMP)) && identical(j8$schema, "overlay_mechanism_map_v2") &&
    length(j8$cells) == length(RFM_ACTIONS) * length(RFM_STATES) && identical(as.integer(j8$k_saturate), 2L) && nzchar(j8$saturation_rule %||% ""))
  ok("⑧ 지도 파일 기록(격리 root · v2 · k·포화 규칙·best 기준 명시)") else ng("⑧ 지도 파일 기록", as.character(p8))
unlink(TMP, recursive = TRUE, force = TRUE)

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_mechanism_map","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
