# BiocJobs

Declare non-interactive jobs inside a Bioconductor package and generate,
from that one declaration, the artifacts workflow systems need to run them:
Galaxy tool wrappers, GA4GH TES tasks, Nextflow DSL2 modules, WDL tasks,
HTCondor submit files and a job manifest.

## Installation

```r
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install("BiocJobs")
```

Until the package is on Bioconductor:

```r
BiocManager::install("almahmoud/BiocJobs", subdir = "BiocJobs")
```

## Quick start

```r
library(BiocJobs)
jobSkeleton("my-analysis", pkg = ".")      # writes inst/biocjobs/my-analysis.{yaml,R}
```

Edit the two files, then from a shell:

```bash
Rscript -e 'BiocJobs::biocjobsCLI()' validate .
Rscript -e 'BiocJobs::biocjobsCLI()' run . my-analysis --input1 data.tsv
Rscript -e 'BiocJobs::biocjobsCLI()' galaxy . my-analysis --out my_analysis.xml
```

`vignette("BiocJobs")` walks through the model with a toy package shipped
in the package. The
[developer guide](https://github.com/almahmoud/BiocJobs/blob/main/docs/developer-guide.md)
covers the full specification, and the
[repository README](https://github.com/almahmoud/BiocJobs#readme)
describes the project as a whole, including the companion GitHub Action.
