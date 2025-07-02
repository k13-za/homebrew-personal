cask "postgres" do
  version "2.8.2-17"

  desc "Postgres.app is a full-featured PostgreSQL installation packaged as a standard Mac app."
  homepage "https://postgresapp.com"

  livecheck do
    url "https://github.com/k13-za/postgres/releases/latest"
    strategy :github_latest
  end

  url "https://github.com/PostgresApp/PostgresApp/releases/download/v2.8.2/Postgres-2.8.2-17.dmg"
  sha256 "b52fa878960bdc345baeb6aa0ba9d6a1f2de5f7979014cc42e1a0cc633c31bf2"

  app "Postgres"

  uninstall quit: "com.postgres.app"

  zap trash: [
    "~/Library/Application Support/Postgres",
    "~/Library/Caches/com.postgres",
    "~/Library/Preferences/com.postgres.plist",
    "~/Library/Saved Application State/com.postgres.savedState",
  ]
end

