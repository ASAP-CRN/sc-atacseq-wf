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
}

task integrate_harmony {
	input {
		String cohort_id
		File processed_bins_adata_object

		String batch_key

		String container_registry
		String zones
	}

	Int mem_gb = ceil(size(processed_bins_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(processed_bins_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

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
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
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

	Int mem_gb = ceil(size(harmony_integrated_adata_object, "GB") * 2 + 20)
	Int disk_size = ceil(size(harmony_integrated_adata_object, "GB") * 2 + 50)

	command <<<
		set -euo pipefail

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
		cpu: 2
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}
}
