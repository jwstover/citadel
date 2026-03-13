# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Citadel.Repo.insert!(%Citadel.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Citadel.Tasks

Tasks.create_task_state!(%{name: "Todo", order: 1}, upsert?: true, upsert_identity: :unique_name)

Tasks.create_task_state!(%{name: "In Progress", order: 2},
  upsert?: true,
  upsert_identity: :unique_name
)

Tasks.create_task_state!(%{name: "Complete", order: 3},
  upsert?: true,
  upsert_identity: :unique_name
)
