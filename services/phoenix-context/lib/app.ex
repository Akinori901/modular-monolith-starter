defmodule App do
  @moduledoc """
  ビジネスロジックの名前空間。

  **ここには何も置かない。** `App.Identity` / `App.Storage` /
  `App.Archiving` はそれぞれ独立した Context であり、
  この名前空間はディレクトリの見出しでしかない。

  boundary 上も、各 Context は `top_level?: true` で
  **この名前空間のサブ境界ではなく、AppWeb と並ぶ独立した境界**
  として扱っている（後述）。
  Rails 版の `packages/` ディレクトリと同じ位置づけ。

  ## なぜ入れ子の境界にしなかったか

  boundary はモジュール名から境界を決めるため、素直に書くと
  `App.Identity` は `App` のサブ境界になる。しかしサブ境界には
  「**外の境界から直接依存できない**」という制約がある
  （親が export したものを、親経由で見ることになる）。

  そうすると Web 層の `deps` は `[App]` の1行になり、
  「**Web 層がどの Context に依存しているか**」が宣言から消える。
  依存表が読めなくなるのは、この構成で一番失いたくないものなので、
  各 Context を top_level にして**フラットに並べる**方を採った。
  """

  use Boundary, deps: [], exports: []
end
