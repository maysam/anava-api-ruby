FROM ruby:3.3-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
RUN bundle install --jobs 4

COPY . .

ENV PORT=8000
EXPOSE 8000

CMD ["bundle", "exec", "rackup", "config.ru", "-o", "0.0.0.0", "-p", "8000"]
