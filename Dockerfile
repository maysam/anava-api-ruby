FROM ruby:3.3-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
RUN bundle install --jobs 4

COPY . .

ENV PORT=8085
ENV RAILS_ENV=production
EXPOSE 8085

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
