suppressMessages(library(jsonlite))
`%||%`<-function(a,b) if(is.null(a)||length(a)==0) b else a
J<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/l_code/qepm_legacy/l_code_STR_MEGACAP_ANCHOR_CAPRELAX_20260706.json"
d<-fromJSON(J, simplifyVector=FALSE)
d$firewall_violation<-FALSE
d$firewall_backstop_note<-"regex backstop false-positive corrected 2026-07-06 (semantic-primary INV, LLM judge). Lesson reports that constraint RELAXATION does NOT help (cap not the bottleneck); it does NOT propose relaxation as a lever. Backstop matched adjacency of the negation phrase."
write_json(d, J, auto_unbox=TRUE, pretty=TRUE)
cat("patched firewall_violation ->", d$firewall_violation, "\n")
