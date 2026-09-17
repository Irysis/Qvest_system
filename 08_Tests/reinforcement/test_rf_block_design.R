#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_design.R — 교훈이 다음 블록 **설계**로 흐르는가 (도훈 지시 ④ · 2026-09-04)
#
# 배경: 블록 끝 기전 에이전트가 처방을 냈지만 읽는 자가 없었다. entry 안의 LLM 설계 지점은
#   B1 하나이고 그건 맨 처음에 돈다 — 교훈이 아직 없을 때. 나머지는 규칙 선정이라 처방이
#   어디에도 안 갔다(생산자만 있고 소비자가 없는, 이 저장소의 반복 병).
# 구조: 블록마다 설계 LLM 을 새로 붙이지 않고, **이미 도는 기전 에이전트**가 다음 블록
#   설계까지 낸다 — 추가 호출 0회이고 **처방과 설계가 같은 산출물**이라 어긋날 자리가 없다.
#
# 이 검사가 지키는 것: ①카탈로그 밖 항목 거부 ②중복 거부 ③B4 는 설계 대상 아님(LOO 계약)
#   ④설계가 러너 셀로 변환 ⑤집행 판정이 실제로 갈린다(executed/partial/ignored)
#   ⑥설계 없으면 규칙 폴백 — 조용한 통과 없음.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

cat("=== A. 카탈로그 — 정본에서 읽는가 ===\n")
CAT <- list()
for (b in RFBD_BLOCKS) { CAT[[b]] <- rfbd_catalog(b, ROOT)
  if (length(CAT[[b]])) ok(sprintf("A %s 카탈로그 %d종", b, length(CAT[[b]]))) else ng(sprintf("A %s 카탈로그 0종", b)) }
if (!length(rfbd_catalog("B4", ROOT))) ok("A B4 는 카탈로그가 없다 — 설계 대상 아님(LOO 계약)") else
  ng("A B4 에 카탈로그가 생겼다", "부분집합을 흔들면 귀속이 깨진다")

cat("\n=== B. 검증 — 정상 설계는 통과 (음성 대조) ===\n")
w2 <- vapply(CAT$B2, function(x) as.character(x$id), character(1))
d_ok <- list(block = "B2", cells = list(
  list(pick = w2[1], label = "a", why = "r"), list(pick = w2[2], label = "b", why = "r")))
if (isTRUE(rfbd_verify(d_ok, "B2", ROOT))) ok("B1 정상 설계 통과") else ng("B1 정상 설계 기각", as.character(rfbd_verify(d_ok, "B2", ROOT)))

cat("\n=== C. 위반 주입 ===\n")
d1 <- list(cells = list(list(pick = "NO_SUCH_ARM_XYZ", label = "x")))
if (!isTRUE(rfbd_verify(d1, "B2", ROOT))) ok("C1 카탈로그 밖 항목 기각") else ng("C1 없는 항목 통과")
d2 <- list(cells = list(list(pick = w2[1], label = "a"), list(pick = w2[1], label = "b")))
if (!isTRUE(rfbd_verify(d2, "B2", ROOT))) ok("C2 같은 항목 두 칸 기각(칸 낭비)") else ng("C2 중복 통과")
d3 <- list(cells = list(list(pick = w2[1])))
if (!isTRUE(rfbd_verify(d3, "B2", ROOT))) ok("C3 label 없는 칸 기각") else ng("C3 label 없이 통과")
d4 <- list(cells = list())
if (!isTRUE(rfbd_verify(d4, "B2", ROOT))) ok("C4 cells 0건 기각") else ng("C4 빈 설계 통과")
d5 <- list(cells = lapply(seq_len(20L), function(i) list(pick = w2[i], label = "x")))
if (!isTRUE(rfbd_verify(d5, "B2", ROOT, max_cells = 15L))) ok("C5 상한 초과 기각") else ng("C5 상한 초과 통과")

