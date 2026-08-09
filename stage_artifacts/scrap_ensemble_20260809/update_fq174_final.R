#!/usr/bin/env Rscript
# update_fq174_final.R — 소비면 순회 + 절대 천장 결과로 FQ-174 최종 갱신 (정본 writer)
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-174"); stopifnot(length(i) == 1)

Q$entries[[i]]$status <- "round_complete_fr002_registered_consumption_swept_20260809"

Q$entries[[i]]$ceiling_20260809 <- paste0(
  "★절대 PORT_t 천장 실측(p0n): 폐지 풀 완전예지 top-K 최대 +2.036(K=5) · 무작위탐색 1500회 +1.647 · ",
  "개별 최강 +2.226 — 85개 중 문턱 2.95 통과 0개. 대조 우량 풀은 동일 방법으로 완전예지 +3.545 · 개별 +3.923(13개 중 1개 통과) ",
  "⇒ 천장은 방법이 아니라 재료의 성질. FR_002 PIT 실측 1.242 = 천장의 61% (선별 규칙은 작동, 재료가 한계). ",
  "축소추정/ML 선별 정교화 방향은 천장에 막혀 철회 — 재료 교체(비-수익 원천 유입)만이 천장을 재산정한다."
)

Q$entries[[i]]$consumption_sweep_20260809 <- paste0(
  "소비면 7종 순회 완료(p2_consumption_sweep + p2b_filter, 헌법 4호 의무): ",
  "①랭킹 NEGATIVE(천장 2.04<2.95) ②★유니버스 필터 양성 후보 — 워크포워드 하위 배제 vs EW85: ",
  "하위10 t_NW3 +3.206(+0.062%/m)·하위20 +3.049(+0.103%/m)·하위30 +2.682(+0.132%/m). ",
  "MAX5 전례(랭킹 사망·필터 생존)의 모듈-레벨 재현. 기전 = 지속되는 것은 승자가 아니라 패자",
  "(IS 최악 4분위만 OOS 최악 유지 -0.79 vs -0.60~-0.67). ⚠basis 명시: 풀 EW 대비 상대 t 이지 자본 자격 아님 — ",
  "정당 소비처 = FR 풀 위생(RCMA admission 전 지속-패자 배제 전처리). ",
  "③오버레이 이관(WT-D20260809_002, beta 실측 3건) ④★위험모델 POSITIVE — trailing-36m→forward-12m beta ",
  "spearman rho 0.564(t 15.4, frac>0 0.968) = β예산/위험모델 신뢰 입력 ",
  "⑤monitoring 무판별(풀 산포 lift 0.95x — 기저 이하) ⑥라벨 처분 완료(FR_002 screen-tier) ",
  "⑦타 모드 이식 없음(RAMP return-derived 천장 공유·QEPM 종목-레벨 전용)."
)

Q$entries[[i]]$next_action <- paste0(
  "[NP-1] FR 풀 위생 규칙 승격 검토 — 지속-패자 배제(하위 10~20)를 run_wf_ensemble/RCMA 전처리로. ",
  "사전등록 후 FR_001 풀 확장판에서 A/B (basis = 앙상블 상대, 자본 주장 아님). ",
  "[NP-2] beta 지속성(rho 0.564)의 β예산 소비 — 노출 스케일 층(WT-D20260809_002)에 이관된 beta 실측과 결합, ",
  "위험모델 Σ 추정 입력으로 모듈-레벨 beta prior 공급 검토. ",
  "[NP-3] 재료 교체 — 비-수익 원천(DART insider 등) 모듈이 풀 유입 시 천장 재산정(v8.3 경로 ① 정합). ",
  "[종전 NP 처분] 축소추정/ML 선별 정교화 = 천장 2.04 에 막혀 철회. 국면 라벨 교체 축은 유지(라벨이 유일 병목)."
)

res <- write_frontier_queue(Q)
cat("[fq174-final] 갱신 완료. n=", res$n, " added=", length(res$added), " removed=", length(res$removed), "\n", sep="")
