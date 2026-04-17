library(data.table); library(jsonlite)
ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/stage_gate_engine.R"))
source(file.path(ROOT, "02_Infrastructure/telegram_notify.R"))

mk <- function(sid, name, fid, factors, hyp, econ, ref, role, why, lesson) {
  dir.create(file.path(STRATEGY_OUTPUT, paste0(sid,"_",name), "stage_artifacts"), recursive=TRUE, showWarnings=FALSE)
  s0 <- list(factor_id=fid, strategy_id=paste0(sid,"_",name),
    hypothesis=hyp, economic_rationale=econ, prior_art="Novel",
    source_reference=ref, expected_role=role, why_now=why,
    lesson_check=lesson, overlay="none",
    created_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"), created_by="scout_v7.0")
  fname <- sprintf("s0_record_%s.json", gsub("[+]","_",fid))
  write(toJSON(s0, auto_unbox=TRUE, pretty=TRUE),
    file.path(STRATEGY_OUTPUT, paste0(sid,"_",name), "stage_artifacts", fname))
  # Forge
  todo <- list(task_type="S1_backtest", strategy_id=paste0(sid,"_",name),
    instructions="S1 EW 30+15bps+liq 2e8.",
    created_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"), created_by="scout_v7.0")
  write(toJSON(todo, auto_unbox=TRUE, pretty=TRUE),
    file.path(PROJECT_ROOT, "qepm/mailbox/forge/inbox", sprintf("TODO_S1_%s_%s.json", sid, name)))
}

# MF_36
sid1 <- allocate_str("roic_sustainable_growth")
sg_init("Q17+Q23", sid1)
mk(sid1, "roic_sustainable_growth", "Q17_ROIC+Q23_Sustainable_Growth", c("Q17","Q23"),
  "ROIC(Q17)+SGR(Q23): ICIR 0.638+0.633=1.27. Fresh pool top 2.",
  "[A] Greenblatt(2006) Magic Formula ROIC. Higgins(1977) SGR=ROE*(1-payout). Quality2 cross.",
  "Greenblatt(2006); Higgins(1977); Novy-Marx(2013)", "core_alpha",
  "ICIR sum 1.27 = all-time best combo. Quality standalone weak(L-002) but 2Q cross untested.",
  "L-002(V standalone) N/A. L-001(CR07) N/A.")
cat(sprintf("MF_36: %s\n", sid1))

# MF_37
sid2 <- allocate_str("coverage_coskewness")
sg_init("C08+D16", sid2)
mk(sid2, "coverage_coskewness", "C08_Coverage+D16_Coskewness", c("C08","D16"),
  "Coverage(C08)+Coskew(D16): ICIR 0.585+0.373=0.96. Consensus x Defense.",
  "[A] Hong et al.(2000) coverage=info efficiency. Harvey&Siddique(2000) coskew pricing.",
  "Hong,Lim,Stein(2000); Harvey&Siddique(2000)", "core_alpha",
  "C08 != C19(composite earnings). D16 != D01(idiovol). Both fresh dimensions.",
  "L-001(CR07)=N/A(C08 is consensus). Defense as component only.")
cat(sprintf("MF_37: %s\n", sid2))

# MF_38
sid3 <- allocate_str("volume_focus_revenue_growth")
sg_init("CR02+GR01", sid3)
mk(sid3, "volume_focus_revenue_growth", "CR02_Volume_Concentration+GR01_Revenue_Growth", c("CR02","GR01"),
  "VolConc(CR02)+RevGrowth(GR01): ICIR 0.225+0.211. Crowding x Growth.",
  "[A] Easley et al.(2002) VPIN volume clustering. Revenue growth=fundamental growth.",
  "Easley,Hvidkjaer,OHara(2002); Lakonishok et al.(1994)", "diversifier",
  "CR02 untested. Volume pattern != price/volatility info. Crowding x Growth novel.",
  "L-001(CR07)=CR02 is different crowding dim. N/A.")
cat(sprintf("MF_38: %s\n", sid3))

# MF_39 (3-factor)
sid4 <- allocate_str("roic_coverage_coskew")
sg_init("Q17+C08+D16", sid4)
mk(sid4, "roic_coverage_coskew", "Q17_ROIC+C08_Coverage+D16_Coskewness", c("Q17","C08","D16"),
  "ROIC+Coverage+Coskew 3F: ICIR 0.638+0.585+0.373=1.60. Project all-time best.",
  "[A] Greenblatt(2006)+Hong(2000)+Harvey&Siddique(2000). 3 independent categories.",
  "Greenblatt(2006); Hong et al.(2000); Harvey&Siddique(2000)", "core_alpha",
  "ICIR sum 1.60. 3-category cross (Quality/Consensus/Defense). False positive minimized.",
  "All L-codes clear. Defense=component only. No CR07. No V standalone.")
cat(sprintf("MF_39: %s\n", sid4))

# MF_40
sid5 <- allocate_str("stable_liq_low_debt")
sg_init("L25+Q16", sid5)
mk(sid5, "stable_liq_low_debt", "L25_Amihud_Vol+Q16_Debt_to_Assets", c("L25","Q16"),
  "AmihudVol(L25)+DebtAssets(Q16): ICIR 0.220+0.229. Liquidity x Quality.",
  "[A] Amihud(2002) illiquidity vol=2nd moment risk. Low debt=Altman(1968) safety.",
  "Amihud(2002); Altman(1968)", "diversifier",
  "L25=Amihud 2nd moment != L01(level). Q16 != Q13(fin leverage, different scaling).",
  "L-002(V standalone)=N/A(Quality). Defense F=N/A(Liquidity x Quality).")
cat(sprintf("MF_40: %s\n", sid5))

# Telegram
msg <- paste0(
  "[Scout] \U0001F52C MF_36~40 (High-ICIR Batch)\n\n",
  "\U0001F525 ICIR 0.5+ fresh: Q17(0.64), Q23(0.63), C08(0.59)\n\n",
  sprintf("MF_36: %s Q17+Q23 ICIR=1.27\n", sid1),
  sprintf("MF_37: %s C08+D16 ICIR=0.96\n", sid2),
  sprintf("MF_38: %s CR02+GR01 ICIR=0.44\n", sid3),
  sprintf("MF_39: %s Q17+C08+D16(3F) ICIR=1.60\U0001F451\n", sid4),
  sprintf("MF_40: %s L25+Q16 ICIR=0.45\n", sid5),
  "\nForge inbox 5\uac74 \ud22c\uc785. \ub204\uc801 MF_18~40 (23\uac74)."
)
tg_send(msg)
cat("\nDone.\n")
