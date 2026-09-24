suppressMessages(library(arrow))
p <- "stage_artifacts/replication/20260902_192126_25496/factors_panel.parquet"
print(open_dataset(p)$schema)
