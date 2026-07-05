## mega-cap 앵커/캡-해제 negative를 Axiom 엔진 Ledger에 emit (발판化).
## 실측 소스: cycle10/11 carrier(vs production ret_orig cor 1.0) build_benchmark_compare.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/axiom/lcode_emit.R"))
res <- fread(file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705/cycle11_cap_relax_results.csv"))
base_ovl <- res[tag=="BASE_prod+ovl0.5"]; a20 <- res[tag=="A2_w0.20_ovl0.5"]
a25 <- res[tag=="A2_w0.25_ovl0.5"]; a30 <- res[tag=="A2_w0.30_ovl0.5"]; a35 <- res[tag=="A2_w0.35_ovl0.5"]

lesson <- sprintf(paste0(
  "KR long-only 20종 book(STR_1715, K200∪KQ150): mega-cap 앵커 구성(top-2 by size 20%cap+알파fill)은 ",
  "production-fidelity(carrier vs bt ret_orig cor 1.0000·offset1 exact) 재측정서 book에 return-additive 아님. ",
  "(A) production book 자체가 이미 강함: BASE PORT_t %.2f·oos %.3f·calmar %.3f — 앞선 07-05 '앵커가 벽 뚫음'은 저-fidelity ",
  "LinearTilt 재구성(C0 PORT_t 3.83, cor 0.84)이 baseline 과소평가한 아티팩트. (B) 앵커는 벤치허깅(tracking-error 축소)이지 알파 추가 아님. ",
  "(C) 개별종목 20%%캡 해제 실측(도훈 지시 탐색): book-marginal ΔIR(ovl0.5 baseline 대비)이 캡 지점 0.20서 +%.3f로 최고, ",
  "풀수록 단조 악화(0.25 %+.3f / 0.30 %+.3f / 0.35 %+.3f) = 단일명 집중이 벤치추종 이득보다 위험을 더 키움. ",
  "즉 20%%캡은 binding 제약 아니며 해제는 성과 개선 안 함(제약이 실패 원인 아님, INV-7 방화벽). ",
  "(D) 앵커가 실제로는 'selected 중 top-2'라 삼성 28%%월만 앵커 = 벤치 지배 mega-cap 강제편입 의도 미구현."),
  base_ovl$PORT_t, base_ovl$oos_ret, base_ovl$calmar, a20$dIR_vs_base, a25$dIR_vs_base, a30$dIR_vs_base, a35$dIR_vs_base)

mech <- paste0(
  "메커니즘: post-2017 감쇠에 cap-weighted 벤치 아티팩트 성분 존재(동일 알파 EW벤치 대비 oos 생존) — 이 진단은 확립된 부수발견이자 ",
  "발판(신규 알파 기각 전 EW-bench oos 확인 규율). 그러나 그 아티팩트를 mega-cap 앵커로 공략하면 벤치허깅으로 tracking-error만 줄 뿐 ",
  "총수익/잔차알파 미추가. 20%cap+ 집중은 위험(단일명 semis 동반급락) > 벤치추종이득.")

fa <- list(
  list(test="production-fidelity 재측정(carrier vs bt ret_orig)", result="falsified",
       effect_retained=list(note=sprintf("cor 1.0로 검증한 BASE PORT_t %.2f가 재구성 4.76 대체 — 앵커 marginal 소멸(6.69 vs 6.66)", base_ovl$PORT_t))),
  list(test="개별종목 캡 sweep(0.20→0.35) book-marginal ΔIR", result="falsified",
       effect_retained=list(note=sprintf("ΔIR 단조 하락 +%.3f→%.3f = 캡 해제 무익", a20$dIR_vs_base, a35$dIR_vs_base))),
  list(test="앵커 종목 식별 감사(top-2 among selected)", result="weakened",
       effect_retained=list(note="삼성 selected 28%월만 = 벤치 mega-cap 앵커 의도 미구현, 정식 force-anchor는 forge 재실행 필요(미검)"))
)

r <- emit_lcode(
  mode="qepm_legacy",
  strategy_id="STR_MEGACAP_ANCHOR_CAPRELAX_20260706",
  grade="F",
  lesson_text=lesson,
  metric_type="canonical_screen",
  construction_type="megacap_anchor_construction",
  mechanism_hypothesis=mech,
  falsification_attempts=fa,
  oos_retention=as.numeric(a20$oos_ret),
  portfolio_alpha_t=as.numeric(a20$PORT_t),
  selection_type="chain",
  core_reference="stage_artifacts/pg2_overlay_gate_composition_20260705/cycle5-12*.R; [[project-megacap-anchor-construction-discovery]]",
  tags=c("MEGACAP_ANCHOR","CAP_RELAX_TESTED_NEGATIVE","BENCHMARK_HUGGING","CAP_WEIGHTED_BENCH_ARTIFACT_DIAGNOSIS","FORGE_FORCE_ANCHOR_UNTESTED")
)
cat("\n=== EMIT RESULT ===\n"); cat("l_code:", r$l_code %||% r$lcode %||% "(see obj)", "\n")
cat("path:", r$path %||% "(see obj)", "\n")
if(!is.null(r$firewall_violation)) cat("firewall_violation:", r$firewall_violation, "\n")
cat("validation:", r$valid %||% r$validation %||% "(ok)", "\n")
str(r, max.level=1)
