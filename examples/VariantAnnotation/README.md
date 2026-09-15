# VariantAnnotation × BiocJobs worked example

This directory follows the format of the example provided in the DESeq
directory. The `variantannotation-extract-numeric-genotypes` script imports a
zipped and indexed VCF, with regions of interest defined in a BED file and
samples of interest defined in a plain text file, and writes a gzipped TSV
containing genotypes expressed as alternative allele counts, suitable for use
in downstream statistical analysis. Provided test data are a tiny subset of
the public Genome-in-a-Bottle dataset.

Regenerate everything (from the repository root, with BiocJobs installed):

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' validate examples/VariantAnnotation
Rscript -e 'BiocJobs::biocjobsCLI()' tes      examples/VariantAnnotation variantannotation-extract-numeric-genotypes --out examples/VariantAnnotation/generated/variantannotation-extract-numeric-genotypes.tes.json
Rscript -e 'BiocJobs::biocjobsCLI()' galaxy   examples/VariantAnnotation variantannotation-extract-numeric-genotypes --out examples/VariantAnnotation/generated/variantannotation_extract_numeric_genotypes.xml
Rscript -e 'BiocJobs::biocjobsCLI()' nextflow examples/VariantAnnotation variantannotation-extract-numeric-genotypes --out examples/VariantAnnotation/generated/variantannotation_extract_numeric_genotypes.nf
Rscript -e 'BiocJobs::biocjobsCLI()' wdl      examples/VariantAnnotation variantannotation-extract-numeric-genotypes --out examples/VariantAnnotation/generated/variantannotation_extract_numeric_genotypes.wdl
Rscript -e 'BiocJobs::biocjobsCLI()' manifest examples/VariantAnnotation --out examples/VariantAnnotation/generated/manifest.json
Rscript -e "BiocExecute::execCompile('examples/VariantAnnotation')"
```

Run the job locally:

``` bash
Rscript -e 'BiocJobs::biocjobsCLI()' run examples/VariantAnnotation \
    variantannotation-extract-numeric-genotypes \
    --vcf examples/VariantAnnotation/test-data/Ashkenazim_GIAB_small.glnexus.vcf.bgz \
    --index examples/VariantAnnotation/test-data/Ashkenazim_GIAB_small.glnexus.vcf.bgz.tbi \
    --samples examples/VariantAnnotation/test-data/Ashkenazim_GIAB_samples.txt \
    --bed examples/VariantAnnotation/test-data/Ashkenazim_GIAB_regions.bed \
    --numeric_genotypes mygenos.tsv.gz
```
