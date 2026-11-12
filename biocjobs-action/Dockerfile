# syntax=docker/dockerfile:1
# Default image for the BiocJobs action: the package, its dependencies and
# BiocJobs on a Bioconductor base. The build context is the package source.
ARG BASE_IMAGE=ghcr.io/bioconductor/bioconductor:devel
FROM ${BASE_IMAGE}

# Dependencies are keyed on DESCRIPTION alone so source edits reuse the layer.
COPY DESCRIPTION /tmp/pkg/DESCRIPTION
RUN Rscript -e 'options(Ncpus = parallel::detectCores()); \
                BiocManager::install("remotes", ask = FALSE, update = FALSE); \
                remotes::install_deps("/tmp/pkg", dependencies = TRUE, upgrade = FALSE, repos = BiocManager::repositories())'

# Until BiocJobs is on Bioconductor. The action passes its own ref, so the
# image gets the BiocJobs of the action version in use. The archive download
# avoids the GitHub API rate limit that install_github() hits on shared
# runners.
ARG BIOCJOBS_REF=HEAD
RUN Rscript -e 'remotes::install_url(paste0("https://github.com/almahmoud/BiocJobs/archive/", Sys.getenv("BIOCJOBS_REF"), ".tar.gz"), subdir = "BiocJobs", upgrade = FALSE)'

# The source is bind-mounted rather than copied, so it stays out of the image.
RUN --mount=type=bind,target=/tmp/src,rw \
    MAKEFLAGS="-j$(nproc)" R CMD INSTALL /tmp/src
