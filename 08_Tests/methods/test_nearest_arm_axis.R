#!/usr/bin/env Rscript
# test_nearest_arm_axis.R — 등재 게이트의 **구별성 축** 계약 (2026-08-13 신설)
#
# 왜: 비-퇴화 검사는 기준선(EW·표본공분산·상수1)과만 비교하므로 **기등재 arm 과 사실상
#   동일한 어댑터**를 통과시킨다. 그러면 배터리가 같은 것을 두 이름으로 재고 결과표엔
#   독립 arm 두 개로 보인다. 계기 = TailConformalBand ↔ ConformalKelly (max|Δw| 1.4e-03).
#
# ★이 검사의 본체는 T2 다: **완전 복제본을 주입하면 ★근접이 떠야 한다.**
#   축이 "돌기만 하고 못 잡는" 상태와 "잡는" 상태는 정상 어댑터만 봐서는 구분이 안 된다
#   — 정상 어댑터는 어차피 다 통과하기 때문이다. 위반을 넣어야만 판별된다.
#   (초판이 weight 에만 붙어 있었고, 바로 다음 exposure 등재에서 조용히 안 돌았다.)
set.seed(20260813)
.root <- (function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
})()
setwd(.root)
suppressWarnings(suppressMessages(source("02_Infrastructure/methods/register_method.R")))

PASS <- 0; FAIL <- 0
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1; cat(sprintf("  ok   %s %s\n", n, d)) }
                                 else { FAIL <<- FAIL + 1; cat(sprintf("  FAIL %s %s\n", n, d)) } }
tmp <- file.path(tempdir(), "nearest"); dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
cat("== 등재 게이트 구별성 축 ==\n")

reg <- jsonlite::fromJSON(file.path(.root, REGISTER_METHOD_PATH), simplifyVector = FALSE)
impl <- Filter(function(m) identical(m$verdict, "implemented"), reg$methods %||% list())

for (kind in c("weight", "sigma", "exposure")) {
  same <- Filter(function(m) identical(m$adapter_kind, kind), impl)
  if (length(same) < 1L) { cat(sprintf("  skip[%s] 등재 arm 0건\n", kind)); next }

  # ── T1 정상 어댑터에서 축이 **보고된다** (침묵하지 않는다)
  #    ★"통과"가 아니라 "보고"가 계약이다 — 차단하지 않는 축이라 침묵과 무해가 겉보기 같다.
  src <- same[[1L]]
  v <- suppressWarnings(verify_adapter(file.path(.root, src$adapter), kind, src$method_id))
  got <- v$checks$nearest_arm %||% ""
  chk(sprintf("T1[%s] 정상 어댑터에서 nearest_arm 보고됨", kind),
      nzchar(got) && !grepl("^비교 실패", got), sprintf("→ %s", substr(got, 1, 46)))

  # ── T2 ★위반 주입 — 기등재 어댑터를 그대로 복제해 다른 이름으로 검증
  #    거리 0 이 나와야 하고 ★근접이 떠야 한다. 안 뜨면 축이 사망한 것이다.
  dup <- file.path(tmp, sprintf("dup_%s.R", kind))
  file.copy(file.path(.root, src$adapter), dup, overwrite = TRUE)
  v2 <- suppressWarnings(verify_adapter(dup, kind, "INJECTED_DUPLICATE"))
  got2 <- v2$checks$nearest_arm %||% ""
  chk(sprintf("T2[%s] ★완전 복제본에서 ★근접 발화", kind),
      grepl("근접", got2), sprintf("→ %s", substr(got2, 1, 60)))
  chk(sprintf("T2b[%s] 복제본의 최근접이 원본으로 지목됨", kind),
      grepl(src$method_id, got2, fixed = TRUE), sprintf("(원본 %s)", src$method_id))

  # ── T3 음성 방향 — 등재 arm 전부가 ★근접이면 문턱이 무의미하다(항진명제 방지)
  if (length(same) >= 2L) {
    flags <- vapply(same, function(m) {
      vv <- suppressWarnings(verify_adapter(file.path(.root, m$adapter), kind, m$method_id))
      grepl("근접", vv$checks$nearest_arm %||% "")
    }, logical(1))
    chk(sprintf("T3[%s] 등재 arm 전부가 ★근접은 아님(문턱 판별력)", kind),
        !all(flags), sprintf("근접 %d/%d", sum(flags), length(flags)))
  }
}

