FROM us-central1-docker.pkg.dev/dnastack-asap-parkinsons/workflow-images/util:1.2.0 as scripts

FROM ubuntu:jammy

LABEL maintainer="bioinformatics@dnastack.com"

ARG IMAGE_NAME
ENV IMAGE_NAME "${IMAGE_NAME}"
ARG IMAGE_TAG
ENV IMAGE_TAG "${IMAGE_TAG}"

RUN apt-get -qq update \
	&& apt-get -qq install -y \
		wget \
		time \
		xxd \
		python3-dev \
		tar \
	&& rm -rf /var/lib/apt/lists/*

# gcloud sdk; needed to upload output files
ARG GCLOUD_CLI_VERSION
ENV GCLOUD_CLI_VERSION "${GCLOUD_CLI_VERSION}"
RUN wget "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_CLI_VERSION}-linux-x86_64.tar.gz" \
	&& tar -zxvf "google-cloud-cli-${GCLOUD_CLI_VERSION}-linux-x86_64.tar.gz" --directory /opt \
	&& rm "google-cloud-cli-${GCLOUD_CLI_VERSION}-linux-x86_64.tar.gz"

ENV PATH "${PATH}:/opt/google-cloud-sdk/bin"

ARG CELLRANGER_ATAC_VERSION
# N.B. this must be passed as a build arg (using the utility script: -b CELLRANGER_ATAC_DOWNLOAD_QUERY_STRING='xxyy')
#   Enter information here: hhttps://www.10xgenomics.com/support/software/cell-ranger-atac/downloads
#   The value of CELLRANGER_ATAC_DOWNLOAD_QUERY_STRING = everything following the ? in the cURL request URL (no quotes)
ARG CELLRANGER_ATAC_DOWNLOAD_QUERY_STRING
RUN wget -O cellranger-atac-${CELLRANGER_ATAC_VERSION}.tar.gz \
	"https://cf.10xgenomics.com/releases/cell-atac/cellranger-atac-${CELLRANGER_ATAC_VERSION}.tar.gz?${CELLRANGER_ATAC_DOWNLOAD_QUERY_STRING}" \
	&& tar -zxvf cellranger-atac-${CELLRANGER_ATAC_VERSION}.tar.gz --directory /opt \
	&& rm cellranger-atac-${CELLRANGER_ATAC_VERSION}.tar.gz

RUN ln -s /opt/cellranger-atac-${CELLRANGER_ATAC_VERSION}/cellranger-atac /usr/local/bin/

COPY --from=scripts /opt/scripts /opt/scripts
COPY scripts /opt/scripts
ENV PATH "${PATH}:/opt/scripts"