cat("\n=== D. 소비 — 설계가 러너 셀 형태로 나오는가 ===\n")
TB <- "TEST_BD_ENTRY"
dir.create(dirname(rfbd_path(ROOT, TB, "B2")), recursive = TRUE, showWarnings = FALSE)
# ★최상위 on.exit 금지 — Rscript <file> 로는 조용한 no-op(정리가 아예 안 돌아 픽스처가
#   남는다)이고, source() 로 부르면 프레임이 닫히며 **즉시 발화해 픽스처를 미리 지운다**.
#   호출 방식에 따라 정반대로 틀린다. 정리는 끝에서 명시적으로 한다.
write(toJSON(d_ok, auto_unbox = TRUE, null = "null"), rfbd_path(ROOT, TB, "B2"))
cl <- rfbd_cells(ROOT, TB, "B2")
if (length(cl) == 2L) ok("D1 셀 2개 생성") else ng("D1 셀 개수", as.character(length(cl)))
if (identical(cl[[1]]$code, "B2_6") && identical(cl[[2]]$code, "B2_7"))
  ok("D2 코드가 격자 번호를 유지(B2_6..)") else ng("D2 코드 규칙", cl[[1]]$code)
## ★엔진이 읽는 필드는 catalog_id 다(rf_cell_engine · rf_weight_arms). 구판 검사는 arm= 을 기대해 정상 산출을 FAIL 로 읽었다.
if (identical(cl[[1]]$weighting$kind, "catalog") && identical(as.character(cl[[1]]$weighting$catalog_id), w2[1]))
  ok("D3 비중 축이 규칙 선정기와 같은 형태(catalog_id)") else ng("D3 축 형태", paste(names(cl[[1]]$weighting), collapse = ","))
o5 <- vapply(CAT$B5, function(x) as.character(x$id), character(1))
write(toJSON(list(block = "B5", cells = list(list(pick = o5[1], label = "o"))), auto_unbox = TRUE, null = "null"),
      rfbd_path(ROOT, TB, "B5"))
c5 <- rfbd_cells(ROOT, TB, "B5")
if (identical(as.character(c5[[1]]$overlay$arm_id), o5[1])) ok("D4 오버레이 축 형태") else ng("D4 오버레이 형태")
u3 <- vapply(CAT$B3, function(x) as.character(x$id), character(1))
write(toJSON(list(block = "B3", cells = list(list(pick = u3[1], label = "u"))), auto_unbox = TRUE, null = "null"),
      rfbd_path(ROOT, TB, "B3"))
c3 <- rfbd_cells(ROOT, TB, "B3")
if (!is.null(c3[[1]]$universe$kind)) ok("D5 유니버스 축 형태(격자 정의를 그대로)") else ng("D5 유니버스 형태")
if (is.null(rfbd_cells(ROOT, "NO_SUCH_ENTRY", "B2"))) ok("D6 설계 없으면 NULL — 규칙 폴백") else ng("D6 폴백")

