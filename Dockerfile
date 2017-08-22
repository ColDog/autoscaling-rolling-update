FROM ruby:2.4-alpine
WORKDIR /usr/src/app
COPY Gemfile* /usr/src/app/
RUN bundle install
COPY main.rb /usr/src/app/
ENTRYPOINT ruby /usr/src/app/main.rb
