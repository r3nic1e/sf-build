FROM ruby:2.3

RUN apt-get update -qq && \
    apt-get install -qq -y rsync vim nano

RUN gem install bundler

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /usr/src

ADD Gemfile Gemfile.lock ./
RUN bundle install

ADD cookery_bashrc /root/.bashrc
