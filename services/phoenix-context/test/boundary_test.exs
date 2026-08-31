defmodule BoundaryTest do
  @moduledoc """
  **境界の宣言そのものを検証する。**

  boundary はコンパイル時に「宣言に反する参照」を見るが、
  「そもそも意図した宣言になっているか」までは見ない。
  ここが崩れると、**コンパイルは通るのに設計だけ壊れる**。

  Rails 版で踏んだ packwerk-extensions の罠
  （設定しても黙って無視される）と同じ種類の事故を防ぐためのテスト。

  宣言は各モジュールの `use Boundary` に持たせた属性から読む。
  boundary の内部 API に触らないので、ライブラリの更新で壊れない。
  """

  use ExUnit.Case, async: true

  # `use Boundary` は宣言内容を `Boundary` という名前のモジュール属性に
  # persist する。ここを読めば「何を宣言したか」がそのまま取れる。
  defp declaration(module) do
    module.module_info(:attributes)
    |> Keyword.get(Boundary, [])
    |> List.first()
    |> Map.fetch!(:opts)
  end

  defp deps(module), do: declaration(module) |> Keyword.get(:deps, []) |> normalize()
  defp exports(module), do: declaration(module) |> Keyword.get(:exports, []) |> normalize()

  defp normalize(entries) do
    entries
    |> Enum.map(fn
      {mod, _opts} -> mod
      mod -> mod
    end)
    |> Enum.sort()
  end

  test "boundary コンパイラが有効になっている" do
    # これが外れると、境界の検証が丸ごと素通りする。
    # 「動いているように見えて何も検知していない」状態の一番の入口。
    assert :boundary in Mix.Project.config()[:compilers]
  end

  test "全ての境界が :strict（依存を継承しない）" do
    # :strict を外すと親の依存が黙って流れ込み、
    # 宣言していない依存が使えてしまう。
    for module <- [App.Identity, App.Storage, App.Archiving, App.Repo, AppWeb] do
      assert Keyword.get(declaration(module), :type) == :strict,
             "#{inspect(module)} が :strict ではない"
    end
  end

  test "Context 同士は互いに依存していない" do
    for {context, others} <- [
          {App.Identity, [App.Storage, App.Archiving]},
          {App.Storage, [App.Identity, App.Archiving]},
          {App.Archiving, [App.Identity, App.Storage]}
        ],
        other <- others do
      refute other in deps(context),
             "#{inspect(context)} が #{inspect(other)} に依存している。" <>
               "Context 同士はイベントで繋ぐこと。"
    end
  end

  test "各 Context が公開しているのは値の構造体だけ" do
    # 公開面が広がるほど内部を変えられなくなる。
    # ゲートウェイやスキーマが混ざっていないことを見る。
    assert exports(App.Identity) == [Tokens, UserView]
    assert exports(App.Storage) == [StoredFile]
    assert exports(App.Archiving) == [LogEntry]
  end

  test "Web 層は Repo に依存していない（DB を触るのは Context の仕事）" do
    refute App.Repo in deps(AppWeb)
  end

  test "Web 層が依存してよいのは Context の公開面だけ" do
    for context <- [App.Identity, App.Storage, App.Archiving] do
      assert context in deps(AppWeb)
    end
  end
end
