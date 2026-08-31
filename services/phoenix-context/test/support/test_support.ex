defmodule AppTest do
  @moduledoc """
  テスト補助モジュールの入れ物。

  **境界の検査対象から外すためだけに存在する。**
  `AppWeb.ConnCase` のような補助モジュールは、性質上
  Web 層と Context の両方に触る。これを AppWeb や App の
  一部として扱うと、本番コードの依存宣言に
  「テストのためだけの依存」が混ざってしまう。

  `check: [in: false, out: false]` は boundary が公式に
  推奨しているテスト補助の扱い方（README / @moduledoc 参照）。
  **本番コードの境界は一切緩めていない**点が要点。
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
end
