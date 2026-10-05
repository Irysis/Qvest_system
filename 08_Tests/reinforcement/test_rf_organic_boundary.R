#!/usr/bin/env Rscript
#==============================================================================
# test_rf_organic_boundary.R — 유기체 헌법 경계 봉쇄 행렬 (O0a · 2026-09-25 · 설계 organic_design_final §5 · §3 G1·G2·G5·G6)
#
#   A [양성] 허용 경로 쓰기(state 포인터 · jsonl append · 하위 디렉터리 json) → 성공 + actions 1행 · 원자 쓰기 잔재 0
#   B write-ahead — 선행 시행 레코드 없는 효과 → rfo_k2 거부(쓰기 0)
#   V 위반 7 — fixed_axes 포인터 · tier_graduation · a_eligibility_gate · 카탈로그 status · n > n_cap · 격리 arm 부활 · 보호 파일 직접 쓰기
#     → 전부 rfo_k1 · 대상·state md5 불변
#   C OneDrive 충돌 사본 → K1 · 스냅샷(denylist md5/stat) 전후 대조가 보호 파일 변경을 잡는다(양성) · 무변경 = same
#   S 정적 봉쇄 — 실제 유기체 파일 3종(writer·adapter·guard 역할) 통과 · 위반 주입 픽스처(G2 토큰 · 쓰기 · 권한 밖 writer) 적발 ·
#     우회 3종(문자열 결합 경로 · do.call("rf_load") · eval(parse(text=))) 적발
#   R 롤백 — 한 결정의 state 쓰기 2건을 역순 복원(대상 포인터 md5 = 적용 전) · 유기체 밖 대상 롤백 → K1
#   H 사람 명령(ops/rf_organic_cmd.R · 자식 Rscript) — 킬 해제(킬 뒤 도훈 결정만) · 휴면 해제(전이표) · 무인 문맥 거부 · actions 1행
#   X 돌연변이 3(장치 제거판에서 위 단정 red) — allowlist 검사 제거 → V3·V7 · 스키마 검사 제거 → V1·V2 · 전이표/관리 대상 검사 제거 → V6
#     + write-ahead 제거 → B · 스캐너 우회 탐지 3종 각각 제거 → 해당 우회 통과(방어 무력화 돌연변이)
# 격리: 임시 root(운영 사본) · 운영 06_Registry/organic·보호 파일 md5 불변.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
cls_of <- function(expr) tryCatch({ force(expr); "none" }, rfo_k1 = function(e) paste0("k1:", e$code), rfo_k2 = function(e) "k2",
                                  error = function(e) paste0("error:", substr(conditionMessage(e), 1, 90)))
