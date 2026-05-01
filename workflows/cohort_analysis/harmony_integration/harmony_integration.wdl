version 1.0

# Integrate Harmony and cluster

workflow harmony_integration {
	input {
		String cohort_id
		File processed_bins_adata_object

		String batch_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	call integrate_harmony {
		input:
			cohort_id = cohort_id,
			processed_bins_adata_object = processed_bins_adata_object,
			batch_key = batch_key,
			container_registry = container_registry,
			zones = zones
	}

	call cluster_harmony {
		input:
			cohort_id = cohort_id,
			harmony_integrated_adata_object = integrate_harmony.harmony_integrated_adata_object,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	output {
		File harmony_integrated_adata_object = integrate_harmony.harmony_integrated_adata_object
		File harmony_clustered_adata_object = cluster_harmony.harmony_clustered_adata_object
		File harmony_clustered_umap_png = cluster_harmony.harmony_clustered_umap_png #!FileCoercion
	}

	meta {
		description: "Integrates samples by applying Harmony batch correction to the spectral embedding and clusters cells using Leiden community detection, producing a corrected AnnData object and UMAP plot."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		processed_bins_adata_object: {help: "Processed AnnData object after dimensionality reduction."}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for merged adata and QC plots outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task integrate_harmony {
	input {
		String cohort_id
		File processed_bins_adata_object

		String batch_key

		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(processed_bins_adata_object, "GB") * 15 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(processed_bins_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		integrate_harmony \
			--adata-input ~{processed_bins_adata_object} \
			--batch-key ~{batch_key} \
			--adata-output ~{cohort_id}.harmony_integrated.h5ad
	>>>

	output {
		File harmony_integrated_adata_object = "~{cohort_id}.harmony_integrated.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Runs Harmony batch correction on the spectral embedding to align cells across batches, producing a corrected low-dimensional representation ('X_spectral_harmony')."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		processed_bins_adata_object: {help: "Processed AnnData object after dimensionality reduction."}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task cluster_harmony {
	input {
		String cohort_id
		File harmony_integrated_adata_object

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int calc_mem_gb = ceil(size(harmony_integrated_adata_object, "GB") * 10 + 50)
	Int mem_gb = if calc_mem_gb > 624 then 624 else calc_mem_gb
	Int disk_size = ceil(size(harmony_integrated_adata_object, "GB") * 4 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		cluster_harmony \
			--adata-input ~{harmony_integrated_adata_object} \
			--plot-prefix ~{cohort_id} \
			--adata-output ~{cohort_id}.harmony_clustered.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.harmony_umap.png"
	>>>

	output {
		File harmony_clustered_adata_object = "~{cohort_id}.harmony_clustered.h5ad"
		String harmony_clustered_umap_png = "~{raw_data_path}/~{cohort_id}.harmony_umap.png"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		cpuPlatform: "Intel Cascade Lake"
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Constructs a k-nearest neighbor graph on the Harmony-corrected spectral embedding and applies Leiden community detection to cluster cells."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		harmony_integrated_adata_object: {help: "Harmony-integrated AnnData object."}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
