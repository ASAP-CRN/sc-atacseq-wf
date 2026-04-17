# Human PMDBS sc/sn ATAC-seq pipeline Python scripts with SnapATAC2, Harmony, PeakVI, and Scanpy

![Workflow diagram](../workflows/workflow_diagram.svg "Workflow diagram")


## _PREPROCESSING_
- _Pre-preprocessing_: executed by WDL [`cellranger-atac count`](../workflows/preprocess/preprocess.wdl)
    - Aligns FASTQ files and generates fragment files per pool

- _Splitting demuxed sample Cell Ranger fragment files_: executed by WDL [`scatac_fragment_tools split`](../workflows/preprocess/preprocess.wdl)
    - Prepares mapping inputs required to split the fragment files
    - Splits pool-level fragment files into sample-level (one subject = one sample per pool)

- _Converting counts to AnnData_: [`counts_to_adata`](./sc_atac_tools/scripts/counts_to_adata)
    - Imports demuxed sample-level Cell Ranger ATAC fragment files via `snap.pp.import_fragments`
    - Performs initial per-sample tiling and stores as backed SnapATAC2 AnnData

- _Merge and QC_: [`merge_and_qc`](./sc_atac_tools/scripts/merge_and_qc)
    - Merges per-sample SnapATAC2 AnnData objects in chunks
    - Calculates QC metrics (TSS enrichment, fragment counts, doublet scores)
    - Plots general QC metrics across all cells
    - Saves initial merged metadata


## _PROCESSING_

## Bin-level (chromatin accessibility)

- _Process bins_: [`process_bins`](./sc_atac_tools/scripts/process_bins)
    - Stores raw tile counts in `layers["tile_counts"]`
    - Performs spectral embedding (LSI/SVD) and UMAP dimensionality reduction on the tile matrix
    - Foundation for all chromatin-level clustering and integration


## _INTEGRATION_

### _Harmony integration option_

- _Run harmony_: [`run_harmony`](./sc_atac_tools/scripts/run_harmony)
    - Applies Harmony batch correction to the spectral embedding
    - Stores corrected embedding in `obsm` for downstream clustering and UMAP

- _Harmony clustering_: [`cluster_harmony`](./sc_atac_tools/scripts/cluster_harmony)
    - Builds KNN graph and runs leiden clustering on the spectral embedding
    - Generates Harmony-integrated UMAP
    - Calls peaks per cluster for use in downstream gene matrix construction

- _Peak calling_: [`call_peaks`](./sc_atac_tools/scripts/call_peaks)
    - Calls peaks per cluster via `snap.tl.macs3` (groupby `leiden`)
    - Constructs a peak-by-cell count matrix via `snap.pp.make_peak_matrix`


### _PeakVI integration option_

- _Integrate PeakVI_: [`integrate_peakvi`](./scvi_tools/scripts/integrate_peakvi)
    - Trains a `PeakVI` model on `layers["tile_counts"]` with batch correction
    - Stores the latent representation in `obsm` for downstream clustering and UMAP
    - Saves the trained PeakVI model to disk

- _Cluster PeakVI_: [`cluster_peakvi`](./scvi_tools/scripts/cluster_peakvi)
    - Builds KNN graph on the PeakVI latent space and runs leiden clustering (`resolution=0.2`)
    - Generates UMAP colored by PeakVI clusters (`clusters_peakvi`)

- _Peak calling_: [`call_peaks`](./sc_atac_tools/scripts/call_peaks)
    - Calls peaks per cluster via `snap.tl.macs3` (groupby `leiden`)
    - Constructs a peak-by-cell count matrix via `snap.pp.make_peak_matrix`


### _Benchmark sc integration tools_

- _Benchmark integration_: [`benchmark_sc_integration`](./scvi_tools/scripts/benchmark_sc_integration)
    - Compares integration methods — Unintegrated (`X_spectral`), Harmony (`X_spectral_harmony`), and PeakVI — using `scib-metrics`
    - Evaluates batch correction metrics: iLISI (KNN), graph connectivity
    - Uses a dummy label (no bio-conservation metrics) since cell type labels are not yet assigned at this stage
    - Exports results table and CSV report to a specified output directory


