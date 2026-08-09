#!/usr/bin/env Rscript
# p11_fq167_gate.R — FQ-167/168 착수 전 사전 확인 결과: 인용 재료 오염 판정 발견 → data_gate 주석
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))

note <- paste0(
  "★착수 전 사전 확인 (2026-08-09, Q-Lead ba4a1c30 — 점유 아님, 미배정 유지): ",
  "본 항목이 인용하는 within_sector_reversal_20260809(STR_AS_20260809_123327_46908)는 ",
  "**2026-08-09 14:18 GRADE_VOID_BENCHMARK_CONTAMINATED** 판정 ",
  "(stage_artifacts/alpha_search/20260809_123327_46908/CONTAMINATED_benchmark_scale_seam.json — ",
  "benchmark.parquet 스케일 이음매, 경계 하루 실측 -89.38% vs 참값 -6.185%, '걸어다니는 이음매' 계통). ",
  "⇒ 인용된 Grade F·IC·OOS 열위 등 **벤치-의존 수치 전부 무효**. MDD 60.4% 는 전략 NAV 성질이라 생존 가능하나 ",
  "재확인 필요. ★data_gate 실질 폐쇄: 수리된 벤치 위 재측정(재실행) 전 착수 금지 — ",
  "무효 전제 위에 게이팅 리서치를 세우면 판정 자체가 오염된다. 재측정 후 본 주석 해제할 것."
)
for (fq in c("FQ-167", "FQ-168")) {
  i <- which(ids == fq)
  if (length(i) == 1) {
    Q$entries[[i]]$contamination_precheck_20260809 <- note
    Q$entries[[i]]$data_gate <- paste0("★폐쇄 2026-08-09: 인용 재료 벤치-오염 무효 — 재측정 선행 (contamination_precheck 참조). 구: ",
                                       as.character(Q$entries[[i]]$data_gate)[1])
    cat("[gate]", fq, "주석 완료\n")
  }
}
res <- write_frontier_queue(Q)
cat("[fq167/168] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "착수 전 확인이 또 한 건 — 대기 중인 연구 두 건의 전제가 오염 등급 위에 있었습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "대기열 연구 2건이 인용하는 전략이 오늘 오후 벤치마크 오염 무효 판정을 받은 것을 확인했습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "확인: 착수 전 10분 읽기 검사에서 인용 재료의 오염 딱지를 발견했습니다",
           "원인: 벤치마크 데이터 이음매 결함 — 경계 하루가 -89% 로 왜곡됩니다",
           "영향: 그 전략의 등급 F 와 상대 성과 수치가 전부 무효입니다",
           "조치: 두 연구 항목에 폐쇄 주석을 달아 재측정 전 착수를 막았습니다",
           "의미: 무효 전제 위에 연구를 세우는 사고를 사전에 차단했습니다")),
    list(type = "kv", emoji = "📊", heading = "요지",
         kv = list(
           "대상"   = "섹터-중립 역전 게이팅 연구 2건 (미배정 유지)",
           "오염"   = "경계 하루 실측 -89.38% vs 참값 -6.19%",
           "무효"   = "등급 F · 정보계수 · 상대 성과 (벤치 의존 수치)",
           "생존"   = "최대낙폭 60.4% 는 재확인 대상",
           "해제조건" = "수리된 벤치마크로 재측정 완료 시")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "재측정은 벤치 수리 담당 레인의 재실행 큐를 따릅니다",
           "재측정 완료 시 주석을 해제하고 원래 가설로 복귀합니다",
           "판정: 자본 영향 없음 — 대기열 위생 조치입니다"))
  ),
  footer = "📚 FQ-167/168 사전 확인 · CONTAMINATED_benchmark_scale_seam.json",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
