## WT-D20260822_007 P7 — 스키마/게이트 검증 + status/governance 갱신
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_007"; OUT <- "stage_artifacts/WT-D20260822_007"
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector = FALSE)
sch <- fromJSON("02_Infrastructure/worktask/schema.json", simplifyVector = FALSE)
ap <- sch$definitions$alpha_package

cat("=== 스키마 필수 필드 ===\n")
req <- unlist(ap$required)
for (f in req) cat(sprintf("  %-22s %s\n", f, if (!is.null(pkg[[f]])) "OK" else "MISSING"))
cat("=== v1.1 조건부 (spec_version=ast_v1.1, verdict=designed) ===\n")
for (f in c("hypothesis","verdict","pit","factors","combination_rule","self_pit_check"))
  cat(sprintf("  %-22s %s\n", f, if (!is.null(pkg[[f]])) "OK" else "MISSING"))
cat(sprintf("  pit.sig_date           %s\n", pkg$pit$sig_date))
cat("=== diagnostics 필수 ===\n")
for (f in unlist(ap$properties$diagnostics$required))
  cat(sprintf("  %-28s %s\n", f, if (!is.null(pkg$diagnostics[[f]])) format(pkg$diagnostics[[f]]) else "MISSING"))

cat("\n=== hypothesis 층 검증 ===\n")
cat(sprintf("  statement len = %d (min 20)\n", nchar(pkg$hypothesis$statement)))
for (f in c("agent","friction","path"))
  cat(sprintf("  mechanism.%-9s len %4d (min 5)\n", f, nchar(pkg$hypothesis$mechanism[[f]])))
cat(sprintf("  falsification: array len %d (min 1) · 전건 group_id 보유 = %s\n",
    length(pkg$hypothesis$falsification),
    all(vapply(pkg$hypothesis$falsification, function(z) !is.null(z$group_id), TRUE))))
fm <- fromJSON("06_Registry/ast_field_map_v0.json", simplifyVector = FALSE)
gids <- if (!is.null(fm$groups)) vapply(fm$groups, function(g) g$group_id %||% "", "") else
        names(fm)
`%||%` <- function(a,b) if (is.null(a)) b else a
gset <- unique(unlist(lapply(fm, function(x) if (is.list(x)) x$group_id else NULL)))
if (length(gset) == 0) gset <- names(fm)
used <- vapply(pkg$hypothesis$falsification, function(z) z$group_id, "")
cat("  falsification group_id:", paste(used, collapse=" | "), "\n")
cat(sprintf("  field_map 등재 확인: %s\n",
    paste(vapply(used, function(u) paste0(u, "=", u %in% gset), ""), collapse=" ")))
cat(sprintf("  regime_scope holds_in %d · weakens %d (둘 다 min 1)\n",
    length(pkg$hypothesis$regime_scope$holds_in),
    length(pkg$hypothesis$regime_scope$weakens_or_reverses_in)))

cat("\n=== factors / escape_contract ===\n")
f1 <- pkg$factors[[1]]
cat(sprintf("  leaf = %s · escape_type = %s · op_code_path 존재 = %s · walk_forward = %s\n",
    f1$ast$leaf, f1$ast$escape_contract$escape_type,
    !is.null(f1$ast$escape_contract$op_code_path), f1$ast$escape_contract$walk_forward))
cat(sprintf("  combination_rule = %s · verdict = %s · self_pit_check.verdict = %s\n",
    pkg$combination_rule, pkg$verdict, pkg$self_pit_check$verdict))
cat(sprintf("  alpha_vector n = %d · confidence_vector n = %d · max conf = %.3f\n",
    length(pkg$alpha_vector), length(pkg$confidence_vector),
    max(unlist(pkg$confidence_vector))))
cat(sprintf("  challenge_flags = %d건 · selection_objective = %s\n",
    length(pkg$challenge_flags), pkg$selection_objective))

cat("\n=== alpha_validation.json 파싱 ===\n")
v <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector = FALSE)
cat(sprintf("  top keys = %d · verdict = %s\n", length(v), v$verdict))
cat(sprintf("  next_probe = %d건 (min 2)\n", length(v$next_probe)))

## ---- status / governance ----
write_json(list(task_id="WT-D20260822_007", current_phase="ALPHA_DONE",
  updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), blocker=NULL,
  round_verdict=v$round_verdict,
  capital_path="NOT_ELIGIBLE — Part B 전 arm 이 FC 전이 게이트·순열 백분위 게이트 미통과. Part A 는 오라클 진단으로 자본 자격 없음(capital_eligible=FALSE).",
  next_stage="risk-research spawn 불요 — 승격 후보 없음. Q-Lead 판단: next_probe NP1~NP4 중 택일 또는 FQ 등재."),
  file.path(MB,"status.json"), pretty=TRUE, auto_unbox=TRUE, null="null")
cat("\n[emit] status.json (ALPHA_DONE)\n")

gl <- if (file.exists(file.path(MB,"governance_log.json")))
  fromJSON(file.path(MB,"governance_log.json"), simplifyVector=FALSE) else list()
if (!is.null(gl$entries)) gl <- gl$entries
gl <- c(if (is.list(gl) && length(gl) && is.null(names(gl))) gl else list(gl), list(list(
  ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent = "alpha-research",
  event = "ALPHA_DONE",
  summary = paste0("FQ-246 NP1 이산 하드 선택 상한 분리. Part A(진단·자본불가): 정보 고정 형태 사다리 17 arm +",
    " 형태 귀무분포 240 run → 회수율 단조 증가(Spearman -0.9794), FQ-246 좌표 미회수 74.81pp 귀속 =",
    " 형태 50.58pp(t 2.934 확립) + 정보/타이밍 24.23pp(t 1.786 미결, MDE95 26.58pp).",
    " Part B(α̂ 축): 성과-비파생 기준 4종 하드 선택 13 arm 전부 C0 미달, FC 전이 게이트 9/9 powered null",
    " (적중률 0.172~0.231 vs 우연 0.200) · FB 매개 13/13 실효 ⇒ 형태는 전도되는데 기준이 무지.",
    " 신규 확립: 족 진짜 상한 ORACLE_K_RET PORT_t 8.8381(paired +31.4926 %p/yr) = IC 판의 2.30배."),
  self_adversarial = "ACCEPT 2 / PARTIAL 3 / REBUTTAL 1 — challenge_note.md. escalate 불발동.",
  inheritance_challenge = "승계 hypothesis B2(solo-advocate = 중심성 최소) 방향이 실측에서 반전 — 재설계 요청 등재(수정 아님, Charter 원칙 8).",
  artifacts = c(paste0(MB,"/alpha_package.json"), paste0(MB,"/challenge_note.md"),
                paste0(OUT,"/alpha_validation.json"), paste0(OUT,"/alpha_scores.parquet"),
                paste0(OUT,"/alpha_vector_live.parquet"), paste0(OUT,"/PREREG.json")))))
write_json(gl, file.path(MB,"governance_log.json"), pretty=TRUE, auto_unbox=TRUE, null="null")
cat("[emit] governance_log.json\n\nOK\n")
