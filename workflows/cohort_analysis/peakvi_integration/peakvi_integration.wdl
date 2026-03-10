version 1.0

# Integrate PeakVI and cluster

workflow peakvi_integration {
	input {
		String cohort_id
		File processed_bins_adata_object

		String batch_key
		String peakvi_latent_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	call integrate_peakvi {
		input:
			cohort_id = cohort_id,
			processed_bins_adata_object = processed_bins_adata_object,
			batch_key = batch_key,
			peakvi_latent_key = peakvi_latent_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	call cluster_peakvi {
		input:
			cohort_id = cohort_id,
			peakvi_integrated_adata_object = integrate_peakvi.peakvi_integrated_adata_object,
			peakvi_latent_key = peakvi_latent_key,
			raw_data_path = raw_data_path,
			workflow_info = workflow_info,
			billing_project = billing_project,
			container_registry = container_registry,
			zones = zones
	}

	output {
		File peakvi_integrated_adata_object = integrate_peakvi.peakvi_integrated_adata_object
		File peakvi_model_tar_gz = integrate_peakvi.peakvi_model_tar_gz #!FileCoercion
		File peakvi_clustered_adata_object = cluster_peakvi.peakvi_clustered_adata_object
		File peakvi_clustered_umap_png = cluster_peakvi.peakvi_clustered_umap_png #!FileCoercion
	}

	meta {
		description: "Integrates samples by training a PeakVI variational autoencoder for batch correction and clusters cells using Leiden community detection, producing an integrated AnnData object, PeakVI model, and UMAP plot."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		processed_bins_adata_object: {help: "Processed AnnData object after dimensionality reduction."}
		peakvi_latent_key: {help: "Latent key to save the peakVI latent to. ['X_peakVI']"}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		raw_data_path: {help: "Raw data bucket path for merged adata and QC plots outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task integrate_peakvi {
	input {
		String cohort_id
		File processed_bins_adata_object

		String batch_key
		String peakvi_latent_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(processed_bins_adata_object, "GB") * 2 + 150)
	Int disk_size = ceil(size(processed_bins_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		mkdir peakvi_dir

		/usr/bin/time -v \
		integrate_peakvi \
			--adata-input ~{processed_bins_adata_object} \
			--batch-key ~{batch_key} \
			--latent-key ~{peakvi_latent_key} \
			--adata-output ~{cohort_id}.peakvi_integrated.h5ad \
			--output-peakvi-dir "~{cohort_id}_peakvi_model"

		# Model name cannot be changed because scvi models serialization expects a path containing a model.pt object
		tar -czvf "~{cohort_id}.peakvi_model.tar.gz" "~{cohort_id}_peakvi_model"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.peakvi_model.tar.gz"
	>>>

	output {
		File peakvi_integrated_adata_object = "~{cohort_id}.peakvi_integrated.h5ad"
		String peakvi_model_tar_gz = "~{raw_data_path}/~{cohort_id}.peakvi_model.tar.gz"
	}

	runtime {
		docker: "~{container_registry}/scvi_tools:1.0.0"
		cpu: 8
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Trains a PeakVI variational autoencoder to learn a batch-corrected latent representation of chromatin accessibility data and exports the trained PeakVI model."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		processed_bins_adata_object: {help: "Processed AnnData object after dimensionality reduction."}
		batch_key: {help: "Key in AnnData object for batch information. ['batch_id']"}
		peakvi_latent_key: {help: "Latent key to save the peakVI latent to. ['X_peakVI']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task cluster_peakvi {
	input {
		String cohort_id
		File peakvi_integrated_adata_object

		String peakvi_latent_key

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(peakvi_integrated_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(peakvi_integrated_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		/usr/bin/time -v \
		cluster_peakvi \
			--adata-input ~{peakvi_integrated_adata_object} \
			--latent-key ~{peakvi_latent_key} \
			--adata-output ~{cohort_id}.peakvi_clustered.h5ad

		mv "plots/umap.png" "plots/~{cohort_id}.peakvi_umap.png"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "plots/~{cohort_id}.peakvi_umap.png"
	>>>

	output {
		File peakvi_clustered_adata_object = "~{cohort_id}.peakvi_clustered.h5ad"
		String peakvi_clustered_umap_png = "~{raw_data_path}/~{cohort_id}.peakvi_umap.png"
	}

	runtime {
		docker: "~{container_registry}/scvi_tools:1.0.0"
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Constructs a k-nearest neighbor graph on the PeakVI latent embedding and applies Leiden community detection to cluster cells."
	}

	parameter_meta {
		cohort_id: {help: "Name of the cohort; used to name output files."}
		peakvi_integrated_adata_object: {help: "PeakVI-integrated AnnData object."}
		peakvi_latent_key: {help: "Latent key to save the peakVI latent to. ['X_peakVI']"}
		raw_data_path: {help: "Raw data bucket path for outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/cohort_analysis/<cohort_analysis_version>/<run_timestamp>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
