## BiocJobs job script: toy-normalize
## See ../toy-normalize.yaml for the declared interface.

params <- BiocJobs::jobParams("toy", "toy-normalize")

m <- as.matrix(read.delim(params$matrix, row.names = 1, check.names = FALSE))
stopifnot(is.numeric(m))

m <- switch(params$method,
    log2 = log2(m + params$pseudocount),
    zscore = scale(m),
    none = m
)
if (params$center)
    m <- scale(m, center = TRUE, scale = FALSE)

write.table(data.frame(id = rownames(m), m, check.names = FALSE),
            params$normalized,
            sep = "\t", quote = FALSE, row.names = FALSE)
