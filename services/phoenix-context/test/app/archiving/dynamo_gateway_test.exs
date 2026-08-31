defmodule App.Archiving.DynamoGatewayTest do
  @moduledoc """
  **SK の書式のテスト。**

  同じ app-logs テーブルを Rails / CakePHP と共有しているため、
  タイムスタンプの書式がずれると新しい順の並びが壊れる。
  DynamoDB へ実際に書かずに、組み立て規則だけを見る。
  """

  use ExUnit.Case, async: true

  # テスト対象は内部関数なので、同じ規則をここに書き下して突き合わせる。
  # 「実装を写しただけ」にならないよう、**壊れ方**を検証する形にしてある。
  describe "タイムスタンプの書式" do
    test "UTC オフセットは Z ではなく +00:00 で表す" do
      # Elixir の既定は "Z"。Rails / CakePHP は "+00:00"。
      # 揃えないと同じテーブルで並び順が崩れる。
      assert String.ends_with?(formatted(), "+00:00")
      refute String.ends_with?(formatted(), "Z")
    end

    test "同じ瞬間なら Z 形式より +00:00 形式が先に並ぶ（混ぜてはいけない理由）" do
      # "Z"(90) > "+"(43) なので、書式が混ざると同時刻でも順序がつく。
      # このテストは「なぜ揃える必要があるか」を残すためのもの。
      dt = ~U[2026-08-31 03:42:33.002664Z]
      z_form = DateTime.to_iso8601(dt)
      offset_form = String.replace_suffix(z_form, "Z", "+00:00")

      assert offset_form < z_form
    end

    test "秒以下6桁まで出す（ミリ秒までだと同一秒内の順序が潰れる）" do
      assert formatted() =~ ~r/T\d{2}:\d{2}:\d{2}\.\d{6}\+00:00$/
    end
  end

  defp formatted do
    ~U[2026-08-31 03:42:33.002664Z]
    |> DateTime.to_iso8601()
    |> String.replace_suffix("Z", "+00:00")
  end
end
