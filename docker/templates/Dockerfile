FROM <%= image_name %>:<%= image_tag %>

ENV DEBIAN_FRONTEND="noninteractive"

RUN apt-get update -qq && \
    apt-get install -qq -y \
        build-essential \
        wget \
        curl \
        git \
        mercurial \
        subversion \
        rsync \
        openssh-client \
        gzip \
        bzip2 \
        xz-utils \
        unzip \
        unrar-free \
        lsb-release \
        python2.7 \
        software-properties-common \
        autoconf \
        automake \
        bison \
        libffi-dev \
        libgdbm-dev \
        libncurses5-dev \
        libsqlite3-dev \
        libtool \
        libyaml-dev \
        pkg-config \
        sqlite3 \
        zlib1g-dev \
        libgmp-dev \
        libreadline-dev \
        libssl-dev \
        gawk \
        apt-transport-https \
    ;

ENV RUBY_VERSION=2.6.6
RUN curl -sSL https://rvm.io/mpapis.asc | gpg --import - && \
    curl -sSL https://rvm.io/pkuczynski.asc | gpg --import - && \
    curl -sSL https://get.rvm.io | bash -s stable && \
    bash -c "source /etc/profile.d/rvm.sh && \
    rvm install $RUBY_VERSION && \
    rvm use $RUBY_VERSION --default"

ENV PATH="/usr/local/rvm/rubies/ruby-$RUBY_VERSION/bin:$PATH"

RUN gem update --system

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /recipes

ADD <%= repo_url %>/pub.key /tmp
RUN cat /tmp/pub.key | apt-key add -
ADD <%= apt_sources %> /etc/apt/sources.list.d/aptly.list
RUN LC_ALL=C.UTF-8 apt-add-repository ppa:ondrej/php

ADD Gemfile Gemfile.lock /usr/src/
RUN cd /usr/src && bundle install --without='test development'

