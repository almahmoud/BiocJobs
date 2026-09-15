## BiocJobs job script: variantannotation-extract-numeric-genotypes
##
## The declared interface lives in ../variantannotation-extract-numeric-genotypes.yaml.
## jobParams() parses the command line against that declaration, so by the
## time it returns, every value below is typed, validated and defaulted.

params <- BiocJobs::jobParams("VariantAnnotation", "variantannotation-extract-numeric-genotypes")

suppressPackageStartupMessages(library(VariantAnnotation))

# Set regions to extract
gr <- rtracklayer::import(params$bed, format = "bed")

# Set samples to include
samples <- readLines(params$samples)

# Build parameters object
svp <- ScanVcfParam(which = gr, geno = "GT", info = NA, samples = samples)

# Import VCF
vcf <- readVcf(params$vcf, param = svp)

# Filter to passing variants
vcf <- vcf[rowRanges(vcf)$FILTER %in% c("PASS", "."),]

# Put multiallelic variants onto separate lines
vcf <- expand(vcf)

# Make data frame of marker info
vardf <- data.frame(
    Chrom = seqnames(vcf),
    Pos = start(vcf),
    Ref = as.character(rowRanges(vcf)$REF),
    Alt = as.character(rowRanges(vcf)$ALT)
)

# Make numeric matrix of genotypes
GT <- geno(vcf)$GT
GTsplit <- strsplit(GT, "[\\/\\|]")
GTcount <- sapply(GTsplit, \(x) sum(x == "1"))
GTnum <- matrix(GTcount, nrow = nrow(GT), ncol = ncol(GT),
                dimnames = dimnames(GT))
GTnum[GT == '.'] <- NA

# Export to TSV
write.table(cbind(vardf, GTnum),
            file = params$numeric_genotypes,
            sep = "\t", row.names = FALSE, col.names = TRUE)

# Provenance to the job log.
message(paste(utils::capture.output(utils::sessionInfo()), collapse = "\n"))
