defmodule App.MixProject do
  use Mix.Project

  def project do
    [
      app: :app,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],

      # ── Context 境界の検証 ──
      # boundary は **コンパイラ**として動く。mix compile のたびに
      # Context 間の依存と公開面を検査し、違反を警告として出す。
      # `--warnings-as-errors` を付ければそのままビルドが落ちる。
      #
      # Rails の packwerk が「別コマンド(bin/packwerk check)」なのに対し、
      # こちらは通常のコンパイルに相乗りする。検証を忘れようがない。
      compilers: [:boundary] ++ Mix.compilers()
    ]
  end

  def application do
    [
      mod: {App.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.13"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.14"},
      # postgrex は hex 上の最新が 1.0.0-rc.1 に見えるが、これは **2016 年**に
      # 公開されたまま放置されている RC。semver の並び順で先頭に来るだけで、
      # 実際に開発が続いているのは 0.22 系（0.22.4 = 2026-08）。
      # `>= 0.0.0` のままにすると解決先が RC に振れる可能性があるため、
      # 安定系列を明示的に固定する。
      {:postgrex, "~> 0.22"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.12"},

      # ── AWS ──
      # ex_aws は署名とリクエスト組み立てだけを担い、HTTP クライアントと
      # XML パーサは別パッケージ。両方入れないと実行時に落ちる。
      #
      # hackney は **~> 4.0** を使う。ex_aws 2.7 が要求するのは 4.x であり、
      # 世に出回っている記事の `~> 1.18` を写すと依存解決に失敗する。
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.5"},
      {:ex_aws_dynamo, "~> 4.2"},
      {:hackney, "~> 4.7"},
      {:sweet_xml, "~> 0.7"},

      # ── JWT 検証 ──
      # joken が JWT の検証、jose が JWKS(公開鍵) の取り扱いを担う。
      {:joken, "~> 2.7"},
      {:jose, "~> 1.11"},

      # ── 境界検証・静的解析 ──
      # boundary が Context 境界（packwerk 相当）、credo が静的解析。
      {:boundary, "~> 0.10.4", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # ローカルでの検証。CI（.github/workflows/verify.yml）と同じ順序。
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "credo", "test"]
    ]
  end
end
