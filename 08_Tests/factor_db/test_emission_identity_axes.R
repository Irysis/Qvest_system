#==============================================================================
# test_emission_identity_axes.R — emission_guard 정체 검사 3축(D/T/I) 상설 검사
#
# 왜 있나 (FQ-210, 2026-08-09):
#   emission_guard v1.0 은 `n_rows > 0` 만 봤다. **존재**를 확인했을 뿐 **정체**를
#   확인하지 않았으므로 다음 둘을 원리적으로 못 봤다:
#     · 다른 팩터와 값이 같은 배출 — C01≡C10 · C04≡C13 · C11≡M25 · C01≡C09 · C09≡C10
#     · 행은 나오는데 횡단면 상수라 소비면 도달 0인 배출 —
#       C15_Forecast_Error_Trend 50/50월 · D60_Leverage·Q16_Debt_to_Assets 각 22/53월
#       (= 2015-06~2025-12 연속 11년 동안 월 2,753~2,968행을 내면서 소비자에겐 0행)
#   3축을 배선했으므로, 그 축들이 **살아 있는지**를 이 검사가 지킨다.
#
# ★이 파일의 존재 이유가 되는 사고 (계측 사망):
#   FQ-210 초판이 "죽은 배출"의 판별통계로 sd(Z_Score) 를 썼다. Z 는 횡단면 표준화
#   산물이라 331종 전부 정확히 1.0000 — 판별력이 **원리적으로 0**인 통계였다.
#   그런데 산출물은 "죽은 배출 0종"이라는 결론처럼 생긴 문자열이었다.
#   ⇒ 축 Z 가 이 계통을 못박는다: 죽은 통계가 실제로 죽어 있음을 실측하고,
#     가드가 그것에 의존하지 않음을 돌연변이로 실증한다.
#   ⇒ "경보 0"과 "측정 불가"는 다른 상태다(UNMEASURED). 축 U 가 그 계약을 잰다.
#
# 구조 8축:
#   P. 실패널 확보    — 이후 모든 실데이터 축의 기준선 (0 을 스킵으로 읽지 않는다)
#   V. 위반 주입 4종  — ①비트동일 ②단조변환 ③전건 상수 ④99.5% 동일
#   N. 음성 대조      — 기확정 결함(C01≡C10 · C04≡C13 · C15)을 실제로 잡는가
#   G. 양성 대조      — 정상 팩터가 같은 실행에서 정상으로 남는가 (과민 아님)
#   X. 면제           — 시장레벨 15종이 DEAD_EMISSION 으로 오분류되지 않는가 (양방향)
#   Z. 죽은 통계      — sd(Z)=1 항등 실측 + 가드가 그것에 의존하지 않음 (돌연변이)
#   U. UNMEASURED     — 못 재는 상태를 '이상 없음'으로 내려앉히지 않는가
#   W. 배선           — 빌더가 정체 축을 실제로 켜서 호출하는가
#
# 단독 실행: Rscript 08_Tests/factor_db/test_emission_identity_axes.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  marker <- "02_Infrastructure/factor_db/emission_guard.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

GUARD_SRC   <- "02_Infrastructure/factor_db/emission_guard.R"
BUILDER_SRC <- "02_Infrastructure/factor_db/factor_db_builder.R"
REGISTRY    <- "02_Infrastructure/factor_db/factor_registry.json"
IDBASE      <- "02_Infrastructure/factor_db/emission_declared_identity.json"
LEDGER      <- ".cache/factor_db/emission_ledger.csv"

