# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET / (dashboard)', type: :request do
  it 'renders the empty state when there are no recordings' do
    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with('text/html')
    expect(response.body).to include('Anava Recordings Dashboard')
    expect(response.body).to include('No recordings found yet')
  end

  it 'renders the recordings list grouped by day for the selected model' do
    create(:recording, model: 'Pixel-7', date: Date.current, slot_id: 1, duration: 65, percentage: 80)
    create(:recording, model: 'iPhone-14', date: Date.current)

    get '/', params: { model: 'Pixel-7' }

    expect(response).to have_http_status(:ok)
    # Model selector lists both models, Pixel-7 selected
    expect(response.body).to include('<option value="Pixel-7" selected>')
    # Day-group header for today, and the slot/percentage row
    expect(response.body).to include(Date.current.strftime('%A, %B %-d, %Y'))
    expect(response.body).to include('Dhuhr') # slot_id 1 -> slots[1]
    expect(response.body).to include('80%')
    # Recording JSON is embedded for the modal
    expect(response.body).to include('id="recordings-json"')
  end

  it 'defaults to the analytics tab and embeds chart data when requested' do
    create(:recording, model: 'Pixel-7', date: Date.current)

    get '/', params: { model: 'Pixel-7', tab: 'analytics' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="analytics-json"')
    expect(response.body).to include('Daily Activity (Last 7 Days)')
    expect(response.body).to include('Detailed Statistics')
  end

  it 'escapes attacker-controlled values embedded in the recordings JSON' do
    create(:recording, model: 'Pixel-7', user_id: '</script><script>alert(1)</script>')

    get '/', params: { model: 'Pixel-7' }

    expect(response).to have_http_status(:ok)
    # The literal closing-script sequence must not appear unescaped inside the
    # embedded JSON (json_escape turns "<" into a unicode escape).
    expect(response.body).not_to include('</script><script>alert(1)')
  end

  it 'paginates and clamps an out-of-range page to the last page' do
    create_list(:recording, 3, model: 'Pixel-7', date: Date.current)

    get '/', params: { model: 'Pixel-7', per_page: 10, page: 99 }

    expect(response).to have_http_status(:ok)
    # 3 records / 10 per page = 1 page, so no pagination controls are shown
    expect(response.body).not_to include('Page 99')
  end
end
