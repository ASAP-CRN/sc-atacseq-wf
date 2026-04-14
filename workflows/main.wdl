version 1.0

# Harmonized human PMDBS brain sc/sn ATAC-seq workflow entrypoint

import "structs.wdl"
import "../wf-common/wdl/tasks/get_workflow_metadata.wdl" as GetWorkflowMetadata
import "preprocess/preprocess.wdl" as Preprocess
import "cohort_analysis/cohort_analysis.wdl" as CohortAnalysis

workflow sc_atacseq_analysis {
	input {
		String cohort_id
		Array[Project] projects

		# Preprocess
		File cellranger_atac_reference_data
		File cellranger_atac_reference_chrom_sizes
		Array[File] vireo_assignment_files

		# Allen Institute's Map My Cells
		File allen_brain_mmc_precomputed_stats_h5

		# Normalization parameters
		Int n_top_genes = 3000
		Int n_comps = 30

		# Sample integration
		String batch_key = "batch_id"
		String peakvi_latent_key = "X_peakVI"
		Int peakvi_max_epochs = 300

		Array[String] groups = ["sample", "batch", "team", "dataset", "batch_id", "leiden"]
		Array[String] features = ["n_fragment", "tsse", "frac_dup", "frac_mito", "doublet_score", "doublet_probability"]

		# Cohort analysis
		Boolean run_cross_team_cohort_analysis = false
		String cohort_raw_data_bucket
		Array[String] cohort_staging_data_buckets

		String container_registry
		String zones = "us-central1-c us-central1-f"
	}

	String workflow_execution_path = "workflow_execution"
	String workflow_name = "pmdbs_sc_atacseq"
	String workflow_version = "v1.0.0"
	String workflow_release = "https://github.com/ASAP-CRN/sc-atacseq-wf/releases/tag/sc_atacseq_analysis-~{workflow_version}"
	String crn_release_version = "v5.0.0"

	call GetWorkflowMetadata.get_workflow_metadata {
		input:
			zones = zones
	}

	scatter (project in projects) {
		String project_raw_data_path_prefix = "~{project.raw_data_bucket}/~{workflow_execution_path}/~{workflow_name}"

		call Preprocess.preprocess {
			input:
				team_id = project.asap_team_id,
				dataset_id = project.asap_dataset_id,
				dataset_doi_url = project.asap_dataset_doi_url,
				pools = project.pools,
				cellranger_atac_reference_data = cellranger_atac_reference_data,
				cellranger_atac_reference_chrom_sizes = cellranger_atac_reference_chrom_sizes,
				vireo_assignment_files = vireo_assignment_files,
				workflow_name = workflow_name,
				workflow_version = workflow_version,
				workflow_release = workflow_release,
				run_timestamp = get_workflow_metadata.timestamp,
				raw_data_path_prefix = project_raw_data_path_prefix,
				billing_project = get_workflow_metadata.billing_project,
				container_registry = container_registry,
				zones = zones
		}

		Array[String] preprocessing_output_file_paths = flatten([
			preprocess.atac_outputs_tar_gz,
			preprocess.singlecell_csv,
			preprocess.peaks_bed,
			preprocess.cut_sites_bigwig,
			preprocess.raw_peaks,
			preprocess.filtered_peaks,
			preprocess.filtered_tf,
			preprocess.fragments_tsv_gz,
			preprocess.summary_csv,
			preprocess.peak_annotation_tsv,
			preprocess.peak_motif_mapping_bed,
			preprocess.initial_adata_object
		]) #!StringCoercion

		if (project.run_project_cohort_analysis) {
			call CohortAnalysis.cohort_analysis as project_cohort_analysis {
				input:
					cohort_id = project.asap_team_id,
					project_sample_ids = preprocess.project_sample_ids,
					preprocessed_adata_objects = preprocess.initial_adata_object,
					preprocessing_output_file_paths = preprocessing_output_file_paths,
					allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
					n_top_genes = n_top_genes,
					n_comps = n_comps,
					batch_key = batch_key,
					peakvi_latent_key = peakvi_latent_key,
					peakvi_max_epochs = peakvi_max_epochs,
					groups = groups,
					features = features,
					workflow_name = workflow_name,
					workflow_version = workflow_version,
					workflow_release = workflow_release,
					crn_release_version = crn_release_version,
					run_timestamp = get_workflow_metadata.timestamp,
					raw_data_path_prefix = project_raw_data_path_prefix,
					staging_data_buckets = project.staging_data_buckets,
					billing_project = get_workflow_metadata.billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}
	}

	if (run_cross_team_cohort_analysis) {
		String cohort_raw_data_path_prefix = "~{cohort_raw_data_bucket}/~{workflow_execution_path}/~{workflow_name}"

		call CohortAnalysis.cohort_analysis as cross_team_cohort_analysis {
			input:
				cohort_id = cohort_id,
				project_sample_ids = flatten(preprocess.project_sample_ids),
				preprocessed_adata_objects = flatten(preprocess.initial_adata_object),
				preprocessing_output_file_paths = flatten(preprocessing_output_file_paths),
				allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
				n_top_genes = n_top_genes,
				n_comps = n_comps,
				batch_key = batch_key,
				peakvi_latent_key = peakvi_latent_key,
				peakvi_max_epochs = peakvi_max_epochs,
				groups = groups,
				features = features,
				workflow_name = workflow_name,
				workflow_version = workflow_version,
				workflow_release = workflow_release,
				crn_release_version = crn_release_version,
				run_timestamp = get_workflow_metadata.timestamp,
				raw_data_path_prefix = cohort_raw_data_path_prefix,
				staging_data_buckets = cohort_staging_data_buckets,
				billing_project = get_workflow_metadata.billing_project,
				container_registry = container_registry,
				zones = zones
		}
	}

	output {
		# Sample-level outputs
		# Sample list
		Array[Array[Array[String]]] project_sample_ids = preprocess.project_sample_ids

		# Cell Ranger ATAC
		Array[Array[File]] cellranger_atac_outputs_tar_gz = preprocess.atac_outputs_tar_gz
		Array[Array[File]] cellranger_atac_singlecell_csv = preprocess.singlecell_csv
		Array[Array[File]] cellranger_atac_peaks_bed = preprocess.peaks_bed
		Array[Array[File]] cellranger_atac_cut_sites_bigwig = preprocess.cut_sites_bigwig
		Array[Array[File]] cellranger_atac_raw_peaks = preprocess.raw_peaks
		Array[Array[File]] cellranger_atac_filtered_peaks = preprocess.filtered_peaks
		Array[Array[File]] cellranger_atac_filtered_tf = preprocess.filtered_tf
		Array[Array[File]] cellranger_atac_fragments_tsv_gz = preprocess.fragments_tsv_gz
		Array[Array[File]] cellranger_atac_summary_csv = preprocess.summary_csv
		Array[Array[File]] cellranger_atac_peak_annotation_tsv = preprocess.peak_annotation_tsv
		Array[Array[File]] cellranger_atac_peak_motif_mapping_bed = preprocess.peak_motif_mapping_bed

		# Preprocess
		Array[Array[File]] initial_adata_object = preprocess.initial_adata_object

		# Project cohort analysis outputs
		## List of samples included in the cohort
		Array[File?] project_cohort_sample_list = project_cohort_analysis.cohort_sample_list

		# Merged adata objects, QC plots, processed bins adata object
		Array[File?] project_merged_adata_object = project_cohort_analysis.merged_adata_object
		Array[File?] project_qc_initial_metadata_csv = project_cohort_analysis.qc_initial_metadata_csv
		Array[Array[File]?] project_qc_plots_png = project_cohort_analysis.qc_plots_png
		Array[File?] project_processed_bins_adata_object = project_cohort_analysis.processed_bins_adata_object

		# Sc integration outputs
		Array[File?] project_harmony_integrated_adata_object = project_cohort_analysis.harmony_integrated_adata_object
		Array[File?] project_harmony_clustered_adata_object = project_cohort_analysis.harmony_clustered_adata_object
		Array[File?] project_harmony_clustered_umap_png = project_cohort_analysis.harmony_clustered_umap_png
		Array[File?] project_harmony_merged_peaks_adata_object = project_cohort_analysis.harmony_merged_peaks_adata_object
		Array[File?] project_harmony_merged_peaks_csv = project_cohort_analysis.harmony_merged_peaks_csv
		Array[File?] project_harmony_peaks_matrix_adata_object = project_cohort_analysis.harmony_peaks_matrix_adata_object

		Array[File?] project_peakvi_integrated_adata_object = project_cohort_analysis.peakvi_integrated_adata_object
		Array[File?] project_peakvi_model_tar_gz = project_cohort_analysis.peakvi_model_tar_gz
		Array[File?] project_peakvi_clustered_adata_object = project_cohort_analysis.peakvi_clustered_adata_object
		Array[File?] project_peakvi_clustered_umap_png = project_cohort_analysis.peakvi_clustered_umap_png
		Array[File?] project_peakvi_merged_peaks_adata_object = project_cohort_analysis.peakvi_merged_peaks_adata_object
		Array[File?] project_peakvi_merged_peaks_csv = project_cohort_analysis.peakvi_merged_peaks_csv
		Array[File?] project_peakvi_peaks_matrix_adata_object = project_cohort_analysis.peakvi_peaks_matrix_adata_object

		# Benchmark sc integration tools
		Array[File?] project_scib_report_results_csv = project_cohort_analysis.scib_report_results_csv
		Array[File?] project_scib_report_results_svg = project_cohort_analysis.scib_report_results_svg

		# Gene matrix adata object
		Array[File?] project_gene_matrix_adata_object = project_cohort_analysis.gene_matrix_adata_object
		Array[File?] project_processed_gene_matrix_adata_object = project_cohort_analysis.processed_gene_matrix_adata_object
		Array[File?] project_all_genes_csv = project_cohort_analysis.all_genes_csv
		Array[File?] project_hvg_genes_csv = project_cohort_analysis.hvg_genes_csv
		Array[File?] project_imputed_gene_matrix_adata_object = project_cohort_analysis.imputed_gene_matrix_adata_object

		# MMC from sc RNA-seq pipeline
		Array[File?] project_mmc_extended_results_json = project_cohort_analysis.mmc_extended_results_json
		Array[File?] project_mmc_results_csv = project_cohort_analysis.mmc_results_csv
		Array[File?] project_mmc_log_txt = project_cohort_analysis.mmc_log_txt
		Array[File?] project_mmc_adata_object = project_cohort_analysis.mmc_adata_object
		Array[File?] project_mmc_results_parquet = project_cohort_analysis.mmc_results_parquet

		# Differential chromatin analysis
		Array[File?] project_celltype_merged_peaks_adata_object = project_cohort_analysis.celltype_merged_peaks_adata_object
		Array[File?] project_celltype_merged_peaks_csv = project_cohort_analysis.celltype_merged_peaks_csv
		Array[File?] project_celltype_peaks_matrix_adata_object = project_cohort_analysis.celltype_peaks_matrix_adata_object
		Array[File?] project_motifs_parquet = project_cohort_analysis.motifs_parquet

		# Groups and features plots
		Array[File?] project_groups_umap_plot_png = project_cohort_analysis.groups_umap_plot_png
		Array[File?] project_features_umap_plot_png = project_cohort_analysis.features_umap_plot_png

		# Final artifacts
		Array[File?] project_final_adata_object = project_cohort_analysis.final_adata_object
		Array[File?] project_final_metadata_csv = project_cohort_analysis.final_metadata_csv

		Array[Array[File]?] preprocess_manifests = project_cohort_analysis.preprocess_manifest_tsvs
		Array[Array[File]?] project_manifests = project_cohort_analysis.cohort_analysis_manifest_tsvs

		# Cross-team cohort analysis outputs
		## List of samples included in the cohort
		File? cohort_sample_list = cross_team_cohort_analysis.cohort_sample_list

		# Merged adata objects, QC plots, processed bins adata object
		File? cohort_merged_adata_object = cross_team_cohort_analysis.merged_adata_object
		File? cohort_qc_initial_metadata_csv = cross_team_cohort_analysis.qc_initial_metadata_csv
		Array[File]? cohort_qc_plots_png = cross_team_cohort_analysis.qc_plots_png
		File? cohort_processed_bins_adata_object = cross_team_cohort_analysis.processed_bins_adata_object

		# Sc integration outputs
		File? cohort_harmony_integrated_adata_object = cross_team_cohort_analysis.harmony_integrated_adata_object
		File? cohort_harmony_clustered_adata_object = cross_team_cohort_analysis.harmony_clustered_adata_object
		File? cohort_harmony_clustered_umap_png = cross_team_cohort_analysis.harmony_clustered_umap_png
		File? cohort_harmony_merged_peaks_adata_object = cross_team_cohort_analysis.harmony_merged_peaks_adata_object
		File? cohort_harmony_merged_peaks_csv = cross_team_cohort_analysis.harmony_merged_peaks_csv
		File? cohort_harmony_peaks_matrix_adata_object = cross_team_cohort_analysis.harmony_peaks_matrix_adata_object

		File? cohort_peakvi_integrated_adata_object = cross_team_cohort_analysis.peakvi_integrated_adata_object
		File? cohort_peakvi_model_tar_gz = cross_team_cohort_analysis.peakvi_model_tar_gz
		File? cohort_peakvi_clustered_adata_object = cross_team_cohort_analysis.peakvi_clustered_adata_object
		File? cohort_peakvi_clustered_umap_png = cross_team_cohort_analysis.peakvi_clustered_umap_png
		File? cohort_peakvi_merged_peaks_adata_object = cross_team_cohort_analysis.peakvi_merged_peaks_adata_object
		File? cohort_peakvi_merged_peaks_csv = cross_team_cohort_analysis.peakvi_merged_peaks_csv
		File? cohort_peakvi_peaks_matrix_adata_object = cross_team_cohort_analysis.peakvi_peaks_matrix_adata_object

		# Benchmark sc integration tools
		File? cohort_scib_report_results_csv = cross_team_cohort_analysis.scib_report_results_csv
		File? cohort_scib_report_results_svg = cross_team_cohort_analysis.scib_report_results_svg

		# Gene matrix adata object
		File? cohort_gene_matrix_adata_object = cross_team_cohort_analysis.gene_matrix_adata_object
		File? cohort_processed_gene_matrix_adata_object = cross_team_cohort_analysis.processed_gene_matrix_adata_object
		File? cohort_all_genes_csv = cross_team_cohort_analysis.all_genes_csv
		File? cohort_hvg_genes_csv = cross_team_cohort_analysis.hvg_genes_csv
		File? cohort_imputed_gene_matrix_adata_object = cross_team_cohort_analysis.imputed_gene_matrix_adata_object

		# MMC from sc RNA-seq pipeline
		File? cohort_mmc_extended_results_json = cross_team_cohort_analysis.mmc_extended_results_json
		File? cohort_mmc_results_csv = cross_team_cohort_analysis.mmc_results_csv
		File? cohort_mmc_log_txt = cross_team_cohort_analysis.mmc_log_txt
		File? cohort_mmc_adata_object = cross_team_cohort_analysis.mmc_adata_object
		File? cohort_mmc_results_parquet = cross_team_cohort_analysis.mmc_results_parquet

		# Differential chromatin analysis
		File? cohort_celltype_merged_peaks_adata_object = cross_team_cohort_analysis.celltype_merged_peaks_adata_object
		File? cohort_celltype_merged_peaks_csv = cross_team_cohort_analysis.celltype_merged_peaks_csv
		File? cohort_celltype_peaks_matrix_adata_object = cross_team_cohort_analysis.celltype_peaks_matrix_adata_object
		File? cohort_motifs_parquet = cross_team_cohort_analysis.motifs_parquet

		# Groups and features plots
		File? cohort_groups_umap_plot_png = cross_team_cohort_analysis.groups_umap_plot_png
		File? cohort_features_umap_plot_png = cross_team_cohort_analysis.features_umap_plot_png

		# Final artifacts
		File? cohort_final_adata_object = cross_team_cohort_analysis.final_adata_object
		File? cohort_final_metadata_csv = cross_team_cohort_analysis.final_metadata_csv

		Array[File]? cohort_manifests = cross_team_cohort_analysis.cohort_analysis_manifest_tsvs
	}

	meta {
		description: "Harmonized human postmortem-derived brain sequencing (PMDBS) brain sc/sn ATAC-seq workflow."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files during cross-team cohort analysis."}
		projects: {help: "The project ID, set of samples and their associated reads and metadata, output bucket locations, sc data type, and whether or not to run project-level cohort analysis."}
		cellranger_atac_reference_data: {help: "Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads."}
		cellranger_atac_reference_chrom_sizes: {help: "Chromosome sizes file (.chrom.sizes or .fa.fai) from the Cell Ranger ATAC reference, used to validate fragment coordinates during splitting."}
		sample_fragments_tsv: {help: "TSV mapping sample names to their corresponding fragment files, used by scatac_fragment_tools to identify which pool-level fragments to split."}
		cell_barcodes_tsv: {help: "TSV mapping cell barcodes to sample identities, used by scatac_fragment_tools to assign fragments to individual samples during splitting."}
		allen_brain_mmc_precomputed_stats_h5: {help: "A precomputed statistics file from the Allen Brain Cell Atlas containing reference statistics (the average gene expression profile per cell type cluster and cell type taxonomy)."}
		n_top_genes: {help: "Number of HVG genes to keep. [3000]"}
		n_comps: {help: "Number of principal components to compute. [30]"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		peakvi_latent_key: {help: "Latent key to save the peakVI latent to. ['X_peakVI']"}
		peakvi_max_epochs: {help: "The maximum number of full passes through the training data during PeakVI model training. If the model converges early, training will halt before this limit is reached. [300]"}
		groups: {help: "Groups to produce umap plots for. ['sample', 'batch', 'team', 'dataset', 'batch_id', 'leiden']"}
		features: {help: "Features to produce umap plots for. ['n_fragment', 'tsse', 'frac_dup', 'frac_mito', 'doublet_score', 'doublet_probability']"}
		run_cross_team_cohort_analysis: {help: "Whether to run downstream harmonization steps on all samples across projects. If set to false, only preprocessing steps (cellranger and generating the initial adata object(s)) will run for samples. [false]"}
		cohort_raw_data_bucket: {help: "Bucket to upload cross-team cohort intermediate files to."}
		cohort_staging_data_buckets: {help: "Set of buckets to stage cross-team cohort analysis outputs in."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
