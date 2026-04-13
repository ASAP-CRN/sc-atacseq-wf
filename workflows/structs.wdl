version 1.0

struct Sample {
	Array[String] source_subject_id
	Array[String] asap_subject_id
	Array[String] sample_id
	Array[String]? batch
}

struct Pool {
	String pool_id

	Array[File]+ fastq_R1s
	Array[File]+ fastq_R2s
	Array[File]+ fastq_R3s
	Array[File] fastq_I1s
	Array[File] fastq_I2s

	Array[Sample] samples

	Boolean multimodal_data
}

struct Project {
	String asap_team_id
	String asap_dataset_id
	String asap_dataset_doi_url
	Array[Pool] pools

	Boolean run_project_cohort_analysis

	String raw_data_bucket
	Array[String] staging_data_buckets
}
