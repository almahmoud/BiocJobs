library(VariantAnnotation)
library(Rsamtools)

bg <- bgzip("Ashkenazim_GIAB_small.glnexus.vcf")
indexVcf(bg)

vcf <- readVcf(bg)

writeLines(samples(header(vcf)), "Ashkenazim_GIAB_samples.txt")

rowRanges(vcf)

bed_df <- data.frame(
    Chrom = c('16', 'X'),
    Start = c(450000, 122530000),
    End   = c(470000, 122550000)
)

write.table(bed_df, "Ashkenazim_GIAB_regions.bed",
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
