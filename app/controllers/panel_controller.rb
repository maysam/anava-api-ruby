# frozen_string_literal: true

# The personal, per-user web panel: what one device has recorded, how it is
# trending, and where it ranks — the same figures the in-app statistics screen
# shows, on a screen big enough to actually read them.
#
# Sign-in is a magic link the app requests for itself (PanelLinksController).
# Redeeming it swaps the single-use token for a session cookie, so the token
# left in browser history is already spent and the URL bar never carries the
# device's anonymous user_id.
class PanelController < ActionController::Base
  layout 'panel'
  skip_forgery_protection

  SESSION_USER_KEY = 'panel_user_id'

  before_action :require_panel_session, only: :show

  # GET /panel
  def show
    @user_id = panel_user_id
    @overview = PanelAnalytics.overview(@user_id)
    @grouped_recordings = @overview[:recentRecordings]
                          .group_by { |recording| recording.date.to_s }
                          .sort_by { |date, _| date }
                          .reverse
                          .to_h
    @grouped_recordings.each_value { |rows| rows.sort_by!(&:end_timestamp) }
  end

  # GET /panel/enter?token=...
  def enter
    user_id = PanelMagicLink.redeem(params[:token])

    if user_id.blank?
      render :link_invalid, status: :unauthorized
      return
    end

    # A fresh session id on sign-in, so a session cookie someone else's browser
    # was already carrying can't be reused as this user's.
    reset_session
    session[SESSION_USER_KEY] = user_id
    redirect_to panel_path
  end

  # DELETE /panel/sign-out (also reachable by GET, for a plain link)
  def sign_out
    reset_session
    redirect_to '/'
  end

  private

  def panel_user_id
    session[SESSION_USER_KEY].presence
  end

  def require_panel_session
    render :signed_out, status: :unauthorized if panel_user_id.blank?
  end
end