# ── T6 ★반대 방향 오경보 — **침묵끼리는 거리가 늘 0** 이다
#    계기: 축을 3 kind 로 넓히자마자 VolRateMatched ↔ HurstRateMatched 가 거리 정확히 0 으로
#    ★근접을 띄웠는데, 중복이 아니라 둘 다 fixture 에서 0/60 발화(상수 1.0)였다.
#    못 잡는 것(초판)과 정반대이지만 같은 병 — **결손을 정상값 모양으로 내려앉힌다.**
mute_fn <- file.path(tmp, "mute_exposure.R")
writeLines(c(
  "exposure_schedule <- function(ctx) {",
  "  pr <- as.data.frame(ctx$periods)",
  "  hs <- as.Date(format(as.Date(pr$decision_date), '%Y-%m-01'))",
  "  list(exposure = data.frame(Date = as.Date(pr$eval_date), exposure = rep(1, nrow(pr))),",
  "       used_cutoff = hs - 1L)",
  "}"), mute_fn)
vm <- suppressWarnings(verify_adapter(mute_fn, "exposure", "INJECTED_MUTE",
                                      allow_fixture_degenerate = "테스트용 비발화 주입"))
got_m <- vm$checks$nearest_arm %||% ""
#    ★"근접이 아니다"만 요구하면 축이 **아예 안 돌아도** 통과한다(빈 문자열 → !grepl = TRUE).
#      초판이 정확히 그렇게 공허 통과했다. 그래서 **말하게** 시킨다 — 긍정 문구를 요구한다.
chk("T6 ★비발화 후보는 '비교 불가'라고 말한다(침묵 통과 금지)",
    nzchar(got_m) && grepl("비교 불가", got_m) && !grepl("근접", got_m),
    sprintf("→ %s", substr(got_m, 1, 52)))

# ── T6b 제외한 건수를 **말한다** (조용한 축소 금지 — 안 말하면 '전부 비교했다'로 읽힌다)
src_e <- Filter(function(m) identical(m$adapter_kind, "exposure"), impl)
live <- NULL
for (m in src_e) {
  vv <- suppressWarnings(verify_adapter(file.path(.root, m$adapter), "exposure", m$method_id))
  g <- vv$checks$nearest_arm %||% ""
  if (nzchar(g) && !grepl("^비교", g)) { live <- g; break }
}
chk("T6b 발화 arm 보고에 비발화 제외 건수가 명시된다",
    !is.null(live) && grepl("비발화 제외", live), sprintf("→ %s", substr(live %||% "(없음)", 1, 56)))

# ── T4 kind 별 문턱·라벨이 전부 정의돼 있다 (초판처럼 한 kind 만 배선되는 것 차단)
chk("T4 세 kind 전부 wrapper/entry/label/문턱 정의",
    all(c("weight","sigma","exposure") %in% names(.ARM_WRAPPER)) &&
    all(c("weight","sigma","exposure") %in% names(.ARM_ENTRY)) &&
    all(c("weight","sigma","exposure") %in% names(.ARM_LABEL)) &&
    all(c("weight","sigma","exposure") %in% names(.ARM_NEAR)))

# ── T5 exposure 산출을 list 로 오독하지 않는다 (wrapper 는 data.table 을 준다)
chk("T5 exposure 값 추출이 data.table 경로를 탄다",
    identical(.arm_value("exposure", data.frame(Date = Sys.Date() + 0:2, exposure = c(1, .7, 1))),
              c(1, .7, 1)))
chk("T5b exposure 열 없으면 NULL (조용한 건너뜀 방지용 신호)",
    is.null(.arm_value("exposure", data.frame(Date = Sys.Date(), x = 1))))

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"nearest_arm_axis","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
