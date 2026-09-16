#' File formats known to BiocJobs
#'
#' BiocJobs uses a small controlled vocabulary of file format names in job
#' specifications.  Each format maps to a Galaxy datatype and a default file
#' extension.  Unknown formats are allowed (they pass through verbatim as the
#' Galaxy datatype and extension) but `validateJob()` reports them as notes so
#' typos are caught.
#'
#' @return A `data.frame` with columns `format`, `galaxy`, `extension`
#'   and `description`.
#' @examples
#' formats <- jobFormats()
#' head(formats)
#'
#' ## What a spec's `format: tsv` means downstream: the Galaxy datatype of
#' ## the generated param, and the file extension used for staged files.
#' formats[formats$format %in% c("tsv", "fastq", "bam"), ]
#' @export
jobFormats <- function() {
    tab <- c(
        ## format,   galaxy,        extension,  description
        "tsv",       "tabular",     "tsv",      "Tab-separated values",
        "csv",       "csv",         "csv",      "Comma-separated values",
        "txt",       "txt",         "txt",      "Plain text",
        "json",      "json",        "json",     "JSON document",
        "yaml",      "yaml",        "yaml",     "YAML document",
        "rds",       "rds",         "rds",      "Serialized single R object",
        "rdata",     "rdata",       "RData",    "Serialized R workspace",
        "pdf",       "pdf",         "pdf",      "PDF document",
        "png",       "png",         "png",      "PNG image",
        "svg",       "svg",         "svg",      "SVG image",
        "html",      "html",        "html",     "HTML document",
        "fasta",     "fasta",       "fasta",    "FASTA sequences",
        "fastq",     "fastqsanger", "fastq",    "FASTQ reads (Sanger quality)",
        "fastq.gz",  "fastqsanger.gz", "fastq.gz", "Compressed FASTQ reads",
        "gff3",      "gff3",        "gff3",     "GFF3 genomic features",
        "gtf",       "gtf",         "gtf",      "GTF genomic features",
        "bed",       "bed",         "bed",      "BED genomic intervals",
        "vcf",       "vcf",         "vcf",      "Variant Call Format",
        "bam",       "bam",         "bam",      "Binary sequence alignments",
        "sam",       "sam",         "sam",      "Sequence alignments",
        "bigwig",    "bigwig",      "bw",       "BigWig signal track",
        "h5",        "h5",          "h5",       "HDF5 container",
        "loom",      "loom",        "loom",     "Loom single-cell matrix (HDF5)",
        "mtx",       "mtx",         "mtx",      "Matrix Market sparse matrix",
        "tar",       "tar",         "tar",      "tar archive",
        "tar.gz",    "tar.gz",      "tar.gz",   "gzip-compressed tar archive",
        "zip",       "zip",         "zip",      "ZIP archive"
    )
    m <- matrix(tab, ncol = 4L, byrow = TRUE)
    data.frame(
        format = m[, 1L], galaxy = m[, 2L], extension = m[, 3L],
        description = m[, 4L], stringsAsFactors = FALSE
    )
}

## Look up a format; unknown formats fall through verbatim.
.formatInfo <- function(format) {
    tab <- jobFormats()
    i <- match(format, tab$format)
    if (is.na(i)) {
        list(format = format, galaxy = format, extension = format,
             known = FALSE)
    } else {
        list(format = tab$format[i], galaxy = tab$galaxy[i],
             extension = tab$extension[i], known = TRUE)
    }
}

## Default file name for an input/output staged into a working directory.
.defaultFileName <- function(name, format) {
    paste0(name, ".", .formatInfo(format)$extension)
}
