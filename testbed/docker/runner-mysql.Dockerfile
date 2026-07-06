# mytop runner with the primary driver path: DBD::mysql from Ubuntu packages.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
        perl libdbi-perl libdbd-mysql-perl libterm-readkey-perl \
        default-mysql-client util-linux \
    && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
