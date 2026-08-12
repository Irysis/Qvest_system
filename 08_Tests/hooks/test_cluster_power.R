## test_cluster_power.R — 군집-상관 검정력 계약의 행동 검사 (위반 주입 포함)
## 대상: 02_Infrastructure/contracts/cluster_power.R
## 왜: 2026-08-10 하루에 계열-간 상관 설계가 4회 미달(FQ-170 P9c/P17a/P19b/P20a).
##     매번 팩터 수로 검정력을 생각했고 묶는 건 계열 수였다. 계약이 그 구분을 강제하는지 잰다.
## ★검사 자체가 양방향이어야 한다: 통과해야 할 것이 통과하고(양성 대조),
##   틀린 입력이 **발화**해야 한다(위반 주입). 둘 다 없으면 검사 사망을 못 본다.
suppressWarnings(suppressMessages({ }))
## ── 자기 위치 우선(금칙④-b: 러너는 self-first) ──────────────────────────────
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash="/", mustWork=FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(.root, "02_Infrastructure/contracts/cluster_power.R"))) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand) && file.exists(file.path(cand, "02_Infrastructure/contracts/cluster_power.R"))) .root <- cand
}
SRC <- file.path(.root, "02_Infrastructure/contracts/cluster_power.R")
if (!file.exists(SRC)) stop(sprintf("계약 파일을 못 찾음: %s (러너 위치 문제이지 계약 실패가 아님)", SRC))
source(SRC)

PASS <- 0L; FAIL <- 0L
.msg1 <- function(x) { x <- as.character(x); if (!length(x)) "(빈 메시지)" else x[1] }
ok  <- function(n, m="") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(.msg1(m))) paste0(" — ", .msg1(m)) else "")) }
bad <- function(n, m="") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(.msg1(m))) paste0(" — ", .msg1(m)) else "")) }
chk <- function(n, cond, m="") if (isTRUE(cond)) ok(n, m) else bad(n, m)

cat("\n[A] 임계 산출의 기본 성질\n")
chk("A1_monotone", all(diff(cp_critical_rho(5:200)) < 0), "n 이 늘면 임계는 단조 감소")
chk("A2_bounds", all(cp_critical_rho(5:200) > 0 & cp_critical_rho(5:200) < 1), "임계는 (0,1)")
chk("A3_small_n_na", is.na(cp_critical_rho(2)), "n<3 은 NA (계산 불가를 값으로 위장하지 않음)")
c19 <- cp_critical_rho(19)
chk("A4_known_point", abs(c19 - 0.456) < 0.01, sprintf("n=19 임계 %.3f ≈ 0.456 (FQ-170 실측치)", c19))

cat("\n[B] 필요 군집 수\n")
r45 <- cp_required_n(0.45)
## ★2026-08-10 정정: 앞선 라운드(P8d)가 근사식 `ceiling(tc^2*(1-r^2)/r^2 + 2)` 로 **23** 을 냈고
##   그 숫자가 메모리·close_round 로 전파됐다. t-기반 임계로 정확히 풀면 **20** 이다
##   (n=19 → 0.4555 > 0.45 · n=20 → 0.4437 <= 0.45). 이 계약이 단일 출처이며 근사식은 폐기.
chk("B1_rho045_needs_20", identical(r45, 20L), sprintf("rho 0.45 → 필요 군집 %s (t-기반 정확해)", r45))
chk("B1b_consistent_with_critical", cp_critical_rho(r45) <= 0.45 && cp_critical_rho(r45 - 1L) > 0.45,
    "필요 n 은 임계 함수와 **정확히** 정합(경계 양쪽 확인) — 근사식 재도입 차단")
chk("B2_bigger_rho_fewer", cp_required_n(0.8) < cp_required_n(0.3), "큰 rho 일수록 적은 군집")
chk("B3_invalid_na", is.na(cp_required_n(0)) && is.na(cp_required_n(1.2)), "범위 밖은 NA")

cat("\n[C] 가부 판정 — 오늘 4회 실패의 재현\n")
## ★2026-08-10 정정: 초판은 계열 19(이름 휴리스틱)로 P19b 를 GO 로 단언했다.
##   선언 필드 기준 계열은 **15** 이고 그때 rho 0.500 은 **NO_GO_CLUSTER_BINDS** 다.
##   휴리스틱 값 19 도 함께 남겨 **분류원이 판정을 뒤집는다**는 사실 자체를 검사한다.
f15 <- cp_feasibility(0.500, n_clusters = 15L, n_obs = 52L)   # 선언 기준
f19 <- cp_feasibility(0.500, n_clusters = 19L, n_obs = 52L)   # 구 휴리스틱
chk("C1_p19b_declared_basis", f15$verdict == "NO_GO_CLUSTER_BINDS",
    sprintf("P19b rho 0.500 · **선언 계열 15** → %s (임계 %.3f)", f15$verdict, f15$critical_rho_at_clusters))
