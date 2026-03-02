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

	Int mem_gb = ceil(size(processed_bins_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(processed_bins_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

		mkdir peakvi_dir

		integrate_peakvi \
			--adata-input ~{processed_bins_adata_object} \
			--batch-key ~{batch_key} \
			--latent-key ~{peakvi_latent_key} \
			--adata-output ~{cohort_id}.peakvi_integrated.h5ad \
			--output-peakvi-dir "~{cohort_id}_peakvi_model"

		# Model name cannot be changed because scvi models serialization expects a path containing a model.pt object
		tar -czvf "~{cohort_id}.scvi_model.tar.gz" "~{cohort_id}_scvi_model"

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{cohort_id}.scvi_model.tar.gz"
	>>>

	output {
		File peakvi_integrated_adata_object = "~{cohort_id}.peakvi_integrated.h5ad"
		String peakvi_model_tar_gz = "~{raw_data_path}/~{cohort_id}.scvi_model.tar.gz"
	}

	runtime {
		docker: "~{container_registry}/scvi_tools:1.0.0"
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
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
		bootDiskSizeGb: 40
		zones: zones
	}
}
