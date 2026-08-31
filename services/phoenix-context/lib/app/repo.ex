defmodule App.Repo do
  @moduledoc """
  Ecto のリポジトリ（DB 接続プール）。

  **これ自体は Context ではない。** すべての Context が
  同じ接続プールを共有するための土台。
  各 Context が自前の Repo を持つと、接続数が Context の数だけ増える。

  boundary 上は独立したサブ境界にしてある。`deps` が空なので、
  **Repo からはどの Context も呼べない**。
  土台が機能を知り始めると、依存が土台経由で一周してしまう。
  """

  use Boundary, top_level?: true, type: :strict, deps: [Ecto, Ecto.Repo, Ecto.Adapters.SQL, Ecto.Adapters.Postgres], exports: []

  use Ecto.Repo,
    otp_app: :app,
    adapter: Ecto.Adapters.Postgres
end
