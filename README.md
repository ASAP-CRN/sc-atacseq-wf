# sc-atacseq-wf

Repo for testing and developing a common postmortem-derived brain sequencing (PMDBS) workflow harmonized across ASAP with single cell ATAC sequencing data.

Common workflows, tasks, utility scripts, and docker images reused across harmonized ASAP workflows are defined in [the wf-common repository](https://github.com/ASAP-CRN/wf-common).


# Table of contents

- [Workflows](#workflows)
- [Inputs](#inputs)
- [Outputs](#outputs)
    - [Output structure](#output-structure)
- [Docker images](#docker-images)


# Workflows

Worfklows are defined in [the `workflows` directory](workflows). The python scripts which process the data at each stage can be found [the docker/sc_atac_tools/scripts directory](docker/sc_atac_tools/scripts). #TODO

![Workflow diagram](workflows/workflow_diagram.svg "Workflow diagram")

**Entrypoint**: [workflows/main.wdl](workflows/main.wdl)

**Input template**: [workflows/inputs.json](workflows/inputs.json)

The workflow is broken up into two main chunks:

1. [Preprocessing](#preprocessing)
2. [Cohort analysis](#cohort-analysis)

> Note: The details of the cohort analysis are described in the [sc_atac_tools docker README](docker/sc_atac_tools/scripts/README.md). #TODO

## Preprocessing

Run once per sample; only rerun when the preprocessing workflow version is updated. Preprocessing outputs are stored in the originating team's raw and staging data buckets.

## Cohort analysis

Run once per team (all samples from a single team) if `project.run_project_cohort_analysis` is set to `true`, and once for the whole cohort (all samples from all teams). This can be rerun using different sample subsets; including additional samples requires this entire analysis to be rerun. Intermediate files from previous runs are not reused and are stored in timestamped directories.

# Inputs

An input template file can be found at [workflows/inputs.json](workflows/inputs.json).

| Type | Name | Description |
| :- | :- | :- |
| String | cohort_id | Name of the cohort; used to name output files during cross-team cohort analysis. |
| Array[[Project](#project)] | projects | The project ID, set of samples and their associated reads and metadata, output bucket locations, and whether or not to run project-level cohort analysis. |
| File | cellranger_atac_reference_data | Cell Ranger ATAC reference data; see https://www.10xgenomics.com/support/software/cell-ranger-atac/downloads#reference-downloads. |
| | | |
| String | cohort_raw_data_bucket | Bucket to upload cross-team cohort intermediate files to. |
| Array[String] | cohort_staging_data_buckets | Buckets to upload cross-team cohort analysis outputs to. |
| String | container_registry | Container registry where workflow Docker images are hosted. |
| String? | zones | GCP zones where compute will take place. ['us-central1-c us-central1-f'] |

## Structs

### Project

| Type | Name | Description |
| :- | :- | :- |
| String | team_id | Unique identifier for team; used for naming output files. |
| String | dataset_id | Unique identifier for dataset; used for metadata. |
| String | dataset_doi_url | Generated Zenodo DOI URL referencing the dataset. |
| Array[[Sample](#sample)] | samples | The set of samples associated with this project. |
| Boolean | run_project_cohort_analysis | Whether or not to run cohort analysis within the project. |
| String | raw_data_bucket | Raw data bucket; intermediate output files that are not final workflow outputs are stored here. |
| String | staging_data_bucket | Staging data bucket; final project-level outputs are stored here. |

### Sample

| Type | Name | Description |
| :- | :- | :- |
| String | sample_id | Unique identifier for the sample within the project. |
| String? | batch | The sample's batch. |
| File | fastq_R1 | Path to the sample's read 1 FASTQ file. |
| File | fastq_R2 | Path to the sample's read 2 FASTQ file. |
| File? | fastq_I1 | Optional fastq index 1. |
| File? | fastq_I2 | Optional fastq index 2. |

## Generating the inputs JSON

The inputs JSON may be generated manually, however when running a large number of samples, this can become unwieldly. The [`generate_inputs` utility script](https://github.com/ASAP-CRN/wf-common/blob/main/util/generate_inputs) may be used to automatically generate the inputs JSON (`inputs.{staging_env}.{source}-{cohort_dataset}.{date}.json`) and a sample list TSV (`{team_id}.{source}-{cohort_dataset}.sample_list.{date}.tsv`); same as the one generated in [the write_cohort_sample_list task](https://github.com/ASAP-CRN/wf-common/wdl/tasks/write_cohort_sample_list.wdl)). The script requires the libraries outlined in [the requirements.txt file](https://github.com/ASAP-CRN/wf-common/util/requirements.txt) and the following inputs:

- `project-tsv`: One or more project TSVs with one row per sample and columns team_id, sample_id, batch, fastq_path. All samples from all projects may be included in the same project TSV, or multiple project TSVs may be provided.
    - `team_id`: A unique identifier for the team from which the sample(s) arose
    - `dataset_id`: A unique identifier for the dataset from which the sample(s) arose
    - `sample_id`: A unique identifier for the sample within the project
    - `batch`: The sample's batch
    - `fastq_path`: The directory in which paired sample FASTQs may be found, including the gs:// bucket name and path
        - This is appended to the `project-tsv` from the `fastq-locs-txt`: FASTQ locations for all samples provided in the `project-tsv`, one per line. Each sample is expected to have one set of paired fastqs located at `${fastq_path}/${sample_id}*`. The read 1 file should include 'R1' somewhere in the filename; the read 2 file should inclue 'R2' somewhere in the filename. Generate this file e.g. by running `gcloud storage ls gs://fastq_bucket/some/path/**.fastq.gz >> fastq_locs.txt`
- `inputs-template`: The inputs template JSON file into which the `projects` information derived from the `project-tsv` will be inserted. Must have a key ending in `*.projects`. Other default values filled out in the inputs template will be written to the output inputs.json file.
- `run-project-cohort-analysis`: Optionally run project-level cohort analysis for provided projects. This value will apply to all projects. [false]
- `workflow_name`: WDL workflow name.
- `cohort-dataset`: Dataset name in cohort bucket name (e.g. 'sc-atacseq').

Example usage:

```bash
./wf-common/util/generate_inputs \
    --project-tsv metadata.tsv \
    --inputs-template workflows/inputs.json \
    --run-project-cohort-analysis \
    --workflow-name sc_atacseq_analysis \
    --cohort-dataset sc-atacseq
```

# Outputs

## Output structure

- `cohort_id`: either the `team_id` for project-level cohort analysis, or the `cohort_id` for the full cohort
- `workflow_run_timestamp`: format: `%Y-%m-%dT%H-%M-%SZ`
- The list of samples used to generate the cohort analysis will be output alongside other cohort analysis outputs in the staging data bucket (`${cohort_id}.sample_list.tsv`)
- The `MANIFEST.tsv` file in the staging data bucket describes the file name, md5 hash, timestamp, workflow version, workflow name, and workflow release for the run used to generate each file in that directory

### Raw data (intermediate files and final outputs for all runs of the workflow)

The raw data bucket will contain *some* artifacts generated as part of workflow execution. Following successful workflow execution, the artifacts will also be copied into the staging bucket as final outputs.

In the workflow, task outputs are either specified as `String` (final outputs, which will be copied in order to live in raw data buckets and staging buckets) or `File` (intermediate outputs that are periodically cleaned up, which will live in the cromwell-output bucket). This was implemented to reduce storage costs.

```bash
asap-raw-{cohort,team-xxyy}-{source}-{dataset}
└── ${workflow_name}
    └── workflow_execution
        ├── cohort_analysis
        │   └──${cohort_analysis_workflow_version}
        │       └── ${workflow_run_timestamp}
        │            └── <cohort outputs>
        └── preprocess  // only produced in project raw data buckets, not in the full cohort bucket
            ├── cellranger_atac
            │   └── ${cellranger_atac_task_version}
            │       └── <cellranger_atac output>
            └── counts_to_adata
                └── ${adata_task_version}
                    └── <counts_to_adata output>
```

### Staging data (intermediate workflow objects and final workflow outputs for the latest run of the workflow)

Following QC by researchers, the objects in the dev or uat bucket are synced into the curated data buckets, maintaining the same file structure. Curated data buckets are named `asap-curated-{cohort,team-xxyy}-{source}-{dataset}`.

Data may be synced using [the `promote_staging_data` script](#promoting-staging-data).

```bash
asap-dev-{cohort,team-xxyy}-{source}-{dataset}
└── ${workflow_name}
    ├── cohort_analysis
    │   ├── ${cohort_id}.. # TODO
    │   └── MANIFEST.tsv
    └── preprocess
        ├── ${sampleA_id}.. # TODO
        ├── MANIFEST.tsv
        ├── ...
        ├── ${sampleN_id}.. # TODO
        └── MANIFEST.tsv
```

## Promoting staging data

The [`promote_staging_data` script](https://github.com/ASAP-CRN/wf-common/blob/main/util/promote_staging_data) can be used to promote staging data that has been approved to the curated data bucket for a team or set of teams.

This script compiles bucket and file information for both the initial (staging) and target (prod) environment. It also runs data integrity tests to ensure staging data can be promoted and generates a Markdown report. It (1) checks that files are not empty and are not less than or equal to 10 bytes (factoring in white space) and (2) checks that files have associated metadata and is present in MANIFEST.tsv.

If data integrity tests pass, this script will upload a combined MANIFEST.tsv and the data promotion Markdown report under a metadata/{timestamp} directory in the staging bucket. Previous manifest files and reports will be kept. Next, it will rsync all files in the staging bucket to the curated bucket's preprocess, cohort_analysis, and metadata directories. **Exercise caution when using this script**; files that are not present in the source (staging) bucket will be deleted at the destination (curated) bucket.

If data integrity tests fail, staging data cannot be promoted. The combined `MANIFEST.tsv`, Markdown report, and `promote_staging_data_script.log` will be locally available.

The script defaults to a dry run, printing out the files that would be copied or deleted for each selected team.

### Options

```
-h  Display this message and exit
-t  Space-delimited team(s) to promote data for
-l  List available teams
-s  Source name in bucket name
-d  Space-delimited dataset name(s) in team bucket name, must follow the same order as {team}
-w  Workflow name used as a directory in bucket
-p  Promote data. If this option is not selected, data that would be copied or deleted is printed out, but files are not actually changed (dry run)
```

### Usage

```bash
# List available teams
./wf-common/util/promote_staging_data -t cohort -l -s pmdbs -d sc-atacseq -w pmdbs_sc_atacseq

# Print out the files that would be copied or deleted from the staging bucket to the curated bucket for teams team-voet, team-lee, and cohort
./wf-common/util/promote_staging_data -t team-voet team-lee cohort -s pmdbs -d sc-atacseq -w pmdbs_sc_atacseq

# Promote data for team-voet, team-lee, and cohort
./wf-common/util/promote_staging_data -t team-voet team-lee cohort -s pmdbs -d sc-atacseq -w pmdbs_sc_atacseq -p
```

# Docker images

Docker images are defined in [the `docker` directory](docker). Each image must minimally define a `build.env` file and a `Dockerfile`.

Example directory structure:
```bash
docker
├── sc_atac_tools
│   ├── build.env
│   ├── Dockerfile
│   ├── requirements.txt
│   └── scripts
│       └── ...
└── cellranger_atac
    ├── build.env
    └── Dockerfile
```

## The `build.env` file

Each target image is defined using the `build.env` file, which is used to specify the name and version tag for the corresponding Docker image. It must contain at minimum the following variables:

- `IMAGE_NAME`
- `IMAGE_TAG`

All variables defined in the `build.env` file will be made available as build arguments during Docker image build.

The `DOCKERFILE` variable may be used to specify the path to a Dockerfile if that file is not found alongside the `build.env` file, for example when multiple images use the same base Dockerfile definition.

## Building Docker images

Docker images can be build using the [`build_docker_images`](https://github.com/DNAstack/bioinformatics-scripts/blob/main/scripts/build_docker_images) script.

```bash
# Build a single image
./build_docker_images -d docker/sc_atac_tools

# Build all images in the `docker` directory
./build_docker_images -d docker

# Build and push all images in the docker directory, using the `dnastack` container registry
./build_docker_images -d docker -c dnastack -p
```

## Tool and library versions

| Image | Major tool versions | Links |
| :- | :- | :- |
| cellranger_atac | <ul><li>[cellranger_atac v2.2](https://www.10xgenomics.com/support/software/cell-ranger-atac/latest/release-notes/release-notes#2025-April)</li><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/sc-atacseq-wf/tree/main/docker/cellranger_atac) |
| #TODO sc_atac_tools | <ul><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li><li>[python 3.10.12](https://www.python.org/downloads/release/python-31012/)</li><li>[torch 2.6.0](https://github.com/pytorch/pytorch/releases/tag/v2.6.0)</li></ul> Python libraries: <ul><li>[scvi-tools 1.3.2](https://github.com/scverse/scvi-tools/releases/tag/1.3.2)</li><li>argparse 1.4.0</li><li>[scanpy 1.11.3](https://scanpy.readthedocs.io/en/stable/release-notes/index.html#v1-11-3)</li><li>muon 0.1.7</li><li>tables 3.10.1</li><li>scrublet 0.2.3</li><li>[scikit-learn 1.7.0](https://github.com/scikit-learn/scikit-learn/releases/tag/1.7.0)</li><li>[harmonypy 0.0.10](https://github.com/slowkow/harmonypy/releases/tag/v0.0.10)</li><li>[scib-metrics 0.5.6](https://github.com/YosefLab/scib-metrics/releases/tag/v0.5.6)</li><li>[cell_type_mapper 1.5.3](https://github.com/AllenInstitute/cell_type_mapper/releases/tag/v1.5.3)</li></ul>| [Dockerfile](https://github.com/ASAP-CRN/sc-atacseq-wf/tree/main/docker/sc_atac_tools) |
| util | <ul><li>[google-cloud-cli 524.0.0](https://cloud.google.com/sdk/docs/release-notes#52400_2025-05-28)</li></ul> | [Dockerfile](https://github.com/ASAP-CRN/wf-common/tree/main/docker/util) |

# wdl-ci

[`wdl-ci`](https://github.com/DNAstack/wdl-ci) provides tools to validate and test workflows and tasks written in [Workflow Description Language (WDL)](https://github.com/openwdl/wdl). `wdl-ci` in this repository is set up to run on pull request.

In general, `wdl-ci` will use inputs provided in the [wdl-ci.config.json](./wdl-ci.config.json) and compare current outputs and validated outputs based on changed tasks/workflows to ensure outputs are still valid by meeting the critera in the specified tests. For example, if the Cell Ranger task in our workflow was changed, then this task would be submitted and that output would be considered the "current output". When inspecting the raw counts generated by Cell Ranger, there is a test specified in the [wdl-ci.config.json](./wdl-ci.config.json) called, "check_hdf5". The test will compare the "current output" and "validated output" (provided in the [wdl-ci.config.json](./wdl-ci.config.json)) to make sure that the raw_feature_bc_matrix.h5 file is still a valid HDF5 file.


# Notes

## References

### Cell Ranger references

| Genome | Cell Ranger ARC reference | Link |
| :- | :- | :- |
| Human GRCh38 | 2024-A | https://www.10xgenomics.com/support/software/cell-ranger-arc/downloads#reference-downloads |
