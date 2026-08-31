defmodule App.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    # Cognito の sub をそのまま主キーにするため、自動採番の id を使わない。
    create table(:users, primary_key: false) do
      add :id, :string, size: 64, primary_key: true, null: false
      add :email, :string, null: false
      add :display_name, :string, size: 50, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
  end
end
