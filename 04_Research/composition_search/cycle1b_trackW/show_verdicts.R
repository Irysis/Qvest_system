suppressMessages(library(jsonlite))
j <- read_json("weighting_results.json")
cat("axis_alive_overall:", unlist(j$axis_alive_overall), "\n\n")
for (s in names(j$verdicts)) {
  v <- j$verdicts[[s]]
  cat(sprintf("%s | baseline %s | IS-argmax %s (%s) is_sr=%.3f d_is=%.3f d_oos=%.3f | oos_nondegrade=%s | n_alive=%d [%s] | %s\n",
      s, v$baseline, v$is_argmax, v$is_argmax_label,
      as.numeric(v$is_argmax_is_sr), as.numeric(v$is_argmax_d_is_sr),
      as.numeric(v$is_argmax_d_oos_sr),
      as.character(v$oos_nondegradation_of_argmax),
      as.integer(v$n_alive), paste(unlist(v$alive_ids), collapse = ","),
      v$axis_verdict))
}
