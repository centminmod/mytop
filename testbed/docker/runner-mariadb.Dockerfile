# mytop runner that exercises the DBD::MariaDB FALLBACK driver path:
# deliberately does NOT install DBD::mysql, so mytop's BEGIN block selects
# DBD::MariaDB and the mariadb_* attribute prefix.
#
# Ubuntu 24.04 (noble) ships no libdbd-mariadb-perl package (checked main +
# universe, at least on arm64), so build it from CPAN against libmariadb-dev.
# Slow the first time (~2 min); cached as an image layer afterwards.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
        perl libdbi-perl libterm-readkey-perl default-mysql-client util-linux \
        build-essential libmariadb-dev cpanminus \
    && cpanm --notest DBD::MariaDB \
    && apt-get purge -y -qq build-essential cpanminus \
    && apt-get autoremove -y -qq \
    && rm -rf /var/lib/apt/lists/* /root/.cpanm
CMD ["sleep", "infinity"]
