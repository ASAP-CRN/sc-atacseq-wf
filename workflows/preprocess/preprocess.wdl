version 1.0

# Generate a preprocessed AnnData object

import "../structs.wdl"

workflow preprocess {
	input {
		String team_id
		String dataset_id
		String dataset_doi_url
		Array[Pool] pools

		File cellranger_atac_reference_data
		File cellranger_atac_reference_chrom_sizes
		Array[File] vireo_assignment_files

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
	String split_fragments_task_version = "1.0.0"
	String adata_task_version = "1.0.0"

	Array[Array[String]] workflow_info = [[run_timestamp, workflow_name, workflow_version, workflow_release]]

	String workflow_raw_data_path_prefix = "~{raw_data_path_prefix}/~{sub_workflow_name}"
	String cellranger_atac_raw_data_path = "~{workflow_raw_data_path_prefix}/cellranger_atac/~{cellranger_atac_task_version}"
	String split_fragments_raw_data_path = "~{workflow_raw_data_path_prefix}/split_demux_fragments/~{split_fragments_task_version}"
	String adata_raw_data_path = "~{workflow_raw_data_path_prefix}/counts_to_adata/~{adata_task_version}"

	scatter (pool_object in pools) {
		String cellranger_atac_count_output = "~{cellranger_atac_raw_data_path}/~{pool_object.pool_id}.raw_peak_bc_matrix.h5"
	}

	# For each sample, outputs an array of true/false: [cellranger_atac_counts_complete]
	call check_output_files_exist as check_cellranger_output_files_exist {
		input:
			output_files = cellranger_atac_count_output,
			billing_project = billing_project,
			zones = zones
	}

	scatter (pool_index in range(length(pools))) {
		Pool pool = pools[pool_index]

		String cellranger_atac_count_complete = check_cellranger_output_files_exist.sample_preprocessing_complete[pool_index][0]

		String cellranger_atac_outputs_tar_gz = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.cellranger_atac_outputs.tar.gz"
		String cellranger_atac_singlecell_csv = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.singlecell.csv"
		String cellranger_atac_peaks_bed = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.peaks.bed"
		String cellranger_atac_cut_sites_bigwig = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.cut_sites.bigwig"
		String cellranger_atac_raw_peaks = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.raw_peak_bc_matrix.h5"
		String cellranger_atac_filtered_peaks = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.filtered_peak_bc_matrix.h5"
		String cellranger_atac_filtered_tf = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.filtered_tf_bc_matrix.h5"
		String cellranger_atac_fragments_tsv_gz = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.fragments.tsv.gz"
		String cellranger_atac_summary_csv = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.summary.csv"
		String cellranger_atac_peak_annotation_tsv = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.peak_annotation.tsv"
		String cellranger_atac_peak_motif_mapping_bed = "~{cellranger_atac_raw_data_path}/~{pool.pool_id}.peak_motif_mapping.bed"

		if (cellranger_atac_count_complete == "false") {
			call cellranger_atac_count {
				input:
					pool_id = pool.pool_id,
					fastq_R1s = pool.fastq_R1s,
					fastq_R2s = pool.fastq_R2s,
					fastq_R3s = pool.fastq_R3s,
					fastq_I1s = pool.fastq_I1s,
					fastq_I2s = pool.fastq_I2s,
					multimodal_data = pool.multimodal_data,
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

		scatter (sample_object in pool.samples) {
			String split_fragments_output = "~{split_fragments_raw_data_path}/~{sample_object.sample_id}.fragments.tsv.gz"
			String initial_adata_object_output = "~{adata_raw_data_path}/~{sample_object.sample_id}.cleaned_unfiltered.h5ad"

			String source_subject_id = sample_object.source_subject_id
			String sample_id = sample_object.sample_id
		}

		call check_output_files_exist as check_split_fragment_outputs_exist {
			input:
				output_files = split_fragments_output,
				billing_project = billing_project,
				zones = zones
		}

		Boolean run_split_demux_fragments = if cellranger_atac_count_complete == "false" then true else !check_split_fragment_outputs_exist.all_exist

		if (run_split_demux_fragments) {
			call split_demux_fragments {
				input:
					pool_id = pool.pool_id,
					source_subject_ids = source_subject_id,
					sample_ids = sample_id,
					cellranger_atac_fragments = fragments_tsv_gz_output,
					cellranger_atac_reference_chrom_sizes = cellranger_atac_reference_chrom_sizes,
					vireo_assignment_files = vireo_assignment_files,
					raw_data_path = split_fragments_raw_data_path,
					workflow_info = workflow_info,
					billing_project = billing_project,
					container_registry = container_registry,
					zones = zones
			}
		}

		Array[File] sample_split_fragments_tsv_gz_output = select_first([split_demux_fragments.sample_split_fragments_tsv_gz, split_fragments_output]) #!FileCoercion

		call check_output_files_exist as check_adata_outputs_exist {
			input:
				output_files = initial_adata_object_output,
				billing_project = billing_project,
				zones = zones
		}

		scatter (sample_index in range(length(pool.samples))) {
			Sample sample = pool.samples[sample_index]

			String initial_adata_object_complete = check_adata_outputs_exist.sample_preprocessing_complete[sample_index][0]
			Boolean run_counts_to_adata = if run_split_demux_fragments then true else (initial_adata_object_complete == "false")

			Array[String] project_sample_id = [team_id, sample.sample_id, dataset_doi_url]

			String preprocessed_adata_object = "~{adata_raw_data_path}/~{sample.sample_id}.cleaned_unfiltered.h5ad"

			if (run_counts_to_adata) {
				call counts_to_adata {
					input:
						team_id = team_id,
						dataset_id = dataset_id,
						pool_id = pool.pool_id,
						source_subject_id = sample.source_subject_id,
						subject_id = sample.asap_subject_id,
						sample_id = sample.sample_id,
						batch = select_first([sample.batch]),
						sample_split_fragments_tsv_gz = sample_split_fragments_tsv_gz_output[sample_index],
						raw_data_path = adata_raw_data_path,
						workflow_info = workflow_info,
						billing_project = billing_project,
						container_registry = container_registry,
						zones = zones
				}
			}

			File preprocessed_adata_object_output = select_first([counts_to_adata.initial_adata_object, preprocessed_adata_object]) #!FileCoercion
		}
	}

	output {
		# Sample list
		Array[Array[String]] project_sample_ids = flatten(project_sample_id)

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

		# Sample-level fragment files
		Array[File] subject_split_fragments_tsv_gz = flatten(select_all(split_demux_fragments.subject_split_fragments_tsv_gz))
		Array[File] sample_split_fragments_tsv_gz = flatten(sample_split_fragments_tsv_gz_output) #!FileCoercion

		# AnnData counts
		Array[File] initial_adata_object = flatten(preprocessed_adata_object_output) #!FileCoercion
	}

	meta {
		description: "Preprocess the 10x Genomics Chromium Epi ATAC data by running cellranger atac count and converting counts to AnnData object."
	}

	parameter_meta {
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		dataset_doi_url: {help: "Generated Zenodo DOI URL referencing the dataset."}
		pools: {help: "Array of Pool structs, each containing FASTQs, vireo assignment, the donors demultiplexed from that pool, and specifies if it's multimodal data."}
		cellranger_atac_reference_data: {help: "Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads."}
		cellranger_atac_reference_chrom_sizes: {help: "Chromosome sizes file (.chrom.sizes or .fa.fai) from the Cell Ranger ATAC reference, used to validate fragment coordinates during splitting."}
		vireo_assignment_files: {help: "Vireo donor assignment CSV with columns: donor_id, sample, raw_bc. Covers all donors in the pool."}
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
		Array[String] output_files

		String billing_project
		String zones
	}

	command <<<
		set -euo pipefail

		all_exist="true"

		while read -r file || [[ -n "${file}" ]]; do
			if gcloud storage ls --billing-project=~{billing_project} "${file}"; then
				echo -e "true" >> sample_preprocessing_complete.tsv
			else
				echo -e "false" >> sample_preprocessing_complete.tsv
				all_exist="false"
			fi
		done < ~{write_lines(output_files)}

		echo "${all_exist}" > all_exist.txt
	>>>

	output {
		Array[Array[String]] sample_preprocessing_complete = read_tsv("sample_preprocessing_complete.tsv")
		Boolean all_exist = read_boolean("all_exist.txt")
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
		description: "Checks for existing preprocessing files per pool or sample and skips certain preprocessing steps if they exist."
	}

	parameter_meta {
		output_files: {help: "Output file to detect."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task cellranger_atac_count {
	input {
		String pool_id

		Array[File] fastq_R1s
		Array[File] fastq_R2s
		Array[File] fastq_R3s
		Array[File] fastq_I1s
		Array[File] fastq_I2s

		Boolean multimodal_data
		File cellranger_atac_reference_data

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	String cellranger_arc_chemistry_flag = if multimodal_data then "--chemistry=ARC-v1" else ""

	Int threads = 16
	Int mem_gb = 48
	Int disk_size = ceil((size(cellranger_atac_reference_data, "GB") + size(flatten([fastq_R1s, fastq_R2s, fastq_R3s, fastq_I1s, fastq_I2s]), "GB")) * 5 + 150)

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
				check_fastq_names --fastq "${fastq}"
				fastq_basename=$(basename "${fastq}")
				ln -s "${fastq}" "fastqs/${fastq_basename}"
			fi
		done < <(cat \
			~{write_lines(fastq_R1s)} \
			~{write_lines(fastq_R2s)} \
			~{write_lines(fastq_R3s)} \
			~{write_lines(fastq_I1s)} \
			~{write_lines(fastq_I2s)})
		
		# Get comma-sep sample names from fastqs for multiplexed runs
		# shellcheck disable=SC2011
		samples=$(ls fastqs | xargs -n1 basename | sed 's/_S[0-9]*_L[0-9]*_.*//' | sort -u | paste -sd,)

		cellranger-atac --version

		/usr/bin/time \
		cellranger-atac count \
			--id=~{pool_id} \
			--reference="$(pwd)/cellranger_atac_refdata" \
			--fastqs="$(pwd)/fastqs" \
			--sample="${samples}" \
			--localcores ~{threads} \
			--localmem ~{mem_gb - 4} \
			~{cellranger_arc_chemistry_flag}

		# Save Cell Ranger ATAC outs
		cp -r ~{pool_id}/outs atac_outputs
		tar -czvf "~{pool_id}.cellranger_atac_outputs.tar.gz" atac_outputs

		# Rename outputs to include sample ID
		mv ~{pool_id}/outs/singlecell.csv ~{pool_id}.singlecell.csv
		mv ~{pool_id}/outs/peaks.bed ~{pool_id}.peaks.bed
		mv ~{pool_id}/outs/cut_sites.bigwig ~{pool_id}.cut_sites.bigwig
		mv ~{pool_id}/outs/raw_peak_bc_matrix.h5 ~{pool_id}.raw_peak_bc_matrix.h5
		mv ~{pool_id}/outs/filtered_peak_bc_matrix.h5 ~{pool_id}.filtered_peak_bc_matrix.h5
		mv ~{pool_id}/outs/filtered_tf_bc_matrix.h5 ~{pool_id}.filtered_tf_bc_matrix.h5
		mv ~{pool_id}/outs/summary.csv ~{pool_id}.summary.csv
		mv ~{pool_id}/outs/peak_annotation.tsv ~{pool_id}.peak_annotation.tsv
		mv ~{pool_id}/outs/peak_motif_mapping.bed ~{pool_id}.peak_motif_mapping.bed

		# Remove the 6th column representing the strand in the fragments file, so paired-ended is considered
		## https://scverse.org/SnapATAC2/api/_autosummary/snapatac2.pp.import_fragments.html
		zcat ~{pool_id}/outs/fragments.tsv.gz | grep -v "^#" | cut -f1-5 | gzip > ~{pool_id}.fragments.tsv.gz

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			-o "~{pool_id}.cellranger_atac_outputs.tar.gz" \
			-o "~{pool_id}.singlecell.csv" \
			-o "~{pool_id}.peaks.bed" \
			-o "~{pool_id}.cut_sites.bigwig" \
			-o "~{pool_id}.raw_peak_bc_matrix.h5" \
			-o "~{pool_id}.filtered_peak_bc_matrix.h5" \
			-o "~{pool_id}.filtered_tf_bc_matrix.h5" \
			-o "~{pool_id}.fragments.tsv.gz" \
			-o "~{pool_id}.summary.csv" \
			-o "~{pool_id}.peak_annotation.tsv" \
			-o "~{pool_id}.peak_motif_mapping.bed"
	>>>

	output {
		String atac_outputs_tar_gz = "~{raw_data_path}/~{pool_id}.cellranger_atac_outputs.tar.gz"
		String singlecell_csv = "~{raw_data_path}/~{pool_id}.singlecell.csv"
		String peaks_bed = "~{raw_data_path}/~{pool_id}.peaks.bed"
		String cut_sites_bigwig = "~{raw_data_path}/~{pool_id}.cut_sites.bigwig"
		String raw_peaks = "~{raw_data_path}/~{pool_id}.raw_peak_bc_matrix.h5"
		String filtered_peaks = "~{raw_data_path}/~{pool_id}.filtered_peak_bc_matrix.h5"
		String filtered_tf = "~{raw_data_path}/~{pool_id}.filtered_tf_bc_matrix.h5"
		String fragments_tsv_gz = "~{raw_data_path}/~{pool_id}.fragments.tsv.gz"
		String summary_csv = "~{raw_data_path}/~{pool_id}.summary.csv"
		String peak_annotation_tsv = "~{raw_data_path}/~{pool_id}.peak_annotation.tsv"
		String peak_motif_mapping_bed = "~{raw_data_path}/~{pool_id}.peak_motif_mapping.bed"
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
		pool_id: {help: "Generated ASAP pool ID; used to name output files."}
		fastq_R1s: {help: "Sample's read 1 FASTQ file."}
		fastq_R2s: {help: "Sample's read 2 FASTQ file."}
		fastq_R3s: {help: "Sample's read 3 FASTQ file."}
		fastq_I1s: {help: "Optional FASTQ index 1."}
		fastq_I2s: {help: "Optional FASTQ index 2."}
		multimodal_data: {help: "Whether or not the sc/sn ATAC-seq is from multimodal data."}
		cellranger_atac_reference_data: {help: "Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads."}
		raw_data_path: {help: "Raw data bucket path for cellranger-atac count outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/cellranger_atac/<cellranger_atac_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}

task split_demux_fragments {
	input {
		String pool_id
		Array[String] source_subject_ids
		Array[String] sample_ids

		File cellranger_atac_fragments
		File cellranger_atac_reference_chrom_sizes
		Array[File] vireo_assignment_files

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int disk_size = ceil(size([cellranger_atac_fragments, cellranger_atac_reference_chrom_sizes], "GB") + size(vireo_assignment_files, "GB") * 2 + 20)

	command <<<
		set -euo pipefail

		# Fix fragment file
		zcat ~{cellranger_atac_fragments} | sed 's/-1\t/-'"~{pool_id}"'\t/' | bgzip -c -@ 4 > "~{pool_id}.mod.fragments.tsv.gz"
		tabix -p bed "~{pool_id}.mod.fragments.tsv.gz"

		# Generate mapping of sample names (pool) to fragment files TSV
		echo -e "sample\tpath_to_fragment_file" > "~{pool_id}.sample_to_fragment.tsv"
		echo -e "~{pool_id}\t~{pool_id}.fragments.tsv.gz" >> "~{pool_id}.sample_to_fragment.tsv"

		# Generate mapping of samples (pool), cell types (subject), and cell barcodes TSV
		## Filter out 'doublet' and 'unassigned' cell types (subject)
		echo -e "sample\tcell_type\tcell_barcode" > cell_barcodes.tsv
		for f in ~{sep=' ' vireo_assignment_files}; do
			awk -F ',' -v pool="~{pool_id}" '$2 ~ /^ASA/ && $3 ~ pool { OFS="\t"; print $3, $2, $4 }' "${f}" >> cell_barcodes.tsv
		done
		
		if [[ $(wc -l < cell_barcodes.tsv) -le 1 ]]; then
			echo "[ERROR] No matching samples found in any vireo assignment file" >&2
			exit 1
		fi

		mkdir fragments_output
		mkdir renamed_fragments_output

		scatac_fragment_tools split \
			--sample_fragments "~{pool_id}.sample_to_fragment.tsv" \
			--cell_type_barcodes cell_barcodes.tsv \
			--chrom ~{cellranger_atac_reference_chrom_sizes} \
			--output "$(pwd)/fragments_output"

		paste \
			~{write_lines(source_subject_ids)} \
			~{write_lines(sample_ids)} \
		> metadata.tsv

		duplicates=$(cut -f2 metadata.tsv | sort | uniq -d)
		if [[ -n "${duplicates}" ]]; then
			echo "[ERROR] Duplicate sample_id found for pool ~{pool_id}: ${duplicates}" >&2
			exit 1
		fi

		# Rename outputs with ASAP_sample_id + pool_id
		while IFS=$'\t' read -r source_subject_id sample_id; do
			ln "fragments_output/${source_subject_id}.fragments.tsv.gz" "renamed_fragments_output/${sample_id}.~{pool_id}.fragments.tsv.gz"
		done < metadata.tsv

		upload_flags=""
		for f in renamed_fragments_output/*; do
			upload_flags="${upload_flags} -o ${f}"
		done

		upload_outputs \
			-b ~{billing_project} \
			-d ~{raw_data_path} \
			-i ~{write_tsv(workflow_info)} \
			"${upload_flags}"

		# shellcheck disable=SC2012
		ls renamed_fragments_output | sed "s|^|~{raw_data_path}/|" > sample_fragment_filenames.txt
	>>>

	output {
		Array[File] subject_split_fragments_tsv_gz = glob("fragments_output/*")
		Array[String] sample_split_fragments_tsv_gz = read_lines("sample_fragment_filenames.txt")
	}

	runtime {
		docker: "~{container_registry}/scatac_fragment_tools:0.1.5"
		cpu: 4
		memory: "16 GB"
		disks: "local-disk ~{disk_size} HDD"
		preemptible: 3
		zones: zones
	}

	meta {
		description: "Split Cell Ranger fragment files to donor/sample-level fragment files with inputs containing demultiplexed samples generated with Vireo."
	}

	parameter_meta {
		pool_id: {help: "Generated ASAP pool ID; used to name output files."}
		source_subject_ids: {help: "An array of generated ASAP subject IDs; used for mapping."}
		sample_ids: {help: "An array of generated ASAP sample ID; used for mapping."}
		cellranger_atac_fragments: {help: "A BED-like TSV file output by Cell Ranger ATAC containing the deduplicated, aligned fragment coordinates, cell barcodes, and read support for each fragment."}
		cellranger_atac_reference_chrom_sizes: {help: "Chromosome sizes file (.chrom.sizes or .fa.fai) from the Cell Ranger ATAC reference, used to validate fragment coordinates during splitting."}
		vireo_assignment_files: {help: "Vireo donor assignment CSV with columns: donor_id, sample, raw_bc. Covers all donors in the pool."}
		raw_data_path: {help: "Raw data bucket path for counts to adata outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/counts_to_adata/<adata_task_version>`)."}
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
		String pool_id
		String source_subject_id
		String subject_id
		String sample_id
		String batch

		File sample_split_fragments_tsv_gz

		String raw_data_path
		Array[Array[String]] workflow_info
		String billing_project
		String container_registry
		String zones
	}

	Int disk_size = ceil(size(sample_split_fragments_tsv_gz, "GB") * 2 + 20)

	command <<<
		set -euo pipefail

		counts_to_adata \
			--cellranger-atac-sample-split-fragments ~{sample_split_fragments_tsv_gz} \
			--team ~{team_id} \
			--dataset-id ~{dataset_id} \
			--pool-id ~{pool_id} \
			--source-subject-id ~{source_subject_id} \
			--subject-id ~{subject_id} \
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
		bootDiskSizeGb: 30
		zones: zones
	}

	meta {
		description: "Converts demultiplexed sample-level Cell Ranger ATAC counts into AnnData objects using SnapATAC2."
	}

	parameter_meta {
		team_id: {help: "Name of the CRN Team; stored in the AnnData objects."}
		dataset_id: {help: "Generated ASAP dataset ID; stored in the AnnData objects."}
		pool_id: {help: "Generated ASAP pool ID; stored in the AnnData objects."}
		source_subject_id: {help: "Source subject ID; stored in the AnnData objects."}
		subject_id: {help: "Generated ASAP subject ID; stored in the AnnData objects."}
		sample_id: {help: "Generated ASAP sample ID; stored in the AnnData objects and used to name output files."}
		batch: {help: "The sample's batch; stored in the AnnData objects."}
		sample_split_fragments_tsv_gz: {help: "A BED-like TSV file output by Cell Ranger ATAC for demultiplexed samples."}
		raw_data_path: {help: "Raw data bucket path for counts to adata outputs; location of raw bucket to upload task outputs to (`<raw_data_bucket>/workflow_execution/preprocess/counts_to_adata/<adata_task_version>`)."}
		workflow_info: {help: "UTC timestamp, workflow name, workflow version, and GitHub release; stored in the file-level manifest and final manifest with all saved files."}
		billing_project: {help: "Billing project to charge GCP costs."}
		container_registry: {help: "Container registry where workflow Docker images are hosted."}
		zones: {help: "Space-delimited set of GCP zones to spin up compute in. ['us-central1-c us-central1-f']"}
	}
}
