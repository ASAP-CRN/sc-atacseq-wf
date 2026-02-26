version 1.0

# Run steps in the cohort analysis

import "../../wf-common/wdl/tasks/write_cohort_sample_list.wdl" as WriteCohortSampleList
import "harmony_integration/harmony_integration.wdl" as HarmonyIntegration
import "peakvi_integration/peakvi_integration.wdl" as PeakVIIntegration
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
		String peakvi_latent_key
		String batch_key

		Array[String] groups
		Array[String] features

		String workflow_name
		String workflow_version
		String workflow_release
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

	call UploadFinalOutputs.upload_final_outputs as upload_preprocess_files {
		input:
			output_file_paths = preprocessing_output_file_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = "~{workflow_name}/preprocess",
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
			harmony_integration.harmony_clustered_adata_object,
			harmony_integration.harmony_clustered_umap_png
		],
		[
			peakvi_integration.peakvi_model_tar_gz,
			peakvi_integration.peakvi_clustered_adata_object,
			peakvi_integration.peakvi_clustered_umap_png
		],
		[
			harmony_peak_calling.merged_peaks_adata_object,
			harmony_peak_calling.merged_peaks_csv,
			harmony_peak_calling.peaks_matrix_adata_object
		],
		[
			peakvi_peak_calling.merged_peaks_adata_object,
			peakvi_peak_calling.merged_peaks_csv,
			peakvi_peak_calling.peaks_matrix_adata_object
		]
	]) #!StringCoercion

	call UploadFinalOutputs.upload_final_outputs as upload_cohort_analysis_files {
		input:
			output_file_paths = cohort_analysis_final_output_paths,
			staging_data_buckets = staging_data_buckets,
			staging_data_path = "~{workflow_name}/~{sub_workflow_name}",
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

		# Harmony integratated adata objects and outputs
		File harmony_integrated_adata_object = harmony_integration.harmony_integrated_adata_object
		File harmony_clustered_adata_object = harmony_integration.harmony_clustered_adata_object #!FileCoercion
		File harmony_clustered_umap_png = harmony_integration.harmony_clustered_umap_png #!FileCoercion
		File harmony_merged_peaks_adata_object = harmony_peak_calling.merged_peaks_adata_object #!FileCoercion
		File harmony_merged_peaks_csv = harmony_peak_calling.merged_peaks_csv #!FileCoercion
		File harmony_peaks_matrix_adata_object = harmony_peak_calling.peaks_matrix_adata_object #!FileCoercion

		# PeakVI integratated adata objects and outputs
		File peakvi_integrated_adata_object = peakvi_integration.peakvi_integrated_adata_object
		File peakvi_model_tar_gz = peakvi_integration.peakvi_model_tar_gz #!FileCoercion
		File peakvi_clustered_adata_object = peakvi_integration.peakvi_clustered_adata_object #!FileCoercion
		File peakvi_clustered_umap_png = peakvi_integration.peakvi_clustered_umap_png #!FileCoercion
		File peakvi_merged_peaks_adata_object = peakvi_peak_calling.merged_peaks_adata_object #!FileCoercion
		File peakvi_merged_peaks_csv = peakvi_peak_calling.merged_peaks_csv #!FileCoercion
		File peakvi_peaks_matrix_adata_object = peakvi_peak_calling.peaks_matrix_adata_object #!FileCoercion

		Array[File] preprocess_manifest_tsvs = upload_preprocess_files.manifests #!FileCoercion
		Array[File] cohort_analysis_manifest_tsvs = upload_cohort_analysis_files.manifests #!FileCoercion
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

	Int mem_gb = ceil(size(preprocessed_adata_objects, "GB") * 3 + 20)
	Int disk_size = ceil(size(preprocessed_adata_objects, "GB") * 3 + 50)

	command <<<
		set -euo pipefail

		while read -r adata_objects || [[ -n "${adata_objects}" ]]; do 
			adata_path=$(realpath "${adata_objects}")
			sample=$(basename "${adata_path}" ".adata_object.h5ad")
			echo -e "${sample}\t${adata_path}" >> adata_samples_paths.tsv
		done < ~{write_lines(preprocessed_adata_objects)}

		merge_and_qc \
			--adata-objects-fofn adata_samples_paths.tsv \
			--plot-prefix ~{cohort_id} \
			--adata-output ~{cohort_id}.merged_cleaned_unfiltered.h5ad \
			--output-metadata ~{cohort_id}.initial_metadata.csv

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.merged_cleaned_unfiltered.h5ad" \
			-o "~{cohort_id}.initial_metadata.csv" \
			-o "~{cohort_id}.frag_size_distr.png" \
			-o "~{cohort_id}.tsse.png"
	>>>

	output {
		String merged_adata_object = "~{raw_data_path}/~{cohort_id}.merged_cleaned_unfiltered.h5ad"
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
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}
}

task reduce_dimensions {
	input {
		String cohort_id
		File merged_adata_object

		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(merged_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(merged_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		process_bins \
			--adata-input ~{merged_adata_object} \
			--adata-output ~{cohort_id}.bins_processed.h5ad
	>>>

	output {
		File processed_bins_adata_object = "~{cohort_id}.processed_bins.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
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

	Int mem_gb = ceil(size(integrated_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(integrated_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		call_peaks \
			--adata-input ~{integrated_adata_object} \
			--macs3-groupby ~{macs3_groupby} \
			--output-prefix ~{cohort_id}.~{integration_method} \
			--adata-output ~{cohort_id}.~{integration_method}.merged_peaks.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.~{integration_method}.merged_peaks.h5ad" \
			-o "~{cohort_id}.~{integration_method}.merged_peaks.csv" \
			-o "~{cohort_id}.~{integration_method}.peaks_matrix.h5ad"
	>>>

	output {
		String merged_peaks_adata_object = "~{raw_data_path}/~{cohort_id}.merged_peaks.h5ad"
		String merged_peaks_csv = "~{raw_data_path}/~{cohort_id}.merged_peaks.csv"
		String peaks_matrix_adata_object = "~{raw_data_path}/~{cohort_id}.peaks_matrix.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}
}
