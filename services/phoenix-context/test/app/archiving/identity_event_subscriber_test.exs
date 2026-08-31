defmodule App.Archiving.IdentityEventSubscriberTest do
  @moduledoc """
  **Context 間がイベントで繋がっていることのテスト。**
  identity は archiving を知らないまま、archiving 側が購読する。
  """

  use ExUnit.Case, async: false

  alias App.Archiving.IdentityEventSubscriber
  alias App.Identity.AuditPublisher

  # 本番の購読者は DynamoDB へ書きに行ってしまうので、
  # このテストの間だけ外して、届いたことだけを確かめる差し替えを入れる。
  setup do
    IdentityEventSubscriber.detach()
    test_pid = self()

    :telemetry.attach_many(
      "test-identity-events",
      [AuditPublisher.sign_in_event(), AuditPublisher.sign_in_failure_event()],
      fn event, _measurements, meta, _ -> send(test_pid, {:event, event, meta}) end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("test-identity-events")
      App.Archiving.subscribe!()
    end)

    :ok
  end

  test "サインイン成功のイベントが購読側へ届く" do
    AuditPublisher.sign_in(%{
      user_id: "sub-1",
      email: "taro@example.com",
      ip: "127.0.0.1",
      user_agent: "test"
    })

    assert_received {:event, [:app, :identity, :sign_in], meta}
    assert meta.user_id == "sub-1"
  end

  test "サインイン失敗のイベントが購読側へ届く" do
    AuditPublisher.sign_in_failure(%{
      email: "nobody@example.com",
      ip: "127.0.0.1",
      reason: "invalid_credentials"
    })

    assert_received {:event, [:app, :identity, :sign_in_failure], meta}
    assert meta.reason == "invalid_credentials"
  end

  test "発行側と購読側のイベント名が一致している" do
    # 依存を切っている代償として、イベント名は両側に**別々に**書かれている。
    # 片方だけ変えると黙って届かなくなるため、ここで突き合わせる。
    #
    # **これが「疎結合の代金」。** 依存を切ると、繋がっていることの保証は
    # 型ではなくテストが持つことになる。
    subscribed = IdentityEventSubscriber.subscribed_events()

    assert AuditPublisher.sign_in_event() in subscribed
    assert AuditPublisher.sign_in_failure_event() in subscribed
  end
end
