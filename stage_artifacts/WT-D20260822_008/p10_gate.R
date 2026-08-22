## WT-D20260822_008 P10 — 스키마/게이트 검증 + status/governance 갱신
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_008"; OUT <- "stage_artifacts/WT-D20260822_008"
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
sch <- fromJSON("02_Infrastructure/worktask/schema.json", simplifyVector=FALSE)
ap  <- sch$definitions$alpha_package

cat("=== 스키마 필수 필드 ===\n")
for (f in unlist(ap$required)) cat(sprintf("  %-22s %s\n", f,
  if (f %in% names(pkg)) "OK (present)" else "MISSING"))
cat("=== v1.1 조건부 (spec_version=ast_v1.1, verdict=designed) ===\n")
for (f in c("hypothesis","verdict","pit","factors","combination_rule","self_pit_check"))
  cat(sprintf("  %-22s %s\n", f, if (!is.null(pkg[[f]])) "OK" else "MISSING"))
cat(sprintf("  pit.sig_date           %s\n", pkg$pit$sig_date))
cat("=== diagnostics 필수 ===\n")
for (f in unlist(ap$properties$diagnostics$required))
  cat(sprintf("  %-28s %s\n", f, if (f %in% names(pkg$diagnostics))
    ifelse(is.null(pkg$diagnostics[[f]]), "present (null + challenge_flag 사유)",
           format(pkg$diagnostics[[f]])) else "MISSING"))

cat("\n=== hypothesis 층 ===\n")
cat(sprintf("  statement len = %d (min 20)\n", nchar(pkg$hypothesis$statement)))
for (f in c("agent","friction","path"))
  cat(sprintf("  mechanism.%-9s len %4d (min 5)\n", f, nchar(pkg$hypothesis$mechanism[[f]])))
fs <- pkg$hypothesis$falsification
gschema <- fs$falsification_gate_schema
cat(sprintf("  falsification.observable len = %d\n", nchar(fs$observable)))
cat(sprintf("  falsification_gate_schema 항목 = %d (min 1) · 전건 group_id 보유 = %s\n",
    length(gschema), all(vapply(gschema, function(z) !is.null(z$group_id), TRUE))))
fm <- fromJSON("06_Registry/ast_field_map_v0.json", simplifyVector=FALSE)
## ★검사기 정정 (2026-08-22): WT-007 p7_gate.R 의 평면 lapply 추출은 이 맵이 domains 아래로
##   중첩돼 있어 group_id 를 0건 수집하고 전건 FALSE 를 낸다 — 실제 위반이 아니라 검사기 오탐.
##   재귀 수집으로 교체(실측: 58 group_id 수집, 사용 5건 전부 등재 TRUE).
.collect_gid <- function(o) { if (is.list(o)) {
    c(if (!is.null(o$group_id) && is.character(o$group_id)) o$group_id else character(0),
      unlist(lapply(o, .collect_gid), use.names=FALSE)) } else character(0) }
gset <- unique(.collect_gid(fm))
cat(sprintf("  [field_map] 재귀 수집 group_id = %d건\n", length(gset)))
used <- vapply(gschema, function(z) z$group_id, "")
cat("  group_id:", paste(used, collapse=" | "), "\n")
cat(sprintf("  field_map 등재: %s\n", paste(vapply(used, function(u) paste0(u,"=",u %in% gset), ""), collapse=" ")))
cat(sprintf("  regime_scope holds_in %d · weakens %d (둘 다 min 1)\n",
    length(pkg$hypothesis$regime_scope$holds_in),
    length(pkg$hypothesis$regime_scope$weakens_or_reverses_in)))

cat("\n=== factors / escape_contract ===\n")
for (f in pkg$factors) cat(sprintf("  %-32s leaf=%s escape=%s walk_forward=%s\n",
  f$factor_id, f$ast$leaf, f$ast$escape_contract$escape_type, f$ast$escape_contract$walk_forward))
cat(sprintf("  combination_rule=%s · verdict=%s · self_pit_check.verdict=%s\n",
    pkg$combination_rule, pkg$verdict, pkg$self_pit_check$verdict))
cat(sprintf("  alpha_vector n=%d (의도적 공집합 — terminal_form=diagnostic) · alpha_discovery_count=%d\n",
    length(pkg$alpha_vector), pkg$alpha_discovery_count))
cat(sprintf("  challenge_flags=%d건 · selection_objective=%s\n",
    length(pkg$challenge_flags), pkg$selection_objective))

cat("\n=== alpha_validation.json ===\n")
v <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
cat(sprintf("  top keys=%d · verdict=%s\n", length(v), v$verdict))
cat(sprintf("  next_probe=%d건 (min 2) · limitations=%d · capital_eligible=%s\n",
    length(v$next_probe), length(v$limitations), v$capital_eligible))
