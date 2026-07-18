# =============================================================================
# smoke_test_claim.R — Cleaner 증류 선점 프로토콜 스모크 (WT_D20260718_001)
#
# 검증 목표 (도훈 mandate 산출물 2): 2회 claim 시 2번째가 in_progress 감지.
# + 부수 시나리오: release→done→already_done · stale 재점유 · v1 하위호환 · owner 보호.
#
# 실제 .cache/cleaner_pending.json 무접촉 — 격리 scratch root(WT 하위)에서만 수행.
# 실행: Rscript stage_artifacts/WT_D20260718_001/smoke_test_claim.R
# =============================================================================
suppressWarnings(suppressMessages(library(jsonlite)))

# 프로젝트 루트 해석 (한글경로 회피 — 상대 아닌 env/known)
root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root) || !dir.exists(root)) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure", "ops", "cleaner_claim.R"))

wt_dir  <- file.path(root, "stage_artifacts", "WT_D20260718_001")
scratch <- file.path(wt_dir, "smoke_root")
unlink(scratch, recursive = TRUE)
dir.create(file.path(scratch, ".cache"), recursive = TRUE, showWarnings = FALSE)
pending <- file.path(scratch, ".cache", "cleaner_pending.json")

.mk_pending <- function(extra = list()) {
  base <- list(schema = "cleaner_pending_v2", week_of = "2026-W29",
               status = "awaiting_distill", distill_status = "pending",
               digest_path = "placeholder", distill_summary = list(l_codes_new = 0))
  write_json(modifyList(base, extra), pending, auto_unbox = TRUE, pretty = TRUE, null = "null")
}
results <- list(); ok_all <- TRUE
chk <- function(name, cond, detail = "") {
  ok_all <<- ok_all && isTRUE(cond)
  results[[length(results) + 1L]] <<- list(check = name, pass = isTRUE(cond), detail = detail)
  cat(sprintf("  [%s] %s%s\n", if (isTRUE(cond)) "PASS" else "FAIL", name,
              if (nzchar(detail)) paste0(" — ", detail) else ""))
}

cat("=== Scenario 1: 2회 claim — 2번째 in_progress 감지 (핵심) ===\n")
.mk_pending()
c1 <- cleaner_claim_distill("session_main", root = scratch)
c2 <- cleaner_claim_distill("task#89",      root = scratch)
chk("claim1 = TRUE (session_main 점유)", isTRUE(c1$claimed), sprintf("reason=%s owner=%s", c1$reason, c1$owner))
chk("claim2 = FALSE (중복 차단)",         isFALSE(c2$claimed), sprintf("reason=%s", c2$reason))
chk("claim2 reason = in_progress",        identical(c2$reason, "in_progress"), c2$message)
chk("claim2가 소유자 보고 (session_main)", identical(as.character(c2$owner), "session_main"), sprintf("owner=%s", c2$owner))
st <- cleaner_distill_state(root = scratch)
chk("state = in_progress + digest_path 보존",
    identical(st$distill_status, "in_progress") &&
      identical(fromJSON(pending)$digest_path, "placeholder"),
    sprintf("distill_status=%s", st$distill_status))

cat("=== Scenario 2: release(done) → 재claim = already_done ===\n")
r1 <- cleaner_release_distill("session_main", root = scratch)
pj <- fromJSON(pending)
chk("release = TRUE",                  isTRUE(r1$released), r1$message)
chk("distill_status = done",           identical(pj$distill_status, "done"))
chk("status = distilled 동기화",        identical(pj$status, "distilled"))
c3 <- cleaner_claim_distill("task#90", root = scratch)
chk("재claim = FALSE / already_done",   isFALSE(c3$claimed) && identical(c3$reason, "already_done"), c3$message)

