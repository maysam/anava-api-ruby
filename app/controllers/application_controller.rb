class ApplicationController < ActionController::API
  class InvalidRequestError < StandardError; end

  # rescue_from handlers are checked most-recently-declared-first, so the
  # generic StandardError catch-all must be declared before the more
  # specific InvalidRequestError one for the latter to win.
  rescue_from StandardError, with: :render_server_error
  rescue_from InvalidRequestError, with: :render_bad_request

  def route_not_found
    render json: { success: false, error: "Not found" }, status: :not_found
  end

  private

  def parsed_json_body
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    raise InvalidRequestError, "Invalid JSON body"
  end

  def render_bad_request(error)
    render json: { success: false, error: error.message }, status: :bad_request
  end

  def render_server_error(error)
    Rails.logger.error("#{request.request_method} #{request.path}: #{error.message}")
    render json: { success: false, error: error.message }, status: :internal_server_error
  end
end
