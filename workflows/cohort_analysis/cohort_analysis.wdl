version 1.0

# Run steps in the cohort analysis

import "../../wf-common/wdl/tasks/write_cohort_sample_list.wdl" as WriteCohortSampleList
import "harmony_integration/harmony_integration.wdl" as HarmonyIntegration
import "peakvi_integration/peakvi_integration.wdl" as PeakVIIntegration
import "../../sc-rnaseq-wf/workflows/cohort_analysis/cohort_analysis.wdl" as ScCohortAnalysis
import "../../wf-common/wdl/tasks/upload_final_outputs.wdl" as UploadFinalOutputs

workflow cohort_analysis {
	input {
		String cohort_id
		Array[Array[String]] project_sample_ids
		Array[File] preprocessed_adata_objects

		# If provided, these files will be uploaded to the staging bucket alongside other intermediate files made by this workflow
		Array[String] preprocessing_output_file_paths = []

		# Allen Institute's Map My Cells
		File allen_brain_mmc_precomputed_stats_h5

		# Normalization parameters
		Int n_top_genes
		Int n_comps

		# Sample integration
		String batch_key
		String peakvi_latent_key
		Int peakvi_max_epochs
		Int peakvi_n_hidden
		Int peakvi_batch_size

		Array[String] groups
		Array[String] features

		String workflow_name
		String workflow_version
		String workflow_release
		String crn_release_version
		String run_timestamp
		String raw_data_path_prefix
		Array[String] staging_data_buckets
		String billing_project
		String container_registry
		String zones
	}

	String sub_workflow_name = "cohort_analysis"
	String sub_workflow_version = "1.0.0"

	Array[Array[String]] workflow_info = [[run_timestamp, workflow_name, workflow_version, workflow_release]]

	String raw_data_path = "~{raw_data_path_prefix}/~{sub_workflow_name}/~{sub_workflow_version}/~{run_timestamp}"

	call WriteCohortSampleList.write_cohort_sample_list {
		input:
			cohort_id = cohort_id,
			project_sample_ids = project_sample_ids,
			billing_project = billing_project,
			workflow_info = workflow_info,
			raw_data_path = raw_data_path,
			container_registry = container_registry,
			zones = zones
	}

	call merge_and_qc {
		input:
			cohort_id = cohort_id,
			preprocessed_adata_objects = preprocessed_adata_objects,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call reduce_dimensions {
		input:
			cohort_id = cohort_id,
			merged_adata_object = merge_and_qc.merged_adata_object, #!FileCoercion
			container_registry = container_registry,
			zones = zones
	}

	call HarmonyIntegration.harmony_integration {
		input:
			cohort_id = cohort_id,
			processed_bins_adata_object = reduce_dimensions.processed_bins_adata_object,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call PeakVIIntegration.peakvi_integration {
		input:
			cohort_id = cohort_id,
			processed_bins_adata_object = reduce_dimensions.processed_bins_adata_object,
			batch_key = batch_key,
			peakvi_latent_key = peakvi_latent_key,
			peakvi_max_epochs = peakvi_max_epochs,
			peakvi_n_hidden = peakvi_n_hidden,
			peakvi_batch_size = peakvi_batch_size,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call peak_calling as harmony_peak_calling {
		input:
			cohort_id = cohort_id,
			integrated_adata_object = harmony_integration.harmony_clustered_adata_object, #!FileCoercion
			integration_method = "harmony",
			macs3_groupby = "leiden",
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call peak_calling as peakvi_peak_calling {
		input:
			cohort_id = cohort_id,
			integrated_adata_object = peakvi_integration.peakvi_clustered_adata_object, #!FileCoercion
			integration_method = "peakvi",
			macs3_groupby = "leiden",
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call benchmark_sc_integration {
		input:
			cohort_id = cohort_id,
			harmony_merged_peaks_adata_object = harmony_peak_calling.merged_peaks_adata_object, #!FileCoercion
			peakvi_merged_peaks_adata_object = peakvi_peak_calling.merged_peaks_adata_object, #!FileCoercion
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call make_gene_matrix {
		input:
			cohort_id = cohort_id,
			harmony_merged_peaks_adata_object = harmony_peak_calling.merged_peaks_adata_object, #!FileCoercion
			container_registry = container_registry,
			zones = zones
	}

	call process_gene_matrix {
		input:
			cohort_id = cohort_id,
			gene_matrix_adata_object = make_gene_matrix.gene_matrix_adata_object, #!FileCoercion
			n_top_genes = n_top_genes,
			n_comps = n_comps,
			batch_key = batch_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call impute_gene_matrix {
		input:
			cohort_id = cohort_id,
			processed_gene_matrix_adata_object = process_gene_matrix.processed_gene_matrix_adata_object,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call ScCohortAnalysis.map_cell_types {
		input:
			cohort_id = cohort_id,
			filtered_adata_object = make_gene_matrix.gene_matrix_adata_object, #!FileCoercion
			allen_brain_mmc_precomputed_stats_h5 = allen_brain_mmc_precomputed_stats_h5,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call ScCohortAnalysis.add_mapped_cell_types {
		input:
			cohort_id = cohort_id,
			normalized_adata_object = harmony_peak_calling.merged_peaks_adata_object, #!FileCoercion
			mmc_results_csv = map_cell_types.mmc_results_csv, #!FileCoercion
			raw_data_path = raw_data_path,
			workflow_name = "pmdbs_sc_rnaseq",
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call peak_calling as celltype_peak_calling {
		input:
			cohort_id = cohort_id,
			integrated_adata_object = add_mapped_cell_types.mmc_adata_object,
			integration_method = "harmony",
			macs3_groupby = "cell_type",
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call motif_enrichment {
		input:
			cohort_id = cohort_id,
			celltype_merged_peaks_adata_object = celltype_peak_calling.merged_peaks_adata_object, #!FileCoercion
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call ScCohortAnalysis.plot_groups_and_features {
		input:
			cohort_id = cohort_id,
			final_adata_object = celltype_peak_calling.merged_peaks_adata_object, #!FileCoercion
			groups = groups,
			features = features,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call export_final_artifacts {
		input:
			cohort_id = cohort_id,
			celltype_merged_peaks_adata_object = celltype_peak_calling.merged_peaks_adata_object, #!FileCoercion
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call UploadFinalOutputs.upload_final_outputs as upload_preprocess_files {
		input:
			output_file_paths = preprocessing_output_file_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = "~{workflow_name}/release/~{crn_release_version}/preprocess",
			billing_project = billing_project,
			zones = zones
	}

	Array[String] cohort_analysis_final_output_paths = flatten([
		[
			write_cohort_sample_list.cohort_sample_list
		],
		[
			merge_and_qc.merged_adata_object,
			merge_and_qc.qc_initial_metadata_csv
		],
		merge_and_qc.qc_plots_png,
		[
			harmony_integration.harmony_clustered_umap_png
		],
		[
			harmony_peak_calling.merged_peaks_adata_object,
			harmony_peak_calling.merged_peaks_csv,
			harmony_peak_calling.peaks_matrix_adata_object
		],
		[
			peakvi_integration.peakvi_model_tar_gz,
			peakvi_integration.peakvi_clustered_umap_png
		],
		[
			peakvi_peak_calling.merged_peaks_adata_object,
			peakvi_peak_calling.merged_peaks_csv,
			peakvi_peak_calling.peaks_matrix_adata_object
		],
		[
			benchmark_sc_integration.scib_report_results_csv,
			benchmark_sc_integration.scib_report_results_svg
		],
		[
			process_gene_matrix.all_genes_csv,
			process_gene_matrix.hvg_genes_csv
		],
		[
			impute_gene_matrix.imputed_gene_matrix_adata_object
		],
		[
			map_cell_types.mmc_extended_results_json,
			map_cell_types.mmc_results_csv,
			map_cell_types.mmc_log_txt
		],
		[
			add_mapped_cell_types.mmc_results_parquet
		],
		[
			celltype_peak_calling.merged_peaks_adata_object,
			celltype_peak_calling.merged_peaks_csv,
			celltype_peak_calling.peaks_matrix_adata_object
		],
		[
			motif_enrichment.motifs_parquet
		],
		[
			plot_groups_and_features.groups_umap_plot_png,
			plot_groups_and_features.features_umap_plot_png
		],
		[
			export_final_artifacts.final_adata_object,
			export_final_artifacts.final_metadata_csv
		]
	]) #!StringCoercion

	call UploadFinalOutputs.upload_final_outputs as upload_cohort_analysis_files {
		input:
			output_file_paths = cohort_analysis_final_output_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = "~{workflow_name}/release/~{crn_release_version}/~{sub_workflow_name}",
			billing_project = billing_project,
			zones = zones
	}

	output {
		File cohort_sample_list = write_cohort_sample_list.cohort_sample_list #!FileCoercion

		# Merged adata objects and processed bins adata object
		File merged_adata_object = merge_and_qc.merged_adata_object #!FileCoercion
		File qc_initial_metadata_csv = merge_and_qc.qc_initial_metadata_csv #!FileCoercion
		Array[File] qc_plots_png = merge_and_qc.qc_plots_png #!FileCoercion
		File processed_bins_adata_object = reduce_dimensions.processed_bins_adata_object

		# Harmony integrated adata objects and outputs
		File harmony_integrated_adata_object = harmony_integration.harmony_integrated_adata_object
		File harmony_clustered_adata_object = harmony_integration.harmony_clustered_adata_object
		File harmony_clustered_umap_png = harmony_integration.harmony_clustered_umap_png #!FileCoercion
		File harmony_merged_peaks_adata_object = harmony_peak_calling.merged_peaks_adata_object #!FileCoercion
		File harmony_merged_peaks_csv = harmony_peak_calling.merged_peaks_csv #!FileCoercion
		File harmony_peaks_matrix_adata_object = harmony_peak_calling.peaks_matrix_adata_object #!FileCoercion

		# PeakVI integrated adata objects and outputs
		File peakvi_integrated_adata_object = peakvi_integration.peakvi_integrated_adata_object
		File peakvi_model_tar_gz = peakvi_integration.peakvi_model_tar_gz #!FileCoercion
		File peakvi_clustered_adata_object = peakvi_integration.peakvi_clustered_adata_object
		File peakvi_clustered_umap_png = peakvi_integration.peakvi_clustered_umap_png #!FileCoercion
		File peakvi_merged_peaks_adata_object = peakvi_peak_calling.merged_peaks_adata_object #!FileCoercion
		File peakvi_merged_peaks_csv = peakvi_peak_calling.merged_peaks_csv #!FileCoercion
		File peakvi_peaks_matrix_adata_object = peakvi_peak_calling.peaks_matrix_adata_object #!FileCoercion

		# Benchmark sc integration tools
		File scib_report_results_csv = benchmark_sc_integration.scib_report_results_csv #!FileCoercion
		File scib_report_results_svg = benchmark_sc_integration.scib_report_results_svg #!FileCoercion

		# Gene matrix adata object
		File gene_matrix_adata_object = make_gene_matrix.gene_matrix_adata_object
		File processed_gene_matrix_adata_object = process_gene_matrix.processed_gene_matrix_adata_object
		File all_genes_csv = process_gene_matrix.all_genes_csv #!FileCoercion
		File hvg_genes_csv = process_gene_matrix.hvg_genes_csv #!FileCoercion
		File imputed_gene_matrix_adata_object = impute_gene_matrix.imputed_gene_matrix_adata_object #!FileCoercion

		# MMC from sc RNA-seq pipeline
		File mmc_extended_results_json = map_cell_types.mmc_extended_results_json #!FileCoercion
		File mmc_results_csv = map_cell_types.mmc_results_csv #!FileCoercion
		File mmc_log_txt = map_cell_types.mmc_log_txt #!FileCoercion
		File mmc_adata_object = add_mapped_cell_types.mmc_adata_object
		File mmc_results_parquet = add_mapped_cell_types.mmc_results_parquet #!FileCoercion

		# Differential chromatin analysis
		File celltype_merged_peaks_adata_object = celltype_peak_calling.merged_peaks_adata_object #!FileCoercion
		File celltype_merged_peaks_csv = celltype_peak_calling.merged_peaks_csv #!FileCoercion
		File celltype_peaks_matrix_adata_object = celltype_peak_calling.peaks_matrix_adata_object #!FileCoercion
		File motifs_parquet = motif_enrichment.motifs_parquet #!FileCoercion

		# Groups and features plots
		File groups_umap_plot_png = plot_groups_and_features.groups_umap_plot_png #!FileCoercion
		File features_umap_plot_png = plot_groups_and_features.features_umap_plot_png #!FileCoercion

		# Final artifacts
		File final_adata_object = export_final_artifacts.final_adata_object #!FileCoercion
		File final_metadata_csv = export_final_artifacts.final_metadata_csv #!FileCoercion

		Array[File] preprocess_manifest_tsvs = upload_preprocess_files.manifests #!FileCoercion
		Array[File] cohort_analysis_manifest_tsvs = upload_cohort_analysis_files.manifests #!FileCoercion
	}

	meta {
		description: "Run team-level and/or cross-team cohort analysis on the 10x Genomics Chromium Epi ATAC data by filtering, normalization, dimensionality reduction, sample integration, clustering, peak calling, and differential chromatin analysis."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		project_sample_ids: {help: "Associated team ID, sample ID, and dataset DOI URL; used to generate a sample list."}
		preprocessed_adata_objects: {help: "An array of preprocessed AnnData objects to run cohort analysis on."}
		preprocessing_output_file_paths: {help: "Selected preprocessed output files to upload to the staging bucket alongside selected cohort analysis output files."}
		allen_brain_mmc_precomputed_stats_h5: {help: "A precomputed statistics file from the Allen Brain Cell Atlas containing reference statistics (the average gene expression profile per cell type cluster and cell type taxonomy)."}
		n_top_genes: {help: "Number of highly-variable genes to keep. [3000]"}
		n_comps: {help: "Number of principal components to compute. [30]"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		peakvi_latent_key: {help: "Latent key to save the peakVI latent to. ['X_peakVI']"}
		peakvi_max_epochs: {help: "The maximum number of full passes through the training data during PeakVI model training. If the model converges early, training will halt before this limit is reached. [300]"}
		peakvi_n_hidden: {help: "Number of nodes per hidden layer (i.e., the number of neurons per fully-connected layer between the input features and the latent space). [128]"}
		peakvi_batch_size: {help: "Training batch size for PeakVI. Controls how many cells are processed per training step. [128]"}
		groups: {help: "Groups to produce umap plots for. ['sample', 'batch', 'team', 'dataset', 'batch_id', 'leiden']"}
		features: {help: "Features to produce umap plots for. ['n_fragment', 'tsse', 'frac_dup', 'frac_mito', 'doublet_score', 'doublet_probability']"}
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_version: {help: "Workflow version; stored in the file-level manifest and final manifest with all saved files."}
		workflow_release: {help: "GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		crn_release_version: {help: "CRN Cloud release version; used to organize outputs and for the CRN Cloud release."}
		run_timestamp: {help: "UTC timestamp; stored in the file-level manifest and final manifest with all saved files."}
		raw_data_path_prefix: {help: "Raw data bucket path prefix; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis`)."}
		staging_data_buckets: {help: "Array of staging data buckets to upload intermediate files to (i.e., DEV or UAT buckets depending on internal QC status)."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task merge_and_qc {
	input {
		String cohort_id
		Array[File] preprocessed_adata_objects

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(preprocessed_adata_objects, "GB") * 13 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(preprocessed_adata_objects, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		while read -r adata_objects || [[ -n "${adata_objects}" ]]; do 
			adata_path=$(realpath "${adata_objects}")
			sample=$(basename "${adata_path}" ".cleaned_unfiltered.h5ad")
			echo -e "${sample}\t${adata_path}" >> adata_samples_paths.tsv
		done < ~{write_lines(preprocessed_adata_objects)}

		/usr/bin/time -v \
			merge_and_qc \
			--adata-objects-fofn adata_samples_paths.tsv \
			--plot-prefix ~{cohort_id} \
			--adata-output ~{cohort_id}.merged_filtered.h5ad \
			--output-metadata ~{cohort_id}.initial_metadata.csv

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.merged_filtered.h5ad" \
			-o "~{cohort_id}.initial_metadata.csv" \
			-o "~{cohort_id}.frag_size_distr.png" \
			-o "~{cohort_id}.tsse.png"
	>>>

	output {
		String merged_adata_object = "~{raw_data_path}/~{cohort_id}.merged_filtered.h5ad"
		String qc_initial_metadata_csv = "~{raw_data_path}/~{cohort_id}.initial_metadata.csv"

		Array[String] qc_plots_png = [
			"~{raw_data_path}/~{cohort_id}.frag_size_distr.png",
			"~{raw_data_path}/~{cohort_id}.tsse.png"
		]
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} SSD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Merges sample-level AnnData objects to a single cohort-level AnnData object and QC based on covariates including matrices, features, and doublets."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		preprocessed_adata_objects: {help: "An array of preprocessed AnnData objects to run cohort analysis on."}
		raw_data_path: {help: "Raw data bucket path for merged adata and QC plots outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task reduce_dimensions {
	input {
		String cohort_id
		File merged_adata_object

		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(merged_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(merged_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		process_bins \
			--adata-input ~{merged_adata_object} \
			--adata-output ~{cohort_id}.processed_bins.h5ad
	>>>

	output {
		File processed_bins_adata_object = "~{cohort_id}.processed_bins.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Performs spectral decomposition and UMAP embedding on the bin-level chromatin accessibility matrix for dimensionality reduction."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		merged_adata_object: {help: "Merged AnnData object."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task peak_calling {
	input {
		String cohort_id
		File integrated_adata_object

		String integration_method
		String macs3_groupby

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(integrated_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(integrated_adata_object, "GB") * 4 + 100)

	command <<<
		set -euo pipefail

		export TMPDIR=/mnt/disks/cromwell_root/macs3_tmp
		mkdir -p $TMPDIR

		/usr/bin/time -v \
		call_peaks \
			--adata-input ~{integrated_adata_object} \
			--macs3-groupby ~{macs3_groupby} \
			--output-prefix ~{cohort_id}.~{integration_method}.~{macs3_groupby} \
			--adata-output ~{cohort_id}.~{integration_method}.~{macs3_groupby}.merged_peaks.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.~{integration_method}.~{macs3_groupby}.merged_peaks.h5ad" \
			-o "~{cohort_id}.~{integration_method}.~{macs3_groupby}.merged_peaks.csv" \
			-o "~{cohort_id}.~{integration_method}.~{macs3_groupby}.peaks_matrix.h5ad"
	>>>

	output {
		String merged_peaks_adata_object = "~{raw_data_path}/~{cohort_id}.~{integration_method}.~{macs3_groupby}.merged_peaks.h5ad"
		String merged_peaks_csv = "~{raw_data_path}/~{cohort_id}.~{integration_method}.~{macs3_groupby}.merged_peaks.csv"
		String peaks_matrix_adata_object = "~{raw_data_path}/~{cohort_id}.~{integration_method}.~{macs3_groupby}.peaks_matrix.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 32
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Calls peaks using MACS3 based on a group (e.g., Leiden clusters or cell types), merges peaks across groups, and generates a cell-by-peak matrix."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		integrated_adata_object: {help: "Batch corrected and integrated AnnData object."}
		integration_method: {help: "Single cell integration method."}
		macs3_groupby: {help: "The cell grouping before peak calling."}
		raw_data_path: {help: "Raw data bucket path for peak calling outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task benchmark_sc_integration {
	input {
		String cohort_id
		File harmony_merged_peaks_adata_object
		File peakvi_merged_peaks_adata_object

		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size([harmony_merged_peaks_adata_object, peakvi_merged_peaks_adata_object], "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size([harmony_merged_peaks_adata_object, peakvi_merged_peaks_adata_object], "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		mkdir scib_report_dir

		/usr/bin/time -v \
		benchmark_sc_integration \
			--adata-harmony-input ~{harmony_merged_peaks_adata_object} \
			--adata-peakvi-input ~{peakvi_merged_peaks_adata_object} \
			--batch-key ~{batch_key} \
			--output-report-dir scib_report_dir

		mv "scib_report_dir/scib_report.csv" "scib_report_dir/~{cohort_id}.scib_report.csv"
		mv "scib_report_dir/scib_results.svg" "scib_report_dir/~{cohort_id}.scib_results.svg"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "scib_report_dir/~{cohort_id}.scib_report.csv" \
			-o "scib_report_dir/~{cohort_id}.scib_results.svg"
	>>>

	output {
		String scib_report_results_csv = "~{raw_data_path}/~{cohort_id}.scib_report.csv"
		String scib_report_results_svg = "~{raw_data_path}/~{cohort_id}.scib_results.svg"
	}

	runtime {
		docker: "~{container_registry}/scvi_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Benchmarks Harmony and PeakVI batch correction methods against an unintegrated baseline using scib-metrics and generates a summary report and results table."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		harmony_merged_peaks_adata_object: {help: "Batch corrected, integrated, clustered, merged peaks AnnData object."}
		peakvi_merged_peaks_adata_object: {help: "Batch corrected, integrated, clustered, merged peaks AnnData object."}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for benchmarking outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task make_gene_matrix {
	input {
		String cohort_id
		File harmony_merged_peaks_adata_object

		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(harmony_merged_peaks_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(harmony_merged_peaks_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		generate_gene_matrix \
			--adata-input ~{harmony_merged_peaks_adata_object} \
			--output-prefix ~{cohort_id}
	>>>

	output {
		File gene_matrix_adata_object = "~{cohort_id}.gene_matrix.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Generates a cell-by-gene matrix by counting the TN5 insertions in each gene’s regulatory domain and using the hg38 genome annotation, filters lowly detected genes, and transfers the UMAP embedding."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		harmony_merged_peaks_adata_object: {help: "Batch corrected, integrated, clustered, merged peaks AnnData object."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task process_gene_matrix {
	input {
		String cohort_id
		File gene_matrix_adata_object

		Int n_top_genes
		Int n_comps
		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(gene_matrix_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(gene_matrix_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		process_genes \
			--adata-input ~{gene_matrix_adata_object} \
			--batch-key ~{batch_key} \
			--n-top-genes ~{n_top_genes} \
			--n-comps ~{n_comps} \
			--adata-output ~{cohort_id}.processed_gene_matrix.h5ad \
			--output-all-genes ~{cohort_id}.all_genes.csv \
			--output-hvg-genes ~{cohort_id}.hvg_genes.csv

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.all_genes.csv" \
			-o "~{cohort_id}.hvg_genes.csv"
	>>>

	output {
		File processed_gene_matrix_adata_object = "~{cohort_id}.processed_gene_matrix.h5ad"
		String all_genes_csv = "~{raw_data_path}/~{cohort_id}.all_genes.csv"
		String hvg_genes_csv = "~{raw_data_path}/~{cohort_id}.hvg_genes.csv"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Normalizes the cell-by-gene matrix, selects highly variable genes (HVGs) using Pearson residuals, and performs PCA."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		gene_matrix_adata_object: {help: "Gene matrix AnnData object."}
		n_top_genes: {help: "Number of HVG genes to keep. [3000]"}
		n_comps: {help: "Number of principal components to compute. [30]"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for processed gene matrix outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task impute_gene_matrix {
	input {
		String cohort_id
		File processed_gene_matrix_adata_object

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(processed_gene_matrix_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(processed_gene_matrix_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		impute_gene_matrix \
			--adata-input ~{processed_gene_matrix_adata_object} \
			--adata-output "~{cohort_id}.gene_matrix.magic_imputed.h5ad"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.gene_matrix.magic_imputed.h5ad"
	>>>

	output {
		String imputed_gene_matrix_adata_object = "~{raw_data_path}/~{cohort_id}.gene_matrix.magic_imputed.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Applies MAGIC imputation to smooth the cell-by-gene matrix, recovering gene expression structure by diffusing signal across similar cells."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		processed_gene_matrix_adata_object: {help: "Processed gene matrix AnnData object."}
		raw_data_path: {help: "Raw data bucket path for imputed gene matrix output; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task motif_enrichment {
	input {
		String cohort_id
		File celltype_merged_peaks_adata_object

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(celltype_merged_peaks_adata_object, "GB") * 15 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(celltype_merged_peaks_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		find_motif_enrichment \
			--adata-input ~{celltype_merged_peaks_adata_object} \
			--output-prefix ~{cohort_id}

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.motifs.parquet"
	>>>

	output {
		String motifs_parquet = "~{raw_data_path}/~{cohort_id}.motifs.parquet"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 8
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Identifies cell type–specific marker peaks and performs TF motif enrichment analysis."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		celltype_merged_peaks_adata_object: {help: "Batch corrected, integrated, clustered, merged peaks, cell type annotated AnnData object."}
		raw_data_path: {help: "Raw data bucket path for motifs output; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task export_final_artifacts {
	input {
		String cohort_id
		File celltype_merged_peaks_adata_object

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(celltype_merged_peaks_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(celltype_merged_peaks_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		export_final_artifacts \
			--cohort-id ~{cohort_id} \
			--adata-input ~{celltype_merged_peaks_adata_object} \
			--adata-output ~{cohort_id}.final.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.final.h5ad" \
			-o "~{cohort_id}.final_metadata.csv"

	>>>

	output {
		String final_adata_object = "~{raw_data_path}/~{cohort_id}.final.h5ad"
		String final_metadata_csv = "~{raw_data_path}/~{cohort_id}.final_metadata.csv"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Exports final AnnData object and grab the metadata."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		celltype_merged_peaks_adata_object: {help: "Batch corrected, integrated, clustered, merged peaks, cell type annotated AnnData object acting as the final AnnData object."}
		raw_data_path: {help: "Raw data bucket path for final outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
