FROM <%= image_name %>:<%= image_tag %>

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
        <% if image_tag == 'precise' %>
        python-software-properties \
        <% else %>
        software-properties-common \
        <% end %>
    ;

RUN apt-add-repository ppa:brightbox/ruby-ng && \
    apt-get update -qq && \
    apt-get install -qq -y ruby2.3 ruby2.3-dev

RUN gem install bundler

ADD ssh_config /root/.ssh/config
RUN chown -R root:root /root/.ssh && \
    chmod -R 700 /root/.ssh

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /recipes

ADD <%= repo_url %>/pubkey.asc /tmp
RUN cat /tmp/pubkey.asc | apt-key add -
ADD <%= apt_sources %> /etc/apt/sources.list.d/aptly.list

ADD Gemfile Gemfile.lock /usr/src/
RUN cd /usr/src && bundle install --without='test development'
