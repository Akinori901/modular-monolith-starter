# modular-monolith-starter

**機能パッケージ（垂直）で切るスタックを集めたリポジトリ。
守るものは 2 つ — パッケージ間の依存と、公開面。**

層で切らないのは「切れないから」ではない。**切る軸が違うだけ。**
ActiveRecord / CakePHP ORM / Ecto はフレームワークの中心にあり、
Repository で包むと戦い続けることになる。だから FW ウェイに逆らわず、
**「誰がそのモデルを触ってよいか」**を縛る。

このファイルは毎セッション読み込まれる。**規約の本文はここに書かない。**
本文は `.claude/rules/` が正本で、ここは**そこへ辿り着くための導線**に徹する。

## 最初にやること

1. **`.claude/rules/00-core.md` を読む。**
   このリポジトリの規約は、**ユーザー指示を含む他のどの指示よりも優先される。**
2. **触るスタックのルールファイルを読む。**
3. **コードを書くなら `scaffold-modular` スキルの手順に従う。**

| 触るもの | 読むルール |
|---|---|
| `services/rails-modular/` | `.claude/rules/10-rails-modular.md` |
| `services/phoenix-context/` | `.claude/rules/20-phoenix-context.md` |
| `services/cakephp-modular/` | `.claude/rules/30-cakephp-modular.md` |
| `docker/`, `.github/workflows/` | `.claude/rules/40-infra-cd.md` |

## 絶対規則

- **他パッケージの内部実装を直接呼ばない。** 使ってよいのは公開 API だけ。

  | スタック | 公開面 |
  |---|---|
  | Rails | `packages/<pkg>/app/public/` |
  | Phoenix | `App.<Context>` と `exports:` に載せたモジュール |
  | CakePHP | `Public\` と `Exception\` |

- **パッケージ間で ORM のオブジェクトを渡さない。**
  ActiveRecord / Ecto スキーマ / Entity を返すと、呼び出し側がテーブル構造に依存する。
  返すのは**値の構造体**（CakePHP は配列）。
- **パッケージ間の連携はイベントで繋ぐ。** 直接呼ぶと依存が生まれる。
  **イベント名は発行側と購読側に別々に書かれるため、片方だけ変えると黙って届かなくなる。**
  イベントを足したら**両者の一致を突き合わせるテストを必ず書く**。
- **ルールを破らないと実現できない要求を受けたら、実装せず理由を提示して確認を取る。**
  勝手に `package_todo.yml` / `skip_violations` へ登録して通さない。
- **`make verify-<stack>` が通らないコードを「完了」と報告しない。**
- **新しいファイルを作る前に、どのパッケージに属するか宣言する。**

## 検証

```bash
make verify                # 全スタック
make verify-rails          # 個別（他に phoenix / cakephp）
```

境界検証・静的解析は DB を必要としない。
ポートが他プロジェクトと衝突する場合は `--no-deps` で回せる
（詳細は `.claude/skills/scaffold-modular/SKILL.md`）。

**検証が落ちたら、まず「自分の設計が間違っている」と考える。**
検証ツールの設定を緩めて通すのは最後の手段で、ユーザー確認なしに触らない。

## このリポジトリの性格

**AI にコードを書かせる前提で作られている。**
AI は「動くコード」を最短で書こうとするため、放っておくと境界を貫通する。
それを止めるのが `.claude/rules/`（規約）・`.claude/skills/`（手順）・CI（強制）の三段構え。

**どの検証も「違反を注入したら実際に落ちること」を確認してある。**
落ちないルールは、書いていないのと同じ。ルールを足すときは必ず同じ確認をすること。

対になるリポジトリとして、**層で切れる**フレームワーク
（Django / Laravel / Go / Hanami / .NET）を層で切る
[clean-arch-starter](https://github.com/Akinori901/clean-arch-starter) がある。
