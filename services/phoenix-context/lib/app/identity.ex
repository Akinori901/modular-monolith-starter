defmodule App.Identity do
  @moduledoc """
  identity Context の**公開 API**。

  他 Context・Web 層から触ってよいのはこのモジュールと、
  `exports` に載せた値の構造体だけ。
  `App.Identity.{User, SignIn, CognitoGateway, JwksCache, AuditPublisher}` は
  すべて内部実装であり、外から参照するとコンパイル時に落ちる。

  公開面を1枚に絞ることで、内部をいくら作り替えても
  呼び出し側が壊れない状態を保つ。

  ## Context は Phoenix の標準機能である

  ここは「本リポジトリのために足した層」ではない。
  `mix phx.gen.context` が生成するのがまさにこの形で、
  **Phoenix 自身が「機能で切れ」と言っている**。
  boundary が足しているのは「その境界を破ったらコンパイルを落とす」
  という強制力だけ。
  """

  # ── Context 境界の宣言 ──
  #
  # top_level?: true — `App` のサブ境界にせず、AppWeb と並ぶ独立した境界にする。
  #       こうしないと Web 層が `deps: [App]` としか書けず、
  #       「どの Context に依存しているか」が宣言から消える。
  # type: :strict — 依存を**一切継承しない**。
  #       外部ライブラリ（Ecto など）もここに書かないと使えない。
  #       つまり **この Context が持ち込む技術スタックが宣言に出る**。
  # deps: 依存してよい境界。**ここに書いていない Context を
  #       参照するとコンパイル時に落ちる。**
  #       archiving が無いのが要点（イベントで繋ぐ）。
  # exports: 外から見えるモジュール。**ここに書いていないものを
  #          外から参照するとコンパイル時に落ちる。**
  #          packwerk の `app/public/` に相当する。
  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [App.Repo, Ecto, Ecto.Changeset, Ecto.Schema, ExAws, Joken, Jason, Logger],
    exports: [Tokens, UserView]

  alias App.Identity.{CognitoGateway, SignIn, User, UserView}
  alias App.Repo

  @typedoc "認証に失敗した理由。Web 層はこれを 401 に翻訳する。"
  @type auth_error :: {:authentication_failed, String.t()}

  @doc """
  サインインする。

  `{:ok, %{tokens: %App.Identity.Tokens{}, user: %App.Identity.UserView{}}}`
  または `{:error, {:authentication_failed, message}}` を返す。
  """
  @spec sign_in(String.t(), String.t(), keyword() | map()) ::
          {:ok, %{tokens: App.Identity.Tokens.t(), user: UserView.t()}} | {:error, term()}
  def sign_in(email, password, meta \\ %{}) do
    case SignIn.call(email, password, Map.new(meta)) do
      {:ok, %{tokens: tokens, user: user}} -> {:ok, %{tokens: tokens, user: to_view(user)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  アクセストークンから現在のユーザーを返す。
  """
  @spec current_user(String.t()) :: {:ok, UserView.t()} | {:error, term()}
  def current_user(access_token) do
    with {:ok, identity} <- CognitoGateway.verify_access_token(access_token),
         %User{} = user <- Repo.get(User, identity.subject) do
      {:ok, to_view(user)}
    else
      # トークンは正しいがローカルに行が無い場合。
      # 認証されていないのと同じ扱いにする（情報を増やさない）。
      nil -> {:error, {:authentication_failed, "ユーザーが見つかりません"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "疎通確認（ヘルスチェック用）。"
  @spec ping() :: :ok | {:error, term()}
  def ping, do: CognitoGateway.ping()

  @doc """
  この Context が必要とする常駐プロセス（JWKS キャッシュ）。

  **起動側に内部モジュールを名指しさせないための口。**
  `App.Application` が `App.Identity.JwksCache` を直接書くと、
  内部実装が起動コードに漏れて、差し替えのたびに起動側を直すことになる。
  """
  @spec children() :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children, do: [App.Identity.JwksCache]

  # Ecto スキーマを外へ出さない。
  # 出すと呼び出し側がテーブル構造に依存する。
  defp to_view(%User{} = user) do
    %UserView{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      active: User.can_sign_in?(user)
    }
  end
end