cat(sprintf("  PREREG 존재=%s (%d bytes) · alpha_scores.parquet=%s (%d bytes)\n",
    file.exists(file.path(OUT,"PREREG.json")), file.size(file.path(OUT,"PREREG.json")),
    file.exists(file.path(OUT,"alpha_scores.parquet")), file.size(file.path(OUT,"alpha_scores.parquet"))))
cat(sprintf("  challenge_note.md=%s (%d bytes)\n", file.exists(file.path(MB,"challenge_note.md")),
    file.size(file.path(MB,"challenge_note.md"))))

## ---- status / governance ----
write_json(list(task_id="WT-D20260822_008", current_phase="ALPHA_DONE",
  updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), blocker=NULL,
  round_verdict=v$round_verdict, terminal_form="diagnostic_criterion_validity",
  capital_path=paste0("NOT_ELIGIBLE — terminal_form=diagnostic_criterion_validity. 정답지가 사후 정보라 ",
    "성과 arm 자체를 구성하지 않았고 α̂ 미방출(alpha_discovery_count=0). capital_eligible=FALSE."),
  next_stage="risk-research spawn 불요 — 승격 후보 없음. Q-Lead 판단: next_probe NP1~NP4 중 택일 또는 FQ 등재."),
  file.path(MB,"status.json"), pretty=TRUE, auto_unbox=TRUE, null="null")
cat("\n[emit] status.json (ALPHA_DONE)\n")

gl <- if (file.exists(file.path(MB,"governance_log.json")))
  fromJSON(file.path(MB,"governance_log.json"), simplifyVector=FALSE) else list()
if (!is.null(gl$entries)) gl <- gl$entries
gl <- c(if (is.list(gl) && length(gl) && is.null(names(gl))) gl else list(gl), list(list(
  ts=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent="alpha-research", event="ALPHA_DONE",
  summary=paste0("FQ-246 NP2 정답지 교체 기준-타당성 진단(terminal_form=diagnostic_criterion_validity, α̂ 미방출). ",
    "대조 패리티: WT-007 IC-정답지 FC 게이트 8방향 Δ=0.000e+00 비트-동일 + ORACLE_K_RET 재현 |Δ|<=2.1e-11. ",
    "전도성: 양성 4/4 발화(잡음 4배 적중 0.2932) · 음성 미발화(0.1810). ",
    "본 측정: RET 정답지 게이트 통과 0/8(raw·Bonferroni·Sidak 전부 0, 최대 적중 0.235294 centrality_MIN, ",
    "정확 임계 0.248869) · 정답지 교체 paired 0/8(최대 |Δhit| 0.022624 vs 양측 MDE 0.059626). ",
    "⇒ '기준이 잘못된 표적을 맞혔다' 가설 powered 기각. ",
    "★신규 확립: 두 정답지 일치율 0.48868778(우연 0.20) · 분할표본 전이에서 IC 는 RET 전이값의 0.867~0.919배로 ",
    "거의 같은데 전수 오라클에서는 2.2999배 ⇒ ORACLE_K_RET 8.8381 의 상한 우위 대부분이 월내 잡음 최대화. ",
    "단 표적 자체는 실재(전이 +8.86~9.48 %p/yr, NW3 t 3.38~4.23) ⇒ null 귀속 = 표적 부재 아니라 기준 부재. ",
    "★부수: 적중률 최고 기준의 선택가치가 유의 음수(-5.2672 %p/yr, 순열 z -2.584)."),
  self_adversarial="ACCEPT 3 / PARTIAL 2 / REBUTTAL 1 — challenge_note.md. escalate 불발동.",
  inheritance_challenge=paste0("승계 mechanism F5(꼬리질량 지문) 미지지(불일치월 breadth z -0.0060 vs 일치월 +0.1085, ",
    "Welch t -0.950) + 승계 regime_scope 미지지(위기 스프레드 0.04873 vs 정상 0.04955, 적중 0.2188 vs 0.2069) ",
    "— 재설계 요청 등재(수정 아님, Charter 원칙 8)."),
  artifacts=c(paste0(MB,"/alpha_package.json"), paste0(MB,"/challenge_note.md"),
    paste0(MB,"/alpha_hypothesis.json"), paste0(OUT,"/alpha_validation.json"),
    paste0(OUT,"/alpha_scores.parquet"), paste0(OUT,"/PREREG.json")))))
write_json(gl, file.path(MB,"governance_log.json"), pretty=TRUE, auto_unbox=TRUE, null="null")
cat("[emit] governance_log.json\n\nOK\n")
