# Credo の設定。
#
# **boundary が「構造」を見て、Credo が「書き方」を見る。**
# 役割が違うので両方走らせる。境界検証だけでは
# 「1関数に全部書く」ような書き方は止められない。
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      strict: true,
      checks: %{
        disabled: [
          # モジュールの @moduledoc は日本語で書いているものが多く、
          # 英語前提のチェックと相性が悪い。
          {Credo.Check.Readability.ModuleDoc, []},
          # 行長は formatter に任せる（98 桁で整形済み）。
          {Credo.Check.Readability.MaxLineLength, []}
        ]
      }
    }
  ]
}