## Gene-level (gene activity matrix)

- _Generate gene matrix_: [`generate_gene_matrix`](./sc_atac_tools/scripts/generate_gene_matrix)
    - Constructs a cell × gene activity matrix from fragment data via `snap.pp.make_gene_matrix` (hg38)
    - Filters lowly detected genes (`min_cells=5`)
    - Copies UMAP embedding from the bin-level AnnData into the gene matrix

- _Process genes_: [`process_genes`](./sc_atac_tools/scripts/process_genes)
    - Stores raw gene activity counts in `layers["gene_counts"]`
    - Normalizes (`normalize_total` + `log1p`) and identifies highly variable genes (HVG) using Pearson residuals (`scvi-tools` flavor)
    - Selects top N HVGs (default: 3000) per batch and runs PCA (default: 30 components)
    - Exports full gene feature metadata and HVG-only feature metadata as CSVs

- _Impute gene matrix_: [`impute_gene_matrix`](./sc_atac_tools/scripts/impute_gene_matrix)
    - Smooths and imputes the sparse gene activity matrix using MAGIC (`approximate` solver via `scanpy.external`)
    - Produces a denser representation useful for visualization
    - Note: imputed values are **not** used for MMC or scVI — raw counts are required for those steps, this AnnData object is saved


## _ANNOTATION_

- _Map my cells_: [`mmc`](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/sc_tools/scripts/main/mmc)
    - Runs Allen Brain Map's [MapMyCells](https://portal.brain-map.org/atlases-and-data/bkp/mapmycells) on the **raw** gene activity matrix against SEA-AD Human taxonomy
    - Must be run on raw (un-normalized) gene counts — before `process_genes`

- _Cell transcriptional phenotype_: [`transcriptional_phenotype`](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/sc_tools/scripts/main/transcriptional_phenotype)
    - Assigns `cell_type` to high-fidelity MMC mappings (correlation > 0.5, bootstrap probability > 0.5); all else labeled `"unknown"`
    - Annotates AnnData and exports full cell type assignments

> **Note**: `mmc` and `transcriptional_phenotype` are shared scripts from [`sc-rnaseq-wf`](https://github.com/ASAP-CRN/sc-rnaseq-wf). The gene activity matrix acts as a proxy for RNA expression by counting the TN5 insertions in each gene’s regulatory domain to enable cell type annotation.


## _DIFFERENTIAL CHROMATIN ANALYSIS_

- _Peak calling_: [`call_peaks`](./sc_atac_tools/scripts/call_peaks)
    - Calls peaks per cell type via `snap.tl.macs3` (groupby `cell_type`)
    - Constructs a peak-by-cell count matrix via `snap.pp.make_peak_matrix`

- _Motif enrichment analysis_: [`motif_enrichment`](./sc_atac_tools/scripts/motif_enrichment)
    - Identifies differentially accessible regions per cell type
    - Runs motif enrichment analysis via `snap.tl.motif_enrichment`
    - Links chromatin accessibility to transcription factor binding activity


# _PLOTTING_

- _Plot groups and features_: [`plot_groups_and_feats`](https://github.com/ASAP-CRN/sc-rnaseq-wf/tree/main/docker/sc_tools/scripts/main/plot_groups_and_feats)
    - Groups: `"sample"`, `"batch"`, `"cell_type"`, `"clusters_peakvi"`
    - Features: `"n_genes_by_counts"`, `"total_counts"`, `"pct_counts_mt"`, `"doublet_score"`

> **Note**: `plot_groups_and_feats` is a shared script from [`sc-rnaseq-wf`](https://github.com/ASAP-CRN/sc-rnaseq-wf).


# _EXPORT_

- _Export final artifacts_: [`export_final_artifacts`](./sc_atac_tools/scripts/export_final_artifacts)
    - Exports final `obs` metadata as `{cohort_id}.final_metadata.csv`
    - Writes final compressed AnnData object (`.h5ad`)
