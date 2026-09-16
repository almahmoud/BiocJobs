FROM bioconductor/bioconductor_docker:RELEASE_3_23

# Runtime dependencies the job script needs beyond the package itself.
RUN Rscript -e 'BiocManager::install(c("apeglm", "ashr"), ask = FALSE, update = FALSE)'

# Until BiocJobs is on Bioconductor, install it from its repository.
RUN Rscript -e 'BiocManager::install("almahmoud/BiocJobs", subdir = "BiocJobs", ask = FALSE, update = FALSE)'

COPY . /src
RUN Rscript -e 'remotes::install_deps("/src", dependencies = TRUE, upgrade = FALSE)' \
 && R CMD INSTALL /src \
 && rm -rf /src