PASS <- 0L; FAIL <- 0L
ok  <- function(id, msg) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %-36s %s\n", id, msg)) }
bad <- function(id, msg) { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %-36s %s\n", id, msg)) }

suppressMessages(source(GUARD_SRC))

DEDUP <- emission_dedup_pairs(REGISTRY)
IDB   <- emission_load_identity_baseline(IDBASE)

#==============================================================================
cat("\n=== P. 실패널 확보 — 이후 실데이터 축의 기준선 ===\n")
#==============================================================================
# ★실패널을 못 얻으면 **스킵이 아니라 실패**로 계상한다. 이 저장소의 반복 사고
#   계통("빈 결과 = 합격")을 여기서 되풀이하지 않는다 — 대조군 없는 초록은
#   검사가 살아 있다는 증거가 아니다.
PANEL_DATE <- as.Date("2026-06-30")
panel <- NULL; panel_ym <- NA_character_; dead_ledger <- NULL
try({
  suppressMessages(suppressWarnings({
    source("02_Infrastructure/config.R")
    source("02_Infrastructure/factor_db/factor_db_connector.R")
    z <- load_month_factors(PANEL_DATE, coverage_min = 0)
  }))
  panel_ym <- sub("^factor_db_([0-9]{6})[.]parquet$", "\\1", attr(z, "factor_db_file"))
  zt <- as.data.table(z)
  # 커넥터는 Coverage==TRUE & !is.na(Z_Score) 만 반환(factor_db_connector.R:261)
  # → 이게 곧 소비면. Z_Score_Aligned 는 Z_Score 의 부호반전·양수배이므로
  #   랭크/동률 구조가 보존된다(축 T·I 계산값 동일).
  panel <- zt[, .(Ticker, Factor_Name, Raw_Value = Z_Score_Aligned,
                  Z_Score = Z_Score_Aligned, Coverage = TRUE)]
  if (file.exists(LEDGER)) {
    led <- fread(LEDGER, colClasses = list(character = "ym"))
    dead_ledger <- led[ym == panel_ym & n_rows > 0 & !Factor_Name %in% unique(zt$Factor_Name)]
  }
}, silent = TRUE)

HAVE_PANEL <- !is.null(panel) && nrow(panel) > 0L
if (HAVE_PANEL) {
  ok("P1_real_panel_loaded", sprintf("%s · %s행 · %d팩터 · %d종목", panel_ym,
     format(nrow(panel), big.mark = ","), uniqueN(panel$Factor_Name), uniqueN(panel$Ticker)))
} else {
  bad("P1_real_panel_loaded", "★실패널 미확보 — 실데이터 대조 축이 전부 공허해진다 (스킵 아님, 실패로 계상)")
}

# 죽은 배출 행 합성: 원장 배출 O · 커넥터 비가시 = Coverage FALSE (빌더 result 와 동형)
mk_full <- function(p) {
  if (is.null(dead_ledger) || nrow(dead_ledger) == 0L) return(p)
  tick <- unique(p$Ticker)
  dr <- rbindlist(lapply(seq_len(nrow(dead_ledger)), function(i) {
    n <- max(min(dead_ledger$n_tickers[i], length(tick)), 1L)
    data.table(Ticker = tick[seq_len(n)], Factor_Name = dead_ledger$Factor_Name[i],
               Raw_Value = 1.0, Z_Score = NA_real_, Coverage = FALSE)
  }))
  rbindlist(list(p, dr), use.names = TRUE)
}
FULL <- if (HAVE_PANEL) mk_full(panel) else NULL

# ★기준 판정 1회 — 음성·양성 대조가 **같은 실행·같은 호출**을 공유한다
BASE <- if (HAVE_PANEL) factor_identity_check(FULL, panel_ym, dedup_pairs = DEDUP,
                                              identity_baseline = IDB) else NULL
if (HAVE_PANEL) {
  ok("P2_base_verdict", sprintf("D 미선언 %d (선언 %d) · T warn %d/watch %d · I hit %d 중 미선언 %d → %s",
     length(BASE$axis_D$dead), length(BASE$axis_D$dead_declared),
     length(BASE$axis_T$tie_warn), length(BASE$axis_T$tie_watch),
     BASE$axis_I$n_pairs_hit, nrow(BASE$axis_I$undeclared), BASE$verdict))
}

#==============================================================================
cat("\n=== V. 위반 주입 4종 — 검사기가 진짜 위반을 잡는가 ===\n")
#==============================================================================
BASE_F <- "M26_Revenue_Mom"
if (!HAVE_PANEL || !BASE_F %in% panel$Factor_Name) {
  bad("V0_injection_base", sprintf("주입 기준 팩터 %s 부재 — 위반 주입 축 전부 공허", BASE_F))
} else {
  src <- panel[Factor_Name == BASE_F]
  n <- nrow(src)
  inj <- rbindlist(list(
    # ① 비트-동일 복제
    copy(src)[, Factor_Name := "INJ1_BITWISE"],
    # ② 단조변환 복제 — 값은 크게 다르나 **순위는 동일**
    copy(src)[, `:=`(Factor_Name = "INJ2_MONOTONE",
                     Z_Score = exp(Z_Score), Raw_Value = exp(Raw_Value))],
    # ④ 99.5% 동일값 (③ 은 Coverage 축이 달라 별도)
    copy(src)[, `:=`(Factor_Name = "INJ4_MODE995",
                     Z_Score = c(rep(0, floor(n * 0.995)), Z_Score[seq_len(n - floor(n * 0.995))]))][
                     , Raw_Value := Z_Score],
    # ③-a 전건 상수인데 Coverage TRUE → 축 T 가 잡아야 한다
    copy(src)[, `:=`(Factor_Name = "INJ3_CONST_COVERED", Z_Score = 0, Raw_Value = 0)],
    # ③-b 전건 상수 → 빌더가 Z=NA/Coverage=FALSE 로 번역한 상태 → 축 D 가 잡아야 한다
    copy(src)[, `:=`(Factor_Name = "INJ3_CONST_DEAD", Z_Score = NA_real_,
                     Raw_Value = 1.0, Coverage = FALSE)]
  ), use.names = TRUE)
  RINJ <- factor_identity_check(rbindlist(list(FULL, inj), use.names = TRUE),
                                panel_ym, dedup_pairs = DEDUP, identity_baseline = IDB)
  und <- RINJ$axis_I$undeclared
  hit_pair <- function(f) if (nrow(und) == 0L) NA_real_ else {
    h <- und[(factor_a == BASE_F & factor_b == f) | (factor_a == f & factor_b == BASE_F)]
    if (nrow(h)) h$abs_rho[1] else NA_real_
  }
  # 측정치를 함께 기록한다 — 검거 여부만으로는 왜 잡혔는지 읽을 수 없다
  md <- function(f) {
    x <- src$Z_Score; y <- inj[Factor_Name == f][match(src$Ticker, Ticker), Z_Score]
    k <- is.finite(x) & is.finite(y); if (!any(k)) NA_real_ else max(abs(x[k] - y[k]))
  }
  r1 <- hit_pair("INJ1_BITWISE")
  if (!is.na(r1) && r1 >= 0.999) ok("V1_bitwise_dup", sprintf("|rho| %.6f · maxdiff %.3e → 축 I 검거", r1, md("INJ1_BITWISE")))
  else bad("V1_bitwise_dup", "비트-동일 복제를 축 I 가 못 잡음")

  r2 <- hit_pair("INJ2_MONOTONE"); m2 <- md("INJ2_MONOTONE")
  if (!is.na(r2) && r2 >= 0.999) {
    ok("V2_monotone_dup", sprintf("|rho| %.6f · maxdiff %.2f → 랭크 축으로 검거", r2, m2))
  } else {
    bad("V2_monotone_dup", "★단조변환 복제 미검거 — 값 축만 보고 있다")
  }
  # ★핵심: 값 축(maxdiff==0)만으로는 ② 를 원리적으로 놓친다는 실증
  if (!is.na(m2) && m2 > 1) {
    ok("V2b_value_axis_would_miss", sprintf("maxdiff %.2f > 0 이므로 값-동일 판정으론 놓친다 — 랭크 축이 필수", m2))
  } else {
    bad("V2b_value_axis_would_miss", sprintf("maxdiff %.3e — 주입 ② 가 단조변환 사례가 못 됨(픽스처 결함)", m2))
  }

  tw <- RINJ$axis_T$tie_warn
  tdet <- RINJ$axis_T$detail
  mf <- function(f) { v <- tdet[Factor_Name == f, modal_frac]; if (length(v)) v[1] else NA_real_ }
  if ("INJ3_CONST_COVERED" %in% tw) {
    ok("V3_all_constant_covered", sprintf("modal_frac %.4f → 축 T 검거", mf("INJ3_CONST_COVERED")))
  } else {
    bad("V3_all_constant_covered", "전건 상수(커버됨)를 축 T 가 못 잡음")
  }
  if ("INJ3_CONST_DEAD" %in% RINJ$axis_D$dead) {
    ok("V3b_all_constant_dead", "Coverage 전건 FALSE → 축 D 검거 (축 T 와 상보)")
  } else {
    bad("V3b_all_constant_dead", "무분산 배출을 축 D 가 못 잡음")
  }
  if ("INJ4_MODE995" %in% tw) {
    ok("V4_mode_995", sprintf("modal_frac %.4f (>= 0.99) → 축 T 검거", mf("INJ4_MODE995")))
  } else {
    bad("V4_mode_995", sprintf("99.5%% 동일값 미검거 (modal_frac %.4f)", mf("INJ4_MODE995")))
  }

  # 돌연변이로 검출력 실증 — 선언 대조를 지우면 경보가 소음으로 폭발한다
  RNODECL <- factor_identity_check(rbindlist(list(FULL, inj), use.names = TRUE),
                                   panel_ym, dedup_pairs = character(0), identity_baseline = IDB)
  if (nrow(RNODECL$axis_I$undeclared) > nrow(und) * 3) {
    ok("V5_declaration_is_load_bearing",
       sprintf("선언 대조 제거 시 미선언 %d→%d쌍 (%.1f배) — 대조가 경보를 실제로 줄이고 있다",
               nrow(und), nrow(RNODECL$axis_I$undeclared),
               nrow(RNODECL$axis_I$undeclared) / max(nrow(und), 1)))
  } else {
    bad("V5_declaration_is_load_bearing",
        sprintf("선언 대조를 지워도 경보량 불변 (%d→%d) — registry dedup 을 안 읽고 있다",
                nrow(und), nrow(RNODECL$axis_I$undeclared)))
  }
}

#==============================================================================
cat("\n=== N. 음성 대조 — 기확정 결함을 실제로 잡는가 ===\n")
#==============================================================================
if (!HAVE_PANEL) {
  bad("N0_negative_controls", "실패널 부재로 음성 대조 불가")
} else {
  und <- BASE$axis_I$undeclared
  chk_pair <- function(id, a, b) {
    h <- if (nrow(und) == 0L) und else und[(factor_a == a & factor_b == b) | (factor_a == b & factor_b == a)]
    if (nrow(h)) ok(id, sprintf("%s ~ %s 검거 (|rho| %.6f)", a, b, h$abs_rho[1]))
    else         bad(id, sprintf("★%s ~ %s 미검거 — 기확정 중복을 놓침", a, b))
  }
  chk_pair("N1_C01_eq_C10", "C01_SUE", "C10_SUE_Persistence")
  chk_pair("N2_C04_eq_C13", "C04_ESBR", "C13_Revision_Breadth_3m")
  chk_pair("N3_C11_eq_M25", "C11_Earnings_Streak", "M25_Earnings_Mom_Streak")
  chk_pair("N4_C01_eq_C09", "C01_SUE", "C09_Earnings_Surprise_Sq")

  if ("C15_Forecast_Error_Trend" %in% BASE$axis_D$dead) {
    d <- BASE$axis_D$detail[Factor_Name == "C15_Forecast_Error_Trend"]
    ok("N5_C15_dead_emission", sprintf("축 D 검거 — n_rows %d · n_cov %d", d$n_rows[1], d$n_cov[1]))
  } else {
    bad("N5_C15_dead_emission", "★C15_Forecast_Error_Trend 미검거 — 죽은 배출 축이 죽어 있다")
  }
}

#==============================================================================
cat("\n=== G. 양성 대조 (같은 실행) — 정상 팩터가 정상으로 남는가 ===\n")
#==============================================================================
POS <- c("M26_Revenue_Mom", "V01_BM", "M01_Mom_12_1", "Q02_ROE", "C18_Earnings_CAR_3d")
if (!HAVE_PANEL) {
  bad("G0_positive_controls", "실패널 부재로 양성 대조 불가 — 과민 여부를 알 수 없다")
} else {
  und <- BASE$axis_I$undeclared
  for (f in POS) {
    if (!f %in% panel$Factor_Name) { bad(paste0("G_", f), "패널 부재 — 대조 불가"); next }
    n_pair <- if (nrow(und) == 0L) 0L else und[factor_a == f | factor_b == f, .N]
    in_T   <- f %in% BASE$axis_T$tie_warn
    in_D   <- f %in% BASE$axis_D$dead
    mfv    <- BASE$axis_T$detail[Factor_Name == f, modal_frac]
    if (n_pair == 0L && !in_T && !in_D) {
      ok(paste0("G_", f), sprintf("정상 — 미선언 중복쌍 0 · 축T/축D 미발화 (modal_frac %.4f)",
                                  if (length(mfv)) mfv[1] else NA_real_))
    } else {
      bad(paste0("G_", f), sprintf("★정상 팩터가 발화 — 중복쌍 %d · T %s · D %s", n_pair, in_T, in_D))
    }
  }
  # 전체 오검거율 — 개별 5종이 우연히 깨끗한 것과 구별한다
  n_fac <- uniqueN(panel$Factor_Name)
  rate_T <- length(BASE$axis_T$tie_warn) / n_fac
  rate_I <- nrow(BASE$axis_I$undeclared)
  if (rate_T <= 0.02 && rate_I <= 12) {
    ok("G_alarm_volume", sprintf("경보량 실행가능 — 축T %d/%d종(%.1f%%) · 축I 미선언 %d쌍",
                                 length(BASE$axis_T$tie_warn), n_fac, 100 * rate_T, rate_I))
  } else {
    bad("G_alarm_volume", sprintf("★경보량 과다(소음은 곧 무시된다) — 축T %.1f%% · 축I %d쌍",
                                  100 * rate_T, rate_I))
  }
}

#==============================================================================
cat("\n=== X. 면제 — 시장레벨 상수 15종이 오분류되지 않는가 (양방향) ===\n")
#==============================================================================
MKT <- IDB[axis == "D", factor]
if (length(MKT) != 15L) {
  bad("X0_declaration_count", sprintf("축 D 선언 %d종 (실측 시장레벨 상수는 15종)", length(MKT)))
} else {
  ok("X0_declaration_count", sprintf("축 D 선언 15종 · 미조사 %d", sum(!IDB$diagnosed)))
}
# 합성으로 15종 전부를 무분산 배출 상태에 놓는다 (실패널 유무와 무관하게 성립해야 함)
syn_tk <- sprintf("A%05d", 1:60)
set.seed(210)
syn_live <- rbindlist(lapply(paste0("SYN", 1:12), function(f)
  data.table(Ticker = syn_tk, Factor_Name = f, Raw_Value = rnorm(60),
             Z_Score = rnorm(60), Coverage = TRUE)))
syn_mkt <- rbindlist(lapply(MKT, function(f)
  data.table(Ticker = syn_tk, Factor_Name = f, Raw_Value = 1.0,
             Z_Score = NA_real_, Coverage = FALSE)))
SYN <- rbindlist(list(syn_live, syn_mkt), use.names = TRUE)
r_ex  <- factor_identity_check(SYN, "202608", dedup_pairs = DEDUP, identity_baseline = IDB)
r_nox <- factor_identity_check(SYN, "202608", dedup_pairs = DEDUP, identity_baseline = NULL)
if (length(intersect(MKT, r_ex$axis_D$dead)) == 0L &&
    length(intersect(MKT, r_ex$axis_D$dead_declared)) == 15L) {
  ok("X1_market_level_exempt", "시장레벨 15종 전부 dead_declared 로 분류 (경고 없음, 기록은 유지)")
} else {
  bad("X1_market_level_exempt",
      sprintf("면제 실패 — 경고 %d종 · 선언분류 %d종",
              length(intersect(MKT, r_ex$axis_D$dead)),
              length(intersect(MKT, r_ex$axis_D$dead_declared))))
}
# 양방향: 선언을 지우면 15종이 실제로 발화해야 한다 (면제가 '보이지 않음'의 결과가 아님)
if (length(intersect(MKT, r_nox$axis_D$dead)) == 15L) {
  ok("X2_exemption_is_what_silences", "선언 제거 시 15종 전부 발화 — 침묵의 원인이 선언임을 실증")
} else {
  bad("X2_exemption_is_what_silences",
      sprintf("선언을 지워도 %d종만 발화 — 축 D 가 애초에 이들을 못 보고 있다",
              length(intersect(MKT, r_nox$axis_D$dead))))
}
# 선언 파일의 이름이 registry 에 실재하는가 (오타가 조용한 영구 면제가 되지 않게)
reg_names <- names(fromJSON(REGISTRY, simplifyVector = FALSE))
unknown <- setdiff(IDB$factor, reg_names)
if (length(unknown) == 0L) {
  ok("X3_declared_names_exist", "선언 항목 전부 registry 에 실재")
} else {
  bad("X3_declared_names_exist", sprintf("registry 에 없는 선언: %s", paste(unknown, collapse = ",")))
}
# 진짜 죽은 배출 3종이 선언에 묻히지 않았는가
buried <- intersect(IDB$factor, c("C15_Forecast_Error_Trend", "D60_Leverage", "Q16_Debt_to_Assets"))
if (length(buried) == 0L) {
  ok("X4_real_defects_not_buried", "C15·D60·Q16 은 선언되지 않음 (경고 계속 수신)")
} else {
  bad("X4_real_defects_not_buried", sprintf("★진짜 결함이 선언에 묻힘: %s", paste(buried, collapse = ",")))
}

#==============================================================================
cat("\n=== Z. 죽은 통계 — sd(Z)=1 항등 실측 + 가드가 거기 의존하지 않음 ===\n")
#==============================================================================
if (!HAVE_PANEL) {
  bad("Z0_dead_statistic", "실패널 부재 — 죽은 통계 실측 불가")
} else {
  sdz <- panel[, .(sd_z = sd(Z_Score, na.rm = TRUE)), by = Factor_Name]$sd_z
  sdz <- sdz[is.finite(sdz)]
  spread <- diff(range(sdz))
  if (spread < 1e-6) {
    ok("Z1_sdz_is_dead_statistic",
       sprintf("sd(Z) 범위 폭 %.2e (n=%d, 고유값 %d) — 판별력 0 임을 재확인", spread,
               length(sdz), length(unique(round(sdz, 10)))))
  } else {
    bad("Z1_sdz_is_dead_statistic",
        sprintf("sd(Z) 가 %.4f 만큼 벌어짐 — 이 저장소의 표준화 항등 전제가 바뀌었다. 축 설계 재검토 필요", spread))
  }
  # 가드는 그 죽은 통계에 의존하지 않는다: sd(Z) 를 판별축으로 쓰는 돌연변이 가드는
  # 같은 입력에서 C15 를 놓친다 (= 초판이 "죽은 배출 0종"을 낸 그 상태의 재현)
  broken <- function(res) {
    s <- res[Coverage %in% TRUE, .(sd_z = sd(Z_Score, na.rm = TRUE)), by = Factor_Name]
    sort(s[is.finite(sd_z) & sd_z < 1e-12, Factor_Name])
  }
  lost <- broken(FULL)
  if (!"C15_Forecast_Error_Trend" %in% lost && "C15_Forecast_Error_Trend" %in% BASE$axis_D$dead) {
    ok("Z2_guard_not_on_dead_axis",
       sprintf("sd(Z) 축 가드는 %d종만 검거(C15 놓침) · 현행 축 D 는 검거 — 돌연변이가 검출력을 실증", length(lost)))
  } else {
    bad("Z2_guard_not_on_dead_axis", "돌연변이 가드가 여전히 C15 를 잡음 — N5 통과가 축 D 덕이 아닐 수 있음")
  }
  if (isTRUE(BASE$axis_T$stat_liveness > 0)) {
    ok("Z3_axisT_statistic_alive", sprintf("축 T stat_liveness sd(modal_frac) = %.6f > 0",
                                           BASE$axis_T$stat_liveness))
  } else {
    bad("Z3_axisT_statistic_alive", "축 T 통계가 퇴화 — 판별력 확인 실패")
  }
}
# 죽은 통계로 갈아끼우면 축 T 는 OK 가 아니라 UNMEASURED 를 내야 한다
deg <- rbindlist(lapply(sprintf("DEG%02d", 1:20), function(f)
  data.table(Ticker = syn_tk, Factor_Name = f, Raw_Value = 1.0, Z_Score = 1.0, Coverage = TRUE)))
r_deg <- factor_identity_check(deg, "202608", dedup_pairs = DEDUP, identity_baseline = IDB)
if (identical(r_deg$axis_T$status, "UNMEASURED")) {
  ok("Z4_degenerate_is_unmeasured", "전 팩터 modal_frac 동일(비-바닥) → UNMEASURED (경보 0 아님)")
} else {
  bad("Z4_degenerate_is_unmeasured", sprintf("퇴화 통계인데 status=%s", r_deg$axis_T$status))
}
# 반대 방향: 값이 전부 서로 다른 건강한 패널은 modal_frac 이 바닥에서 상수여도 UNMEASURED 아님
cont <- rbindlist(lapply(sprintf("CON%02d", 1:20), function(f)
  data.table(Ticker = syn_tk, Factor_Name = f, Raw_Value = rnorm(60),
             Z_Score = rnorm(60), Coverage = TRUE)))
r_cont <- factor_identity_check(cont, "202608", dedup_pairs = DEDUP, identity_baseline = IDB)
if (identical(r_cont$axis_T$status, "OK")) {
  ok("Z5_healthy_not_false_unmeasured",
     sprintf("전 값 상이 패널 = OK (modal_frac 바닥 상수는 정상, sd %.2e)", r_cont$axis_T$stat_liveness))
} else {
  bad("Z5_healthy_not_false_unmeasured",
      sprintf("★건강한 패널을 UNMEASURED 로 오분류 — %s", r_cont$axis_T$reason))
}

#==============================================================================
cat("\n=== U. UNMEASURED 계약 — 못 재는 상태를 '이상 없음'으로 내려앉히지 않는가 ===\n")
#==============================================================================
r_nocov <- factor_identity_check(data.table(Factor_Name = "X", Ticker = "A1", Z_Score = 1.0),
                                 "202608", dedup_pairs = DEDUP)
if (identical(r_nocov$verdict, "UNMEASURED") && length(r_nocov$warnings) > 0L) {
  ok("U1_missing_column_unmeasured", "Coverage 컬럼 결측 → UNMEASURED + 경고 (침묵 통과 아님)")
} else {
  bad("U1_missing_column_unmeasured", sprintf("verdict=%s warnings=%d", r_nocov$verdict, length(r_nocov$warnings)))
}
r_novcol <- factor_identity_check(
  data.table(Factor_Name = rep("X", 40), Ticker = sprintf("A%d", 1:40), Coverage = TRUE),
  "202608", dedup_pairs = DEDUP)
if (identical(r_novcol$axis_T$status, "UNMEASURED") && identical(r_novcol$axis_I$status, "UNMEASURED")) {
  ok("U2_missing_value_col_unmeasured", "Z_Score 결측 → 축 T/I UNMEASURED (축 D 는 계속 판정)")
} else {
  bad("U2_missing_value_col_unmeasured",
      sprintf("T=%s I=%s", r_novcol$axis_T$status, r_novcol$axis_I$status))
}
# 어떤 입력에도 stop 하지 않는다 (설계 원칙 ① — 정당한 상수 팩터가 실재하므로)
crashed <- tryCatch({
  factor_identity_check(NULL, "202608")
  factor_identity_check(data.table(), "202608")
  factor_identity_check(data.table(Factor_Name = "X", Ticker = "A", Coverage = NA), "202608")
  FALSE
}, error = function(e) conditionMessage(e))
if (isFALSE(crashed)) {
  ok("U3_never_stops_build", "빈/기형 입력에서도 stop 하지 않음")
} else {
  bad("U3_never_stops_build", sprintf("예외로 빌드를 죽임: %s", crashed))
}
# 래퍼도 마찬가지 — 정체 검사 실패가 존재 축까지 삼키지 않는가
wrapped <- tryCatch({
  tmpd <- file.path(tempdir(), paste0("eg_", as.integer(Sys.time())))
  dir.create(tmpd, showWarnings = FALSE, recursive = TRUE)
  suppressWarnings(factor_emission_guard(
    result = data.table(Factor_Name = "C01_SUE", Ticker = "A1", n = 1L),
    ym = "202608", fdb_dir = tmpd, registry_path = REGISTRY,
    write_artifacts = FALSE, identity_baseline_path = IDBASE))
}, error = function(e) NULL)
if (!is.null(wrapped) && !is.null(wrapped$identity)) {
  ok("U4_wrapper_isolates_identity", sprintf("정체 축이 스키마 미달에도 존재 축 판정을 보존 (identity verdict=%s)",
                                             wrapped$identity$verdict))
} else {
  bad("U4_wrapper_isolates_identity", "래퍼가 정체 축 실패에 존재 축까지 잃음")
}

#==============================================================================
cat("\n=== S. 사이드카 — 3축 판정이 기록까지 도달하는가 ===\n")
#==============================================================================
# ★래퍼의 tryCatch 는 정체 검사 실패를 삼킨다(빌드를 죽이지 않기 위해). 그래서
#   중첩 data.table 직렬화가 깨지면 **경고도 사이드카도 없이** 조용히 사라진다.
#   판정이 났다는 것과 그 판정이 기록됐다는 것은 다른 사실이다 — 밟아서 확인한다.
tmpd <- file.path(tempdir(), paste0("id_sidecar_", as.integer(Sys.time())))
unlink(tmpd, recursive = TRUE); dir.create(tmpd, recursive = TRUE, showWarnings = FALSE)
s_tk <- sprintf("A%05d", 1:80)
set.seed(9)
s_live <- rbindlist(lapply(paste0("SYN", sprintf("%02d", 1:15)), function(f)
  data.table(Ticker = s_tk, Factor_Name = f, Raw_Value = rnorm(80),
             Z_Score = rnorm(80), Coverage = TRUE)))
s_res <- rbindlist(list(
  s_live,
  copy(s_live[Factor_Name == "SYN01"])[, Factor_Name := "SYN01_CLONE"],
  data.table(Ticker = s_tk, Factor_Name = "SYN_DEAD", Raw_Value = 1.0,
             Z_Score = NA_real_, Coverage = FALSE),
  data.table(Ticker = s_tk, Factor_Name = "SYN_TIE", Raw_Value = 0,
             Z_Score = 0, Coverage = TRUE)), use.names = TRUE)
invisible(suppressWarnings(factor_emission_guard(
  result = s_res, ym = "209901", fdb_dir = tmpd, registry_path = REGISTRY,
  write_artifacts = TRUE, identity_baseline_path = IDBASE)))
sc <- file.path(tmpd, "emission_report_209901.json")
if (!file.exists(sc)) {
  bad("S1_sidecar_written", "★사이드카 미생성 — 판정이 기록에 도달하지 않음")
} else {
  j <- tryCatch(fromJSON(sc, simplifyVector = FALSE), error = function(e) NULL)
  d_ok <- !is.null(j) && identical(unlist(j$identity$axis_D$dead), "SYN_DEAD")
  t_ok <- !is.null(j) && identical(unlist(j$identity$axis_T$tie_warn), "SYN_TIE")
  i_ok <- !is.null(j) && length(j$identity$axis_I$undeclared) == 1L
  w_ok <- !is.null(j) && length(j$identity$warnings) >= 3L
  if (d_ok && t_ok && i_ok && w_ok) {
    ok("S1_sidecar_written", sprintf("3축 판정 + 경고 %d건이 JSON 왕복 후 보존 (%.1f KB)",
                                     length(j$identity$warnings), file.size(sc) / 1024))
  } else {
    bad("S1_sidecar_written", sprintf("직렬화 손실 — D %s · T %s · I %s · warnings %s",
                                      d_ok, t_ok, i_ok, w_ok))
  }
}
unlink(tmpd, recursive = TRUE)

#==============================================================================
cat("\n=== W. 배선 — 빌더가 정체 축을 실제로 켜서 호출하는가 ===\n")
#==============================================================================
b <- readLines(BUILDER_SRC, warn = FALSE)
live <- b[!grepl("^\\s*#", b)]
call_i <- grep("factor_emission_guard(", b, fixed = TRUE)
call_i <- call_i[!grepl("^\\s*#", b[call_i])]
if (any(grepl("identity_baseline_path", live, fixed = TRUE))) {
  ok("W1_identity_baseline_wired", "빌더가 identity_baseline_path 를 전달")
} else {
  bad("W1_identity_baseline_wired", "★선언 래칫이 전달되지 않음 — 면제가 작동하지 않는다")
}
if (any(grepl("run_identity = TRUE", live, fixed = TRUE)) ||
    any(grepl("run_identity=TRUE", live, fixed = TRUE))) {
  ok("W2_identity_enabled", "빌더가 run_identity=TRUE 로 정체 축을 켬")
} else {
  bad("W2_identity_enabled", "★정체 축이 꺼진 채 배선 — 파일만 있고 발화 없음")
}
if (file.exists(IDBASE)) {
  ok("W3_declaration_file_exists", sprintf("선언 래칫 파일 실재 (%d항목)", nrow(IDB)))
} else {
  bad("W3_declaration_file_exists", "선언 래칫 파일 부재 — 시장레벨 15종이 매달 오발화한다")
}
g <- readLines(GUARD_SRC, warn = FALSE)
gl <- g[!grepl("^\\s*#", g)]
if (any(grepl("factor_identity_check(", gl, fixed = TRUE)) &&
    any(grepl("emission_dedup_pairs(", gl, fixed = TRUE))) {
  ok("W4_guard_calls_identity", "래퍼가 정체 검사 + registry dedup 대조를 호출")
} else {
  bad("W4_guard_calls_identity", "래퍼 배선 누락")
}
if (!any(grepl("stop(", gl[grep("factor_identity_check <- function", gl):length(gl)], fixed = TRUE))) {
  ok("W5_no_stop_in_identity", "정체 검사 경로에 stop() 없음 (정당한 상수 팩터가 실재하므로 전면 차단 금지)")
} else {
  bad("W5_no_stop_in_identity", "★정체 검사 경로에 stop() — 시장레벨 15종이 매 빌드를 죽인다")
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "emission_identity_axes", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
