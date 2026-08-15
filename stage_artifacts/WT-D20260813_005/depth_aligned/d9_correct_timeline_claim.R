## D9 — ★자기적발 정정: D6 의 "재료가 죽었다" 는 basis 의존적 진술이었다 (No Silent Override)
##
## D6 은 cap-w 활성만 보고 "sp3 에서 4개 arm 전부 음수 ⇒ 선별할 알파가 사라졌다" 로 썼다.
## D7/D8 이 그 결론을 반증했다: EW-유니버스 basis 에서는 sp3 음수 arm 이 1/4 뿐이다.
## ⇒ 결론을 철회하고 "basis 의존 · 미해결" 로 교체한다. primary 판정은 불변.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R")
DOUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"
V  <- fromJSON(file.path(DOUT, "alpha_validation_depth.json"), simplifyVector = FALSE)
B  <- fromJSON(file.path(DOUT, "d8_basis_dependence.json"),    simplifyVector = FALSE)
S  <- as.data.table(do.call(rbind, lapply(B$sp3_by_basis, as.data.frame)))
P  <- as.data.table(do.call(rbind, lapply(B$paired_by_basis, as.data.frame)))

V$mechanism_timeline$basis_dependence_check <- list(
  why = "D6 의 '재료 사망' 결론이 cap-w 단일 basis 위에 있었다. v8.3 dual-basis 의무(기각·결론 전 EW-대비 확인)를 뒤늦게 적용해 반증됨.",
  sp3_negative_arm_count = list(capw = S[basis=="capw" & mean < 0, .N], ew = S[basis=="ew" & mean < 0, .N], of = 4),
  sp3_mean_active = list(
    capw = list(OBJ_RANK = S[basis=="capw" & arm=="OBJ_RANK", mean], OBJ_MEAN_DEPTH = S[basis=="capw" & arm=="OBJ_MEAN_DEPTH", mean]),
    ew   = list(OBJ_RANK = S[basis=="ew"   & arm=="OBJ_RANK", mean], OBJ_MEAN_DEPTH = S[basis=="ew"   & arm=="OBJ_MEAN_DEPTH", mean])),
  paired_primary_is_basis_invariant = list(
    capw_t = P[basis=="capw", t], ew_t = P[basis=="ew", t],
    note = "★paired 설계의 부수 이득 — 벤치가 차분에서 상쇄돼 primary 는 basis 에 거의 불변(1.5706 vs 1.5709). 따라서 판정은 벤치 구성 논쟁과 독립이다. sp3 paired 도 두 basis 모두 −0.32 로 동일."),
  ew_caveat = "EW t 는 계약이 명시하듯 se_shrink 채널을 포함한다(전 arm 지배채널 se_shrink, t배율 1.37~1.68) — 알파 증거가 아니다. 따라서 'EW 에서 양수니 재료는 살아 있다' 도 주장하지 않는다.",
  corrected_reading = "sp3 활성 소멸은 **basis 의존**이며 원인(재료 감쇠 vs 벤치 구성 = 2020+ mega-cap 지배)은 본 라운드가 가르지 못한다. D6 의 '선별할 알파가 사라졌다' 는 철회한다.")

V$mechanism_timeline$verdict <- paste0(
  "(수정) 연료(왜도·갈림)는 감쇠하지 않았다 — 이 부분은 유지(구조 관측이라 basis 무관). ",
  "그러나 '재료의 활성이 죽었다' 는 cap-w basis 에서만 성립하며 EW-유니버스에서는 sp3 음수 arm 1/4 뿐이다 ⇒ **미해결**. ",
  "확립된 것은 좁다: paired 차이(DEPTH−RANK)의 sp3 소멸은 두 basis 모두에서 유지된다(−0.32 / −0.32).")
V$mechanism_timeline$consequence <- paste0(
  "pooled t +1.5706 은 sp1 신호와 sp3 무신호를 섞은 값이다(판정 불변). 재료 축 라우팅의 근거는 ",
  "'재료가 죽었다' 가 아니라 '이 프레임의 선별 축이 sp1 이후 구간에서 이득을 재현하지 못한다' 로 좁혀 서술한다.")

V$routing$next_probe[[5]] <- paste0(
  "P5 (신규, 재료 축 판정의 전제 조건): '월간 return-파생 320종의 활성 소멸' 은 **basis 의존**이라 미해결이다 ",
  "(cap-w sp3 음수 4/4 vs EW 1/4). 벤치 구성(2020+ mega-cap 지배)과 재료 감쇠를 가르려면 ",
  "cap-tier 분해(MEGA top-10 / MID 11-30 / OTHER — canonical_screen_bt diag_cap_tier 이미 산출) 를 sp3 에 국한해 읽고, ",
  "EW-대비 t 는 se_shrink 채널을 뺀 mean_shift 채널로만 해석해야 한다. 본 라운드 데이터로 판정 금지(사후선택) — 새 사전등록 필요.")
V$challenge_flags[[9]] <- paste0(
  "CF9 ★자기적발 정정 — 초판(d6)에서 'sp3 에 4개 arm 전부 음수 ⇒ 선별할 알파가 사라졌다' 로 썼으나, ",
  "EW-유니버스 basis 확인(v8.3 dual-basis 의무)에서 sp3 음수는 1/4 뿐이었다. 결론 철회 후 'basis 의존·미해결' 로 교체. ",
  "부수 소득: paired primary 는 basis 불변(1.5706 vs 1.5709)이라 판정 자체는 벤치 논쟁과 독립.")

V$patch_log[[length(V$patch_log) + 1]] <- list(at = format(Sys.time()), by = "d9_correct_timeline_claim.R",
  what = "mechanism_timeline.verdict/consequence 정정 + basis_dependence_check 추가 + next_probe P5 교체 + CF9 신설",
  unchanged = "primary_endpoint / verdict / 문턱 / falsification / detection_power / three_way_comparison / robustness 불변",
  reason = "자기 반증 — D6 결론이 단일 basis 위에 있었고 D7/D8 이 반증. Charter 원칙 8(No Silent Override): 조용히 고치지 않고 철회 사실을 남긴다.")

write_json(V, file.path(DOUT, "alpha_validation_depth.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("정정 반영: primary 불변 (t %+.4f / %s) · CF %d건 · patch_log %d건\n",
            V$primary_endpoint$nw3_t, V$primary_endpoint$verdict, length(V$challenge_flags), length(V$patch_log)))