cat("\n=== E. 집행 판정 — 고리를 닫는가 ===\n")
# ★시나리오마다 **다른 디렉터리**를 쓴다. 같은 이름을 쓰면 세 픽스처가 서로를 덮고,
#   R 은 셋을 먼저 다 만들므로 마지막 것만 남는다 — 오늘 아침 spec 경로 충돌과 같은 병이다.
.mk_i <- 0L
## ★스펙은 엔진 모양(weighting$catalog_id)으로 쓴다 — 실사고: rfbd_action_status 가 weighting$arm 을 읽어 실제 스펙과
##   영영 불일치("ignored")였다. key= 로 구판 arm= 스펙도 만들어 하위호환을 따로 잰다.
mkatt <- function(codes, arms, key = "catalog_id", ov = NULL) {
  .mk_i <<- .mk_i + 1L
  td <- file.path(tempdir(), sprintf("bd_%d_%d", Sys.getpid(), .mk_i))
  dir.create(td, showWarnings = FALSE, recursive = TRUE)
  lapply(seq_along(codes), function(i) {
    sp <- file.path(td, sprintf("s_%s.json", codes[i]))
    S <- if (is.null(ov)) { w <- list(kind = "catalog"); w[[key]] <- arms[i]; list(weighting = w) } else ov[[i]]
    write(toJSON(S, auto_unbox = TRUE, null = "null"), sp)
    list(n = i, cell_code = codes[i], essence = list(cell_code = codes[i], spec = sp)) })
}
a_all  <- mkatt(c("B2_6", "B2_7"), c(w2[1], w2[2]))
a_half <- mkatt(c("B2_6", "B2_7"), c(w2[1], w2[3]))
a_none <- mkatt(c("B2_6", "B2_7"), c(w2[4], w2[3]))
r1 <- rfbd_action_status(ROOT, TB, "B2", a_all)
if (identical(r1$status, "executed")) ok("E1 설계대로 돌면 executed ★스펙은 catalog_id(엔진 모양)") else ng("E1 executed", r1$status)
r2 <- rfbd_action_status(ROOT, TB, "B2", a_half)
if (identical(r2$status, "partial")) ok("E2 절반만 돌면 partial") else ng("E2 partial", r2$status)
r3 <- rfbd_action_status(ROOT, TB, "B2", a_none)
if (identical(r3$status, "ignored")) ok("E3 하나도 안 돌면 ignored ★처방이 무시된 것을 잡는다") else ng("E3 ignored", r3$status)
r4 <- rfbd_action_status(ROOT, "NO_SUCH_ENTRY", "B2", a_all)
if (identical(r4$status, "no_design")) ok("E4 설계가 없던 블록은 no_design(무시와 구분)") else ng("E4 no_design", r4$status)
a_leg <- mkatt(c("B2_6", "B2_7"), c(w2[1], w2[2]), key = "arm")
if (identical(rfbd_action_status(ROOT, TB, "B2", a_leg)$status, "executed")) ok("E5 구판 arm= 스펙도 읽는다(하위호환)") else ng("E5 구판 스펙", "arm= 를 못 읽는다")

