max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
min_threads_count = ENV.fetch("RAILS_MIN_THREADS", max_threads_count).to_i
threads min_threads_count, max_threads_count

bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 8085)}"

workers ENV.fetch("WEB_CONCURRENCY", 0).to_i

environment ENV.fetch("RAILS_ENV", "development")
