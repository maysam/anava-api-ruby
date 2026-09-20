# frozen_string_literal: true

# Single-use, short-lived tokens that let a device hand its anonymous user_id
# to a browser session for the personal panel (see PanelController).
#
# Only the SHA-256 digest of a token is stored, so a database leak can't be
# replayed into someone's panel. Mirrored in db/init.sql (the Postgres
# bootstrap docker-compose applies on first container start).
class CreatePanelMagicLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :panel_magic_links do |t|
      t.string :user_id, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :panel_magic_links, :token_digest, unique: true
    add_index :panel_magic_links, :user_id
    add_index :panel_magic_links, :expires_at
  end
end