chk("C1b_taxonomy_flips_verdict", f19$verdict == "GO" && f15$verdict != "GO",
    "분류원(휴리스틱 19 vs 선언 15)이 **판정을 뒤집는다** — 계열 정의는 결과에 직결")
f20 <- cp_feasibility(0.410, n_clusters = 15L, n_obs = 43L)   # P20a 실측
chk("C2_p20a_reproduced", f20$verdict == "NO_GO_CLUSTER_BINDS",
    sprintf("P20a rho 0.410 · 군집 15 → %s", f20$verdict))
chk("C3_split_flagged", isTRUE(f20$criteria_split),
    "관측 기준 통과 ∧ 군집 기준 미달을 **별도 판정값으로** 구분")
chk("C4_split_message", grepl("관측 수를 늘려도", f20$message),
    "메시지가 '팩터를 늘려도 안 풀린다' 를 명시")
f_lo <- cp_feasibility(0.10, n_clusters = 19L, n_obs = 52L)
chk("C5_plain_underpowered", f_lo$verdict == "NO_GO_UNDERPOWERED" && !isTRUE(f_lo$criteria_split),
    "양 기준 모두 미달이면 split 아님")

cat("\n[D] 위반 주입 — 틀린 입력이 발화하는가\n")
chk("D1_invalid_target", cp_feasibility(0, 19L)$verdict == "INVALID_TARGET", "rho=0 은 INVALID")
chk("D2_invalid_high", cp_feasibility(1.5, 19L)$verdict == "INVALID_TARGET", "rho>1 은 INVALID")
chk("D3_obs_basis_needs_reason",
    inherits(try(cp_declare(0.41, 15L, 43L, basis = "obs"), silent = TRUE), "try-error"),
    "basis='obs' 를 사유 없이 고르면 **거부**")
d_ok <- try(cp_declare(0.41, 15L, 43L, basis = "obs", reason = "탐색적"), silent = TRUE)
chk("D4_obs_basis_with_reason", !inherits(d_ok, "try-error") && identical(d_ok$declared_basis, "obs"),
    "사유가 있으면 허용되고 basis 가 기록됨")
d_cl <- cp_declare(0.41, 15L, 43L)
chk("D5_default_is_cluster", identical(d_cl$declared_basis, "cluster"),
    "기본 basis 는 **군집** (관측 기준을 기본으로 두면 오늘의 실패가 반복된다)")
chk("D6_threshold_follows_basis",
    abs(d_cl$threshold_used - cp_critical_rho(15)) < 1e-12 &&
    abs(d_ok$threshold_used - cp_critical_rho(43)) < 1e-12,
    "선언한 basis 에 따라 실제 임계가 바뀐다(라벨만 바뀌는 게 아님)")

cat("\n[E] 돌연변이 — 구분을 없애면 검사가 무너지는가 (검사 사망 통제)\n")
mut <- function(nc, no) {           # 군집을 무시하고 관측 수로만 보는 잘못된 구현
  crit <- cp_critical_rho(no); list(verdict = if (0.410 >= crit) "GO" else "NO_GO") }
chk("E1_mutation_flips", mut(15L, 43L)$verdict == "GO" && f20$verdict != "GO",
    "군집을 무시하면 P20a 가 GO 로 뒤집힌다 — C2 의 PASS 는 군집 구분에서 온 것")

cat("\n[F] DB 상수 — 출처는 선언 필드 (드리프트 감시)\n")
chk("F1_db_constant", identical(CP_FACTOR_DB_CLUSTERS, 15L),
    "팩터 DB 계열 수 **15**(선언 category/economic_family 고유값). 이름 휴리스틱 19 는 폐기")
fdb <- cp_feasibility_factor_db(0.45, n_obs = 331L)
chk("F2_db_wrapper", fdb$n_clusters == 15L && fdb$verdict != "GO",
    sprintf("팩터 331종을 다 써도 rho 0.45 는 %s (계열 15)", fdb$verdict))
decl <- cp_declared_cluster_count()
chk("F3_constant_matches_registry", is.na(decl) || identical(as.integer(decl), CP_FACTOR_DB_CLUSTERS),
    sprintf("레지스트리 실측 %s ↔ 상수 %d — **드리프트하면 여기서 잡힌다**(레지스트리 부재 시 NA 로 스킵)",
            ifelse(is.na(decl), "NA(부재)", as.character(decl)), CP_FACTOR_DB_CLUSTERS))
chk("F4_reader_no_zero_disguise", is.na(cp_declared_cluster_count("__no_such_file__.json")),
    "읽기 실패는 **NA** — 0 을 반환해 '계열 없음' 으로 위장하지 않는다")

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"cluster_power","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
