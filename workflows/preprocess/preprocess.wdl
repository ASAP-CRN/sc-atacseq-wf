version 1.0

# Generate a preprocessed AnnData object

import "../structs.wdl"

workflow preprocess {
	input {
		String team_id
		String dataset_id
		String dataset_doi_url
		Array[Sample] samples

		Boolean multimodal_sc_data
		File cellranger_atac_reference_data

		String workflow_name
		String workflow_version
		String workflow_release
		String run_timestamp
		String raw_data_path_prefix
		String billing_project
		String container_registry
		String zones
	}

	# Task and subworkflow versions
	String sub_workflow_name = "preprocess"
	String cellranger_atac_task_version = "1.0.0"
	String adata_task_version = "1.0.0"

	Array[Array[String]] workflow_info = [[run_timestamp, workflow_name, workflow_version, workflow_release]]

	String workflow_raw_data_path_prefix = "~{raw_data_path_prefix}/~{sub_workflow_name}"
	String cellranger_atac_raw_data_path = "~{workflow_raw_data_path_prefix}/cellranger_atac/~{cellranger_atac_task_version}"
	String adata_raw_data_path = "~{workflow_raw_data_path_prefix}/counts_to_adata/~{adata_task_version}"

	scatter (sample_object in samples) {
		String cellranger_atac_count_output = "~{cellranger_atac_raw_data_path}/~{sample_object.asap_sample_id}.raw_peak_bc_matrix.h5"
		String initial_adata_object_output = "~{adata_raw_data_path}/~{sample_object.asap_sample_id}.cleaned_unfiltered.h5ad"
	}

	# For each sample, outputs an array of true/false: [cellranger_atac_counts_complete, initial_adata_object_complete]
	call check_output_files_exist {
		input:
			cellranger_atac_count_output_files = cellranger_atac_count_output,
			initial_adata_object_output_files = initial_adata_object_output,
			billing_project = billing_project,
			zones = zones
	}

	scatter (index in range(length(samples))) {
		Sample sample = samples[index]

		Array[String] project_sample_id = [team_id, sample.asap_sample_id, dataset_doi_url]

		String cellranger_atac_count_complete = check_output_files_exist.sample_preprocessing_complete[index][0]
		String initial_adata_object_complete = check_output_files_exist.sample_preprocessing_complete[index][1]

		String cellranger_atac_outputs_tar_gz = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.cellranger_atac_outputs.tar.gz"
		String cellranger_atac_singlecell_csv = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.singlecell.csv"
		String cellranger_atac_peaks_bed = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.peaks.bed"
		String cellranger_atac_cut_sites_bigwig = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.cut_sites.bigwig"
		String cellranger_atac_raw_peaks = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.raw_peak_bc_matrix.h5"
		String cellranger_atac_filtered_peaks = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.filtered_peak_bc_matrix.h5"
		String cellranger_atac_filtered_tf = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.filtered_tf_bc_matrix.h5"
		String cellranger_atac_fragments_tsv_gz = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.fragments.tsv.gz"
		String cellranger_atac_summary_csv = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.summary.csv"
		String cellranger_atac_peak_annotation_tsv = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.peak_annotation.tsv"
		String cellranger_atac_peak_motif_mapping_bed = "~{cellranger_atac_raw_data_path}/~{sample.asap_sample_id}.peak_motif_mapping.bed"

		if (cellranger_atac_count_complete == "false") {
			call cellranger_atac_count {
				input:
					sample_id = sample.asap_sample_id,
					fastq_R1s = sample.fastq_R1s,
					fastq_R2s = sample.fastq_R2s,
					fastq_R3s = sample.fastq_R3s,
					fastq_I1s = sample.fastq_I1s,
					fastq_I2s = sample.fastq_I2s,
					multimodal_sc_data = multimodal_sc_data,
					cellranger_atac_reference_data = cellranger_atac_reference_data,
					raw_data_path = cellranger_atac_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		File atac_outputs_tar_gz_output = select_first([cellranger_atac_count.atac_outputs_tar_gz, cellranger_atac_outputs_tar_gz]) #!FileCoercion
		File singlecell_csv_output = select_first([cellranger_atac_count.singlecell_csv, cellranger_atac_singlecell_csv]) #!FileCoercion
		File peaks_bed_output = select_first([cellranger_atac_count.peaks_bed, cellranger_atac_peaks_bed]) #!FileCoercion
		File cut_sites_bigwig_output = select_first([cellranger_atac_count.cut_sites_bigwig, cellranger_atac_cut_sites_bigwig]) #!FileCoercion
		File raw_peaks_output = select_first([cellranger_atac_count.raw_peaks, cellranger_atac_raw_peaks]) #!FileCoercion
		File filtered_peaks_output = select_first([cellranger_atac_count.filtered_peaks, cellranger_atac_filtered_peaks]) #!FileCoercion
		File filtered_tf_output = select_first([cellranger_atac_count.filtered_tf, cellranger_atac_filtered_tf]) #!FileCoercion
		File fragments_tsv_gz_output = select_first([cellranger_atac_count.fragments_tsv_gz, cellranger_atac_fragments_tsv_gz]) #!FileCoercion
		File summary_csv_output = select_first([cellranger_atac_count.summary_csv, cellranger_atac_summary_csv]) #!FileCoercion
		File peak_annotation_tsv_output = select_first([cellranger_atac_count.peak_annotation_tsv, cellranger_atac_peak_annotation_tsv]) #!FileCoercion
		File peak_motif_mapping_bed_output = select_first([cellranger_atac_count.peak_motif_mapping_bed, cellranger_atac_peak_motif_mapping_bed]) #!FileCoercion

		String preprocessed_adata_object = "~{adata_raw_data_path}/~{sample.asap_sample_id}.cleaned_unfiltered.h5ad"

		if (initial_adata_object_complete == "false") {
			call counts_to_adata {
				input:
					sample_id = sample.asap_sample_id,
					batch = select_first([sample.batch]),
					team_id = team_id,
					dataset_id = dataset_id,
					cellranger_atac_fragments = fragments_tsv_gz_output,
					raw_data_path = adata_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		File preprocessed_adata_object_output = select_first([counts_to_adata.initial_adata_object, preprocessed_adata_object]) #!FileCoercion
	}

	output {
		# Sample list
		Array[Array[String]] project_sample_ids = project_sample_id

		# Cell Ranger ATAC
		Array[File] atac_outputs_tar_gz = atac_outputs_tar_gz_output #!FileCoercion
		Array[File] singlecell_csv = singlecell_csv_output #!FileCoercion
		Array[File] peaks_bed = peaks_bed_output #!FileCoercion
		Array[File] cut_sites_bigwig = cut_sites_bigwig_output #!FileCoercion
		Array[File] raw_peaks = raw_peaks_output #!FileCoercion
		Array[File] filtered_peaks = filtered_peaks_output #!FileCoercion
		Array[File] filtered_tf = filtered_tf_output #!FileCoercion
		Array[File] fragments_tsv_gz = fragments_tsv_gz_output #!FileCoercion
		Array[File] summary_csv = summary_csv_output #!FileCoercion
		Array[File] peak_annotation_tsv = peak_annotation_tsv_output #!FileCoercion
		Array[File] peak_motif_mapping_bed = peak_motif_mapping_bed_output #!FileCoercion

		# AnnData counts
		Array[File] initial_adata_object = preprocessed_adata_object_output #!FileCoercion
	}

	meta {
		description: "Preprocess the 10x Genomics Chromium Epi ATAC data by running cellranger atac count and converting counts to AnnData object."
	}

	parameter_meta {
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		dataset_doi_url: {help: "Generated Zenodo DOI URL referencing the dataset."}
		samples: {help: "An array of Sample struct, set of samples and their associated reads and metadata information."}
		multimodal_sc_data: {help: "Whether or not the sc/sn RNAseq is from multimodal data."}
		cellranger_atac_reference_data: {help: "Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads."}
		workflow_name: {help: "Workflow name; stored in the file-level manifest and final manifest with all saved files."}
		workflow_version: {help: "Workflow version; stored in the file-level manifest and final manifest with all saved files."}
		workflow_release: {help: "GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		run_timestamp: {help: "UTC timestamp; stored in the file-level manifest and final manifest with all saved files."}
		raw_data_path_prefix: {help: "Raw data bucket path prefix; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess`)."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task check_output_files_exist {
	input {
		Array[String] cellranger_atac_count_output_files
		Array[String] initial_adata_object_output_files

		String billing_project
		String zones
	}

	command <<<
		set -euo pipefail

		while read -r output_files || [[ -n "${output_files}" ]]; do
			cellranger_atac_counts_file=$(echo "${output_files}" | cut -f 1)
			initial_adata_object_file=$(echo "${output_files}" | cut -f 2)

			if gcloud storage ls --billing-project=~{billing_project} "${cellranger_atac_counts_file}"; then
				if gcloud storage ls --billing-project=~{billing_project} "${initial_adata_object_file}"; then
					# If we find all outputs, don't rerun anything
					echo -e "true\ttrue" >> sample_preprocessing_complete.tsv
				else
					# If we find cellranger-atac outputs, but don't find adata outputs, just rerun counts_to_adata
					echo -e "true\tfalse" >> sample_preprocessing_complete.tsv
				fi
			else
				# If we don't find cellranger-atac output, we must also need to run (or rerun) preprocessing
				echo -e "false\tfalse" >> sample_preprocessing_complete.tsv
			fi
		done < <(paste ~{write_lines(cellranger_atac_count_output_files)} ~{write_lines(initial_adata_object_output_files)})
	>>>

	output {
		Array[Array[String]] sample_preprocessing_complete = read_tsv("sample_preprocessing_complete.tsv")
	}

	runtime {
		docker: "gcr.io/google.com/cloudsdktool/google-cloud-cli:524.0.0-slim"
		cpu: 2
		memory: "4 GB"
		disks: "local-disk 20 HDD"
		preemptible: 3
		zones: zones
	}

	meta {
		description: "Checks for existing preprocessing files per sample and skips certain preprocessing steps if they exist."
	}

	parameter_meta {
		cellranger_atac_count_output_files: {help: "Cell Ranger count output file to detect (`<sample>.raw_peak_bc_matrix.h5`)."}
		initial_adata_object_output_files: {help: "Converted AnnData object output file to detect (`<sample>.cleaned_unfiltered.h5ad`)."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task cellranger_atac_count {
	input {
		String sample_id

		Array[File] fastq_R1s
		Array[File] fastq_R2s
		Array[File] fastq_R3s
		Array[File] fastq_I1s
		Array[File] fastq_I2s

		Boolean multimodal_sc_data
		File cellranger_atac_reference_data

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	String cellranger_arc_chemistry_flag = if multimodal_sc_data then "--chemistry=ARC-v1" else ""

	Int threads = 16
	Int mem_gb = 48
	Int disk_size = ceil((size(cellranger_atac_reference_data, "GB") + size(flatten([fastq_R1s, fastq_R2s, fastq_R3s, fastq_I1s, fastq_I2s]), "GB")) * 4 + 50)

	command <<<
		set -euo pipefail

		# Unpack refdata
		mkdir cellranger_atac_refdata
		tar \
			-zxvf ~{cellranger_atac_reference_data} \
			-C cellranger_atac_refdata \
			--strip-components 1

		# Ensure fastqs are in the same directory
		mkdir fastqs
		while read -r fastq || [[ -n "${fastq}" ]]; do
			if [[ -n "${fastq}" ]]; then
				validated_fastq_name=$(fix_fastq_names --fastq "${fastq}" --sample-id "~{sample_id}")
				if [[ -e "fastqs/${validated_fastq_name}" ]]; then
					echo "[ERROR] Something's gone wrong with fastq renaming; trying to create fastq [${validated_fastq_name}] but it already exists. Exiting."
					exit 1
				else
					ln -s "${fastq}" "fastqs/${validated_fastq_name}"
				fi
			fi
		done < <(cat \
			~{write_lines(fastq_R1s)} \
			~{write_lines(fastq_R2s)} \
			~{write_lines(fastq_R3s)} \
			~{write_lines(fastq_I1s)} \
			~{write_lines(fastq_I2s)})

		cellranger-atac --version

		/usr/bin/time \
		cellranger-atac count \
			--id=~{sample_id} \
			--transcriptome="$(pwd)/cellranger_atac_refdata" \
			--fastqs="$(pwd)/fastqs" \
			--localcores ~{threads} \
			--localmem ~{mem_gb - 4} \
			~{cellranger_arc_chemistry_flag}

		# Save Cell Ranger ATAC outs
		cp -r ~{sample_id}/outs atac_outputs
		tar -czvf "~{sample_id}.cellranger_atac_outputs.tar.gz" atac_outputs

		# Rename outputs to include sample ID
		mv ~{sample_id}/outs/singlecell.csv ~{sample_id}.singlecell.csv
		mv ~{sample_id}/outs/peaks.bed ~{sample_id}.peaks.bed
		mv ~{sample_id}/outs/cut_sites.bigwig ~{sample_id}.cut_sites.bigwig
		mv ~{sample_id}/outs/raw_peak_bc_matrix.h5 ~{sample_id}.raw_peak_bc_matrix.h5
		mv ~{sample_id}/outs/filtered_peak_bc_matrix.h5 ~{sample_id}.filtered_peak_bc_matrix.h5
		mv ~{sample_id}/outs/filtered_tf_bc_matrix.h5 ~{sample_id}.filtered_tf_bc_matrix.h5
		mv ~{sample_id}/outs/summary.csv ~{sample_id}.summary.csv
		mv ~{sample_id}/outs/peak_annotation.tsv ~{sample_id}.peak_annotation.tsv
		mv ~{sample_id}/outs/peak_motif_mapping.bed ~{sample_id}.peak_motif_mapping.bed

		# Remove the 6th column representing the strand in the fragments file, so paired-ended is considered
		## https://scverse.org/SnapATAC2/api/_autosummary/snapatac2.pp.import_fragments.html
		zcat ~{sample_id}/outs/fragments.tsv.gz | grep -v "^#" | cut -f1-5 | gzip > ~{sample_id}.fragments.tsv.gz

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{sample_id}.singlecell.csv" \
			-o "~{sample_id}.peaks.bed" \
			-o "~{sample_id}.cut_sites.bigwig" \
			-o "~{sample_id}.raw_peak_bc_matrix.h5" \
			-o "~{sample_id}.filtered_peak_bc_matrix.h5" \
			-o "~{sample_id}.filtered_tf_bc_matrix.h5" \
			-o "~{sample_id}.fragments.tsv.gz" \
			-o "~{sample_id}.summary.csv" \
			-o "~{sample_id}.peak_annotation.tsv" \
			-o "~{sample_id}.peak_motif_mapping.bed"
	>>>

	output {
		String atac_outputs_tar_gz = "~{raw_data_path}/~{sample_id}.cellranger_atac_outputs.tar.gz"
		String singlecell_csv = "~{raw_data_path}/~{sample_id}.singlecell.csv"
		String peaks_bed = "~{raw_data_path}/~{sample_id}.peaks.bed"
		String cut_sites_bigwig = "~{raw_data_path}/~{sample_id}.cut_sites.bigwig"
		String raw_peaks = "~{raw_data_path}/~{sample_id}.raw_peak_bc_matrix.h5"
		String filtered_peaks = "~{raw_data_path}/~{sample_id}.filtered_peak_bc_matrix.h5"
		String filtered_tf = "~{raw_data_path}/~{sample_id}.filtered_tf_bc_matrix.h5"
		String fragments_tsv_gz = "~{raw_data_path}/~{sample_id}.fragments.tsv.gz"
		String summary_csv = "~{raw_data_path}/~{sample_id}.summary.csv"
		String peak_annotation_tsv = "~{raw_data_path}/~{sample_id}.peak_annotation.tsv"
		String peak_motif_mapping_bed = "~{raw_data_path}/~{sample_id}.peak_motif_mapping.bed"
	}

	runtime {
		docker: "~{container_registry}/cellranger_atac:2.2.0"
		cpu: threads
		memory: "~{mem_gb} GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		bootDiskSizeGb: 40
		zones: zones
	}

	meta {
		description: "Processes raw sequencing data from 10x Epi ATAC experiments to generate chromatin accessibility and transcription factor (TF) activity matrices."
	}

	parameter_meta {
		sample_id: {help: "Generated ASAP sample ID; used to name output files."}
		fastq_R1s: {help: "Sample's read 1 FASTQ file."}
		fastq_R2s: {help: "Sample's read 2 FASTQ file."}
		fastq_R3s: {help: "Sample's read 3 FASTQ file."}
		fastq_I1s: {help: "Optional FASTQ index 1."}
		fastq_I2s: {help: "Optional FASTQ index 2."}
		multimodal_sc_data: {help: "Whether or not the sc/sn RNAseq is from multimodal data."}
		cellranger_atac_reference_data: {help: "Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads."}
		raw_data_path: {help: "Raw data bucket path for cellranger-atac count outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/cellranger_atac/<cellranger_atac_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task counts_to_adata {
	input {
		String team_id
		String dataset_id
		String sample_id
		String batch

		File cellranger_atac_fragments

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int disk_size = ceil(size(cellranger_atac_fragments, "GB") * 2 + 20)

	command <<<
		set -euo pipefail

		counts_to_adata \
			--cellranger-atac-fragments ~{cellranger_atac_fragments} \
			--team ~{team_id} \
			--dataset ~{dataset_id} \
			--sample-id ~{sample_id} \
			--batch ~{batch} \
			--adata-output ~{sample_id}.cleaned_unfiltered.h5ad

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{sample_id}.cleaned_unfiltered.h5ad"
	>>>

	output {
		String initial_adata_object = "~{raw_data_path}/~{sample_id}.cleaned_unfiltered.h5ad"
	}

	runtime {
		docker: "~{container_registry}/sc_atac_tools:1.0.0"
		cpu: 4
		memory: "32 GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		zones: zones
	}

	meta {
		description: "Converts Cell Ranger ATAC counts to AnnData objects using SnapATAC2."
	}

	parameter_meta {
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		sample_id: {help: "Generated ASAP sample ID; stored in the AnnData objects and used to name output files."}
		batch: {help: "The sample's batch; stored in the AnnData objects."}
		cellranger_atac_fragments: {help: "A BED-like TSV file output by Cell Ranger ATAC containing the deduplicated, aligned fragment coordinates, cell barcodes, and read support for each fragment."}
		raw_data_path: {help: "Raw data bucket path for counts to adata outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/counts_to_adata/<adata_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