cat("=== Scenario 3: owner 불일치 release 거부 ===\n")
.mk_pending()
invisible(cleaner_claim_distill("owner_A", root = scratch))
rmis <- cleaner_release_distill("owner_B", root = scratch)      # 불일치 → 거부
rfrc <- cleaner_release_distill("owner_B", root = scratch, force = TRUE)  # force → 허용
chk("불일치 release 거부",   isFALSE(rmis$released) && identical(rmis$reason, "owner_mismatch"), rmis$message)
chk("force release 허용",     isTRUE(rfrc$released))

cat("=== Scenario 4: stale in_progress 재점유 (6h 초과) ===\n")
.mk_pending(list(distill_status = "in_progress", distill_owner = "crashed_session",
                 distill_claimed_at = format(Sys.time() - 10 * 3600, "%Y-%m-%d %H:%M:%S")))
cstale <- cleaner_claim_distill("session_new", root = scratch, stale_hours = 6)
chk("stale(10h>6h) 재점유 성공", isTRUE(cstale$claimed) && identical(cstale$reason, "stale_reclaim"),
    sprintf("reason=%s prev_owner=%s", cstale$reason, cstale$prev_owner))
# fresh(1h) in_progress는 재점유 거부
.mk_pending(list(distill_status = "in_progress", distill_owner = "active_session",
                 distill_claimed_at = format(Sys.time() - 1 * 3600, "%Y-%m-%d %H:%M:%S")))
cfresh <- cleaner_claim_distill("session_new", root = scratch, stale_hours = 6)
chk("fresh(1h<6h) 재점유 거부", isFALSE(cfresh$claimed) && identical(cfresh$reason, "in_progress"))

cat("=== Scenario 5: v1 하위호환 (distill_status 필드 결측) ===\n")
# v1 awaiting_distill (필드 없음) → claim 가능
write_json(list(schema = "cleaner_pending_v1", status = "awaiting_distill"),
           pending, auto_unbox = TRUE, pretty = TRUE)
cv1 <- cleaner_claim_distill("v1_session", root = scratch)
chk("v1 awaiting_distill → claim 가능", isTRUE(cv1$claimed))
# v1 이미 distilled (필드 없음) → done 취급
write_json(list(schema = "cleaner_pending_v1", status = "distilled"),
           pending, auto_unbox = TRUE, pretty = TRUE)
sv1 <- cleaner_distill_state(root = scratch)
cv1d <- cleaner_claim_distill("v1_session2", root = scratch)
chk("v1 distilled → state=done", identical(sv1$distill_status, "done"))
chk("v1 distilled → claim 차단(already_done)",
    isFALSE(cv1d$claimed) && identical(cv1d$reason, "already_done"))

cat("=== Scenario 6: pending 부재 ===\n")
unlink(pending)
cnp <- cleaner_claim_distill("x", root = scratch)
chk("pending 부재 → no_pending", isFALSE(cnp$claimed) && identical(cnp$reason, "no_pending"))

# ── 로그 기록 ────────────────────────────────────────────────────────────────
n_pass <- sum(vapply(results, function(r) isTRUE(r$pass), logical(1)))
log_obj <- list(
  test = "cleaner_distill_claim_preemption_smoke",
  wt = "WT_D20260718_001",
  ran_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  helper = "02_Infrastructure/ops/cleaner_claim.R",
  scratch_root = scratch,
  n_checks = length(results), n_pass = n_pass,
  all_pass = ok_all,
  headline = "2회 claim 시 2번째 in_progress 감지 (핵심) + release/stale/v1-호환/owner-보호",
  checks = results)
write_json(log_obj, file.path(wt_dir, "smoke_test_claim_result.json"),
           auto_unbox = TRUE, pretty = TRUE, null = "null")
unlink(scratch, recursive = TRUE)   # scratch 정리 (로그만 남김)

cat(sprintf("\n=== SMOKE %s : %d/%d PASS ===\n",
            if (ok_all) "GREEN" else "RED", n_pass, length(results)))
if (!ok_all) quit(status = 1)