Sys.unsetenv(c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE"))
PROT <- file.path(ROOT, c("06_Registry/reinforce_program.json", "06_Registry/a_eligibility_gate.json", "06_Registry/overlay_catalog.json",
                          "06_Registry/reinforce_ledger_l1.json", "06_Registry/reinforce_auto_config.json"))
md5p <- function() vapply(PROT, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
P0 <- md5p(); ORG0 <- dir.exists(file.path(ROOT, "06_Registry/organic/state.json"))
TMP <- normalizePath(tempdir(), winslash = "/")
mk_root <- function(tag) {
  d <- file.path(TMP, sprintf("rfob_%s_%d", tag, Sys.getpid())); unlink(d, recursive = TRUE, force = TRUE)
  for (s in c("02_Infrastructure/reinforcement", "02_Infrastructure/ops", "02_Infrastructure/utils", "02_Infrastructure/factor_db",
              "02_Infrastructure/worktask", "06_Registry/organic", "06_Registry/book", ".cache"))
    dir.create(file.path(d, s), recursive = TRUE, showWarnings = FALSE)
  cp <- function(rel) if (file.exists(file.path(ROOT, rel))) file.copy(file.path(ROOT, rel), file.path(d, rel), overwrite = TRUE)
  for (f in c("02_Infrastructure/config.R", "02_Infrastructure/reinforcement/reinforce_ledger.R", "02_Infrastructure/reinforcement/rf_organic_guard.R",
              "02_Infrastructure/reinforcement/rf_organic_write.R", "02_Infrastructure/reinforcement/rf_organic_ledger_adapter.R",
              "02_Infrastructure/ops/rf_organic_cmd.R", "02_Infrastructure/ops/rf_claim.R", "02_Infrastructure/utils/atomic_json.R",
              "02_Infrastructure/factor_db/factor_registry.json", "02_Infrastructure/worktask/constraint_defaults.json",
              "06_Registry/organic/schema.json", "06_Registry/overlay_catalog.json", "06_Registry/weight_catalog.json", "06_Registry/pit_quarantine.json",
              "06_Registry/reinforce_program.json", "06_Registry/a_eligibility_gate.json", "06_Registry/reinforce_auto_config.json")) cp(f)
  writeLines("{\"schema_version\":\"reinforce_ledger_v2\",\"layer\":1,\"max_attempts\":35,\"entries\":[]}", file.path(d, "06_Registry/reinforce_ledger_l1.json"))
  normalizePath(d, winslash = "/")
}
R <- mk_root("a")
if (!file.exists(file.path(R, "06_Registry/organic/schema.json"))) { ng("전제 — 06_Registry/organic/schema.json 부재(배포 대상)"); }
led <- new.env(); invisible(capture.output(sys.source(file.path(R, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = led)))
W <- new.env(); sys.source(file.path(R, "02_Infrastructure/reinforcement/rf_organic_write.R"), envir = W)
G <- new.env(); sys.source(file.path(R, "02_Infrastructure/reinforcement/rf_organic_guard.R"), envir = G)
POL <- list(policy_id = "pi_test", policy_sha = "abc123", mode = "shadow")
trial <- function(Rt, kind = "organic_shadow", layer = "budget") {
  did <- led$.rf_uid("M-ORG-", c(kind, layer))
  led$rf_trial_log_append(kind, "program", decision_id = did, policy = POL, organic = list(layer = layer, view_md5 = "v", tau_D = "2016-11-21"), root = Rt)
  did }
sp <- function(Rt) file.path(Rt, "06_Registry/organic/state.json")
md5f <- function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent"
n_actions <- function(Rt) { p <- file.path(Rt, "06_Registry/organic/actions.jsonl"); if (file.exists(p)) length(readLines(p, warn = FALSE)) else 0L }
ov_active <- local({ o <- fromJSON(file.path(R, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)
  ids <- vapply(Filter(function(a) identical(a$status, "active"), o$arms), function(a) a$id, character(1)); ids[1] })

cat("=== A [양성] 허용 경로 ===\n")
d1 <- trial(R)
r1 <- W$rfo_write("06_Registry/organic/state.json", list(n = 3L, n_cap = 5L, n_min = 1L, n_attempted = 2L, frozen = FALSE, policy_sha = "abc123"),
                  d1, pointer = "plan/RP_X/B2", root = R, layer = "budget", policy = POL)
st <- fromJSON(sp(R), simplifyVector = FALSE)
chk(isTRUE(r1$ok) && identical(as.integer(st$plan$RP_X$B2$n), 3L) && n_actions(R) == 1L &&
      !length(list.files(file.path(R, "06_Registry/organic"), pattern = "^\\.", all.files = TRUE, no.. = TRUE)),
    "A1 state 포인터 쓰기 → 반영 · actions 1행 · 원자 쓰기 잔재(.tmp) 0")
d2 <- trial(R, "organic_proposal", "space")
W$rfo_write("06_Registry/organic/decisions.jsonl", list(decision_id = d2, layer = "space", chosen = "none"), d2, root = R, layer = "space")
W$rfo_write("06_Registry/organic/runs/asof_batch/2026-09-25", list(done = TRUE), d2, root = R)
chk(length(readLines(file.path(R, "06_Registry/organic/decisions.jsonl"))) == 1L && file.exists(file.path(R, "06_Registry/organic/runs/asof_batch/2026-09-25")) &&
      n_actions(R) == 3L, "A2 jsonl append · 하위 디렉터리(runs/) 쓰기 → 성공 · actions 누적 3")
d3 <- trial(R, "organic_policy_transition", "space")
W$rfo_write("06_Registry/organic/state.json", list(status = "organic_dormant", since = "2026-09-25"), d3, pointer = sprintf("arms/%s", ov_active), root = R, layer = "space")
chk(identical(fromJSON(sp(R), simplifyVector = FALSE)$arms[[ov_active]]$status, "organic_dormant"), sprintf("A3 정본 active arm(%s) pi0 → organic_dormant(전이표 안)", ov_active))
act_ids <- vapply(lapply(readLines(file.path(R, "06_Registry/organic/actions.jsonl"), warn = FALSE), fromJSON), function(x) as.character(x$decision_id), character(1))
chk(length(act_ids) >= 4L && all(vapply(act_ids, function(d) isTRUE(led$rf_trial_log_has(d, R)), logical(1))),
    "A4 state 효과(actions 행) 전부에 선행 시행 레코드 — 조인 100%(write-ahead)", paste(act_ids[!vapply(act_ids, function(d) isTRUE(led$rf_trial_log_has(d, R)), logical(1))], collapse = ","))
iso <- file.path(ROOT, c("02_Infrastructure/reinforcement/rf_runner_gates.R", "02_Infrastructure/contracts/essence_score.R",
                         "02_Infrastructure/alpha_search/run_paper_replication.R", ".claude/agents/judge.md"))
iso <- iso[file.exists(iso)]
hit_iso <- iso[vapply(iso, function(f) any(grepl("06_Registry/organic", readLines(f, warn = FALSE, encoding = "UTF-8"), fixed = TRUE)), logical(1))]
chk(length(iso) >= 2L && !length(hit_iso), sprintf("A5 판정 경로 격리 — 관문·essence·충실구현 러너·judge.md(%d파일)에 06_Registry/organic 참조 0", length(iso)), paste(basename(hit_iso), collapse = ","))

cat("\n=== B write-ahead ===\n")
m0 <- md5f(sp(R)); na0 <- n_actions(R)
b <- cls_of(W$rfo_write("06_Registry/organic/state.json", list(n = 2L, n_cap = 5L), "M-ORG-20260925T000000000-9-ffffff", pointer = "plan/RP_Y/B2", root = R))
chk(identical(b, "k2") && identical(md5f(sp(R)), m0) && n_actions(R) == na0, "B 선행 시행 레코드 없는 효과 → K2 거부 · 쓰기 0", b)

cat("\n=== V 위반 7 ===\n")
dv <- trial(R, "organic_live", "budget")
pq <- Filter(function(x) identical(x$status, "active"), fromJSON(file.path(R, "06_Registry/pit_quarantine.json"), simplifyVector = FALSE)$quarantines)
qarm <- unlist(lapply(pq, function(x) vapply(x$overlay_arms %||% list(), function(z) z$id, character(1))))[1]
V <- list(
  V1 = function() W$rfo_write("06_Registry/organic/state.json", 30L, dv, pointer = "fixed_axes/n_max", root = R),
  V2 = function() W$rfo_write("06_Registry/organic/state.json", list(port_t = 2.0), dv, pointer = "policies/pi_x/tier_graduation", root = R),
  V3 = function() W$rfo_write("06_Registry/a_eligibility_gate.json", list(holds = list()), dv, root = R),
  V4 = function() W$rfo_write("06_Registry/overlay_catalog.json", list(arms = list()), dv, root = R),
  V5 = function() W$rfo_write("06_Registry/organic/state.json", list(n = 7L, n_cap = 5L, n_min = 1L, n_attempted = 0L), dv, pointer = "plan/RP_X/B3", root = R),
  V6 = function() W$rfo_write("06_Registry/organic/state.json", list(status = "organic_dormant"), dv, pointer = sprintf("arms/%s", qarm %||% "pg2_risk_overlay_v1"), root = R),
  V7 = function() W$rfo_write("06_Registry/reinforce_ledger_l1.json", list(entries = list()), dv, root = R))
tgt <- c(V1 = sp(R), V2 = sp(R), V3 = file.path(R, "06_Registry/a_eligibility_gate.json"), V4 = file.path(R, "06_Registry/overlay_catalog.json"),
         V5 = sp(R), V6 = sp(R), V7 = file.path(R, "06_Registry/reinforce_ledger_l1.json"))
res <- vapply(names(V), function(k) { m <- md5f(tgt[[k]]); s0 <- md5f(sp(R)); c <- cls_of(V[[k]]())
  sprintf("%s|%s", c, if (identical(md5f(tgt[[k]]), m) && identical(md5f(sp(R)), s0)) "unchanged" else "CHANGED") }, character(1))
exp_code <- c(V1 = "k1:schema", V2 = "k1:schema", V3 = "k1:path_denied", V4 = "k1:path_denied", V5 = "k1:schema", V6 = "k1:arm_unmanaged", V7 = "k1:path_denied")
for (k in names(V)) chk(identical(res[[k]], paste0(exp_code[[k]], "|unchanged")), sprintf("%s → %s · 대상·state 불변", k, exp_code[[k]]), res[[k]])

cat("\n=== C 충돌 사본 · 스냅샷 ===\n")
host <- Sys.info()[["nodename"]]
cf <- file.path(R, "06_Registry/organic", sprintf("state-%s.json", host)); writeLines("{}", cf)
cc <- cls_of(W$rfo_write("06_Registry/organic/state.json", list(n = 3L, n_cap = 5L), d1, pointer = "plan/RP_Z/B2", root = R))
unlink(cf)
chk(identical(cc, "k1:onedrive_conflict"), sprintf("C1 OneDrive 충돌 사본(state-%s.json) → K1", host), cc)
s0 <- G$rfo_snapshot(R); s1 <- G$rfo_snapshot(R)
chk(isTRUE(G$rfo_snapshot_diff(s0, s1)$same), "C2 [양성] 무변경 → 스냅샷 동일")
cat(" ", file = file.path(R, "06_Registry/reinforce_program.json"), append = TRUE); writeLines("x", file.path(R, "06_Registry/book/BOOK_T.json"))
dd <- G$rfo_snapshot_diff(s0, G$rfo_snapshot(R))
chk(!dd$same && "06_Registry/reinforce_program.json" %in% dd$changed && any(grepl("06_Registry/book", dd$changed)),
    "C3 보호 파일 1바이트 · BOOK 새 파일 → 스냅샷 불일치(K1 원천)", paste(dd$changed, collapse = ","))

cat("\n=== S 정적 봉쇄 ===\n")
sc <- function(f, role, fns = character(0)) G$rfo_static_scan(f, role, writer_fns = fns)
real <- list(writer = sc(file.path(R, "02_Infrastructure/reinforcement/rf_organic_write.R"), "writer", W$RFO_WRITER_FNS),
             adapter = sc(file.path(R, "02_Infrastructure/reinforcement/rf_organic_ledger_adapter.R"), "adapter"),
             guard = sc(file.path(R, "02_Infrastructure/reinforcement/rf_organic_guard.R"), "guard"))
for (k in names(real)) chk(isTRUE(real[[k]]$ok), sprintf("S1 실제 유기체 파일(%s 역할) 정적 봉쇄 통과", k),
                           paste(apply(real[[k]]$violations, 1, paste, collapse = ":"), collapse = " | "))
fx <- function(name, lines) { p <- file.path(TMP, name); writeLines(lines, p, useBytes = TRUE); p }
clean <- fx("fx_clean.R", c("rfo_view_score <- function(view) {", "  x <- view$window_deviation_months", "  mean(x, na.rm = TRUE)", "}"))
chk(isTRUE(sc(clean, "decision")$ok), "S2 [양성] 깨끗한 결정 픽스처 통과")
inj <- list(g2 = c("f <- function(L) L$attempts[[1]]$essence$calmar", "g <- function() rf_load(1L)"),
            write = c("f <- function(p) writeLines('x', p)"), auth = c("f <- function() dr_resolve('X', 'a', decided_by = 'dohoon')"))
for (k in names(inj)) { v <- sc(fx(sprintf("fx_%s.R", k), inj[[k]]), "decision")
  chk(!v$ok, sprintf("S3 위반 주입 %s 적발", k), paste(v$violations$kind, collapse = ",")) }
byp <- list(concat = c("f <- function(root) { p <- paste0('reinforce_ledger', '_l1.json'); jsonlite::fromJSON(file.path(root, '06_Registry', p)) }"),
            docall = c("f <- function() do.call('rf_load', list(1L))"),
            evalparse = c("f <- function() eval(parse(text = 'rf_load(1L)'))"))
# 우회별 1차 탐지기(kind·token) — 다른 층이 겹쳐 잡아도 1차 탐지기가 살아 있는지를 잰다(돌연변이가 그것만 지우면 이 단정이 red)
byp_prim <- list(concat = c("concat_bypass", "reinforce_ledger_l1.json"), docall = c("dynamic_eval", "do.call"), evalparse = c("dynamic_eval", "eval"))
has_prim <- function(v, p) any(v$violations$kind == p[1] & v$violations$token == p[2])
for (k in names(byp)) { v <- sc(fx(sprintf("fx_byp_%s.R", k), byp[[k]]), "decision")
  chk(!v$ok && has_prim(v, byp_prim[[k]]), sprintf("S4 우회 %s 적발(1차 탐지 %s:%s)", k, byp_prim[[k]][1], byp_prim[[k]][2]),
      paste(sprintf("%s:%s", v$violations$kind, v$violations$token), collapse = ",")) }

cat("\n=== R 롤백 ===\n")
R2 <- mk_root("r"); dA <- trial(R2)
W$rfo_write("06_Registry/organic/state.json", list(n = 5L, n_cap = 5L), dA, pointer = "plan/RP_R/B2", root = R2)
before_all <- fromJSON(sp(R2), simplifyVector = FALSE)$plan
dB <- trial(R2)
W$rfo_write("06_Registry/organic/state.json", list(n = 3L, n_cap = 5L), dB, pointer = "plan/RP_R/B2", root = R2)
W$rfo_write("06_Registry/organic/state.json", list(n = 2L, n_cap = 5L), dB, pointer = "plan/RP_R/B3", root = R2)
dRb <- trial(R2, "organic_rollback", "budget")
rr <- W$rfo_rollback(dB, dRb, R2)
after_rb <- fromJSON(sp(R2), simplifyVector = FALSE)$plan
chk(rr$n_restored == 2L && identical(after_rb$RP_R$B2, before_all$RP_R$B2) && is.null(after_rb$RP_R$B3),
    "R1 결정 dB 의 state 쓰기 2건 역순 복원 → 대상 포인터 = 적용 전(B2 5칸 · B3 없음)", toJSON(after_rb, auto_unbox = TRUE))
cat(toJSON(list(decision_id = "M-ORG-BAD", target = "06_Registry/reinforce_ledger_l1.json", pointer = "", before = NULL), auto_unbox = TRUE, null = "null"), "\n",
    file = file.path(R2, "06_Registry/organic/actions.jsonl"), append = TRUE, sep = "")
rb2 <- cls_of(W$rfo_rollback("M-ORG-BAD", trial(R2, "organic_rollback", "budget"), R2))
chk(identical(rb2, "k1:rollback_target"), "R2 원장을 가리키는 롤백 → K1 거부(원장·측정은 롤백 대상 아님)", rb2)

cat("\n=== H 사람 명령(ops/rf_organic_cmd.R) ===\n")
RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
EMPTY <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY)
run_cmd <- function(Rt, args, env = character(0)) {
  old <- Sys.getenv(c("R_ENVIRON_USER", "QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE", "QVEST_RF_CLAIM"), unset = NA)
  on.exit(for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])), add = TRUE)
  Sys.setenv(R_ENVIRON_USER = EMPTY, QVEST_RF_CLAIM = file.path(Rt, ".cache/rf.claim")); Sys.unsetenv(c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE"))
  if (length(env)) do.call(Sys.setenv, as.list(env))
  out <- suppressWarnings(system2(RS, c("--no-environ", shQuote(file.path(Rt, "02_Infrastructure/ops/rf_organic_cmd.R")), paste0("--root=", Rt), args),
                                  stdout = TRUE, stderr = TRUE))
  list(rc = as.integer(attr(out, "status") %||% 0L), out = paste(out, collapse = "\n"))
}
R3 <- mk_root("h")
seed <- function(Rt) { led$dr_open("REINFORCE-ORGANIC-AUTONOMY", "자율", "승인", "승인", "보류", character(0), source = "t", root = Rt)
  led$dr_resolve("REINFORCE-ORGANIC-AUTONOMY", "승인", decided_by = "dohoon", root = Rt, recorded_by = "Q(세션)", evidence = "픽스처") }
seed(R3)
led$dr_open("DOHOON-OLD", "킬 전 결정", "해제", "해제", "유지", character(0), source = "t", root = R3)
led$dr_resolve("DOHOON-OLD", "해제", decided_by = "dohoon", root = R3, recorded_by = "Q(세션)", evidence = "픽스처", decided_at = "2026-09-20T00:00:00+0900")
dk <- trial(R3, "organic_kill", "all")
W$rfo_write("06_Registry/organic/state.json", list(flag = TRUE, code = "K1", at = format(Sys.time() - 60, "%Y-%m-%dT%H:%M:%S%z")), dk, pointer = "killed", root = R3)
Sys.sleep(1.2)
led$dr_open("DOHOON-REL", "킬 해제", "해제", "해제", "유지", character(0), source = "t", root = R3)
led$dr_resolve("DOHOON-REL", "해제", decided_by = "dohoon", root = R3, recorded_by = "Q(세션)", evidence = "도훈 채팅(픽스처)")
h0 <- run_cmd(R3, c("kill-release", "DOHOON-OLD"))
na3 <- n_actions(R3)
h1 <- run_cmd(R3, c("kill-release", "DOHOON-REL"))
st3 <- fromJSON(sp(R3), simplifyVector = FALSE)
chk(h0$rc != 0L && grepl("뒤가 아니다", h0$out), "H1 킬 전에 내린 도훈 결정으로 해제 → 거부", substr(h0$out, 1, 200))
chk(h1$rc == 0L && identical(st3$kill_release_seen$decision_id, "DOHOON-REL") && n_actions(R3) == na3 + 1L,
    "H2 킬 뒤 도훈 결정 → state.kill_release_seen 기록 · actions 1행", substr(h1$out, 1, 300))
mrow <- Filter(function(x) identical(x$record_class, "machine"), led$dr_load(R3)$items)
chk(length(mrow) == 1L && identical(mrow[[1]]$kind, "organic_kill") && identical(mrow[[1]]$status, "resolved") && grepl("actions.jsonl#H-ORG-", mrow[[1]]$evidence),
    "H2b 킬 해제 → 결정 레지스터 포인터 행 1(기계 · resolved · 본문 = actions.jsonl 포인터)", if (length(mrow)) mrow[[1]]$evidence else "행 없음")
h2 <- run_cmd(R3, c("kill-release", "DOHOON-REL"), env = c(QVEST_UNATTENDED_LANE = "1"))
h3 <- run_cmd(R3, c("status"), env = c(QVEST_ORGANIC_CTX = "1"))
chk(h2$rc != 0L && grepl("무인", h2$out) && h3$rc != 0L, "H3 무인·유기체 문맥 → 사람 명령 거부", paste(substr(h2$out, 1, 80), substr(h3$out, 1, 80)))
dd3 <- trial(R3, "organic_policy_transition", "space")
W$rfo_write("06_Registry/organic/state.json", list(status = "organic_dormant"), dd3, pointer = sprintf("arms/%s", ov_active), root = R3)
h4 <- run_cmd(R3, c("dormant-release", ov_active, "사람 판단(픽스처)"))
chk(h4$rc == 0L && identical(fromJSON(sp(R3), simplifyVector = FALSE)$arms[[ov_active]]$status, "pi0"), "H4 휴면 해제 organic_dormant → pi0(전이표 안)", substr(h4$out, 1, 200))

cat("\n=== X 돌연변이 ===\n")
mut <- function(f, from, to) { src <- deparse(f, width.cutoff = 500L); m <- sub(from, to, src, fixed = TRUE)
  if (sum(src != m) != 1L) return(NULL); g <- eval(parse(text = m)); environment(g) <- environment(f); g }
RM <- mk_root("m"); dm <- trial(RM, "organic_live", "budget")
W$.rfow_env$root <- NULL; W$.rfow_libs(RM); keep <- W$.rfow_env$g$rfo_path_allowed
W$.rfow_env$g$rfo_path_allowed <- mut(keep, "!is.na(rel) && any(", "TRUE || any(")
x1 <- if (is.null(W$.rfow_env$g$rfo_path_allowed)) "mutation_failed" else
  c(V3 = cls_of(W$rfo_write("06_Registry/a_eligibility_gate.json", list(holds = list()), dm, root = RM)),
    V7 = cls_of(W$rfo_write("06_Registry/reinforce_ledger_l1.json", list(entries = list()), dm, root = RM)))
W$.rfow_env$g$rfo_path_allowed <- keep; W$.rfow_env$root <- NULL
chk(is.character(x1) && all(x1 %in% "none"), "X1 [돌연변이] allowlist 검사 제거 → 보호 파일 쓰기 통과 = V3·V7 이 이 결함을 잡는다", paste(x1, collapse = ","))
RM2 <- mk_root("m2"); dm2 <- trial(RM2, "organic_live", "budget")
W$.rfow_libs(RM2); keep <- W$.rfow_env$g$rfo_schema_check
W$.rfow_env$g$rfo_schema_check <- function(state, schema, grid_n = NULL) list(ok = TRUE, errors = character(0))
x2 <- c(V1 = cls_of(W$rfo_write("06_Registry/organic/state.json", 30L, dm2, pointer = "fixed_axes/n_max", root = RM2)),
        V2 = cls_of(W$rfo_write("06_Registry/organic/state.json", list(port_t = 2.0), dm2, pointer = "policies/pi_x/tier_graduation", root = RM2)))
W$.rfow_env$g$rfo_schema_check <- keep; W$.rfow_env$root <- NULL
chk(all(x2 == "none") && identical(as.integer(fromJSON(sp(RM2), simplifyVector = FALSE)$fixed_axes$n_max), 30L),
    "X2 [돌연변이] 스키마 검사 제거 → 고정 축·문턱 키가 state 에 박힌다 = V1·V2 가 이 결함을 잡는다", paste(x2, collapse = ","))
RM3 <- mk_root("m3"); dm3 <- trial(RM3, "organic_live", "budget")
W$.rfow_libs(RM3); keep <- W$.rfow_env$g$rfo_canonical_status
W$.rfow_env$g$rfo_canonical_status <- function(catalog_id, root, schema) list(found = TRUE, status = "active", source = "mut", quarantined = FALSE, managed = TRUE)
x3 <- cls_of(W$rfo_write("06_Registry/organic/state.json", list(status = "organic_dormant"), dm3, pointer = sprintf("arms/%s", qarm %||% "pg2_risk_overlay_v1"), root = RM3))
W$.rfow_env$g$rfo_canonical_status <- keep; W$.rfow_env$root <- NULL
chk(identical(x3, "none"), "X3 [돌연변이] 관리 대상(정본 status·PIT 격리) 검사 제거 → 격리 arm 휴면 관리 = V6 이 이 결함을 잡는다", x3)
RM4 <- mk_root("m4"); W$.rfow_env$root <- NULL
g4 <- mut(W$rfo_write, "if (!nzchar(did) || !isTRUE(L$rf_trial_log_has(did, root)))", "if (FALSE)")
x4 <- if (is.null(g4)) "mutation_failed" else cls_of(g4("06_Registry/organic/state.json", list(n = 2L, n_cap = 5L), "M-ORG-NONE", pointer = "plan/RP_Y/B2", root = RM4))
chk(identical(x4, "none") && file.exists(sp(RM4)), "X4 [돌연변이] write-ahead 검사 제거 → 선행 기록 없는 효과가 쓰인다 = B 가 이 결함을 잡는다", x4)
scan_mut <- function(from, to, k) { g <- mut(G$rfo_static_scan, from, to); if (is.null(g)) return(NA)
  !has_prim(g(file.path(TMP, sprintf("fx_byp_%s.R", k)), "decision"), byp_prim[[k]]) }
y1 <- scan_mut('addv(fc$line1[i], "concat_bypass", b)', "NULL", "concat")
y2 <- scan_mut('if (is_call && identical(t, "do.call") && first_arg_sym(sym$id[i]) %in% benign_fn)', 'if (is_call && identical(t, "do.call"))', "docall")
y3 <- scan_mut('if (is_call && t %in% dyn && !identical(t, "parse"))', 'if (is_call && t %in% setdiff(dyn, "eval") && !identical(t, "parse"))', "evalparse")
chk(isTRUE(y1), "X5 [돌연변이] 결합 우회 탐지 제거 → 문자열 결합 원장 경로의 1차 탐지 소멸 = S4 concat 이 잡는다", as.character(y1))
chk(isTRUE(y2), "X6 [돌연변이] do.call 무해 판정을 전부로 넓힘 → do.call(\"rf_load\") 1차 탐지 소멸 = S4 docall 이 잡는다", as.character(y2))
chk(isTRUE(y3), "X7 [돌연변이] eval 을 동적 평가 목록에서 뺌 → eval(parse(text=)) 1차 탐지 소멸 = S4 evalparse 가 잡는다", as.character(y3))

cat("\n=== Z 운영 무접촉 ===\n")
chk(identical(md5p(), P0) && identical(dir.exists(file.path(ROOT, "06_Registry/organic/state.json")), ORG0), "Z1 운영 보호 파일 md5 · organic state 부재 불변")
unlink(c(R, R2, R3, RM, RM2, RM3, RM4), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_organic_boundary","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
