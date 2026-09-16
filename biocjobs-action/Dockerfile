# syntax=docker/dockerfile:1
# Default image for the BiocJobs action: the package, its dependencies and
# BiocJobs on a Bioconductor base. The build context is the package source.
ARG BASE_IMAGE=ghcr.io/bioconductor/bioconductor:devel
FROM ${BASE_IMAGE}

# Dependencies are keyed on DESCRIPTION alone so source edits reuse the layer.
COPY DESCRIPTION /tmp/pkg/DESCRIPTION
RUN Rscript -e 'options(Ncpus = parallel::detectCores()); \
                BiocManager::install("remotes", ask = FALSE, update = FALSE); \
                remotes::install_deps("/tmp/pkg", dependencies = TRUE, upgrade = FALSE)'

# Until BiocJobs is on Bioconductor.
RUN Rscript -e 'BiocManager::install("almahmoud/BiocJobs", subdir = "BiocJobs", ask = FALSE, update = FALSE)'

COPY . /tmp/pkg
RUN MAKEFLAGS="-j$(nproc)" R CMD INSTALL /tmp/pkg && rm -rf /tmp/pkg