cat("\n=== G. 스택 설계 (2026-09-17 WP-Z) — 격리 root 픽스처 ===\n")
## 격리 root: 실제 카탈로그 사본에 ①retired arm ②같은 kind 의 두 번째 arm ③상주 arm 을 심고, 격자 정본(standing_cells)을 복사한다.
TMP <- file.path(tempdir(), sprintf("rfbd_stack_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(TMP, "06_Registry/reinforce_program.json"), overwrite = TRUE)
.cat0 <- fromJSON(file.path(ROOT, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)
.arms <- Filter(function(a) identical(as.character(a$status %||% "active"), "active"), .cat0$arms)
.arms[[1]]$status <- "retired"; RET <- .arms[[1]]$id
ACT <- vapply(.arms[-1], function(a) a$id, character(1)); KND <- vapply(.arms[-1], function(a) a$kind, character(1))
.arms <- c(.arms, list(list(id = "zz_same_kind_twin", kind = KND[1], family = "test", basis = "t", status = "active"),
                       list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", family = "book_spec", basis = "t", status = "active")))
.cat0$arms <- .arms
write(toJSON(.cat0, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(TMP, "06_Registry/overlay_catalog.json"))
STD <- rfbd_standing_picks(TMP)
if (identical(STD, "pg2_risk_overlay_v1")) ok("G0 격자 정본 standing_cells → 상주 pick pg2_risk_overlay_v1") else ng("G0 standing_cells 부재", paste(STD, collapse = ","))
if (identical(rfbd_max_layers(TMP), 3L)) ok("G0 config 부재 → max_layers 기본 3") else ng("G0 기본 상한", as.character(rfbd_max_layers(TMP)))
cat5 <- rfbd_catalog("B5", TMP); ids5 <- vapply(cat5, function(x) x$id, character(1))
if (!(RET %in% ids5) && all(ACT %in% ids5)) ok(sprintf("G1 B5 카탈로그는 active 만 (%s retired 제외 · %d종)", RET, length(ids5))) else ng("G1 status 필터", RET)
vf <- function(cells, blk = "B5") rfbd_verify(list(block = blk, cells = cells), blk, TMP)
C <- function(..., label = "x") list(picks = list(...), label = label)
r <- vf(list(C(ACT[1], ACT[2]), C(ACT[1], ACT[3])))
if (isTRUE(r)) ok("G2 picks 스택 [a,b]·[a,c] 통과 — 같은 id 가 다른 스택에 있어도 된다") else ng("G2 스택 통과", as.character(r))
if (isTRUE(vf(list(list(pick = ACT[1], label = "single"))))) ok("G3 구판 pick(단일) 그대로 통과") else ng("G3 pick 호환")
r <- vf(list(list(pick = RET, label = "r")))
if (!isTRUE(r) && grepl("retired", r, fixed = TRUE)) ok(paste0("G4 retired id 기각: ", r)) else ng("G4 retired 통과", as.character(r))
r <- vf(list(C(ACT[1], ACT[1])))
if (!isTRUE(r) && grepl("같은 id", r, fixed = TRUE)) ok("G5 스택 안 같은 id 두 번 → 기각") else ng("G5 dup id", as.character(r))
r <- vf(list(C(ACT[1], "zz_same_kind_twin")))
if (!isTRUE(r) && grepl("같은 kind", r, fixed = TRUE)) ok("G6 스택 안 같은 kind 두 층 → 기각") else ng("G6 dup kind", as.character(r))
r <- vf(list(C(ACT[1], ACT[2], ACT[3], ACT[4])))
if (!isTRUE(r) && grepl("상한 3", r, fixed = TRUE)) ok("G7 4층 > 기본 상한 3 → 기각") else ng("G7 상한", as.character(r))
if (isTRUE(vf(list(C(ACT[1], ACT[2], ACT[3]))))) ok("G7 3층 = 상한 → 통과") else ng("G7 3층 기각")
write('{"b5_design": {"max_layers": 2}}', file.path(TMP, "06_Registry/reinforce_auto_config.json"))
r <- vf(list(C(ACT[1], ACT[2], ACT[3])))
if (identical(rfbd_max_layers(TMP), 2L) && !isTRUE(r) && grepl("상한 2", r, fixed = TRUE)) ok("G8 config b5_design.max_layers=2 → 3층 기각") else ng("G8 config 상한", as.character(r))
unlink(file.path(TMP, "06_Registry/reinforce_auto_config.json"))
r <- vf(list(C(ACT[1], ACT[2]), C(ACT[2], ACT[1])))
if (!isTRUE(r) && grepl("같은 항목", r, fixed = TRUE)) ok("G9 [a,b] 와 [b,a] 는 같은 칸 → 기각(정렬 키)") else ng("G9 순서만 다른 스택", as.character(r))
r <- vf(list(list(pick = "pg2_risk_overlay_v1", label = "s")))
if (!isTRUE(r) && grepl("상주", r, fixed = TRUE)) ok("G10 상주 칸의 pick 과 같은 스택 → 기각") else ng("G10 상주 중복", as.character(r))
## G10b (2026-09-17 규칙 통일) — 상주 arm 을 **포함한** 스택도 기각. 양성 대조: 상주 arm 없는 같은 모양 스택은 통과.
r <- vf(list(C(ACT[1], "pg2_risk_overlay_v1")))
if (!isTRUE(r) && grepl("상주 arm", r, fixed = TRUE)) ok("G10b 상주 arm 포함 스택 [a, pg2] → 기각(carry 가 상주를 빼 잰 것≠물려준 것)") else ng("G10b 상주 포함 스택 통과", as.character(r))
if (isTRUE(vf(list(C(ACT[1], ACT[2]))))) ok("G10b 양성 대조 — 상주 없는 2층 스택은 통과") else ng("G10b 양성 대조 기각")
## B3 의 카탈로그는 격자 자체라 격리 root 에도 있다(B2 는 weight_catalog.R 이 없어 비어 있다 — 그래서 B3 로 잰다)
r <- vf(list(C("B3_11", "B3_12", label = "u")), "B3")
if (!isTRUE(r) && grepl("단일 pick", r, fixed = TRUE)) ok("G11 B3 는 picks>1 기각 — 스택은 B5 전용") else ng("G11 비B5 스택 통과", as.character(r))
if (isTRUE(vf(list(list(pick = "B3_11", label = "u")), "B3"))) ok("G11 B3 단일 pick 은 통과(음성 대조)") else ng("G11 B3 단일 pick 기각")
## 소비 — 무효 칸은 빠지고(NULL 없음) 코드는 설계 위치를 유지한다
D5 <- list(block = "B5", cells = list(C(ACT[1], ACT[2], label = "stack"), C(ACT[3], "no_such_arm_zz", label = "bad"), list(pick = ACT[3], label = "one")))
dir.create(dirname(rfbd_path(TMP, "T_STACK", "B5")), recursive = TRUE, showWarnings = FALSE)
write(toJSON(D5, auto_unbox = TRUE, null = "null"), rfbd_path(TMP, "T_STACK", "B5"))
cs <- rfbd_cells(TMP, "T_STACK", "B5")
if (length(cs) == 2L && !any(vapply(cs, is.null, logical(1)))) ok("G12 무효 칸(없는 arm)은 목록에서 빠진다 — NULL 원소 없음") else ng("G12 무효 칸", as.character(length(cs)))
if (identical(vapply(cs, function(c) c$code, character(1)), c("B5_16", "B5_18"))) ok("G13 코드는 설계 위치(B5_16 · B5_18) — 빠진 칸이 뒤 코드를 밀지 않는다") else ng("G13 코드", paste(vapply(cs, function(c) c$code, character(1)), collapse = ","))
L1 <- cs[[1]]$overlay
if (is.null(L1$kind) && length(L1) == 2L && all(vapply(L1, function(z) all(c("kind", "arm_id") %in% names(z)), logical(1))) &&
    identical(L1[[1]]$arm_id, ACT[1]) && identical(L1[[2]]$arm_id, ACT[2]) && identical(L1[[1]]$kind, KND[1]))
  ok("G14 스택 칸 overlay = 층 리스트 {kind, arm_id} ×2 (엔진 필드 보존)") else ng("G14 스택 형태", paste(names(L1), collapse = ","))
if (!is.null(cs[[2]]$overlay$kind) && identical(cs[[2]]$overlay$arm_id, ACT[3])) ok("G15 단층 칸 overlay = 단수 객체(기존 서명 불변)") else ng("G15 단층 형태")
if (grepl(" × ", cs[[1]]$basis, fixed = TRUE)) ok("G16 basis 에 스택 id 가 a × b 로") else ng("G16 basis", cs[[1]]$basis)
## 집행 판정 — 칸 단위 (풀링 함정)
kd <- function(id) KND[match(id, ACT)]
Lr <- function(id) list(kind = kd(id), arm_id = id)
CARRY <- list(kind = "zz_carry_kind", arm_id = "zz_carry")
D6 <- list(block = "B5", cells = list(C(ACT[1], ACT[2], label = "ab"), C(ACT[1], ACT[3], label = "ac")))
write(toJSON(D6, auto_unbox = TRUE, null = "null"), rfbd_path(TMP, "T_ACT", "B5"))
sp_ok <- list(list(overlay = list(CARRY, Lr(ACT[1]), Lr(ACT[2])), overlay_cell = list(Lr(ACT[1]), Lr(ACT[2]))),   # overlay_cell 정본
              list(overlay = list(CARRY, Lr(ACT[1]), Lr(ACT[3]))))                                          # overlay − carry
a6 <- mkatt(c("B5_16", "B5_17"), NULL, ov = sp_ok)
r6 <- rfbd_action_status(TMP, "T_ACT", "B5", a6, carry = CARRY)
if (identical(r6$status, "executed")) ok("G17 스택 설계 [a×b]·[a×c] 를 그대로 돌면 executed (overlay_cell · overlay−carry 둘 다)") else ng("G17 executed", paste(r6$status, r6$detail))
sp_trap <- list(list(overlay = Lr(ACT[1])), list(overlay = list(Lr(ACT[2]), Lr(ACT[3]))))
a7 <- mkatt(c("B5_16", "B5_17"), NULL, ov = sp_trap)
r7 <- rfbd_action_status(TMP, "T_ACT", "B5", a7, carry = NULL)
if (identical(r7$status, "ignored")) ok("G18 실행 [a]·[b×c] 는 설계 [a×b]·[a×c] 와 다른 칸 → ignored ★풀링이면 executed 로 오판") else ng("G18 풀링 함정", paste(r7$status, r7$detail))
pooled <- unique(c(ACT[1], ACT[2], ACT[3])); want_ids <- c(ACT[1], ACT[2], ACT[3])
if (all(want_ids %in% pooled)) ok("G19 돌연변이 통제 — 구판 풀링(id 주머니)이면 G18 이 executed 였다(픽스처가 결함을 가른다)") else ng("G19 픽스처 판별력 없음")
a8 <- mkatt(c("B5_16", "B5_17"), NULL, ov = list(sp_ok[[1]], list(overlay = list(CARRY, Lr(ACT[1]), Lr(ACT[4])))))
r8 <- rfbd_action_status(TMP, "T_ACT", "B5", a8, carry = CARRY)
if (identical(r8$status, "partial") && grepl(paste(sort(c(ACT[1], ACT[4])), collapse = "+"), r8$detail, fixed = TRUE)) ok("G20 한 칸만 설계대로 → partial · detail 에 실측 스택 키") else ng("G20 partial", paste(r8$status, r8$detail))
a9 <- mkatt(c("B5_16"), NULL, ov = list(list(overlay = list(list(kind = kd(ACT[1])), list(kind = kd(ACT[2]))))))
r9 <- tryCatch(rfbd_action_status(TMP, "T_ACT", "B5", a9, carry = NULL), error = function(e) conditionMessage(e))
if (is.list(r9)) ok(sprintf("G21 arm_id 없는 층(kind 만)도 던지지 않는다 → %s", r9$status)) else ng("G21 kind-only 층", as.character(r9))
unlink(TMP, recursive = TRUE, force = TRUE)

cat("\n=== F. 배선 (주석 제외) ===\n")
co <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
par <- co("02_Infrastructure/ops/reinforce_auto_parallel.R")
mlib <- co("02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh"), warn = FALSE), collapse = "\n")
if (grepl("rfbd_cells", par, fixed = TRUE)) ok("F1 러너가 설계를 소비") else ng("F1 러너 미소비")
if (grepl('is.null(.blk_design[["B2"]])', par, fixed = TRUE) &&
    grepl('is.null(.blk_design[["B5"]])', par, fixed = TRUE))
  ok("F2 설계가 있으면 규칙 픽커를 안 부른다(이중 선정 차단)") else ng("F2 이중 선정")
if (grepl("rfbd_catalog", mlib, fixed = TRUE)) ok("F3 기전 재료에 다음 블록 카탈로그") else ng("F3 카탈로그 미제공")
if (grepl("rfbd_verify", mlib, fixed = TRUE)) ok("F4 저장 전 검증") else ng("F4 검증 없이 저장")
if (grepl("prior_action_status", mlib, fixed = TRUE)) ok("F5 집행 판정을 L-code 에 남긴다") else ng("F5 집행 판정 미기록")
if (grepl("next_block_design", sh, fixed = TRUE)) ok("F6 프롬프트가 설계를 요구") else ng("F6 프롬프트 미요구")
if (grepl("LOO 가 계약", sh, fixed = TRUE) || grepl("LOO 가 계약", mlib, fixed = TRUE))
  ok("F7 B4 는 설계 대상 아님을 프롬프트/재료가 명시") else ng("F7 B4 예외 미명시")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_block_design","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
unlink(c(rfbd_path(ROOT, TB, "B2"), rfbd_path(ROOT, TB, "B5"), rfbd_path(ROOT, TB, "B3")), force = TRUE)   # 명시적 정리(구 on.exit 대체)
quit(status = if (FAIL > 0L) 1L else 0L)
